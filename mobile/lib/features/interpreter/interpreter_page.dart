import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/touchable.dart';
import '../../core/widgets/ui_kit.dart';
import '../chat/utils/voice_record_path.dart';
import 'apple_translate.dart';
import 'interpreter_languages.dart';
import 'interpreter_phrases.dart';
import '../../core/widgets/page_kit.dart';

class InterpreterTurn {
  const InterpreterTurn({
    required this.fromDoctor,
    required this.original,
    required this.translated,
    required this.sourceLang,
    required this.targetLang,
    this.toneChecked = true,
  });

  final bool fromDoctor;
  final String original;
  final String translated;
  final String sourceLang;
  final String targetLang;

  /// False when an offline Apple draft was used where the LLM should have
  /// checked politeness.
  final bool toneChecked;
}

/// Chairside doctor ↔ patient interpreter (voice + text). Not app UI language.
class InterpreterPage extends StatefulWidget {
  const InterpreterPage({
    super.key,
    required this.api,
    required this.patientSession,
    this.active = true,
  });

  final ApiClient api;
  final PatientSession patientSession;
  final bool active;

  @override
  State<InterpreterPage> createState() => _InterpreterPageState();
}

class _InterpreterPageState extends State<InterpreterPage> {
  static const _kDoctorLang = 'interpreter.doctor_lang';
  static const _kPatientLang = 'interpreter.patient_lang';
  static const _kAutoSpeak = 'interpreter.auto_speak';

  final _doctorInput = TextEditingController();
  final _patientInput = TextEditingController();
  final _doctorFocus = FocusNode();
  final _patientFocus = FocusNode();
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  // Languages without Apple Speech: record, backend transcribes + translates.
  final _recorder = AudioRecorder();
  bool _cloudStt = false;
  Timer? _recordCap;
  // Languages without an Apple voice: OpenAI TTS, cached on disk per sentence.
  final _cloudPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _cloudState;

  /// Text being read aloud right now; [_speakingLive] once sound has
  /// actually started (before that the speaker shows it's loading).
  String? _speaking;
  bool _speakingLive = false;

  /// How each language gets spoken, resolved once: a system voice, a system
  /// locale, or null for cloud audio. Resolving it is the slow part.
  final _binding = <String, ({Map<String, String>? voice, String? locale, bool installed})>{};

  /// Installed system voices, read once — listing them is slow on iOS and
  /// made every speaker tap lag.
  List<Map<String, String>>? _voices;

  /// Audio session is in playback mode; recording switches it away.
  bool _playbackReady = false;
  bool _cloudTts = false;
  // Doctor sentences repeat across visits; their translations are reused so
  // the LLM (and then the cached voice) is paid for once.
  static const _kTranslations = 'interpreter.translations';
  static const _maxTranslations = 300;
  Map<String, String> _translations = {};

  List<InterpreterLanguage> _languages = List.of(kInterpreterLanguages);
  String _doctorLang = 'de';
  String _patientLang = 'ar';
  bool _autoSpeak = true;
  bool _busy = false;
  bool _speechReady = false;
  bool _listeningDoctor = false;
  bool _listeningPatient = false;
  bool _warnedNoVoice = false;
  // Live STT text lives in a notifier so partial results repaint only the text
  // area, not both blurred panes (that rebuild was the main source of lag).
  final _partialText = ValueNotifier<String>('');
  String get _partial => _partialText.value;
  set _partial(String v) => _partialText.value = v;
  String _speechStatus = '';
  String? _speechError;
  double _peakSoundLevel = -120;
  DateTime? _pointerDownAt;
  int? _holdPointer;
  int _holdEpoch = 0;
  bool _pressToStop = false;
  Completer<void>? _speechIdle;
  List<LocaleName> _speechLocales = const [];
  final List<InterpreterTurn> _turns = [];
  // Doctor phrases persist across visits (per doctor language); patient
  // phrases only live for the current visit + patient language.
  PhraseCounts _doctorPhrases = PhraseCounts();
  final PhraseCounts _patientPhrases = PhraseCounts();
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    widget.patientSession.addListener(_onPatientSession);
    widget.patientSession.ensureLoaded();
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant InterpreterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      unawaited(_speech.stop());
      unawaited(_tts.stop());
      unawaited(_cloudPlayer.stop());
      if (_listeningDoctor) unawaited(_stopHold(true, cancelled: true));
      if (_listeningPatient) unawaited(_stopHold(false, cancelled: true));
    }
  }

  @override
  void dispose() {
    widget.patientSession.removeListener(_onPatientSession);
    _doctorInput.dispose();
    _patientInput.dispose();
    _partialText.dispose();
    _doctorFocus.dispose();
    _patientFocus.dispose();
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    _recordCap?.cancel();
    unawaited(_recorder.dispose().catchError((_) {}));
    unawaited(_cloudState?.cancel());
    unawaited(_cloudPlayer.dispose().catchError((_) {}));
    super.dispose();
  }

  InterpreterLanguage get _doctor =>
      InterpreterLanguage.byCode(_languages, _doctorLang) ??
      kInterpreterLanguages.firstWhere((e) => e.code == 'de');

  InterpreterLanguage get _patient =>
      InterpreterLanguage.byCode(_languages, _patientLang) ??
      kInterpreterLanguages.firstWhere((e) => e.code == 'ar');

  void _onPatientSession() {
    if (!mounted) return;
    unawaited(_loadPatientLanguage());
    setState(() {});
  }

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final appLang = LocaleScope.maybeOf(context)?.code ?? 'de';
    _doctorLang =
        _prefs?.getString(_kDoctorLang) ?? (appLang == 'en' ? 'en' : 'de');
    if (_doctorLang != 'de' && _doctorLang != 'en') {
      _doctorLang = 'de';
    }
    _patientLang = _prefs?.getString(_kPatientLang) ?? 'ar';
    _autoSpeak = _prefs?.getBool(_kAutoSpeak) ?? true;
    try {
      final raw = jsonDecode(_prefs?.getString(_kTranslations) ?? '{}');
      if (raw is Map) _translations = raw.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {}
    _loadDoctorPhrases();
    if (mounted) setState(() {});
    await _loadPatientLanguage();
    await _loadCatalog();
    await _initTts();
    // Ask for Speech on first Hold, not here — a system dialog during
    // bootstrap cancels the pointer and never shows again on the button.
    try {
      if (await _speech.hasPermission) await _initSpeech();
    } catch (_) {}
  }

  Future<void> _loadCatalog() async {
    try {
      final raw = await widget.api.interpreterCatalog();
      final rows = raw['languages'];
      final parsed = <InterpreterLanguage>[];
      if (rows is List) {
        for (final row in rows) {
          if (row is Map) {
            final lang = InterpreterLanguage.fromJson(
              Map<String, dynamic>.from(row),
            );
            if (lang.code.isNotEmpty) parsed.add(lang);
          }
        }
      }
      final providers = raw['providers'];
      if (!mounted) return;
      setState(() {
        if (parsed.length >= 20) _languages = parsed;
        _cloudStt = providers is Map && providers['stt'] == 'whisper';
        _cloudTts = providers is Map && providers['tts'] == 'openai';
      });
    } catch (_) {
      // Local catalog is enough for the picker.
    }
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onError: (error) {
          _speechError = error.errorMsg;
          debugPrint(
            'interpreter stt error: ${error.errorMsg} permanent=${error.permanent}',
          );
        },
        onStatus: (status) {
          _speechStatus = status;
          debugPrint('interpreter stt status: $status');
          if (status == 'notListening' || status == 'done') {
            final idle = _speechIdle;
            if (idle != null && !idle.isCompleted) idle.complete();
          }
        },
      );
      if (ok) {
        try {
          _speechLocales = await _speech.locales();
          debugPrint(
            'interpreter stt locales: ${_speechLocales.map((e) => e.localeId).take(12).join(", ")}',
          );
        } catch (_) {
          _speechLocales = const [];
        }
      }
      if (mounted) setState(() => _speechReady = ok);
      if (ok) _warmSpeechForSelection();
      unawaited(_warmBindings());
    } catch (e) {
      debugPrint('interpreter stt init: $e');
      if (mounted) setState(() => _speechReady = false);
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.autoStopSharedSession(false);
      await _tts.awaitSpeakCompletion(false);
      await _ensureTtsPlayback();
      await _tts.setSpeechRate(0.46);
      await _tts.setVolume(1.0);
      _tts.setErrorHandler((msg) {
        debugPrint('interpreter tts error: $msg');
        _doneSpeaking();
      });
      _tts.setStartHandler(_nowSpeaking);
      _tts.setCompletionHandler(_doneSpeaking);
      _tts.setCancelHandler(_doneSpeaking);
      _cloudState = _cloudPlayer.playerStateStream.listen((st) {
        if (st.processingState == ProcessingState.completed) {
          _doneSpeaking();
        } else if (st.playing && st.processingState == ProcessingState.ready) {
          _nowSpeaking();
        }
      });
      // List the system voices now, not on the first speaker tap.
      unawaited(_loadVoices().then((_) => _warmBindings(), onError: (_) {}));
    } catch (e) {
      debugPrint('interpreter tts init: $e');
    }
  }

  Future<void> _ensureTtsPlayback() async {
    // defaultToSpeaker is only valid with playAndRecord. playback+speaker
    // fails silently (plugin returns 0) and the session stays ambient, which
    // is mute when the iPad ringer is off. Bluetooth HFP + A2DP together
    // can also fail the category set.
    var ok = await _tryIosAudioCategory(
      IosTextToSpeechAudioCategory.playAndRecord,
      const [
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
      IosTextToSpeechAudioMode.spokenAudio,
    );
    if (!ok) {
      ok = await _tryIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        const [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }
    try {
      await _tts.setSharedInstance(true);
    } catch (e) {
      debugPrint('interpreter tts activate: $e');
    }
    if (!ok) {
      debugPrint('interpreter tts audio session: category set failed');
    }
    _playbackReady = ok;
  }

  void _doneSpeaking() {
    if (mounted && _speaking != null) {
      setState(() {
        _speaking = null;
        _speakingLive = false;
      });
    }
  }

  void _nowSpeaking() {
    if (mounted && _speaking != null && !_speakingLive) setState(() => _speakingLive = true);
  }

  /// Resolve both languages' voices in the background so a tap plays at once.
  Future<void> _warmBindings() async {
    for (final lang in {_doctorLang, _patientLang}) {
      if (!_binding.containsKey(lang)) await _resolveBinding(lang);
    }
  }

  Future<({Map<String, String>? voice, String? locale, bool installed})> _resolveBinding(String lang) async {
    if (_binding[lang] case final cached?) return cached;
    final row = InterpreterLanguage.byCode(_languages, lang);
    final locales = row?.ttsLocales ?? <String>[lang.replaceAll('_', '-'), lang];
    ({Map<String, String>? voice, String? locale, bool installed})? b;
    final voice = await _installedVoice(locales);
    if (voice != null) {
      b = (voice: voice, locale: null, installed: true);
    } else {
      for (final locale in locales) {
        if (await _languageInstalled(locale)) {
          b = (voice: null, locale: locale, installed: true);
          break;
        }
      }
      // No system voice: _speak uses cloud audio when on, else tries anyway.
      b ??= (voice: null, locale: locales.first, installed: false);
    }
    return _binding[lang] = b;
  }

  /// Speaker button: read [text] aloud, or stop when it's already playing.
  Future<void> _toggleSpeak(String text, String lang) async {
    if (_speaking == text.trim()) {
      await _tts.stop();
      await _cloudPlayer.stop();
      _doneSpeaking();
      return;
    }
    await _speak(text, lang: lang, announceIfSilent: true);
  }

  /// Leave TTS spokenAudio mode so the mic can actually capture.
  Future<void> _ensureMicCapture() async {
    _playbackReady = false;
    _doneSpeaking();
    try {
      await _tts.stop();
      await _cloudPlayer.stop();
    } catch (_) {}
    await _tryIosAudioCategory(
      IosTextToSpeechAudioCategory.playAndRecord,
      const [
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
      IosTextToSpeechAudioMode.defaultMode,
    );
    try {
      await _tts.setSharedInstance(false);
    } catch (_) {}
  }

  Future<bool> _tryIosAudioCategory(
    IosTextToSpeechAudioCategory category,
    List<IosTextToSpeechAudioCategoryOptions> options,
    IosTextToSpeechAudioMode mode,
  ) async {
    try {
      final result = await _tts.setIosAudioCategory(category, options, mode);
      return result != 0 && result != false;
    } catch (e) {
      debugPrint('interpreter tts audio session: $e');
      return false;
    }
  }

  Future<void> _loadPatientLanguage() async {
    final prefs = _prefs;
    final patient = widget.patientSession.selected;
    if (prefs == null || patient == null) return;
    final id = widget.patientSession.pidOf(patient);
    if (id.isEmpty) return;
    final stored = prefs.getString('interpreter.patient.$id.lang');
    if (stored == null || stored.isEmpty) return;
    if (stored == _patientLang) return;
    if (!mounted) return;
    setState(() {
      _patientLang = stored;
      _resetConversation();
    });
  }

  Future<void> _persistLangs() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_kDoctorLang, _doctorLang);
    await prefs.setString(_kPatientLang, _patientLang);
    await prefs.setBool(_kAutoSpeak, _autoSpeak);
    final patient = widget.patientSession.selected;
    if (patient == null) return;
    final id = widget.patientSession.pidOf(patient);
    if (id.isEmpty) return;
    await prefs.setString('interpreter.patient.$id.lang', _patientLang);
  }

  InterpreterTurn? get _lastForDoctor {
    for (final turn in _turns.reversed) {
      if (!turn.fromDoctor) return turn;
    }
    return null;
  }

  InterpreterTurn? get _lastForPatient {
    for (final turn in _turns.reversed) {
      if (turn.fromDoctor) return turn;
    }
    return null;
  }

  String get _phrasesKey => 'interpreter.phrases.doctor.$_doctorLang';

  void _loadDoctorPhrases() {
    _doctorPhrases = PhraseCounts.fromJson(_prefs?.getString(_phrasesKey));
  }

  /// A language change starts a fresh conversation: old-language turns and
  /// patient phrases would otherwise leak into the new language's panes.
  void _resetConversation() {
    unawaited(_tts.stop());
    _turns.clear();
    _patientPhrases.clear();
    _loadDoctorPhrases();
  }

  Future<void> _setDoctorLang(String code) async {
    if (code == _doctorLang) return;
    setState(() {
      if (code == _patientLang) _patientLang = _doctorLang;
      _doctorLang = code;
      _resetConversation();
    });
    await _persistLangs();
  }

  Future<void> _setPatientLang(String code) async {
    if (code == _patientLang) return;
    setState(() {
      if (code == _doctorLang) _doctorLang = _patientLang;
      _patientLang = code;
      _resetConversation();
    });
    await _persistLangs();
  }

  Future<void> _swapLangs() async {
    AppHaptics.selection();
    setState(() {
      final tmp = _doctorLang;
      _doctorLang = _patientLang;
      _patientLang = tmp;
      _resetConversation();
    });
    await _persistLangs();
  }

  /// Put a phrase in the box for the user to send as-is or edit first.
  void _fillInput(bool fromDoctor, String text) {
    final controller = fromDoctor ? _doctorInput : _patientInput;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    (fromDoctor ? _doctorFocus : _patientFocus).requestFocus();
  }

  void _forgetDoctorPhrase(String text) {
    setState(() => _doctorPhrases.remove(text));
    unawaited(_prefs?.setString(_phrasesKey, _doctorPhrases.toJson()));
  }

  Future<void> _showHistory(bool fromDoctor, AppLocalizations loc) => _pickText(
        fromDoctor,
        loc.interpreterHistory,
        [
          for (final t in _turns.reversed)
            if (t.fromDoctor == fromDoctor) t.original,
        ],
      );

  /// Sheet of [said] lines; the picked one goes into the input box.
  Future<void> _pickText(bool fromDoctor, String title, List<String> said) async {
    if (said.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  title,
                  style: AppFonts.style(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: said.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    title: Text(
                      said[i],
                      textDirection: (fromDoctor ? _doctor : _patient).rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                    ),
                    onTap: () => Navigator.of(ctx).pop(said[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) _fillInput(fromDoctor, picked);
  }

  Future<void> _clearTurns() async {
    AppHaptics.light();
    await _tts.stop();
    setState(_turns.clear);
  }

  Future<void> _submitText({required bool fromDoctor}) async {
    final controller = fromDoctor ? _doctorInput : _patientInput;
    final text = controller.text.trim();
    if (_busy) return;
    if (text.isEmpty) {
      AppSnackBars.info(
        context,
        AppLocalizations.of(context).interpreterTypeHint,
      );
      return;
    }
    controller.clear();
    await _runTurn(text: text, fromDoctor: fromDoctor);
  }

  Future<void> _runTurn({
    required bool fromDoctor,
    required String text,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _partial = '';
    });
    AppHaptics.medium();
    try {
      final source = fromDoctor ? _doctorLang : _patientLang;
      final target = fromDoctor ? _patientLang : _doctorLang;
      final original = text.trim();
      var translated = '';
      var toneChecked = true;
      Object? backendError;
      final cacheKey = fromDoctor
          ? _translationKey(source, target, original)
          : null;
      final cached = cacheKey == null ? null : _translations[cacheKey];
      if (source == target) {
        translated = original;
      } else if (cached != null) {
        translated = cached;
      } else if (targetNeedsRegister(target)) {
        // Politeness matters in this target language: one LLM call translates
        // and keeps the register. Apple has no formality control.
        try {
          translated = await _backendTranslate(
            original,
            sourceLang: source,
            targetLang: target,
            formality: 'formal',
            timeout: const Duration(seconds: 15),
          );
        } catch (e) {
          backendError = e;
          // Offline / service down: an installed Apple pack is better than
          // nothing, but its tone is unchecked. Never prompt a download here.
          translated = await _appleIfInstalled(original, source, target) ?? '';
          toneChecked = false;
        }
      } else {
        // Register-neutral target: Apple on-device is free, fast and offline.
        translated = await _appleOrAsk(original, source, target) ?? '';
        if (translated.isEmpty) {
          try {
            translated = await _backendTranslate(
              original,
              sourceLang: source,
              targetLang: target,
              formality: 'formal',
            );
          } catch (e) {
            backendError = e;
          }
        }
      }
      if (!mounted) return;
      if (translated.isEmpty) {
        throw backendError ??
            Exception(
              AppLocalizations.of(context).interpreterAppleTranslateFailed,
            );
      }
      if (cacheKey != null && cached == null && toneChecked) {
        _rememberTranslation(cacheKey, translated);
      }
      await _commitTurn(
        InterpreterTurn(
          fromDoctor: fromDoctor,
          original: original,
          translated: translated,
          sourceLang: source,
          targetLang: target,
          toneChecked: toneChecked,
        ),
      );
    } on _TurnAborted catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _fillInput(fromDoctor, text.trim());
      final msg = e.message;
      if (msg != null) AppSnackBars.error(context, msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackBars.error(
        context,
        friendlyError(e, AppLocalizations.of(context)),
      );
    }
  }

  String _translationKey(String source, String target, String text) =>
      '$source|$target|${text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';

  void _rememberTranslation(String key, String translated) {
    _translations.remove(key);
    _translations[key] = translated;
    while (_translations.length > _maxTranslations) {
      _translations.remove(_translations.keys.first);
    }
    unawaited(_prefs?.setString(_kTranslations, jsonEncode(_translations)));
  }

  Future<void> _commitTurn(InterpreterTurn turn) async {
    if (!mounted) return;
    setState(() {
      _turns.add(turn);
      _busy = false;
      (turn.fromDoctor ? _doctorPhrases : _patientPhrases).add(turn.original);
    });
    if (turn.fromDoctor) {
      unawaited(_prefs?.setString(_phrasesKey, _doctorPhrases.toJson()));
    }
    AppHaptics.success();
    if (_autoSpeak && turn.translated.isNotEmpty) {
      await _speak(
        turn.translated,
        lang: turn.targetLang,
        announceIfSilent: true,
        // Auto-speak never buys OpenAI audio; it plays it only if cached.
        // The speaker button fetches (and shows "Loading voice…" meanwhile).
        fetchCloud: false,
      );
    }
  }

  /// Backend transcribes (OpenAI) and translates (LLM, formal) in one call.
  Future<void> _runAudioTurn(String path, {required bool fromDoctor}) async {
    if (_busy) return;
    setState(() => _busy = true);
    AppHaptics.medium();
    try {
      final bytes = await XFile(path).readAsBytes();
      unawaited(deleteVoiceRecord(path));
      final source = fromDoctor ? _doctorLang : _patientLang;
      final target = fromDoctor ? _patientLang : _doctorLang;
      final raw = await widget.api
          .interpreterTurnAudio(
            bytes: bytes,
            filename: 'speech.m4a',
            sourceLang: source,
            targetLang: target,
            formality: 'formal',
          )
          .timeout(const Duration(seconds: 60));
      final original = '${raw['original'] ?? ''}'.trim();
      final translated = '${raw['translated'] ?? ''}'.trim();
      if (!mounted) return;
      if (original.isEmpty || translated.isEmpty) {
        throw Exception(
          AppLocalizations.of(context).interpreterAppleTranslateFailed,
        );
      }
      await _commitTurn(
        InterpreterTurn(
          fromDoctor: fromDoctor,
          original: original,
          translated: translated,
          sourceLang: source,
          targetLang: target,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackBars.error(
        context,
        friendlyError(e, AppLocalizations.of(context)),
      );
    }
  }

  Future<String?> _appleTranslate(
    String text,
    String source,
    String target,
  ) async {
    final out = (await AppleTranslate.translate(
      text: text,
      sourceLang: source,
      targetLang: target,
    ))?.trim();
    return (out == null || out.isEmpty) ? null : out;
  }

  Future<String?> _appleIfInstalled(
    String text,
    String source,
    String target,
  ) async {
    try {
      final status = await AppleTranslate.status(
        sourceLang: source,
        targetLang: target,
      );
      if (status != AppleLanguageStatus.installed) return null;
      return await _appleTranslate(text, source, target);
    } on AppleTranslateUnsupported {
      return null;
    } on AppleTranslateNotInstalled {
      return null;
    }
  }

  /// Apple translation, asking before any language-pack download.
  /// Returns null when the caller should use the backend instead; throws
  /// [_TurnAborted] if the user cancels or the download does not finish.
  Future<String?> _appleOrAsk(String text, String source, String target) async {
    try {
      return await _appleTranslate(text, source, target);
    } on AppleTranslateUnsupported {
      return null;
    } on AppleTranslateNotInstalled {
      // Fall through to the install prompt.
    }
    final loc = AppLocalizations.of(context);
    final targetRow = InterpreterLanguage.byCode(_languages, target);
    final choice = await showDialog<_PackChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.interpreterPackTitle(targetRow?.name ?? target)),
        content: Text(loc.interpreterPackBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _PackChoice.cancel),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _PackChoice.online),
            child: Text(loc.interpreterPackOnline),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _PackChoice.download),
            child: Text(loc.interpreterPackDownload),
          ),
        ],
      ),
    );
    switch (choice) {
      case _PackChoice.online:
        return null;
      case _PackChoice.download:
        if (await AppleTranslate.prepare(
          sourceLang: source,
          targetLang: target,
        )) {
          try {
            return await _appleTranslate(text, source, target);
          } on AppleTranslateUnsupported {
            return null;
          } on AppleTranslateNotInstalled {
            // Pack still missing — report below.
          }
        }
        throw _TurnAborted(mounted ? loc.interpreterPackFailed : null);
      case _PackChoice.cancel:
      case null:
        throw const _TurnAborted(null);
    }
  }

  Future<String> _backendTranslate(
    String text, {
    required String sourceLang,
    required String targetLang,
    String? formality,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final raw = await widget.api
        .interpreterTurn(
          text: text,
          sourceLang: sourceLang,
          targetLang: targetLang,
          formality: formality,
        )
        .timeout(timeout);
    return '${raw['translated'] ?? ''}'.trim();
  }

  Future<void> _speak(
    String text, {
    required String lang,
    bool announceIfSilent = false,
    bool fetchCloud = true,
  }) async {
    final spoken = text.trim();
    if (spoken.isEmpty) return;
    // Show Stop right away; the voice lookup below can take a moment.
    if (mounted) {
      setState(() {
        _speaking = spoken;
        _speakingLive = false;
      });
    }
    try {
      await _tts.stop();
      // Nothing to stop shouldn't cancel speaking.
      await _cloudPlayer.stop().catchError((_) {});
      if (!_playbackReady) await _ensureTtsPlayback();
      final b = await _resolveBinding(lang);
      final bound = b.installed;
      if (b.voice case final voice?) {
        final payload = <String, String>{'name': voice['name']!, 'locale': voice['locale']!};
        final id = voice['identifier'];
        if (id != null && id.isNotEmpty) payload['identifier'] = id;
        await _tts.setVoice(payload);
      } else if (bound || !_cloudTts) {
        await _tts.clearVoice();
        await _tts.setLanguage(b.locale!);
      }
      if (!bound && _cloudTts) {
        await _speakCloud(
          spoken,
          lang,
          fetch: fetchCloud,
          announceIfSilent: announceIfSilent && fetchCloud,
        );
        return;
      }
      if (!bound && announceIfSilent) _announceNoVoice();
      final started = await _tts.speak(spoken);
      if (started == 0 || started == false) {
        _doneSpeaking();
        if (announceIfSilent) _announceNoVoice();
      } else {
        // Backup for platforms that never fire the start handler.
        _nowSpeaking();
      }
    } catch (e) {
      _doneSpeaking();
      debugPrint('interpreter tts speak: $e');
      if (announceIfSilent && mounted) {
        AppSnackBars.info(
          context,
          AppLocalizations.of(context).interpreterTtsFailed,
        );
      }
    }
  }

  Future<void> _speakCloud(
    String text,
    String lang, {
    required bool fetch,
    required bool announceIfSilent,
  }) async {
    try {
      final path = await ttsCachePath(_stableHash('$lang\n$text'));
      if (path.isEmpty) throw StateError('no cache dir');
      if (!await audioFileExists(path)) {
        if (!fetch) return _doneSpeaking();
        final bytes = await widget.api.interpreterSpeak(text: text, lang: lang);
        await writeAudioFile(path, bytes);
      }
      await _cloudPlayer.setFilePath(path);
      unawaited(_cloudPlayer.play());
    } catch (e) {
      _doneSpeaking();
      debugPrint('interpreter cloud tts: $e');
      if (announceIfSilent) _announceNoVoice();
    }
  }

  void _announceNoVoice() {
    if (!mounted || _warnedNoVoice) return;
    _warnedNoVoice = true;
    AppSnackBars.info(context, AppLocalizations.of(context).interpreterNoVoice);
  }

  Future<Map<String, String>?> _installedVoice(Iterable<String> locales) async {
    try {
      final voices = _voices ?? await _loadVoices();
      for (final locale in locales) {
        final hit = matchTtsVoice(locale, voices);
        if (hit != null) return hit;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, String>>> _loadVoices() async {
    final raw = await _tts.getVoices;
    final voices = <Map<String, String>>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) {
          final name = '${row['name'] ?? ''}'.trim();
          final loc = '${row['locale'] ?? ''}'.trim();
          if (name.isEmpty || loc.isEmpty) continue;
          final id = '${row['identifier'] ?? ''}'.trim();
          voices.add({
            'name': name,
            'locale': loc,
            if (id.isNotEmpty) 'identifier': id,
          });
        }
      }
    }
    // Empty means "none installed yet": look again next time.
    if (voices.isNotEmpty) _voices = voices;
    return voices;
  }

  Future<bool> _languageInstalled(String locale) async {
    try {
      final ok = await _tts.isLanguageAvailable(locale);
      if (ok == true || ok == 1 || ok == '1') return true;
      final langs = await _tts.getLanguages;
      if (langs is List) {
        return matchSpeechLocale(locale, langs.map((e) => '$e')) != null;
      }
    } catch (_) {}
    return false;
  }

  String? _deviceSpeechLocale(InterpreterLanguage lang) {
    if (!lang.supportsSpeech) return null;
    final hit = matchSpeechLocale(
      lang.speechLocale,
      _speechLocales.map((e) => e.localeId),
    );
    if (hit != null) return hit;
    if (!_speechReady || _speechLocales.isEmpty) return lang.speechLocale;
    return null;
  }

  bool _canHold(bool fromDoctor) {
    if (_busy) return false;
    return (fromDoctor ? _doctor : _patient).supportsSpeech || _cloudStt;
  }

  Future<void> _startRecording(bool fromDoctor, int epoch) async {
    try {
      if (await _recorder.hasPermission() && epoch == _holdEpoch) {
        await _ensureMicCapture();
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 32000,
          ),
          path: await resolveVoiceRecordPath(extension: 'm4a'),
        );
        if (epoch != _holdEpoch) {
          // Released while the recorder was still starting.
          await _recorder.cancel();
          return;
        }
        // Same cap as Apple's listenFor, so a forgotten tap stops on its own.
        _recordCap = Timer(
          const Duration(seconds: 30),
          () => unawaited(_stopHold(fromDoctor)),
        );
        return;
      }
    } catch (e) {
      debugPrint('interpreter record start: $e');
    }
    if (epoch != _holdEpoch || !mounted) return;
    setState(() {
      _listeningDoctor = false;
      _listeningPatient = false;
    });
    AppSnackBars.info(
      context,
      AppLocalizations.of(context).interpreterAllowSpeech,
    );
  }

  void _warmSpeechForSelection() {
    for (final lang in [_doctor, _patient]) {
      if (!lang.supportsSpeech) continue;
      final locale = _deviceSpeechLocale(lang) ?? lang.speechLocale;
      unawaited(AppleTranslate.warmSpeech(locale));
    }
  }

  Future<bool> _listenApple(String locale, int epoch) async {
    if (epoch != _holdEpoch) return false;
    debugPrint('interpreter stt listen locale=$locale');
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty || !mounted) return;
        _partial = words;
      },
      onSoundLevelChange: (level) {
        if (level > _peakSoundLevel) _peakSoundLevel = level;
      },
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        cancelOnError: false,
        onDevice: false,
        autoPunctuation: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 8),
      ),
    );
    return epoch == _holdEpoch &&
        (_speech.isListening || _speechStatus == 'listening');
  }

  Future<void> _startHold(bool fromDoctor, int epoch) async {
    if (epoch != _holdEpoch) return;
    if (_listeningDoctor || _listeningPatient) return;
    final lang = fromDoctor ? _doctor : _patient;
    if (!lang.supportsSpeech && !_cloudStt) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _peakSoundLevel = -120;
    _speechError = null;
    setState(() {
      if (fromDoctor) {
        _listeningDoctor = true;
      } else {
        _listeningPatient = true;
      }
      _partial = '';
    });
    if (!lang.supportsSpeech) {
      await _startRecording(fromDoctor, epoch);
      return;
    }
    try {
      if (!_speechReady) {
        await _initSpeech();
        if (epoch != _holdEpoch) return;
      }
      if (!_speechReady) {
        if (!mounted) return;
        setState(() {
          _listeningDoctor = false;
          _listeningPatient = false;
        });
        AppSnackBars.info(
          context,
          AppLocalizations.of(context).interpreterAllowSpeech,
        );
        return;
      }
      await _ensureMicCapture();
      if (epoch != _holdEpoch) return;
      if (_speechLocales.isEmpty) {
        try {
          _speechLocales = await _speech.locales();
        } catch (_) {}
      }
      final deviceLocale = _deviceSpeechLocale(lang) ?? lang.speechLocale;
      final started = await _listenApple(deviceLocale, epoch);
      if (started) {
        return;
      }
      debugPrint(
        'interpreter stt did not start status=$_speechStatus err=$_speechError',
      );
    } catch (e) {
      debugPrint('interpreter stt listen: $e');
    }
    if (epoch != _holdEpoch) return;
    if (!mounted) return;
    setState(() {
      _listeningDoctor = false;
      _listeningPatient = false;
      _partial = '';
    });
    AppSnackBars.info(
      context,
      AppLocalizations.of(context).interpreterTypeInstead,
    );
  }

  Future<void> _stopHold(bool fromDoctor, {bool cancelled = false}) async {
    _holdEpoch++;
    _pressToStop = false;
    final listening = fromDoctor ? _listeningDoctor : _listeningPatient;
    if (!listening) return;
    _recordCap?.cancel();
    var recording = false;
    try {
      recording = await _recorder.isRecording();
    } catch (_) {}
    if (recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _listeningDoctor = false;
        _listeningPatient = false;
      });
      if (path == null || path.isEmpty) return;
      if (cancelled) {
        unawaited(deleteVoiceRecord(path));
        return;
      }
      await _runAudioTurn(path, fromDoctor: fromDoctor);
      return;
    }
    var spoken = _partial.trim();
    try {
      if (_speech.isListening || _speechStatus == 'listening') {
        _speechIdle = Completer<void>();
        await _speech.stop();
        await _speechIdle!.future.timeout(
          const Duration(milliseconds: 1200),
          onTimeout: () {},
        );
        final after = _partial.trim();
        if (after.isNotEmpty) spoken = after;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _listeningDoctor = false;
      _listeningPatient = false;
      _partial = '';
    });
    if (cancelled) return;
    if (spoken.isNotEmpty) {
      await _runTurn(text: spoken, fromDoctor: fromDoctor);
      return;
    }
    final loc = AppLocalizations.of(context);
    final lang = fromDoctor ? _doctor : _patient;
    debugPrint(
      'interpreter stt empty peak=$_peakSoundLevel status=$_speechStatus err=$_speechError',
    );
    AppSnackBars.info(
      context,
      loc.interpreterNothingHeardLang(lang.nativeName),
    );
  }

  Future<void> _pickLanguage({required bool doctor}) async {
    final loc = AppLocalizations.of(context);
    final selected = await showDialog<InterpreterLanguage>(
      context: context,
      builder: (ctx) => _LanguagePickerDialog(
        languages: _languages,
        title: doctor
            ? loc.interpreterDoctorLanguage
            : loc.interpreterPatientLanguage,
        selectedCode: doctor ? _doctorLang : _patientLang,
      ),
    );
    if (selected == null) return;
    _voices = null;
    _binding.clear();
    if (doctor) {
      await _setDoctorLang(selected.code);
    } else {
      await _setPatientLang(selected.code);
    }
    _warmSpeechForSelection();
    unawaited(_warmBindings());
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final portrait = AppBreakpoints.isPortrait(context);

    return Padding(
      padding: AppBreakpoints.pagePadding(
        context,
        portrait: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.translate_rounded,
            title: loc.navInterpreter,
            subtitle: loc.interpreterSubtitle,
            chromeActions: [
              AppButtons.icon(
                tooltip: loc.interpreterAutoSpeak,
                onPressed: () async {
                  setState(() => _autoSpeak = !_autoSpeak);
                  await _persistLangs();
                },
                icon: _autoSpeak
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: _autoSpeak ? AppColors.dentalBlue : AppColors.muted,
              ),
              AppButtons.icon(
                tooltip: loc.interpreterClear,
                onPressed: _turns.isEmpty ? null : _clearTurns,
                icon: Icons.delete_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _LanguageBar(
            doctor: _doctor,
            patient: _patient,
            doctorLabel: loc.interpreterDoctor,
            patientLabel: loc.interpreterPatient,
            onDoctorTap: () => _pickLanguage(doctor: true),
            onPatientTap: () => _pickLanguage(doctor: false),
            onSwap: _swapLangs,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: portrait
                ? Column(
                    children: [
                      Expanded(child: _buildPane(fromDoctor: true, loc: loc)),
                      const SizedBox(height: 12),
                      Expanded(child: _buildPane(fromDoctor: false, loc: loc)),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildPane(fromDoctor: true, loc: loc)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildPane(fromDoctor: false, loc: loc)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPane({required bool fromDoctor, required AppLocalizations loc}) {
    final lang = fromDoctor ? _doctor : _patient;
    final last = fromDoctor ? _lastForDoctor : _lastForPatient;
    final listening = fromDoctor ? _listeningDoctor : _listeningPatient;
    final controller = fromDoctor ? _doctorInput : _patientInput;
    final canHold = _canHold(fromDoctor);
    final headline = last?.translated.trim() ?? '';
    final pills = (fromDoctor ? _doctorPhrases : _patientPhrases).repeated();
    final hasHistory = _turns.any((t) => t.fromDoctor == fromDoctor);
    final original = last?.original.trim() ?? '';
    final speaking = headline.isNotEmpty && _speaking == headline;
    final dir = lang.rtl ? TextDirection.rtl : TextDirection.ltr;
    final hint = listening
        ? loc.interpreterListening
        : (fromDoctor ? loc.interpreterDoctorHint : loc.interpreterPatientHint);
    final holdLabel = listening
        ? loc.interpreterListening
        : (canHold ? loc.interpreterHoldToTalk : loc.interpreterTypeInstead);
    final muted = AppFonts.style(fontSize: 16, height: 1.4, color: AppColors.muted);

    // One calm reading area: the latest translation, big, with its speaker.
    final Widget reading;
    if (listening) {
      reading = ValueListenableBuilder<String>(
        valueListenable: _partialText,
        builder: (_, partial, _) => partial.isEmpty
            ? Text(hint, textDirection: TextDirection.ltr, style: muted)
            : Text(
                partial,
                style: AppFonts.style(fontSize: 26, fontWeight: FontWeight.w600, height: 1.25, color: AppColors.navy),
              ),
      );
    } else if (headline.isEmpty) {
      reading = Text(hint, textDirection: TextDirection.ltr, style: muted);
    } else {
      reading = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            headline,
            style: AppFonts.style(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.navy),
          ),
          if (original.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(original, style: AppFonts.style(fontSize: 13, height: 1.35, color: AppColors.muted)),
          ],
          if (last != null && !last.toneChecked) ...[
            const SizedBox(height: 8),
            Text(
              loc.interpreterToneUnchecked,
              textDirection: TextDirection.ltr,
              style: AppFonts.style(fontSize: 12, color: AppColors.danger),
            ),
          ],
        ],
      );
    }

    return RepaintBoundary(
      child: AdminCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  fromDoctor ? Icons.medical_services_outlined : Icons.accessibility_new_rounded,
                  size: 18,
                  color: fromDoctor ? AppColors.navy : AppColors.dentalBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${fromDoctor ? loc.interpreterDoctor : loc.interpreterPatient} · ${lang.nativeName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (pills.isNotEmpty)
                  AppButtons.icon(
                    tooltip: loc.tr('interpreter.quickPhrases'),
                    onPressed: _busy || listening
                        ? null
                        : () => _pickText(fromDoctor, loc.tr('interpreter.quickPhrases'), pills.toList()),
                    icon: Icons.bolt_rounded,
                    color: AppColors.navy,
                  ),
                AppButtons.icon(
                  tooltip: loc.interpreterHistory,
                  onPressed: hasHistory ? () => _showHistory(fromDoctor, loc) : null,
                  icon: Icons.history_rounded,
                  color: AppColors.navy,
                ),
                if (headline.isNotEmpty && !listening)
                  _SpeakerButton(
                    key: ValueKey(fromDoctor ? 'interpreter-doctor-speak' : 'interpreter-patient-speak'),
                    state: !speaking
                        ? _Speak.idle
                        : _speakingLive
                            ? _Speak.playing
                            : _Speak.loading,
                    onTap: () => _toggleSpeak(headline, lang.code),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                decoration: BoxDecoration(
                  color: AppColors.inset.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_busy || listening) return;
                          (fromDoctor ? _doctorFocus : _patientFocus).requestFocus();
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Directionality(textDirection: dir, child: reading),
                              ),
                            ),
                            // Starters only before anything is said; later
                            // they sit behind the ⚡ button.
                            if (pills.isNotEmpty && headline.isEmpty && !listening) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 40,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: pills.length,
                                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final phrase = pills[index];
                                    return GestureDetector(
                                      onLongPress: fromDoctor && !_busy ? () => _forgetDoctorPhrase(phrase) : null,
                                      child: Touchable(
                                        onTap: _busy ? null : () => _fillInput(fromDoctor, phrase),
                                        borderRadius: BorderRadius.circular(999),
                                        child: Container(
                                          constraints: const BoxConstraints(maxWidth: 220),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.8),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            phrase,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textDirection: dir,
                                            style: AppFonts.style(fontSize: 12.5, color: AppColors.navy),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Composer: type and send, or hold the mic — one row.
            Row(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => TextField(
                      key: ValueKey(fromDoctor ? 'interpreter-doctor-field' : 'interpreter-patient-field'),
                      controller: controller,
                      focusNode: fromDoctor ? _doctorFocus : _patientFocus,
                      enabled: !_busy && !listening,
                      minLines: 1,
                      maxLines: 3,
                      textDirection: dir,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitText(fromDoctor: fromDoctor),
                      style: AppFonts.style(fontSize: 15, color: AppColors.navy),
                      decoration: InputDecoration(
                        hintText: loc.interpreterTypeHint,
                        hintStyle: AppFonts.style(color: AppColors.muted),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.8),
                        contentPadding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                        suffixIcon: IconButton(
                          key: ValueKey(fromDoctor ? 'interpreter-doctor-send' : 'interpreter-patient-send'),
                          tooltip: loc.interpreterSend,
                          onPressed: _busy ? null : () => _submitText(fromDoctor: fromDoctor),
                          icon: _busy && !listening
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(
                                  Icons.arrow_upward_rounded,
                                  color: controller.text.trim().isEmpty ? AppColors.muted : AppColors.dentalBlue,
                                ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: holdLabel,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      if (_holdPointer != null) return;
                      if (_busy && !listening) return;
                      if (!listening && !canHold) return;
                      _holdPointer = event.pointer;
                      _pointerDownAt = DateTime.now();
                      if (listening) {
                        _pressToStop = true;
                        return;
                      }
                      _pressToStop = false;
                      final epoch = ++_holdEpoch;
                      unawaited(_startHold(fromDoctor, epoch));
                    },
                    onPointerUp: (event) {
                      if (_holdPointer != event.pointer) return;
                      _holdPointer = null;
                      if (_pressToStop) {
                        _pressToStop = false;
                        unawaited(_stopHold(fromDoctor));
                        return;
                      }
                      final down = _pointerDownAt;
                      final held = down == null ? Duration.zero : DateTime.now().difference(down);
                      // Finger-up after a real hold stops. A tap leaves Apple Speech
                      // running until the next tap (the permission sheet also cancels
                      // the pointer and must not abort listen).
                      if (held >= const Duration(milliseconds: 450)) {
                        unawaited(_stopHold(fromDoctor));
                      }
                    },
                    onPointerCancel: (event) {
                      if (_holdPointer != event.pointer) return;
                      _holdPointer = null;
                      _pressToStop = false;
                    },
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: listening ? AppColors.danger : (canHold ? AppColors.navy : AppColors.inset),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                            color: canHold || listening ? Colors.white : AppColors.muted,
                          ),
                          if (canHold || listening) ...[
                            const SizedBox(width: 6),
                            Text(
                              listening ? loc.interpreterListening : loc.tr('interpreter.hold'),
                              style: AppFonts.style(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Speak { idle, loading, playing }

/// Header speaker: plain while idle, a spinner with "Loading voice…" while
/// the voice gets ready (no sound yet), a filled Stop while it plays.
class _SpeakerButton extends StatelessWidget {
  const _SpeakerButton({super.key, required this.state, required this.onTap});

  final _Speak state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final playing = state == _Speak.playing;
    final loading = state == _Speak.loading;
    return Tooltip(
      message: switch (state) {
        _Speak.idle => loc.interpreterSpeak,
        _Speak.loading => loc.tr('interpreter.loadingVoice'),
        _Speak.playing => loc.tr('interpreter.stopSpeaking'),
      },
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        builder: (_, _) => AnimatedContainer(
          duration: AppMotion.fast,
          height: 36,
          margin: const EdgeInsets.only(left: 4),
          padding: EdgeInsets.symmetric(horizontal: loading ? 12 : 8),
          decoration: BoxDecoration(
            color: playing
                ? AppColors.dentalBlue
                : loading
                    ? AppColors.dentalBlue.withValues(alpha: 0.10)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dentalBlue),
                )
              else
                Icon(
                  playing ? Icons.stop_rounded : Icons.volume_up_outlined,
                  size: 22,
                  color: playing ? Colors.white : AppColors.dentalBlue,
                ),
              if (loading) ...[
                const SizedBox(width: 8),
                Text(
                  loc.tr('interpreter.loadingVoice'),
                  style: AppFonts.style(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.dentalBlue),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _PackChoice { download, online, cancel }

class _TurnAborted implements Exception {
  const _TurnAborted(this.message);
  final String? message;
}

class _LanguageBar extends StatelessWidget {
  const _LanguageBar({
    required this.doctor,
    required this.patient,
    required this.doctorLabel,
    required this.patientLabel,
    required this.onDoctorTap,
    required this.onPatientTap,
    required this.onSwap,
  });

  final InterpreterLanguage doctor;
  final InterpreterLanguage patient;
  final String doctorLabel;
  final String patientLabel;
  final VoidCallback onDoctorTap;
  final VoidCallback onPatientTap;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    // Same 14pt gap as the panes below, so each chip lines up with its pane;
    // swap sits on the seam instead of eating width.
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            Expanded(child: _LangChip(prefix: doctorLabel, language: doctor, onTap: onDoctorTap)),
            const SizedBox(width: 14),
            Expanded(child: _LangChip(prefix: patientLabel, language: patient, onTap: onPatientTap, seamLeft: true)),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            boxShadow: NeoShadows.soft(depth: 0.4),
          ),
          child: AppButtons.icon(
            tooltip: AppLocalizations.of(context).interpreterSwap,
            onPressed: onSwap,
            icon: Icons.swap_horiz_rounded,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.prefix,
    required this.language,
    required this.onTap,
    this.seamLeft = false,
  });

  final String prefix;
  final InterpreterLanguage language;
  final VoidCallback onTap;

  /// The swap button overlaps this side.
  final bool seamLeft;

  @override
  Widget build(BuildContext context) {
    return Touchable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: EdgeInsets.fromLTRB(seamLeft ? 32 : 16, 10, seamLeft ? 16 : 32, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AdminCard.radius,
          boxShadow: NeoShadows.raised(depth: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prefix,
                    style: AppFonts.style(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  Text(
                    language.nativeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _LanguagePickerDialog extends StatefulWidget {
  const _LanguagePickerDialog({
    required this.languages,
    required this.title,
    required this.selectedCode,
  });

  final List<InterpreterLanguage> languages;
  final String title;
  final String selectedCode;

  @override
  State<_LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<_LanguagePickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final q = _query.trim().toLowerCase();
    final clinic = <InterpreterLanguage>[];
    final rest = <InterpreterLanguage>[];
    for (final lang in widget.languages) {
      if (q.isNotEmpty) {
        final hay = '${lang.name} ${lang.nativeName} ${lang.code}'
            .toLowerCase();
        if (!hay.contains(q)) continue;
      }
      if (lang.clinic) {
        clinic.add(lang);
      } else {
        rest.add(lang);
      }
    }

    Widget section(String label, List<InterpreterLanguage> rows) {
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
            child: Text(
              label,
              style: AppFonts.style(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
                letterSpacing: 0.3,
              ),
            ),
          ),
          ...rows.map((lang) {
            final selected = lang.code == widget.selectedCode;
            return ListTile(
              onTap: () => Navigator.pop(context, lang),
              selected: selected,
              title: Text(
                lang.nativeName,
                style: AppFonts.style(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
              subtitle: Text(
                lang.name,
                style: AppFonts.style(fontSize: 12, color: AppColors.muted),
              ),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: AppColors.dentalBlue)
                  : null,
            );
          }),
        ],
      );
    }

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.border),
      child: SizedBox(
        width: 460,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppFonts.style(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: loc.interpreterSearchLanguage,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                children: [
                  section(loc.interpreterClinicLanguages, clinic),
                  section(loc.interpreterAllLanguages, rest),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two 32-bit FNV-1a passes (different seeds), hex. Stable across launches
/// (String.hashCode is not) and exact on web, so it can name cache files.
String _stableHash(String value) {
  final bytes = utf8.encode(value);
  String fnv(int h) {
    for (final b in bytes) {
      h ^= b;
      // h * 16777619 mod 2^32, split so it stays exact as a JS double.
      h = (h * 403 + ((h << 24) & 0xffffffff)) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  return fnv(0x811c9dc5) + fnv(0x050c5d1f);
}

import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/touchable.dart';
import '../../core/widgets/ui_kit.dart';
import '../chat/utils/voice_record_path.dart';
import 'interpreter_languages.dart';

class InterpreterTurn {
  const InterpreterTurn({
    required this.fromDoctor,
    required this.original,
    required this.translated,
    required this.sourceLang,
    required this.targetLang,
  });

  final bool fromDoctor;
  final String original;
  final String translated;
  final String sourceLang;
  final String targetLang;
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
  final _recorder = AudioRecorder();

  List<InterpreterLanguage> _languages = List.of(kInterpreterLanguages);
  String _doctorLang = 'de';
  String _patientLang = 'ar';
  bool _autoSpeak = true;
  bool _busy = false;
  bool _speechReady = false;
  bool _cloudStt = false;
  bool _listeningDoctor = false;
  bool _listeningPatient = false;
  String _partial = '';
  final List<InterpreterTurn> _turns = [];
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
      if (_listeningDoctor) unawaited(_stopHold(true, cancelled: true));
      if (_listeningPatient) unawaited(_stopHold(false, cancelled: true));
    }
  }

  @override
  void dispose() {
    widget.patientSession.removeListener(_onPatientSession);
    _doctorInput.dispose();
    _patientInput.dispose();
    _doctorFocus.dispose();
    _patientFocus.dispose();
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    unawaited(_recorder.dispose());
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
    _doctorLang = _prefs?.getString(_kDoctorLang) ??
        (appLang == 'en' ? 'en' : 'de');
    if (_doctorLang != 'de' && _doctorLang != 'en') {
      _doctorLang = 'de';
    }
    _patientLang = _prefs?.getString(_kPatientLang) ?? 'ar';
    _autoSpeak = _prefs?.getBool(_kAutoSpeak) ?? true;
    if (mounted) setState(() {});
    await _loadPatientLanguage();
    await _loadCatalog();
    await _initSpeech();
    await _initTts();
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
      final stt = providers is Map ? '${providers['stt'] ?? ''}' : '';
      if (!mounted) return;
      setState(() {
        if (parsed.length >= 20) _languages = parsed;
        _cloudStt = stt == 'whisper';
      });
    } catch (_) {
      // Local catalog is enough for the picker.
    }
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      if (mounted) setState(() => _speechReady = ok);
    } catch (_) {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setSpeechRate(0.46);
      await _tts.setVolume(1);
    } catch (_) {}
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
    setState(() => _patientLang = stored);
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

  Future<void> _setDoctorLang(String code) async {
    if (code == _patientLang) {
      setState(() {
        _patientLang = _doctorLang;
        _doctorLang = code;
      });
    } else {
      setState(() => _doctorLang = code);
    }
    await _persistLangs();
  }

  Future<void> _setPatientLang(String code) async {
    if (code == _doctorLang) {
      setState(() {
        _doctorLang = _patientLang;
        _patientLang = code;
      });
    } else {
      setState(() => _patientLang = code);
    }
    await _persistLangs();
  }

  Future<void> _swapLangs() async {
    AppHaptics.selection();
    setState(() {
      final tmp = _doctorLang;
      _doctorLang = _patientLang;
      _patientLang = tmp;
    });
    await _persistLangs();
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
    String? text,
    List<int>? audio,
    String filename = 'speech.m4a',
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
      final Map<String, dynamic> raw;
      if (audio != null && audio.isNotEmpty) {
        raw = await widget.api
            .interpreterTurnAudio(
              bytes: audio,
              filename: filename,
              sourceLang: source,
              targetLang: target,
            )
            .timeout(const Duration(seconds: 45));
      } else {
        raw = await widget.api
            .interpreterTurn(
              text: text ?? '',
              sourceLang: source,
              targetLang: target,
            )
            .timeout(const Duration(seconds: 45));
      }
      if (!mounted) return;
      final translated = '${raw['translated'] ?? ''}'.trim();
      if (translated.isEmpty) {
        throw Exception(
          AppLocalizations.of(context).interpreterNothingHeard,
        );
      }
      final turn = InterpreterTurn(
        fromDoctor: fromDoctor,
        original: '${raw['original'] ?? text ?? ''}'.trim(),
        translated: translated,
        sourceLang: '${raw['source_lang'] ?? source}',
        targetLang: '${raw['target_lang'] ?? target}',
      );
      if (!mounted) return;
      setState(() {
        _turns.add(turn);
        _busy = false;
      });
      AppHaptics.success();
      if (_autoSpeak && turn.translated.isNotEmpty) {
        await _speak(turn.translated, turn.targetLang);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackBars.error(context, friendlyError(e, AppLocalizations.of(context)));
    }
  }

  Future<void> _speak(String text, String lang) async {
    final row = InterpreterLanguage.byCode(_languages, lang);
    final locale = row?.speechLocale.isNotEmpty == true
        ? row!.speechLocale.replaceAll('_', '-')
        : lang;
    try {
      await _tts.stop();
      await _tts.setLanguage(locale);
      await _tts.speak(text);
    } catch (_) {}
  }

  bool _canHold(bool fromDoctor) {
    final lang = fromDoctor ? _doctor : _patient;
    if (_busy) return false;
    if (lang.supportsSpeech && _speechReady) return true;
    if (_cloudStt) return true;
    return false;
  }

  Future<void> _startHold(bool fromDoctor) async {
    if (!_canHold(fromDoctor) || _listeningDoctor || _listeningPatient) return;
    AppHaptics.medium();
    final lang = fromDoctor ? _doctor : _patient;
    setState(() {
      if (fromDoctor) {
        _listeningDoctor = true;
      } else {
        _listeningPatient = true;
      }
      _partial = '';
    });
    if (lang.supportsSpeech && _speechReady) {
      try {
        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() => _partial = result.recognizedWords);
          },
          listenOptions: SpeechListenOptions(
            localeId: lang.speechLocale,
            partialResults: true,
            cancelOnError: true,
            listenMode: ListenMode.dictation,
            listenFor: const Duration(seconds: 25),
            pauseFor: const Duration(seconds: 8),
          ),
        );
        return;
      } catch (_) {
        // Fall through to file recording.
      }
    }
    if (!_cloudStt) {
      await _stopHold(fromDoctor, cancelled: true);
      if (!mounted) return;
      AppSnackBars.info(
        context,
        AppLocalizations.of(context).interpreterTypeInstead,
      );
      return;
    }
    try {
      final hasMic = await _recorder.hasPermission();
      if (!hasMic) {
        await _stopHold(fromDoctor, cancelled: true);
        return;
      }
      final encoder = await _recorder.isEncoderSupported(AudioEncoder.aacLc)
          ? AudioEncoder.aacLc
          : AudioEncoder.wav;
      final ext = encoder == AudioEncoder.wav ? 'wav' : 'm4a';
      final path = await resolveVoiceRecordPath(extension: ext);
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
    } catch (_) {
      await _stopHold(fromDoctor, cancelled: true);
    }
  }

  Future<void> _stopHold(bool fromDoctor, {bool cancelled = false}) async {
    final listening = fromDoctor ? _listeningDoctor : _listeningPatient;
    if (!listening) return;
    String spoken = _partial.trim();
    List<int>? audio;
    String filename = 'speech.m4a';
    try {
      if (_speech.isListening) {
        await _speech.stop();
        await Future<void>.delayed(const Duration(milliseconds: 180));
        spoken = _partial.trim();
      }
      if (await _recorder.isRecording()) {
        final path = await _recorder.stop();
        if (path != null && path.isNotEmpty) {
          audio = await XFile(path).readAsBytes();
          filename = path.split('/').last;
        }
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
    if (audio != null && audio.isNotEmpty) {
      await _runTurn(audio: audio, filename: filename, fromDoctor: fromDoctor);
      return;
    }
    AppSnackBars.info(
      context,
      AppLocalizations.of(context).interpreterNothingHeard,
    );
  }

  Future<void> _pickLanguage({required bool doctor}) async {
    final loc = AppLocalizations.of(context);
    final selected = await showDialog<InterpreterLanguage>(
      context: context,
      builder: (ctx) => _LanguagePickerDialog(
        languages: _languages,
        title: doctor ? loc.interpreterDoctorLanguage : loc.interpreterPatientLanguage,
        selectedCode: doctor ? _doctorLang : _patientLang,
      ),
    );
    if (selected == null) return;
    if (doctor) {
      await _setDoctorLang(selected.code);
    } else {
      await _setPatientLang(selected.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final portrait = AppBreakpoints.isPortrait(context);
    final patients = widget.patientSession.patients;
    final selected = widget.patientSession.selected;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        portrait ? 16 : 28,
        portrait ? 16 : 24,
        portrait ? 16 : 28,
        portrait ? 16 : 24,
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
            actions: [
              PatientPickerButton(
                patients: patients,
                selected: selected,
                onSelect: widget.patientSession.select,
                onAdd: widget.patientSession.requestNavigateToNewPatient,
                onRefresh: () => widget.patientSession.refresh(keepSelection: true),
                emptyHint: loc.interpreterPatientOptional,
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

  Widget _buildPane({
    required bool fromDoctor,
    required AppLocalizations loc,
  }) {
    final lang = fromDoctor ? _doctor : _patient;
    final last = fromDoctor ? _lastForDoctor : _lastForPatient;
    final listening = fromDoctor ? _listeningDoctor : _listeningPatient;
    final controller = fromDoctor ? _doctorInput : _patientInput;
    final canHold = _canHold(fromDoctor);
    final headline = last?.translated.trim() ?? '';
    final original = last?.original.trim() ?? '';
    final hint = fromDoctor
        ? loc.interpreterDoctorHint
        : loc.interpreterPatientHint;
    final holdLabel = listening
        ? loc.interpreterListening
        : (canHold ? loc.interpreterHoldToTalk : loc.interpreterTypeInstead);

    return GlassSurface(
      borderRadius: AppRadii.border,
      blur: 18,
      tint: Colors.white.withValues(alpha: 0.62),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                fromDoctor
                    ? Icons.medical_services_outlined
                    : Icons.accessibility_new_rounded,
                size: 18,
                color: fromDoctor ? AppColors.navy : AppColors.dentalBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fromDoctor
                      ? '${loc.interpreterDoctor} · ${lang.nativeName}'
                      : '${loc.interpreterPatient} · ${lang.nativeName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (headline.isNotEmpty)
                AppButtons.icon(
                  tooltip: loc.interpreterSpeak,
                  onPressed: () => _speak(headline, lang.code),
                  icon: Icons.volume_up_outlined,
                  color: AppColors.dentalBlue,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.inset.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Directionality(
                        textDirection: lang.rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: listening && _partial.isNotEmpty
                            ? Text(
                                _partial,
                                style: AppFonts.style(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                  color: AppColors.navy,
                                ),
                              )
                            : headline.isEmpty
                                ? Text(
                                    hint,
                                    textDirection: TextDirection.ltr,
                                    style: AppFonts.style(
                                      fontSize: 16,
                                      height: 1.4,
                                      color: AppColors.muted,
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        headline,
                                        style: AppFonts.style(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w700,
                                          height: 1.25,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                      if (original.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          original,
                                          style: AppFonts.style(
                                            fontSize: 13,
                                            height: 1.35,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                      ),
                    ),
                  ),
                  if (_turns.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _turns.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final turn = _turns[index];
                          final mine = turn.fromDoctor == fromDoctor;
                          final label = mine ? turn.original : turn.translated;
                          return Container(
                            constraints: const BoxConstraints(maxWidth: 220),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? AppColors.navy.withValues(alpha: 0.08)
                                  : AppColors.dentalBlue.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(
                                fontSize: 12,
                                color: AppColors.navy,
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey(
                    fromDoctor
                        ? 'interpreter-doctor-field'
                        : 'interpreter-patient-field',
                  ),
                  controller: controller,
                  focusNode: fromDoctor ? _doctorFocus : _patientFocus,
                  enabled: !_busy && !listening,
                  minLines: 1,
                  maxLines: 3,
                  textDirection:
                      lang.rtl ? TextDirection.rtl : TextDirection.ltr,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitText(fromDoctor: fromDoctor),
                  style: AppFonts.style(fontSize: 15, color: AppColors.navy),
                  decoration: InputDecoration(
                    hintText: loc.interpreterTypeHint,
                    hintStyle: AppFonts.style(color: AppColors.muted),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.8),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.8),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppButtons.primary(
                key: ValueKey(
                  fromDoctor
                      ? 'interpreter-doctor-send'
                      : 'interpreter-patient-send',
                ),
                compact: true,
                busy: _busy && !listening,
                onPressed:
                    _busy ? null : () => _submitText(fromDoctor: fromDoctor),
                icon: Icons.send_rounded,
                label: loc.interpreterSend,
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              (fromDoctor ? _doctorFocus : _patientFocus).requestFocus();
            },
            onLongPressStart: (_) => _startHold(fromDoctor),
            onLongPressEnd: (_) => _stopHold(fromDoctor),
            onLongPressCancel: () =>
                _stopHold(fromDoctor, cancelled: true),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: listening
                    ? AppColors.danger
                    : (canHold ? AppColors.navy : AppColors.inset),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: canHold || listening
                        ? Colors.white
                        : AppColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      holdLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: canHold || listening
                            ? Colors.white
                            : AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    return Row(
      children: [
        Expanded(
          child: _LangChip(
            prefix: doctorLabel,
            language: doctor,
            onTap: onDoctorTap,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: AppButtons.icon(
            tooltip: AppLocalizations.of(context).interpreterSwap,
            onPressed: onSwap,
            icon: Icons.swap_horiz_rounded,
            color: AppColors.navy,
          ),
        ),
        Expanded(
          child: _LangChip(
            prefix: patientLabel,
            language: patient,
            onTap: onPatientTap,
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
  });

  final String prefix;
  final InterpreterLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Touchable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
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
                      fontSize: 15,
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
        final hay =
            '${lang.name} ${lang.nativeName} ${lang.code}'.toLowerCase();
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

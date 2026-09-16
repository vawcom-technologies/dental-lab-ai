/// Spoken languages for the chairside interpreter (not app UI locales).
class InterpreterLanguage {
  const InterpreterLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.rtl,
    required this.clinic,
    required this.speechLocale,
  });

  final String code;
  final String name;
  final String nativeName;
  final bool rtl;
  final bool clinic;
  final String speechLocale;

  bool get supportsSpeech => speechLocale.isNotEmpty;

  /// Locales to try for TTS, most specific first (`ar_SA` → `ar-SA` → `ar`).
  List<String> get ttsLocales {
    final out = <String>[];
    void add(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return;
      final dash = s.replaceAll('_', '-');
      if (!out.contains(dash)) out.add(dash);
    }

    add(speechLocale);
    add(code);
    switch (code) {
      case 'ar':
        add('ar-SA');
        add('ar-EG');
        add('ar-AE');
        break;
      case 'en':
        add('en-US');
        add('en-GB');
        break;
      case 'de':
        add('de-DE');
        add('de-AT');
        break;
      case 'zh':
        add('zh-CN');
        add('zh-Hans');
        add('zh-TW');
        break;
    }
    return out;
  }

  String get pickerLabel => nativeName == name ? name : '$name · $nativeName';

  factory InterpreterLanguage.fromJson(Map<String, dynamic> json) {
    return InterpreterLanguage(
      code: '${json['code'] ?? ''}'.trim().toLowerCase(),
      name: '${json['name'] ?? ''}'.trim(),
      nativeName: '${json['native'] ?? json['nativeName'] ?? ''}'.trim(),
      rtl: json['rtl'] == true,
      clinic: json['clinic'] == true,
      speechLocale: '${json['speech'] ?? ''}'.trim(),
    );
  }

  static InterpreterLanguage? byCode(
    Iterable<InterpreterLanguage> all,
    String code,
  ) {
    final key = code.trim().toLowerCase();
    for (final lang in all) {
      if (lang.code == key) return lang;
    }
    return null;
  }

  /// BCP-47 for iOS TTS (`ar-SA`). Speech locales in this catalog use `_`.
  String get ttsLocale {
    final raw = speechLocale.trim();
    if (raw.isEmpty) return code;
    return raw.replaceAll('_', '-');
  }
}

String _normLocale(String value) =>
    value.trim().replaceAll('-', '_').toLowerCase();

/// Pick a device speech-recognition locale that matches [wanted]
/// (`ar_SA`, `ar-SA`, or a language prefix like `ar`).
String? matchSpeechLocale(String wanted, Iterable<String> available) {
  final needle = _normLocale(wanted);
  if (needle.isEmpty) return null;
  final prefix = needle.split('_').first;
  String? prefixHit;
  for (final raw in available) {
    final id = _normLocale(raw);
    if (id == needle) return raw;
    if (prefixHit == null && (id == prefix || id.startsWith('${prefix}_'))) {
      prefixHit = raw;
    }
  }
  return prefixHit;
}

/// Pick an installed TTS voice whose locale matches [wanted] (`ar-SA`).
Map<String, String>? matchTtsVoice(
  String wanted,
  Iterable<Map<String, String>> voices,
) {
  final needle = _normLocale(wanted);
  if (needle.isEmpty) return null;
  final prefix = needle.split('_').first;
  Map<String, String>? prefixHit;
  for (final voice in voices) {
    final locale = _normLocale(voice['locale'] ?? '');
    if (locale.isEmpty) continue;
    if (locale == needle) return voice;
    if (prefixHit == null &&
        (locale == prefix || locale.startsWith('${prefix}_'))) {
      prefixHit = voice;
    }
  }
  return prefixHit;
}

/// Offline fallback — same clinic-first order as the API.
const kInterpreterLanguages = <InterpreterLanguage>[
  InterpreterLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية', rtl: true, clinic: true, speechLocale: 'ar_SA'),
  InterpreterLanguage(code: 'ku', name: 'Kurdish (Kurmanji)', nativeName: 'Kurdî', rtl: true, clinic: true, speechLocale: ''),
  InterpreterLanguage(code: 'ckb', name: 'Kurdish (Sorani)', nativeName: 'کوردی', rtl: true, clinic: true, speechLocale: ''),
  InterpreterLanguage(code: 'tr', name: 'Turkish', nativeName: 'Türkçe', rtl: false, clinic: true, speechLocale: 'tr_TR'),
  InterpreterLanguage(code: 'fa', name: 'Persian', nativeName: 'فارسی', rtl: true, clinic: true, speechLocale: 'fa_IR'),
  InterpreterLanguage(code: 'en', name: 'English', nativeName: 'English', rtl: false, clinic: true, speechLocale: 'en_US'),
  InterpreterLanguage(code: 'de', name: 'German', nativeName: 'Deutsch', rtl: false, clinic: true, speechLocale: 'de_DE'),
  InterpreterLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский', rtl: false, clinic: true, speechLocale: 'ru_RU'),
  InterpreterLanguage(code: 'uk', name: 'Ukrainian', nativeName: 'Українська', rtl: false, clinic: true, speechLocale: 'uk_UA'),
  InterpreterLanguage(code: 'pl', name: 'Polish', nativeName: 'Polski', rtl: false, clinic: true, speechLocale: 'pl_PL'),
  InterpreterLanguage(code: 'ro', name: 'Romanian', nativeName: 'Română', rtl: false, clinic: true, speechLocale: 'ro_RO'),
  InterpreterLanguage(code: 'bg', name: 'Bulgarian', nativeName: 'Български', rtl: false, clinic: true, speechLocale: 'bg_BG'),
  InterpreterLanguage(code: 'sq', name: 'Albanian', nativeName: 'Shqip', rtl: false, clinic: true, speechLocale: 'sq_AL'),
  InterpreterLanguage(code: 'sr', name: 'Serbian', nativeName: 'Српски', rtl: false, clinic: true, speechLocale: 'sr_RS'),
  InterpreterLanguage(code: 'hr', name: 'Croatian', nativeName: 'Hrvatski', rtl: false, clinic: true, speechLocale: 'hr_HR'),
  InterpreterLanguage(code: 'bs', name: 'Bosnian', nativeName: 'Bosanski', rtl: false, clinic: true, speechLocale: 'bs_BA'),
  InterpreterLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano', rtl: false, clinic: true, speechLocale: 'it_IT'),
  InterpreterLanguage(code: 'fr', name: 'French', nativeName: 'Français', rtl: false, clinic: true, speechLocale: 'fr_FR'),
  InterpreterLanguage(code: 'es', name: 'Spanish', nativeName: 'Español', rtl: false, clinic: true, speechLocale: 'es_ES'),
  InterpreterLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português', rtl: false, clinic: true, speechLocale: 'pt_PT'),
  InterpreterLanguage(code: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt', rtl: false, clinic: true, speechLocale: 'vi_VN'),
  InterpreterLanguage(code: 'zh', name: 'Chinese', nativeName: '中文', rtl: false, clinic: true, speechLocale: 'zh_CN'),
  InterpreterLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', rtl: false, clinic: true, speechLocale: 'hi_IN'),
  InterpreterLanguage(code: 'ur', name: 'Urdu', nativeName: 'اردو', rtl: true, clinic: true, speechLocale: 'ur_PK'),
  InterpreterLanguage(code: 'so', name: 'Somali', nativeName: 'Soomaali', rtl: false, clinic: true, speechLocale: ''),
  InterpreterLanguage(code: 'ps', name: 'Pashto', nativeName: 'پښتو', rtl: true, clinic: true, speechLocale: ''),
  InterpreterLanguage(code: 'am', name: 'Amharic', nativeName: 'አማርኛ', rtl: false, clinic: true, speechLocale: ''),
  InterpreterLanguage(code: 'ti', name: 'Tigrinya', nativeName: 'ትግርኛ', rtl: false, clinic: true, speechLocale: ''),
  InterpreterLanguage(code: 'af', name: 'Afrikaans', nativeName: 'Afrikaans', rtl: false, clinic: false, speechLocale: 'af_ZA'),
  InterpreterLanguage(code: 'az', name: 'Azerbaijani', nativeName: 'Azərbaycan', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'be', name: 'Belarusian', nativeName: 'Беларуская', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'bn', name: 'Bengali', nativeName: 'বাংলা', rtl: false, clinic: false, speechLocale: 'bn_BD'),
  InterpreterLanguage(code: 'ca', name: 'Catalan', nativeName: 'Català', rtl: false, clinic: false, speechLocale: 'ca_ES'),
  InterpreterLanguage(code: 'cs', name: 'Czech', nativeName: 'Čeština', rtl: false, clinic: false, speechLocale: 'cs_CZ'),
  InterpreterLanguage(code: 'cy', name: 'Welsh', nativeName: 'Cymraeg', rtl: false, clinic: false, speechLocale: 'cy_GB'),
  InterpreterLanguage(code: 'da', name: 'Danish', nativeName: 'Dansk', rtl: false, clinic: false, speechLocale: 'da_DK'),
  InterpreterLanguage(code: 'el', name: 'Greek', nativeName: 'Ελληνικά', rtl: false, clinic: false, speechLocale: 'el_GR'),
  InterpreterLanguage(code: 'et', name: 'Estonian', nativeName: 'Eesti', rtl: false, clinic: false, speechLocale: 'et_EE'),
  InterpreterLanguage(code: 'eu', name: 'Basque', nativeName: 'Euskara', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'fi', name: 'Finnish', nativeName: 'Suomi', rtl: false, clinic: false, speechLocale: 'fi_FI'),
  InterpreterLanguage(code: 'ga', name: 'Irish', nativeName: 'Gaeilge', rtl: false, clinic: false, speechLocale: 'ga_IE'),
  InterpreterLanguage(code: 'gl', name: 'Galician', nativeName: 'Galego', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી', rtl: false, clinic: false, speechLocale: 'gu_IN'),
  InterpreterLanguage(code: 'ha', name: 'Hausa', nativeName: 'Hausa', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'he', name: 'Hebrew', nativeName: 'עברית', rtl: true, clinic: false, speechLocale: 'he_IL'),
  InterpreterLanguage(code: 'hu', name: 'Hungarian', nativeName: 'Magyar', rtl: false, clinic: false, speechLocale: 'hu_HU'),
  InterpreterLanguage(code: 'hy', name: 'Armenian', nativeName: 'Հայերեն', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'id', name: 'Indonesian', nativeName: 'Bahasa Indonesia', rtl: false, clinic: false, speechLocale: 'id_ID'),
  InterpreterLanguage(code: 'ig', name: 'Igbo', nativeName: 'Igbo', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'is', name: 'Icelandic', nativeName: 'Íslenska', rtl: false, clinic: false, speechLocale: 'is_IS'),
  InterpreterLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語', rtl: false, clinic: false, speechLocale: 'ja_JP'),
  InterpreterLanguage(code: 'ka', name: 'Georgian', nativeName: 'ქართული', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'kk', name: 'Kazakh', nativeName: 'Қазақ', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'km', name: 'Khmer', nativeName: 'ខ្មែរ', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ', rtl: false, clinic: false, speechLocale: 'kn_IN'),
  InterpreterLanguage(code: 'ko', name: 'Korean', nativeName: '한국어', rtl: false, clinic: false, speechLocale: 'ko_KR'),
  InterpreterLanguage(code: 'lo', name: 'Lao', nativeName: 'ລາວ', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'lt', name: 'Lithuanian', nativeName: 'Lietuvių', rtl: false, clinic: false, speechLocale: 'lt_LT'),
  InterpreterLanguage(code: 'lv', name: 'Latvian', nativeName: 'Latviešu', rtl: false, clinic: false, speechLocale: 'lv_LV'),
  InterpreterLanguage(code: 'mk', name: 'Macedonian', nativeName: 'Македонски', rtl: false, clinic: false, speechLocale: 'mk_MK'),
  InterpreterLanguage(code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം', rtl: false, clinic: false, speechLocale: 'ml_IN'),
  InterpreterLanguage(code: 'mn', name: 'Mongolian', nativeName: 'Монгол', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'mr', name: 'Marathi', nativeName: 'मराठी', rtl: false, clinic: false, speechLocale: 'mr_IN'),
  InterpreterLanguage(code: 'ms', name: 'Malay', nativeName: 'Bahasa Melayu', rtl: false, clinic: false, speechLocale: 'ms_MY'),
  InterpreterLanguage(code: 'mt', name: 'Maltese', nativeName: 'Malti', rtl: false, clinic: false, speechLocale: 'mt_MT'),
  InterpreterLanguage(code: 'my', name: 'Burmese', nativeName: 'မြန်မာ', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'nb', name: 'Norwegian', nativeName: 'Norsk', rtl: false, clinic: false, speechLocale: 'nb_NO'),
  InterpreterLanguage(code: 'ne', name: 'Nepali', nativeName: 'नेपाली', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'nl', name: 'Dutch', nativeName: 'Nederlands', rtl: false, clinic: false, speechLocale: 'nl_NL'),
  InterpreterLanguage(code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ', rtl: false, clinic: false, speechLocale: 'pa_IN'),
  InterpreterLanguage(code: 'sk', name: 'Slovak', nativeName: 'Slovenčina', rtl: false, clinic: false, speechLocale: 'sk_SK'),
  InterpreterLanguage(code: 'sl', name: 'Slovenian', nativeName: 'Slovenščina', rtl: false, clinic: false, speechLocale: 'sl_SI'),
  InterpreterLanguage(code: 'sv', name: 'Swedish', nativeName: 'Svenska', rtl: false, clinic: false, speechLocale: 'sv_SE'),
  InterpreterLanguage(code: 'sw', name: 'Swahili', nativeName: 'Kiswahili', rtl: false, clinic: false, speechLocale: 'sw_KE'),
  InterpreterLanguage(code: 'ta', name: 'Tamil', nativeName: 'தமிழ்', rtl: false, clinic: false, speechLocale: 'ta_IN'),
  InterpreterLanguage(code: 'te', name: 'Telugu', nativeName: 'తెలుగు', rtl: false, clinic: false, speechLocale: 'te_IN'),
  InterpreterLanguage(code: 'th', name: 'Thai', nativeName: 'ไทย', rtl: false, clinic: false, speechLocale: 'th_TH'),
  InterpreterLanguage(code: 'tl', name: 'Filipino', nativeName: 'Filipino', rtl: false, clinic: false, speechLocale: 'fil_PH'),
  InterpreterLanguage(code: 'uz', name: 'Uzbek', nativeName: 'Oʻzbek', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'yo', name: 'Yoruba', nativeName: 'Yorùbá', rtl: false, clinic: false, speechLocale: ''),
  InterpreterLanguage(code: 'zu', name: 'Zulu', nativeName: 'isiZulu', rtl: false, clinic: false, speechLocale: 'zu_ZA'),
];

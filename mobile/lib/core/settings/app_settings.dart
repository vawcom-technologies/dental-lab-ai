import 'package:shared_preferences/shared_preferences.dart';

/// Local dentist preferences (device-scoped). Profile stays on the server.
class AppSettings {
  AppSettings._();

  static const _kNotifyMessages = 'settings_notify_messages';
  static const _kNotifyCaseStatus = 'settings_notify_case_status';
  static const _kNotifyScanQuality = 'settings_notify_scan_quality';
  static const _kLanguage = 'settings_language';
  static const _kAutoShade = 'settings_auto_shade';
  static const _kAutoScanQuality = 'settings_auto_scan_quality';
  static const _kAutoScanBody = 'settings_auto_scan_body';

  bool notifyMessages = true;
  bool notifyCaseStatus = true;
  bool notifyScanQuality = true;

  /// `en` | `de`
  String language = 'en';
  bool autoShade = true;
  bool autoScanQuality = true;
  bool autoScanBody = true;

  /// Master notifications switch — keeps the three category flags in sync.
  bool get notificationsEnabled =>
      notifyMessages && notifyCaseStatus && notifyScanQuality;

  set notificationsEnabled(bool value) {
    notifyMessages = value;
    notifyCaseStatus = value;
    notifyScanQuality = value;
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppSettings._();
    s.notifyMessages = prefs.getBool(_kNotifyMessages) ?? true;
    s.notifyCaseStatus = prefs.getBool(_kNotifyCaseStatus) ?? true;
    s.notifyScanQuality = prefs.getBool(_kNotifyScanQuality) ?? true;
    s.language = prefs.getString(_kLanguage) ?? 'en';
    s.autoShade = prefs.getBool(_kAutoShade) ?? true;
    s.autoScanQuality = prefs.getBool(_kAutoScanQuality) ?? true;
    s.autoScanBody = prefs.getBool(_kAutoScanBody) ?? true;
    return s;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifyMessages, notifyMessages);
    await prefs.setBool(_kNotifyCaseStatus, notifyCaseStatus);
    await prefs.setBool(_kNotifyScanQuality, notifyScanQuality);
    await prefs.setString(_kLanguage, language);
    await prefs.setBool(_kAutoShade, autoShade);
    await prefs.setBool(_kAutoScanQuality, autoScanQuality);
    await prefs.setBool(_kAutoScanBody, autoScanBody);
  }
}

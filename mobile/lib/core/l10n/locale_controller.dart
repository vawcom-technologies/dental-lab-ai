import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide locale. Changing language notifies listeners so MaterialApp rebuilds.
class LocaleController extends ChangeNotifier {
  static const prefsKey = 'settings_language';

  String _code = 'en';

  String get code => _code;
  Locale get locale => Locale(_code);
  bool get isGerman => _code == 'de';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _code = prefs.getString(prefsKey) ?? 'en';
    if (_code != 'en' && _code != 'de') _code = 'en';
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    final next = (code == 'de') ? 'de' : 'en';
    if (next == _code) return;
    _code = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, next);
    notifyListeners();
  }
}

class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'LocaleScope not found in widget tree');
    return scope!.notifier!;
  }

  static LocaleController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.notifier;
  }
}

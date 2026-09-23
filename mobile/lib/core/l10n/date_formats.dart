import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Locale used by [DateFormat] (matches the in-app language).
String appIntlLocale(BuildContext context) {
  final loc = Localizations.localeOf(context);
  return loc.languageCode == 'de' ? 'de' : 'en';
}

DateFormat appDateFormat(BuildContext context, String pattern) {
  final code = appIntlLocale(context);
  return DateFormat(code == 'de' ? _germanDatePattern(pattern) : pattern, code);
}

/// Clinic screens used US-style patterns; map them so DE shows 23. Sep.
String _germanDatePattern(String pattern) {
  return switch (pattern) {
    'MMM d, yyyy' => 'd. MMM y',
    'MMM d' => 'd. MMM',
    'EEE, MMM d' => 'EEE, d. MMM',
    'EEE, MMM d, yyyy' => 'EEE, d. MMM y',
    'EEEE, MMM d' => 'EEEE, d. MMM',
    'EEEE, MMMM d' => 'EEEE, d. MMMM',
    _ => pattern,
  };
}

String formatAppDate(BuildContext context, DateTime dt, String pattern) {
  return appDateFormat(context, pattern).format(dt);
}

/// 24-hour clock in German, 12-hour in English.
String formatAppTime(BuildContext context, DateTime dt) {
  final code = appIntlLocale(context);
  return DateFormat(code == 'de' ? 'HH:mm' : 'h:mm a', code).format(dt);
}

String formatAppDateTime(BuildContext context, DateTime dt) {
  final code = appIntlLocale(context);
  return DateFormat(
    code == 'de' ? 'd. MMM y, HH:mm' : 'MMM d, yyyy, h:mm a',
    code,
  ).format(dt);
}

List<String> appMonthNames(BuildContext context, {required bool short}) {
  final symbols = DateFormat.MMMM(appIntlLocale(context)).dateSymbols;
  return short ? symbols.SHORTMONTHS : symbols.MONTHS;
}

List<String> appWeekdayShort(BuildContext context) {
  final symbols = DateFormat.E(appIntlLocale(context)).dateSymbols;
  // dateSymbols.SHORTWEEKDAYS is Sun-first; clinic calendar is Monday-first.
  final sunFirst = symbols.SHORTWEEKDAYS;
  if (sunFirst.length < 7) {
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  }
  return [
    sunFirst[1],
    sunFirst[2],
    sunFirst[3],
    sunFirst[4],
    sunFirst[5],
    sunFirst[6],
    sunFirst[0],
  ];
}

import '../l10n/app_localizations.dart';

/// App roles: only [dentist] and [laboratory].
class AppRoles {
  AppRoles._();

  static const dentist = 'dentist';
  static const laboratory = 'laboratory';

  /// Human-readable label for UI chips/badges.
  static String label(String? role, [AppLocalizations? loc]) {
    final r = role?.trim().toLowerCase() ?? '';
    switch (r) {
      case dentist:
      case 'admin': // legacy
        return loc?.roleDentist ?? 'Dentist';
      case laboratory:
      case 'clinic': // legacy
      case 'lab': // legacy
        return loc?.roleLaboratory ?? 'Laboratory';
      default:
        return role?.trim() ?? '';
    }
  }

  static bool isDentist(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    return r == dentist || r == 'admin';
  }

  static bool isLaboratory(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    return r == laboratory || r == 'clinic' || r == 'lab';
  }
}

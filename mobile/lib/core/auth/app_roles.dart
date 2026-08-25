import '../l10n/app_localizations.dart';

/// App roles: [dentist], [laboratory], and [admin].
class AppRoles {
  AppRoles._();

  static const dentist = 'dentist';
  static const laboratory = 'laboratory';
  static const admin = 'admin';

  /// Human-readable label for UI chips/badges.
  static String label(String? role, [AppLocalizations? loc]) {
    final r = role?.trim().toLowerCase() ?? '';
    switch (r) {
      case admin:
        return loc?.roleAdmin ?? 'Admin';
      case dentist:
        return loc?.roleDentist ?? 'Dentist';
      case laboratory:
      case 'clinic': // legacy
      case 'lab': // legacy
        return loc?.roleLaboratory ?? 'Laboratory';
      default:
        return role?.trim() ?? '';
    }
  }

  static bool isAdmin(String? role) {
    return (role?.trim().toLowerCase() ?? '') == admin;
  }

  static bool isDentist(String? role) {
    return (role?.trim().toLowerCase() ?? '') == dentist;
  }

  static bool isLaboratory(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    return r == laboratory || r == 'clinic' || r == 'lab';
  }
}

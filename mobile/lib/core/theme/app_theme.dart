import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Elite Dent Pro — soft neumorphic tokens (navy + dental blue).
class AppColors {
  static const navy = Color(0xFF1D3557);
  static const dentalBlue = Color(0xFF4A90E2);
  static const aiPurple = Color(0xFF8B7CF6);
  static const aiPurpleSoft = Color(0xFFF3F0FF);

  /// Soft clinical canvas (neumorphic base).
  static const surface = Color(0xFFE4EBF4);
  static const surfaceDeep = Color(0xFFD8E2EE);
  static const neo = Color(0xFFEAF0F7);
  static const card = Color(0xFFEEF3F9);
  static const inset = Color(0xFFDDE5F0);

  static const text = Color(0xFF1D3557);
  static const muted = Color(0xFF6B7C93);
  static const border = Color(0xFFD0DBE8);
  static const success = Color(0xFF1F9D63);
  static const successSoft = Color(0xFFE8F8F0);
  static const warning = Color(0xFFE09B2D);
  static const warningSoft = Color(0xFFFFF5E6);
  static const danger = Color(0xFFE05252);
  static const dangerSoft = Color(0xFFFDECEC);
  static const review = Color(0xFF8B7CF6);
  static const reviewSoft = Color(0xFFF3F0FF);
  static const sidebarBg = Color(0xFFEAF0F7);
  static const sidebarActive = Color(0xFFE0EAF6);

  // Backward-compatible aliases
  static const primary = navy;
  static const accent = dentalBlue;
  static const silver = Color(0xFFA8B0BD);
}

class AppRadii {
  static const r = 18.0;
  static const rSm = 14.0;
  static const rLg = 24.0;
  static BorderRadius get border => BorderRadius.circular(r);
  static BorderRadius get borderSm => BorderRadius.circular(rSm);
  static BorderRadius get borderLg => BorderRadius.circular(rLg);
}

/// Soft dual-tone shadows for raised / pressed neumorphic surfaces.
class NeoShadows {
  static List<BoxShadow> raised({double depth = 1}) {
    final d = depth.clamp(0.5, 1.6);
    return [
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.85),
        offset: Offset(-5 * d, -5 * d),
        blurRadius: 10 * d,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: const Color(0xFF9AADC4).withValues(alpha: 0.42),
        offset: Offset(6 * d, 6 * d),
        blurRadius: 14 * d,
        spreadRadius: 0,
      ),
    ];
  }

  static List<BoxShadow> soft({double depth = 0.7}) => raised(depth: depth);

  static List<BoxShadow> pressed() => [
        BoxShadow(
          color: const Color(0xFF9AADC4).withValues(alpha: 0.35),
          offset: const Offset(2, 2),
          blurRadius: 6,
          spreadRadius: -1,
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.55),
          offset: const Offset(-2, -2),
          blurRadius: 5,
          spreadRadius: -1,
        ),
      ];
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.dentalBlue,
        primary: AppColors.navy,
        secondary: AppColors.dentalBlue,
        surface: AppColors.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: AppRadii.borderSm,
      borderSide: BorderSide.none,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.neo,
        foregroundColor: AppColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.borderSm),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          backgroundColor: AppColors.neo,
          side: BorderSide.none,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.borderSm),
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.dentalBlue,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inset,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.muted, fontSize: 14),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.muted,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.dentalBlue,
          fontWeight: FontWeight.w600,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.borderSm,
          borderSide: const BorderSide(color: AppColors.dentalBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.borderSm,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.borderSm,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.border),
      ),
      dividerColor: AppColors.border.withValues(alpha: 0.7),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.border),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(AppColors.card),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: AppRadii.borderSm),
          ),
        ),
      ),
    );
  }
}

class StatusStyle {
  final String label;
  final Color fg;
  final Color bg;

  const StatusStyle(this.label, this.fg, this.bg);

  static StatusStyle of(String key) {
    switch (key) {
      case 'in_progress':
        return const StatusStyle('In Progress', AppColors.dentalBlue, Color(0xFFEAF3FC));
      case 'pending':
      case 'awaiting_scan':
        return const StatusStyle('Awaiting Scan', AppColors.warning, AppColors.warningSoft);
      case 'in_review':
        return const StatusStyle('In Review', AppColors.review, AppColors.reviewSoft);
      case 'completed':
      case 'complete':
        return const StatusStyle('Complete', AppColors.success, AppColors.successSoft);
      case 'rejected':
        return const StatusStyle('Rejected', AppColors.danger, AppColors.dangerSoft);
      case 'none':
      case 'no_case':
        return const StatusStyle('No case', AppColors.muted, Color(0xFFE8EDF4));
      default:
        return StatusStyle(key, AppColors.muted, AppColors.surface);
    }
  }
}

/// Canonical Elite Dent case workflow statuses (matches backend).
class CaseStatuses {
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const inReview = 'in_review';
  static const completed = 'completed';
  static const rejected = 'rejected';

  static const all = <String>[
    pending,
    inProgress,
    inReview,
    completed,
    rejected,
  ];

  /// Filter chips shown on Patients (excludes raw aliases).
  static const filters = <({String key, String label})>[
    (key: 'all', label: 'All'),
    (key: pending, label: 'Awaiting Scan'),
    (key: inProgress, label: 'In Progress'),
    (key: inReview, label: 'In Review'),
    (key: completed, label: 'Complete'),
    (key: rejected, label: 'Rejected'),
  ];

  static String normalize(String? raw) {
    final s = (raw ?? pending).trim().toLowerCase();
    if (s == 'awaiting_scan') return pending;
    if (s == 'complete') return completed;
    if (all.contains(s)) return s;
    return pending;
  }

  static bool matchesFilter(String? status, String filter) {
    if (filter == 'all') return true;
    return normalize(status) == normalize(filter);
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// DentalLab Pro Edition tokens (from Figma Make samples).
class AppColors {
  static const navy = Color(0xFF1D3557);
  static const dentalBlue = Color(0xFF4A90E2);
  static const aiPurple = Color(0xFF8B7CF6);
  static const aiPurpleSoft = Color(0xFFF3F0FF);
  static const surface = Color(0xFFF4F6F9);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF1D3557);
  static const muted = Color(0xFF6B7C93);
  static const border = Color(0xFFE4E9F0);
  static const success = Color(0xFF1F9D63);
  static const successSoft = Color(0xFFE8F8F0);
  static const warning = Color(0xFFE09B2D);
  static const warningSoft = Color(0xFFFFF5E6);
  static const danger = Color(0xFFE05252);
  static const dangerSoft = Color(0xFFFDECEC);
  static const review = Color(0xFF8B7CF6);
  static const reviewSoft = Color(0xFFF3F0FF);
  static const sidebarBg = Color(0xFFFFFFFF);
  static const sidebarActive = Color(0xFFEAF3FC);

  // Backward-compatible aliases
  static const primary = navy;
  static const accent = dentalBlue;
  static const silver = Color(0xFFA8B0BD);
}

class AppRadii {
  static const r = 14.0;
  static BorderRadius get border => BorderRadius.circular(r);
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

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.border),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: AppColors.muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: AppRadii.border,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.border,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.border,
          borderSide: const BorderSide(color: AppColors.dentalBlue, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.border,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerColor: AppColors.border,
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
      case 'awaiting_scan':
        return const StatusStyle('Awaiting Scan', AppColors.warning, AppColors.warningSoft);
      case 'in_review':
        return const StatusStyle('In Review', AppColors.review, AppColors.reviewSoft);
      case 'complete':
        return const StatusStyle('Complete', AppColors.success, AppColors.successSoft);
      case 'rejected':
        return const StatusStyle('Rejected', AppColors.danger, AppColors.dangerSoft);
      default:
        return StatusStyle(key, AppColors.muted, AppColors.surface);
    }
  }
}

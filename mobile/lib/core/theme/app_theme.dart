import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// Single typeface for the whole iPad app (SF Pro on Apple platforms).
class AppFonts {
  AppFonts._();

  /// SF Pro on Apple; `null` elsewhere so Flutter uses the platform default.
  static String? get family {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return '.SF Pro Text';
      default:
        return null;
    }
  }

  static TextStyle style({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
    );
  }

  static TextTheme textTheme(TextTheme base) {
    TextStyle adapt(TextStyle? style, {FontWeight? weight}) {
      final s = style ?? const TextStyle();
      return s.copyWith(
        fontFamily: family,
        fontWeight: weight ?? s.fontWeight,
        color: s.color ?? AppColors.text,
      );
    }

    return base.copyWith(
      displayLarge: adapt(base.displayLarge, weight: FontWeight.w700),
      displayMedium: adapt(base.displayMedium, weight: FontWeight.w700),
      displaySmall: adapt(base.displaySmall, weight: FontWeight.w700),
      headlineLarge: adapt(base.headlineLarge, weight: FontWeight.w700),
      headlineMedium: adapt(base.headlineMedium, weight: FontWeight.w700),
      headlineSmall: adapt(base.headlineSmall, weight: FontWeight.w600),
      titleLarge: adapt(base.titleLarge, weight: FontWeight.w700),
      titleMedium: adapt(base.titleMedium, weight: FontWeight.w600),
      titleSmall: adapt(base.titleSmall, weight: FontWeight.w600),
      bodyLarge: adapt(base.bodyLarge, weight: FontWeight.w400),
      bodyMedium: adapt(base.bodyMedium, weight: FontWeight.w400),
      bodySmall: adapt(base.bodySmall, weight: FontWeight.w400),
      labelLarge: adapt(base.labelLarge, weight: FontWeight.w600),
      labelMedium: adapt(base.labelMedium, weight: FontWeight.w600),
      labelSmall: adapt(base.labelSmall, weight: FontWeight.w600),
    );
  }
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
  /// Cupertino theme matching Material colors + SF Pro.
  static CupertinoThemeData cupertino() {
    final textStyle = AppFonts.style(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      color: AppColors.text,
    );
    return CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.dentalBlue,
      primaryContrastingColor: Colors.white,
      barBackgroundColor: AppColors.neo.withValues(alpha: 0.94),
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: CupertinoTextThemeData(
        primaryColor: AppColors.dentalBlue,
        textStyle: textStyle,
        actionTextStyle: AppFonts.style(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.dentalBlue,
        ),
        navLargeTitleTextStyle: AppFonts.style(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          letterSpacing: -0.5,
        ),
        navTitleTextStyle: AppFonts.style(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
        navActionTextStyle: AppFonts.style(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: AppColors.dentalBlue,
        ),
        pickerTextStyle: AppFonts.style(
          fontSize: 21,
          fontWeight: FontWeight.w400,
          color: AppColors.text,
        ),
        dateTimePickerTextStyle: AppFonts.style(
          fontSize: 21,
          fontWeight: FontWeight.w400,
          color: AppColors.text,
        ),
        tabLabelTextStyle: AppFonts.style(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.muted,
        ),
      ),
    );
  }

  static ThemeData light() {
    // iPad-first: always use iOS Material adaptations (scrollbars, etc.).
    final base = ThemeData(
      useMaterial3: true,
      platform: TargetPlatform.iOS,
      fontFamily: AppFonts.family,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.dentalBlue,
        primary: AppColors.navy,
        secondary: AppColors.dentalBlue,
        surface: AppColors.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );

    final textTheme = AppFonts.textTheme(base.textTheme);

    final fieldBorder = OutlineInputBorder(
      borderRadius: AppRadii.borderSm,
      borderSide: BorderSide.none,
    );

    const cupertinoTransitions = PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    );

    return base.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      // iOS feel: no Material ink ripples
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: AppColors.dentalBlue.withValues(alpha: 0.06),
      focusColor: AppColors.dentalBlue.withValues(alpha: 0.10),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      cupertinoOverrideTheme: cupertino(),
      pageTransitionsTheme: cupertinoTransitions,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.neo,
        foregroundColor: AppColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppFonts.style(
          color: AppColors.navy,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppFonts.style(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          backgroundColor: AppColors.neo.withValues(alpha: 0.85),
          disabledForegroundColor: AppColors.muted,
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.85)),
          elevation: 0,
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppFonts.style(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.dentalBlue,
          disabledForegroundColor: AppColors.muted,
          minimumSize: const Size(44, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: AppFonts.style(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          foregroundColor: AppColors.navy,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 10,
        minLeadingWidth: 40,
        horizontalTitleGap: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        iconColor: AppColors.muted,
        dense: true,
        titleTextStyle: AppFonts.style(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: AppColors.text,
        ),
        subtitleTextStyle: AppFonts.style(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.muted,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: AppFonts.style(
          color: AppColors.text,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inset,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppFonts.style(color: AppColors.muted, fontSize: 16),
        labelStyle: AppFonts.style(
          color: AppColors.muted,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
        floatingLabelStyle: AppFonts.style(
          color: AppColors.dentalBlue,
          fontWeight: FontWeight.w600,
          fontSize: 14,
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
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: AppFonts.style(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
        contentTextStyle: AppFonts.style(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.text,
          height: 1.35,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: AppFonts.style(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(AppColors.card),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        splashRadius: 0,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
        showDuration: Duration(seconds: 2),
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
        return const StatusStyle(
          'In Progress',
          AppColors.dentalBlue,
          Color(0xFFEAF3FC),
        );
      case 'pending':
      case 'awaiting_scan':
        return const StatusStyle(
          'Awaiting Scan',
          AppColors.warning,
          AppColors.warningSoft,
        );
      case 'in_review':
        return const StatusStyle(
          'In Review',
          AppColors.review,
          AppColors.reviewSoft,
        );
      case 'completed':
      case 'complete':
        return const StatusStyle(
          'Complete',
          AppColors.success,
          AppColors.successSoft,
        );
      case 'rejected':
        return const StatusStyle(
          'Rejected',
          AppColors.danger,
          AppColors.dangerSoft,
        );
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

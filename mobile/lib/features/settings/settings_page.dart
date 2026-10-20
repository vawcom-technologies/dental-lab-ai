import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/auth/session_coordinator.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/ui_kit.dart';
import 'change_password_screen.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/widgets/page_kit.dart';
import '../lab/dentist_lab_settings.dart';
import '../lab/lab_page.dart';

const _kHairline = Color(0xFFC6C6C8);

/// Glassy iPadOS Settings with full account deletion.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings? _settings;
  bool _loading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
    });
    try {
      final settings = await AppSettings.load();
      if (mounted) {
        settings.language = LocaleScope.of(context).code;
      }
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackBars.error(context, friendlyError(e));
    }
  }

  Future<void> _persist(void Function(AppSettings s) mutate) async {
    final s = _settings;
    if (s == null) return;
    mutate(s);
    setState(() {
      _settings = s;
    });
    await s.save();
    if (!mounted) return;
    AppSnackBars.success(
      context,
      AppLocalizations.of(context).preferenceSaved,
    );
  }

  Future<void> _setLanguage(String code) async {
    await LocaleScope.of(context).setLanguage(code);
    await _persist((x) => x.language = code);
  }

  void _signOut() {
    SessionCoordinator.signOut(widget.api);
  }

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final loc = AppLocalizations.of(context);

    // Require typing DELETE before any further steps.
    final typed = await AppDialogs.prompt(
      context,
      title: loc.settingsDeleteAccount,
      message: loc.settingsDeleteAccountBody,
      placeholder: loc.settingsDeleteConfirmToken,
      cancelLabel: loc.cancel,
      confirmLabel: loc.settingsContinue,
      confirmEquals: loc.settingsDeleteConfirmToken,
    );
    if (typed == null || !mounted) return;

    final password = await AppDialogs.prompt(
      context,
      title: loc.settingsConfirmWithPassword,
      message: loc.settingsEnterPasswordToFinish,
      placeholder: loc.password,
      obscureText: true,
      cancelLabel: loc.cancel,
      confirmLabel: loc.settingsDeleteAccount,
    );
    if (password == null || !mounted) return;
    if (password.trim().isEmpty) {
      AppSnackBars.error(context, loc.settingsPasswordRequired);
      return;
    }

    setState(() => _deleting = true);
    try {
      final message = await AppDialogs.runWithLoading(
        context,
        message: loc.settingsDeletingAccount,
        action: () => widget.api.deleteAccount(password: password),
      );
      if (!mounted) return;
      SessionCoordinator.signOut(widget.api, message: message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppSnackBars.error(
        context,
        friendlyError(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (_loading) {
      return Center(
        child: ToothPageLoader(message: loc.settingsLoading),
      );
    }
    final s = _settings;
    if (s == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loc.settingsLoadError,
              style: AppFonts.style(
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _bootstrap,
              child: Text(loc.refresh),
            ),
          ],
        ),
      );
    }

    final api = widget.api;
    final name = (api.userName ?? '').trim().isEmpty
        ? loc.settingsAccountFallback
        : api.userName!.trim();
    final email = (api.email ?? '').trim();
    final clinic = (api.clinicName ?? '').trim();
    final role = AppRoles.label(api.role, loc);

    return BusyBarrier(
      busy: _deleting,
      message: loc.settingsDeletingAccount,
      child: CustomScrollView(
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: AppBreakpoints.pagePadding(context).copyWith(bottom: 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const PhoneMenuButton(),
                  Expanded(
                    child: Text(
                      loc.settingsTitle,
                      style: AppFonts.style(
                        fontSize: AppBreakpoints.isPhone(context) ? 28 : 34,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                  ),
                  AppButtons.glass(
                    icon: Icons.logout_rounded,
                    label: loc.signOut,
                    onPressed: _deleting ? null : _signOut,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: AppBreakpoints.pagePadding(context).copyWith(top: 8, bottom: 36),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.crossAxisExtent >= 900;
                final profile = _GlassProfileHero(
                  name: name,
                  email: email,
                  clinic: clinic,
                  role: role,
                  lab: widget.api.isDentist ? (widget.api.labName ?? '') : '',
                );
                final account = _GlassSettingsGroup(
                  footer: loc.securitySub,
                  children: [
                    _GlassNavRow(
                      icon: CupertinoIcons.lock_fill,
                      iconBg: const Color(0xFF8E8E93),
                      title: loc.updatePassword,
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoutes.cupertino(
                            ChangePasswordScreen(api: api),
                            title: loc.updatePassword,
                          ),
                        );
                      },
                    ),
                    Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 58),
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                    _GlassNavRow(
                      icon: CupertinoIcons.person_crop_circle_badge_minus,
                      iconBg: const Color(0xFFAEAEB2),
                      title: loc.settingsDeleteAccount,
                      titleColor: AppColors.muted,
                      showChevron: false,
                      onTap: _deleting ? null : _deleteAccount,
                    ),
                  ],
                );
                final ai = _GlassSettingsGroup(
                  header: loc.settingsAiTitle.toUpperCase(),
                  footer: loc.settingsAiSub,
                  children: [
                    _GlassToggleRow(
                      icon: CupertinoIcons.sparkles,
                      iconBg: AppColors.aiPurple,
                      title: loc.settingsAutoShade,
                      subtitle: loc.settingsAutoShadeSub,
                      value: s.autoShade,
                      onChanged: (v) => _persist((x) => x.autoShade = v),
                      showDivider: true,
                    ),
                    _GlassToggleRow(
                      icon: CupertinoIcons.checkmark_seal_fill,
                      iconBg: AppColors.dentalBlue,
                      title: loc.settingsAutoQuality,
                      subtitle: loc.settingsAutoQualitySub,
                      value: s.autoScanQuality,
                      onChanged: (v) =>
                          _persist((x) => x.autoScanQuality = v),
                      showDivider: false,
                    ),
                    // Scan body parked — restore when needed.
                    // _GlassToggleRow(
                    //   icon: CupertinoIcons.circle_grid_3x3_fill,
                    //   iconBg: const Color(0xFF34C759),
                    //   title: loc.settingsAutoScanBody,
                    //   subtitle: loc.settingsAutoScanBodySub,
                    //   value: s.autoScanBody,
                    //   onChanged: (v) => _persist((x) => x.autoScanBody = v),
                    //   showDivider: false,
                    // ),
                  ],
                );
                final notify = _GlassSettingsGroup(
                  header: loc.settingsNotificationsTitle.toUpperCase(),
                  footer: loc.settingsNotificationsSub,
                  children: [
                    _GlassToggleRow(
                      icon: CupertinoIcons.bell_fill,
                      iconBg: AppColors.danger,
                      title: loc.settingsNotifyMaster,
                      subtitle: loc.settingsNotifyMasterSub,
                      value: s.notificationsEnabled,
                      onChanged: (v) =>
                          _persist((x) => x.notificationsEnabled = v),
                      showDivider: false,
                    ),
                  ],
                );
                final language = _GlassSettingsGroup(
                  header: loc.settingsLanguageTitle.toUpperCase(),
                  footer: loc.settingsLanguageSub,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            loc.settingsAppLanguage,
                            style: AppFonts.style(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 10),
                          CupertinoSlidingSegmentedControl<String>(
                            groupValue: s.language == 'de' ? 'de' : 'en',
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.35),
                            thumbColor: Colors.white.withValues(alpha: 0.92),
                            children: {
                              'en': Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(loc.languageEnglish),
                              ),
                              'de': Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(loc.languageGerman),
                              ),
                            },
                            onValueChanged: (code) {
                              if (code == null) return;
                              _setLanguage(code);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final about = _GlassSettingsGroup(
                  children: [
                    _GlassNavRow(
                      icon: CupertinoIcons.info_circle_fill,
                      iconBg: AppColors.dentalBlue,
                      title: loc.aboutTitle,
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoutes.cupertino(
                            AboutPage(api: api),
                            title: loc.aboutTitle,
                          ),
                        );
                      },
                    ),
                  ],
                );
                final labId = api.userId ?? '';
                final labVisibility = api.isLaboratory && labId.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8),
                            child: Text(
                              loc.tr('lab.tab.settings').toUpperCase(),
                              style: AppFonts.style(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          LabVisibilitySettings(api: api, labId: labId),
                        ],
                      )
                    : null;
                final dentistLab = api.isDentist
                    ? DentistLabSettings(api: api)
                    : null;
                if (!wide) {
                  return SliverList(
                    delegate: SliverChildListDelegate([
                      profile,
                      const SizedBox(height: 20),
                      account,
                      if (dentistLab != null) ...[
                        const SizedBox(height: 20),
                        dentistLab,
                      ],
                      if (labVisibility != null) ...[
                        const SizedBox(height: 20),
                        labVisibility,
                      ],
                      const SizedBox(height: 20),
                      ai,
                      const SizedBox(height: 20),
                      notify,
                      const SizedBox(height: 20),
                      language,
                      const SizedBox(height: 20),
                      about,
                    ]),
                  );
                }

                return SliverToBoxAdapter(
                  child: Column(
                    children: [
                      profile,
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                account,
                                if (dentistLab != null) ...[
                                  const SizedBox(height: 20),
                                  dentistLab,
                                ],
                                if (labVisibility != null) ...[
                                  const SizedBox(height: 20),
                                  labVisibility,
                                ],
                                const SizedBox(height: 20),
                                notify,
                                const SizedBox(height: 20),
                                language,
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              children: [
                                ai,
                                const SizedBox(height: 20),
                                about,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// About Elite Dent: intro, features, website links and account details.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.api});

  final ApiClient api;

  static Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    Widget section(String title, String body) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppFonts.style(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: AppFonts.style(
                fontSize: 15,
                color: const Color(0xFF6B7C93),
                height: 1.4,
              ),
            ),
          ],
        );
    Widget divider() => Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 58),
          color: Colors.black.withValues(alpha: 0.08),
        );
    List<Widget> divided(List<Widget> rows) => [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) divider(),
            rows[i],
          ],
        ];
    Widget feature(IconData icon, Color bg, String key) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _GlassIcon(icon: icon, bg: bg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.tr('about.f.$key'),
                      style: AppFonts.style(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc.tr('about.f.${key}Sub'),
                      style: AppFonts.style(
                        fontSize: 13,
                        color: const Color(0xFF6B7C93),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    Widget link(IconData icon, String title, String url) => _GlassNavRow(
          icon: icon,
          iconBg: AppColors.dentalBlue,
          title: title,
          onTap: () => _open(url),
        );
    Widget info(String label, String? value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: CopyableText(
                  (value ?? '').trim().isEmpty ? '—' : value!.trim(),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  style: AppFonts.style(
                    fontSize: 15,
                    color: const Color(0xFF6B7C93),
                  ),
                ),
              ),
            ],
          ),
        );

    final what = section(loc.aboutWhatTitle, loc.aboutWhatBody);
    final who = section(loc.aboutWhoTitle, loc.aboutWhoBody);
    final intro = AdminCard(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandLogo(height: 64, width: 150),
                const SizedBox(width: 28),
                Expanded(child: what),
                const SizedBox(width: 28),
                Expanded(child: who),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLogo(height: 56)),
                const SizedBox(height: 20),
                what,
                const SizedBox(height: 18),
                who,
              ],
            ),
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: true,
        title: Text(loc.aboutTitle),
      ),
      body: ListView(
        padding: AppBreakpoints.pagePadding(context).copyWith(top: 8, bottom: 36),
        children: [
          intro,
          const SizedBox(height: 28),
          _GlassSettingsGroup(
            header: loc.aboutFeaturesTitle.toUpperCase(),
            children: divided([
              feature(CupertinoIcons.sparkles, AppColors.aiPurple, 'shade'),
              feature(CupertinoIcons.checkmark_seal_fill, AppColors.dentalBlue,
                  'scans'),
              feature(CupertinoIcons.person_2_fill, const Color(0xFF34C759),
                  'patients'),
              feature(CupertinoIcons.chat_bubble_2_fill, const Color(0xFFFF9500),
                  'messages'),
              feature(CupertinoIcons.globe, const Color(0xFF5AC8FA),
                  'interpreter'),
            ]),
          ),
          const SizedBox(height: 28),
          _GlassSettingsGroup(
            header: loc.aboutLinksTitle.toUpperCase(),
            children: divided([
              link(CupertinoIcons.house_fill, loc.aboutWebsite,
                  'https://www.elite-d.de'),
              link(CupertinoIcons.question_circle_fill, loc.aboutSupport,
                  'https://www.elite-d.de/support'),
              link(CupertinoIcons.lock_shield_fill, loc.aboutPrivacy,
                  'https://www.elite-d.de/privacy/'),
              link(CupertinoIcons.doc_text_fill, loc.aboutImprint,
                  'https://www.elite-d.de/impressum'),
            ]),
          ),
          const SizedBox(height: 28),
          _GlassSettingsGroup(
            header: loc.aboutAccountTitle.toUpperCase(),
            children: [
              info(loc.aboutName, api.userName),
              info(loc.email, api.email),
              info(loc.aboutClinic, api.clinicName),
              if (api.isDentist) info(loc.tr('admin.lab'), api.labName),
              info(loc.role, AppRoles.label(api.role, loc)),
              info(loc.aboutUserId, api.userId),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _open('https://www.vawcom.com/'),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text.rich(
                  TextSpan(
                    text: '${loc.aboutCredit} ',
                    children: [
                      TextSpan(
                        text: 'VAWCOM',
                        style: AppFonts.style(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dentalBlue,
                        ),
                      ),
                    ],
                  ),
                  style: AppFonts.style(
                    fontSize: 13,
                    color: const Color(0xFF6C6C70),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassProfileHero extends StatelessWidget {
  const _GlassProfileHero({
    required this.name,
    required this.email,
    required this.clinic,
    required this.role,
    this.lab = '',
  });

  final String name;
  final String email;
  final String clinic;
  final String role;

  /// Dentists: their lab, shown as "Lab · Clinic".
  final String lab;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final subtitle = [
      if (role.isNotEmpty) role,
      if (lab.isNotEmpty) lab,
      if (clinic.isNotEmpty) clinic,
    ].join(' · ');

    return AdminCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.dentalBlue.withValues(alpha: 0.9),
                  AppColors.navy,
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
            child: Text(
              initial,
              style: AppFonts.style(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: AppBreakpoints.isPhone(context) ? 18 : 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    letterSpacing: -0.3,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 15,
                      color: const Color(0xFF6B7C93),
                    ),
                  ),
                ],
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dentalBlue,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassSettingsGroup extends StatelessWidget {
  const _GlassSettingsGroup({
    required this.children,
    this.header,
    this.footer,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              header!,
              style: AppFonts.style(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6C6C70),
                letterSpacing: -0.08,
              ),
            ),
          ),
        ],
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
        if (footer != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              footer!,
              style: AppFonts.style(
                fontSize: 13,
                color: const Color(0xFF6C6C70),
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GlassNavRow extends StatelessWidget {
  const _GlassNavRow({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.onTap,
    this.titleColor,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final Color? titleColor;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _GlassIcon(icon: icon, bg: iconBg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.style(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: titleColor ?? AppColors.navy,
                  ),
                ),
              ),
              if (showChevron)
                const Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: Color(0xFFC7C7CC),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassToggleRow extends StatelessWidget {
  const _GlassToggleRow({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.showDivider,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              _GlassIcon(icon: icon, bg: iconBg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppFonts.style(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppFonts.style(
                        fontSize: 13,
                        color: const Color(0xFF6B7C93),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CupertinoSwitch(
                value: value,
                activeTrackColor: AppColors.dentalBlue,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 58),
            child: Divider(height: 0.5, thickness: 0.5, color: _kHairline),
          ),
      ],
    );
  }
}

class _GlassIcon extends StatelessWidget {
  const _GlassIcon({required this.icon, required this.bg});

  final IconData icon;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 17, color: Colors.white),
    );
  }
}

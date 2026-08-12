import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/auth/session_coordinator.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'change_password_screen.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
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
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _persist(void Function(AppSettings s) mutate) async {
    final s = _settings;
    if (s == null) return;
    mutate(s);
    setState(() {
      _settings = s;
      _error = null;
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
      title: 'Delete account',
      message:
          'This permanently removes your account and associated data. '
          'Type DELETE to continue.',
      placeholder: 'DELETE',
      cancelLabel: loc.cancel,
      confirmLabel: 'Continue',
      confirmEquals: 'DELETE',
    );
    if (typed == null || !mounted) return;

    final password = await AppDialogs.prompt(
      context,
      title: 'Confirm with password',
      message: 'Enter your account password to finish.',
      placeholder: 'Password',
      obscureText: true,
      cancelLabel: loc.cancel,
      confirmLabel: 'Delete account',
    );
    if (password == null || !mounted) return;
    if (password.trim().isEmpty) {
      AppSnackBars.error(context, 'Password is required.');
      return;
    }

    setState(() => _deleting = true);
    try {
      final message = await AppDialogs.runWithLoading(
        context,
        message: 'Deleting account…',
        action: () => widget.api.deleteAccount(password: password),
      );
      if (!mounted) return;
      SessionCoordinator.signOut(widget.api, message: message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppSnackBars.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: ToothPageLoader(message: 'Loading settings…'),
      );
    }
    final s = _settings;
    if (s == null) {
      return Center(
        child: Text(
          _error ?? AppLocalizations.of(context).settingsLoadError,
          style: const TextStyle(color: AppColors.danger),
        ),
      );
    }

    final loc = AppLocalizations.of(context);
    final api = widget.api;
    final name = (api.userName ?? '').trim().isEmpty
        ? 'Account'
        : api.userName!.trim();
    final email = (api.email ?? '').trim();
    final clinic = (api.clinicName ?? '').trim();
    final role = AppRoles.label(api.role);

    return BusyBarrier(
      busy: _deleting,
      message: 'Deleting account…',
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      loc.settingsTitle,
                      style: AppFonts.style(
                        fontSize: 34,
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
          if (_error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  _error!,
                  style: AppFonts.style(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 36),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.crossAxisExtent >= 900;
                final profile = _GlassProfileHero(
                  name: name,
                  email: email,
                  clinic: clinic,
                  role: role,
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
                      title: 'Delete account',
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
                      showDivider: true,
                    ),
                    _GlassToggleRow(
                      icon: CupertinoIcons.circle_grid_3x3_fill,
                      iconBg: const Color(0xFF34C759),
                      title: loc.settingsAutoScanBody,
                      subtitle: loc.settingsAutoScanBodySub,
                      value: s.autoScanBody,
                      onChanged: (v) => _persist((x) => x.autoScanBody = v),
                      showDivider: false,
                    ),
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
                if (!wide) {
                  return SliverList(
                    delegate: SliverChildListDelegate([
                      profile,
                      const SizedBox(height: 20),
                      account,
                      const SizedBox(height: 20),
                      ai,
                      const SizedBox(height: 20),
                      notify,
                      const SizedBox(height: 20),
                      language,
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
                                const SizedBox(height: 20),
                                notify,
                                const SizedBox(height: 20),
                                language,
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: ai),
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

class _GlassProfileHero extends StatelessWidget {
  const _GlassProfileHero({
    required this.name,
    required this.email,
    required this.clinic,
    required this.role,
  });

  final String name;
  final String email;
  final String clinic;
  final String role;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final subtitle = [
      if (role.isNotEmpty) role,
      if (clinic.isNotEmpty) clinic,
    ].join(' · ');

    return GlassSurface(
      borderRadius: BorderRadius.circular(18),
      blur: 22,
      tint: Colors.white.withValues(alpha: 0.48),
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
                  style: AppFonts.style(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    letterSpacing: -0.3,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    email,
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
        GlassSurface(
          borderRadius: BorderRadius.circular(14),
          blur: 20,
          tint: Colors.white.withValues(alpha: 0.5),
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

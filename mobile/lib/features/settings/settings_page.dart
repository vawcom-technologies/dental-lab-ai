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
import '../admin/admin_signups_page.dart';
import '../lab/lab_page.dart';

const _kHairline = Color(0xFFC6C6C8);

/// Glassy iPadOS Settings with full account deletion.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api, this.tab, this.active = true});

  final ApiClient api;

  /// Selected section, owned by the shell so other pages can deep-link.
  final ValueNotifier<int>? tab;
  final bool active;

  /// Section index of the admin reject list, for deep links.
  static final rejectListTab = _Section.rejectList.index;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings? _settings;
  bool _loading = true;
  bool _deleting = false;

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
  void initState() {
    super.initState();
    _bootstrap();
    widget.tab?.addListener(_onDeepLink);
  }

  @override
  void dispose() {
    widget.tab?.removeListener(_onDeepLink);
    super.dispose();
  }

  /// Dashboard / top bar asked for a section; on narrow screens push it.
  void _onDeepLink() {
    final i = widget.tab!.value;
    if (_split || i <= 0 || i >= _Section.values.length) return;
    final section = _Section.values[i];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sections().contains(section)) _push(section);
    });
  }

  /// Wide enough for list + detail side by side.
  bool _split = false;

  ValueNotifier<int> get _tab => widget.tab ?? _ownTab;
  late final _ownTab = ValueNotifier(0);

  List<_Section> _sections() {
    final api = widget.api;
    return [
      _Section.account,
      if (api.isDentist || (api.isLaboratory && (api.userId ?? '').isNotEmpty)) _Section.lab,
      // Auto-analysis is chairside dentist work.
      if (api.isDentist) _Section.ai,
      _Section.notifications,
      _Section.language,
      if (api.isAdmin) _Section.rejectList,
      _Section.about,
    ];
  }

  (IconData, Color, String, String?) _meta(AppLocalizations loc, _Section s) => switch (s) {
        _Section.account => (CupertinoIcons.person_crop_circle_fill, AppColors.dentalBlue, loc.tr('settings.sec.account'), loc.securitySub),
        _Section.lab => (
            CupertinoIcons.building_2_fill,
            AppColors.navy,
            widget.api.isLaboratory ? loc.tr('lab.tab.settings') : loc.tr('settings.sec.myLab'),
            null,
          ),
        _Section.ai => (CupertinoIcons.sparkles, AppColors.aiPurple, loc.settingsAiTitle, loc.settingsAiSub),
        _Section.notifications => (CupertinoIcons.bell_fill, AppColors.danger, loc.settingsNotificationsTitle, loc.settingsNotificationsSub),
        _Section.language => (CupertinoIcons.globe, const Color(0xFF5AC8FA), loc.settingsLanguageTitle, loc.settingsLanguageSub),
        _Section.rejectList => (CupertinoIcons.nosign, AppColors.review, loc.tr('admin.rejectList'), loc.tr('settings.sec.rejectSub')),
        _Section.about => (CupertinoIcons.info_circle_fill, AppColors.dentalBlue, loc.aboutTitle, null),
      };

  void _push(_Section s) {
    final loc = AppLocalizations.of(context);
    final (_, _, title, _) = _meta(loc, s);
    Navigator.of(context).push(
      AppPageRoutes.cupertino(
        Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.navy,
            elevation: 0,
            title: Text(title),
          ),
          // Toggles change [_settings]; rebuild the pushed page with them.
          body: SafeArea(
            child: StatefulBuilder(
              builder: (context, setLocal) => _content(context, s, padding: AppBreakpoints.pagePadding(context), refresh: () => setLocal(() {})),
            ),
          ),
        ),
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (_loading) return ToothPageLoader(message: loc.settingsLoading);
    if (_settings == null) {
      return AdminEmpty(
        icon: Icons.cloud_off_rounded,
        title: loc.settingsLoadError,
        subtitle: '',
        action: AppButtons.secondary(onPressed: _bootstrap, icon: Icons.refresh_rounded, label: loc.tr('admin.retry')),
      );
    }
    final sections = _sections();
    return BusyBarrier(
      busy: _deleting,
      message: loc.settingsDeletingAccount,
      child: Padding(
        padding: AppBreakpoints.pagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              icon: Icons.settings_outlined,
              title: loc.settingsTitle,
              subtitle: loc.tr('settings.sub'),
              actions: [
                AppButtons.secondary(
                  icon: Icons.logout_rounded,
                  label: loc.signOut,
                  onPressed: _deleting ? null : _signOut,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  _split = box.maxWidth >= 860;
                  return ValueListenableBuilder<int>(
                    valueListenable: _tab,
                    builder: (context, t, _) {
                      final current = t >= 0 && t < _Section.values.length && sections.contains(_Section.values[t])
                          ? _Section.values[t]
                          : _Section.account;
                      final list = _sectionList(loc, sections, _split ? current : null);
                      if (!_split) return list;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: (box.maxWidth * 0.34).clamp(280.0, 360.0), child: list),
                          const SizedBox(width: 16),
                          Expanded(
                            child: AdminCard(
                              padding: EdgeInsets.zero,
                              child: AppSwitcher(
                                child: KeyedSubtree(
                                  key: ValueKey(current),
                                  child: _content(context, current, padding: const EdgeInsets.all(22)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Profile card + the section rows. [selected] highlights a row (split).
  Widget _sectionList(AppLocalizations loc, List<_Section> sections, _Section? selected) {
    final api = widget.api;
    final name = (api.userName ?? '').trim().isEmpty ? loc.settingsAccountFallback : api.userName!.trim();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        AdminCard(
          onTap: () => _open(_Section.account),
          child: Row(
            children: [
              UserAvatar(name: name, url: api.avatarUrl, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    Text(
                      [AppRoles.label(api.role, loc), ?((api.email ?? '').trim().isEmpty ? null : api.email!.trim())].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AdminCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final (i, s) in sections.where((s) => s != _Section.account).indexed) ...[
                if (i > 0) Divider(height: 1, indent: 58, color: AppColors.border.withValues(alpha: 0.5)),
                _SectionRow(
                  meta: _meta(loc, s),
                  selected: selected == s,
                  onTap: () => _open(s),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _open(_Section s) {
    if (_split) {
      _tab.value = s.index;
    } else {
      _push(s);
    }
  }

  /// One section's controls. [refresh] rebuilds a pushed page after a toggle.
  Widget _content(BuildContext context, _Section section, {required EdgeInsets padding, VoidCallback? refresh}) {
    final loc = AppLocalizations.of(context);
    final api = widget.api;
    final s = _settings!;
    Future<void> persist(void Function(AppSettings s) mutate) async {
      await _persist(mutate);
      refresh?.call();
    }

    final (_, _, title, sub) = _meta(loc, section);
    // Pushed pages show the title in the app bar; the description always.
    Widget heading() => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (refresh == null)
                Text(title, style: AppFonts.style(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.navy)),
              if (sub != null) ...[
                const SizedBox(height: 4),
                Text(sub, style: AppFonts.style(fontSize: 13.5, color: AppColors.muted, height: 1.35)),
              ],
            ],
          ),
        );
    final showHeading = refresh == null || sub != null;

    if (section == _Section.rejectList) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeading) heading(),
            Expanded(child: RejectList(api: api, active: widget.active)),
          ],
        ),
      );
    }
    if (section == _Section.about) return AboutContent(api: api, padding: padding);

    final List<Widget> body = switch (section) {
      _Section.account => [
          _GlassProfileHero(
            name: (api.userName ?? '').trim().isEmpty ? loc.settingsAccountFallback : api.userName!.trim(),
            email: (api.email ?? '').trim(),
            clinic: (api.clinicName ?? '').trim(),
            role: AppRoles.label(api.role, loc),
            lab: api.isDentist ? (api.labName ?? '') : '',
          ),
          const SizedBox(height: 20),
          _GlassSettingsGroup(
            header: loc.security.toUpperCase(),
            children: [
              _GlassNavRow(
                icon: CupertinoIcons.lock_fill,
                iconBg: const Color(0xFF8E8E93),
                title: loc.updatePassword,
                onTap: () => Navigator.of(context).push(
                  AppPageRoutes.cupertino(ChangePasswordScreen(api: api), title: loc.updatePassword),
                ),
              ),
              Container(height: 0.5, margin: const EdgeInsets.only(left: 58), color: Colors.black.withValues(alpha: 0.08)),
              _GlassNavRow(
                icon: CupertinoIcons.person_crop_circle_badge_minus,
                iconBg: AppColors.danger,
                title: loc.settingsDeleteAccount,
                titleColor: AppColors.danger,
                showChevron: false,
                onTap: _deleting ? null : _deleteAccount,
              ),
            ],
          ),
        ],
      _Section.lab => [
          if (api.isDentist) DentistLabSettings(api: api) else LabVisibilitySettings(api: api, labId: api.userId ?? ''),
        ],
      _Section.ai => [
          _GlassSettingsGroup(
            children: [
              _GlassToggleRow(
                icon: CupertinoIcons.sparkles,
                iconBg: AppColors.aiPurple,
                title: loc.settingsAutoShade,
                subtitle: loc.settingsAutoShadeSub,
                value: s.autoShade,
                onChanged: (v) => persist((x) => x.autoShade = v),
                showDivider: true,
              ),
              _GlassToggleRow(
                icon: CupertinoIcons.checkmark_seal_fill,
                iconBg: AppColors.dentalBlue,
                title: loc.settingsAutoQuality,
                subtitle: loc.settingsAutoQualitySub,
                value: s.autoScanQuality,
                onChanged: (v) => persist((x) => x.autoScanQuality = v),
                showDivider: false,
              ),
            ],
          ),
        ],
      _Section.notifications => [
          _GlassSettingsGroup(
            children: [
              _GlassToggleRow(
                icon: CupertinoIcons.bell_fill,
                iconBg: AppColors.danger,
                title: loc.settingsNotifyMaster,
                subtitle: loc.settingsNotifyMasterSub,
                value: s.notificationsEnabled,
                onChanged: (v) => persist((x) => x.notificationsEnabled = v),
                showDivider: false,
              ),
            ],
          ),
        ],
      _Section.language => [
          _GlassSettingsGroup(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(loc.settingsAppLanguage,
                        style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)),
                    const SizedBox(height: 10),
                    CupertinoSlidingSegmentedControl<String>(
                      groupValue: s.language == 'de' ? 'de' : 'en',
                      backgroundColor: AppColors.inset.withValues(alpha: 0.7),
                      thumbColor: Colors.white,
                      children: {
                        'en': Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(loc.languageEnglish)),
                        'de': Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(loc.languageGerman)),
                      },
                      onValueChanged: (code) async {
                        if (code == null) return;
                        await _setLanguage(code);
                        refresh?.call();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      _Section.rejectList || _Section.about => const [],
    };
    return ListView(
      padding: padding,
      children: [
        if (showHeading) heading(),
        // Readable line length on a wide pane.
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
        ),
      ],
    );
  }
}

enum _Section { account, lab, ai, notifications, language, rejectList, about }

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.meta, required this.selected, required this.onTap});

  final (IconData, Color, String, String?) meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, _) = meta;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: selected ? AppColors.dentalBlue.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                _GlassIcon(icon: icon, bg: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 15.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.dentalBlue : AppColors.navy,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// About Elite Dent: intro, features, website links and account details.
class AboutContent extends StatelessWidget {
  const AboutContent({super.key, required this.api, this.padding});

  final ApiClient api;
  final EdgeInsets? padding;

  static Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    // Two columns only when this pane itself is wide.
    final wide = MediaQuery.sizeOf(context).width >= 1200;

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

    return ListView(
        padding: padding ?? AppBreakpoints.pagePadding(context).copyWith(top: 8, bottom: 36),
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
      );
  }
}

/// About as a pushed page (its own app bar).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: true,
        title: Text(loc.aboutTitle),
      ),
      body: AboutContent(api: api),
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
  });

  final String? header;
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

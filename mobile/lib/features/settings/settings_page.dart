import 'dart:async';

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


/// Glassy iPadOS Settings with full account deletion.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api, this.tab, this.active = true});

  final ApiClient api;

  /// Selected section, owned by the shell so other pages can deep-link.
  final ValueNotifier<int>? tab;
  final bool active;

  /// Section index of the admin reject list, for deep links.
  static final rejectListTab = _Tab.rejectList.index;

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
    AppSnackBars.success(context, AppLocalizations.of(context).preferenceSaved);
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
      AppSnackBars.error(context, friendlyError(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    _flash?.cancel();
    super.dispose();
  }

  ValueNotifier<int> get _tab => widget.tab ?? _ownTab;
  late final _ownTab = ValueNotifier(0);

  final _search = TextEditingController();
  String _query = '';

  /// Setting a search result jumped to; its row glows for a moment.
  String? _highlight;
  Timer? _flash;

  List<_Section> _sections() {
    final api = widget.api;
    return [
      _Section.profile,
      _Section.security,
      if (api.isDentist || (api.isLaboratory && (api.userId ?? '').isNotEmpty)) _Section.lab,
      _Section.notifications,
      _Section.language,
      if (api.isAdmin) _Section.rejectList,
      _Section.about,
    ];
  }

  /// Tabs grouped so each has real content.
  List<_Tab> _tabs() => [
        _Tab.account,
        _Tab.preferences,
        if (_sections().contains(_Section.lab)) _Tab.lab,
        if (widget.api.isAdmin) _Tab.rejectList,
      ];

  static _Tab _tabOf(_Section s) => switch (s) {
        _Section.profile || _Section.security || _Section.about => _Tab.account,
        _Section.notifications || _Section.language => _Tab.preferences,
        _Section.lab => _Tab.lab,
        _Section.rejectList => _Tab.rejectList,
      };

  String _tabName(AppLocalizations loc, _Tab t) => switch (t) {
        _Tab.account => loc.tr('settings.tab.account'),
        _Tab.preferences => loc.tr('settings.prefs'),
        _Tab.lab => widget.api.isLaboratory ? loc.tr('lab.tab.settings') : loc.tr('settings.sec.myLab'),
        _Tab.rejectList => loc.tr('admin.rejectList'),
      };

  /// Search results show the tab a setting lives in.
  String _tabLabel(AppLocalizations loc, _Section s) => _tabName(loc, _tabOf(s));

  // ── Search ────────────────────────────────────────────────────────────────

  /// Everything findable: the setting's own words plus the things people
  /// type when they're trying to do something ("forgot password").
  /// ponytail: a fixed in-memory list, matched on device — fine for a few
  /// dozen entries; no server or index needed.
  List<_Entry> _entries(AppLocalizations loc) {
    final api = widget.api;
    final sections = _sections();
    return [
      _Entry('name', _Section.profile, loc.aboutName, loc.tr('settings.d.name'), ['name', 'profile', 'account', 'konto', 'profil']),
      _Entry('email', _Section.profile, loc.email, loc.tr('settings.d.email'), ['email', 'e-mail', 'mail', 'address', 'adresse', 'login']),
      if ((api.clinicName ?? '').trim().isNotEmpty) _Entry('clinic', _Section.profile, loc.aboutClinic, loc.tr('settings.d.clinic'), ['clinic', 'practice', 'praxis', 'office']),
      _Entry('role', _Section.profile, loc.role, loc.tr('settings.d.role'), ['role', 'rolle', 'dentist', 'zahnarzt', 'lab', 'admin', 'permissions']),
      _Entry('password', _Section.security, loc.updatePassword, loc.securitySub, [
        'password',
        'passwort',
        'kennwort',
        'change password',
        'forgot',
        'vergessen',
        'reset',
        'security',
        'sicherheit',
        'login',
      ]),
      _Entry('delete', _Section.security, loc.settingsDeleteAccount, loc.tr('settings.d.delete'), [
        'delete',
        'löschen',
        'remove account',
        'close account',
        'konto löschen',
        'gdpr',
        'dsgvo',
        'data',
        'daten',
        'leave',
      ]),
      if (sections.contains(_Section.lab))
        api.isLaboratory
            ? _Entry('lab', _Section.lab, loc.tr('lab.tab.settings'), loc.tr('settings.d.labVis'), [
                'hide',
                'visibility',
                'sichtbar',
                'verbergen',
                'directory',
                'verzeichnis',
                'dentists',
                'zahnärzte',
                'lab',
                'labor',
              ])
            : _Entry('lab', _Section.lab, loc.tr('settings.sec.myLab'), loc.tr('settings.d.myLab'), [
                'lab',
                'labor',
                'join',
                'beitreten',
                'leave',
                'verlassen',
                'switch lab',
                'change lab',
                'wechseln',
                'transfer',
                'patients',
              ]),
      _Entry('notify', _Section.notifications, loc.settingsNotifyMaster, loc.settingsNotifyMasterSub, [
        'notifications',
        'benachrichtigungen',
        'alerts',
        'mute',
        'stumm',
        'silence',
        'popup',
        'banner',
        'sound',
      ]),
      _Entry('language', _Section.language, loc.settingsAppLanguage, loc.settingsLanguageSub, ['language', 'sprache', 'german', 'deutsch', 'english', 'englisch', 'translate']),
      if (sections.contains(_Section.rejectList))
        _Entry('reject', _Section.rejectList, loc.tr('admin.rejectList'), loc.tr('settings.sec.rejectSub'), [
          'reject',
          'rejected',
          'blocked',
          'banned',
          'sperrliste',
          'gesperrt',
          'signup',
          'registration',
          'unblock',
          'email',
        ]),
      _Entry('about', _Section.about, loc.aboutTitle, loc.tr('settings.d.about'), [
        'about',
        'über',
        'version',
        'support',
        'help',
        'hilfe',
        'contact',
        'kontakt',
        'privacy',
        'datenschutz',
        'imprint',
        'impressum',
        'website',
        'user id',
      ]),
    ];
  }

  /// Every word must hit the title, description or a keyword; titles rank
  /// first, then descriptions, then keywords.
  List<_Entry> _results(AppLocalizations loc) {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final scored = <(int, _Entry)>[];
    for (final e in _entries(loc)) {
      final title = e.title.toLowerCase();
      final desc = e.description.toLowerCase();
      final kw = e.keywords.join(' ');
      var score = 0;
      var all = true;
      for (final w in words) {
        if (title.startsWith(w)) {
          score += 4;
        } else if (title.contains(w)) {
          score += 3;
        } else if (kw.contains(w)) {
          score += 2;
        } else if (desc.contains(w)) {
          score += 1;
        } else {
          all = false;
          break;
        }
      }
      if (all) scored.add((score, e));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, e) in scored) e];
  }

  void _goTo(_Entry e) {
    _search.clear();
    _flash?.cancel();
    setState(() {
      _query = '';
      _highlight = e.id;
    });
    _tab.value = _tabOf(e.section).index;
    _flash = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  void _openAbout() {
    final loc = AppLocalizations.of(context);
    Navigator.of(context).push(AppPageRoutes.cupertino(AboutPage(api: widget.api), title: loc.aboutTitle));
  }

  // ── Page ─────────────────────────────────────────────────────────────────

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
    final tabs = _tabs();
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
              subtitleAsInfo: true,
              actions: [
                SizedBox(
                  width: 300,
                  child: AdminSearchField(
                    controller: _search,
                    hint: loc.tr('settings.search'),
                    onChanged: (q) => setState(() => _query = q.trim()),
                  ),
                ),
                AppButtons.secondary(
                  icon: Icons.logout_rounded,
                  label: loc.signOut,
                  onPressed: _deleting ? null : _signOut,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _tab,
                builder: (context, t, _) {
                  final current = t >= 0 && t < _Tab.values.length && tabs.contains(_Tab.values[t]) ? _Tab.values[t] : _Tab.account;
                  final searching = _query.isNotEmpty;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TabStrip(
                        labels: [for (final x in tabs) _tabName(loc, x)],
                        selected: searching ? -1 : tabs.indexOf(current),
                        onSelect: (i) {
                          _search.clear();
                          setState(() => _query = '');
                          _tab.value = tabs[i].index;
                        },
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: AppSwitcher(
                          child: KeyedSubtree(
                            key: ValueKey(searching ? 'search' : current),
                            child: searching
                                ? _searchResults(loc)
                                : current == _Tab.rejectList
                                    // A list: the card fills the space.
                                    ? AdminCard(padding: const EdgeInsets.fromLTRB(14, 14, 14, 0), child: _content(context, _Section.rejectList))
                                    // Settings: the card ends with its content.
                                    : SingleChildScrollView(
                                        padding: const EdgeInsets.only(bottom: 24),
                                        child: AdminCard(
                                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                                          child: _tabBody(context, current),
                                        ),
                                      ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A tab's groups, each with a small heading, separated by dividers.
  Widget _tabBody(BuildContext context, _Tab t) {
    final loc = AppLocalizations.of(context);
    Widget group(String title, Widget body) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 14, 8, 4), child: SectionLabel(title)),
            body,
          ],
        );
    final groups = switch (t) {
      _Tab.account => [
          group(loc.tr('settings.tab.profile'), _content(context, _Section.profile)),
          group(loc.security, _content(context, _Section.security)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openAbout,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Row(
                  children: [
                    const AdminIcon(icon: Icons.info_outline_rounded, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(loc.tr('settings.aboutRow'),
                              style: AppFonts.style(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                          Text(loc.tr('settings.d.about'), style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      _Tab.preferences => [
          group(loc.settingsNotificationsTitle, _content(context, _Section.notifications)),
          group(loc.settingsLanguageTitle, _content(context, _Section.language)),
        ],
      _Tab.lab => [group(_tabName(loc, _Tab.lab), _content(context, _Section.lab))],
      _Tab.rejectList => const <Widget>[],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, g) in groups.indexed) ...[if (i > 0) _divider(), g],
      ],
    );
  }

  Widget _divider() => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5));

  Widget _searchResults(AppLocalizations loc) {
    final hits = _results(loc);
    if (hits.isEmpty) {
      return AdminEmpty(
        icon: Icons.search_off_rounded,
        title: loc.tr('settings.noHits'),
        subtitle: loc.tr('settings.noHitsSub'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: hits.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = hits[i];
        return Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _goTo(e),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, style: AppFonts.style(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
                        const SizedBox(height: 2),
                        Text(e.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AdminBadge(_tabLabel(loc, e.section)),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// A setting inside a card: name + description, control on the right
  /// (or under it when [stacked] / the card is narrow).
  Widget _row(String id, String title, String description, Widget child, {bool stacked = false}) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = !stacked && box.maxWidth >= 380;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppFonts.style(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
            const SizedBox(height: 2),
            Text(description, style: AppFonts.style(fontSize: 12.5, color: AppColors.muted, height: 1.35)),
          ],
        );
        return AnimatedContainer(
          duration: AppMotion.normal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: _highlight == id ? AppColors.dentalBlue.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: side
              ? Row(children: [Expanded(child: text), const SizedBox(width: 16), child])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [text, const SizedBox(height: 10), Align(alignment: Alignment.centerLeft, child: child)],
                ),
        );
      },
    );
  }

  Widget _rows(List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, r) in rows.indexed) ...[if (i > 0) _divider(), r],
        ],
      );

  /// Read-only profile line: label, then the value.
  Widget _info(String id, String label, String value) => AnimatedContainer(
        duration: AppMotion.normal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          color: _highlight == id ? AppColors.dentalBlue.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: AppFonts.style(fontSize: 13.5, color: AppColors.muted)),
            ),
            Expanded(
              child: CopyableText(
                value.trim().isEmpty ? '—' : value.trim(),
                maxLines: 1,
                style: AppFonts.style(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.navy),
              ),
            ),
          ],
        ),
      );

  Widget _content(BuildContext context, _Section section) {
    final loc = AppLocalizations.of(context);
    final api = widget.api;
    final s = _settings!;
    switch (section) {
      case _Section.profile:
        final name = (api.userName ?? '').trim().isEmpty ? loc.settingsAccountFallback : api.userName!.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Row(
                children: [
                  UserAvatar(name: name, url: api.avatarUrl, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.style(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
                        const SizedBox(height: 4),
                        AdminBadge(AppRoles.label(api.role, loc)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _divider(),
            _info('name', loc.aboutName, name),
            _info('email', loc.email, api.email ?? ''),
            if ((api.clinicName ?? '').trim().isNotEmpty) _info('clinic', loc.aboutClinic, api.clinicName!),
            _info('role', loc.role, AppRoles.label(api.role, loc)),
            if (api.isDentist) _info('labname', loc.tr('admin.lab'), api.labName ?? ''),
            _info('userid', loc.aboutUserId, api.userId ?? ''),
          ],
        );
      case _Section.security:
        return _rows([
          _row(
            'password',
            loc.updatePassword,
            loc.securitySub,
            AppButtons.secondary(
              icon: Icons.lock_outline_rounded,
              label: loc.tr('settings.change'),
              compact: true,
              onPressed: () => Navigator.of(context).push(
                AppPageRoutes.cupertino(ChangePasswordScreen(api: api), title: loc.updatePassword),
              ),
            ),
          ),
          _row(
            'delete',
            loc.settingsDeleteAccount,
            loc.tr('settings.d.delete'),
            AppButtons.danger(
              icon: Icons.person_remove_outlined,
              label: loc.commonDelete,
              soft: true,
              compact: true,
              onPressed: _deleting ? null : _deleteAccount,
            ),
          ),
        ]);
      case _Section.lab:
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: api.isDentist ? DentistLabSettings(api: api) : LabVisibilitySettings(api: api, labId: api.userId ?? ''),
        );
      case _Section.notifications:
        return _row(
          'notify',
          loc.settingsNotifyMaster,
          loc.settingsNotifyMasterSub,
          CupertinoSwitch(
            value: s.notificationsEnabled,
            onChanged: (v) => _persist((x) => x.notificationsEnabled = v),
          ),
        );
      case _Section.language:
        return _row(
          'language',
          loc.settingsAppLanguage,
          loc.settingsLanguageSub,
          SizedBox(
            width: 200,
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: s.language == 'de' ? 'de' : 'en',
              backgroundColor: AppColors.inset.withValues(alpha: 0.7),
              thumbColor: Colors.white,
              children: {
                'en': Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Text(loc.languageEnglish)),
                'de': Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Text(loc.languageGerman)),
              },
              onValueChanged: (code) {
                if (code != null) _setLanguage(code);
              },
            ),
          ),
        );
      case _Section.rejectList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text(loc.tr('settings.sec.rejectSub'),
                  style: AppFonts.style(fontSize: 12.5, color: AppColors.muted, height: 1.35)),
            ),
            Expanded(child: RejectList(api: api, active: widget.active)),
          ],
        );
      case _Section.about:
        return const SizedBox.shrink();
    }
  }
}

/// A searchable setting: where it lives and the words that find it.
class _Entry {
  const _Entry(this.id, this.section, this.title, this.description, this.keywords);

  final String id;
  final _Section section;
  final String title;
  final String description;
  final List<String> keywords;
}

/// What each searchable setting belongs to.
enum _Section { profile, security, lab, notifications, language, rejectList, about }

/// Settings tabs; index order is the shell's deep-link number.
enum _Tab { account, preferences, lab, rejectList }

/// Underlined tabs (scroll sideways on narrow screens).
class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.labels, required this.selected, required this.onSelect});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.7)))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, l) in labels.indexed)
              InkWell(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: i == selected ? AppColors.navy : Colors.transparent, width: 2.5)),
                  ),
                  child: Text(
                    l,
                    style: AppFonts.style(
                      fontSize: 15,
                      fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                      color: i == selected ? AppColors.navy : AppColors.muted,
                    ),
                  ),
                ),
              ),
          ],
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


  static Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    Widget section(String title, String body) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        Text(body, style: AppFonts.style(fontSize: 15, color: const Color(0xFF6B7C93), height: 1.4)),
      ],
    );
    Widget divider() => Container(height: 0.5, margin: const EdgeInsets.only(left: 58), color: Colors.black.withValues(alpha: 0.08));
    List<Widget> divided(List<Widget> rows) => [
      for (var i = 0; i < rows.length; i++) ...[if (i > 0) divider(), rows[i]],
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
                  style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.navy),
                ),
                const SizedBox(height: 2),
                Text(loc.tr('about.f.${key}Sub'), style: AppFonts.style(fontSize: 13, color: const Color(0xFF6B7C93), height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
    Widget link(IconData icon, String title, String url) => _GlassNavRow(icon: icon, iconBg: AppColors.dentalBlue, title: title, onTap: () => _open(url));
    Widget info(String label, String? value) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Label column, then the value right after it (no gap mid-row).
          SizedBox(
            width: 120,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF6B7C93)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CopyableText(
              (value ?? '').trim().isEmpty ? '—' : value!.trim(),
              maxLines: 1,
              style: AppFonts.style(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
          ),
        ],
      ),
    );

    final what = section(loc.aboutWhatTitle, loc.aboutWhatBody);
    final who = section(loc.aboutWhoTitle, loc.aboutWhoBody);
    final intro = AdminCard(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: Alignment.centerLeft, child: BrandLogo(height: 52)),
          const SizedBox(height: 18),
          what,
          const SizedBox(height: 18),
          who,
        ],
      ),
    );
    final features = _GlassSettingsGroup(
      header: loc.aboutFeaturesTitle.toUpperCase(),
      children: divided([
        feature(CupertinoIcons.sparkles, AppColors.aiPurple, 'shade'),
        feature(CupertinoIcons.checkmark_seal_fill, AppColors.dentalBlue, 'scans'),
        feature(CupertinoIcons.person_2_fill, const Color(0xFF34C759), 'patients'),
        feature(CupertinoIcons.chat_bubble_2_fill, const Color(0xFFFF9500), 'messages'),
        feature(CupertinoIcons.globe, const Color(0xFF5AC8FA), 'interpreter'),
      ]),
    );
    final account = _GlassSettingsGroup(
      header: loc.aboutAccountTitle.toUpperCase(),
      children: [
        info(loc.aboutName, api.userName),
        info(loc.email, api.email),
        info(loc.aboutClinic, api.clinicName),
        if (api.isDentist) info(loc.tr('admin.lab'), api.labName),
        info(loc.role, AppRoles.label(api.role, loc)),
        info(loc.aboutUserId, api.userId),
      ],
    );
    final links = _GlassSettingsGroup(
      header: loc.aboutLinksTitle.toUpperCase(),
      children: divided([
        link(CupertinoIcons.house_fill, loc.aboutWebsite, 'https://www.elite-d.de'),
        link(CupertinoIcons.question_circle_fill, loc.aboutSupport, 'https://www.elite-d.de/support'),
        link(CupertinoIcons.lock_shield_fill, loc.aboutPrivacy, 'https://www.elite-d.de/privacy/'),
        link(CupertinoIcons.doc_text_fill, loc.aboutImprint, 'https://www.elite-d.de/impressum'),
      ]),
    );
    final credit = Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open('https://www.vawcom.com/'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text.rich(
            TextSpan(
              text: '${loc.aboutCredit} ',
              children: [
                TextSpan(
                  text: 'VAWCOM',
                  style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dentalBlue),
                ),
              ],
            ),
            style: AppFonts.style(fontSize: 13, color: const Color(0xFF6C6C70)),
          ),
        ),
      ),
    );
    const gap = SizedBox(height: 24);
    return LayoutBuilder(
      builder: (context, box) {
        final pad = padding ?? AppBreakpoints.pagePadding(context).copyWith(top: 8, bottom: 36);
        // Wide: two filled columns — the app on the left, you on the right.
        // Two columns only with room for both; portrait stacks in one
        // ordered column instead of two uneven ones.
        if (box.maxWidth >= 1000) {
          final row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [intro, gap, features])),
                const SizedBox(width: 24),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [account, gap, links, gap, credit])),
              ],
            );
          return SingleChildScrollView(padding: pad, child: row);
        }
        return ListView(padding: pad, children: [intro, gap, account, gap, features, gap, links, gap, credit]);
      },
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
      appBar: AppBar(backgroundColor: AppColors.surface, foregroundColor: AppColors.navy, elevation: 0, centerTitle: true, title: Text(loc.aboutTitle)),
      body: AboutContent(api: api),
    );
  }
}

class _GlassSettingsGroup extends StatelessWidget {
  const _GlassSettingsGroup({required this.children, this.header});

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
              style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6C6C70), letterSpacing: -0.08),
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
  const _GlassNavRow({required this.icon, required this.iconBg, required this.title, required this.onTap});

  final IconData icon;
  final Color iconBg;
  final String title;
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
                  style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.navy),
                ),
              ),
              const Icon(CupertinoIcons.chevron_forward, size: 16, color: Color(0xFFC7C7CC)),
            ],
          ),
        ),
      ),
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
        boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 17, color: Colors.white),
    );
  }
}

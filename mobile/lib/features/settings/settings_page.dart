import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_coordinator.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'change_password_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings? _settings;
  bool _loading = true;
  String? _status;
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
      _status = null;
      _error = null;
    });
    await s.save();
    if (!mounted) return;
    final msg = AppLocalizations.of(context).preferenceSaved;
    setState(() => _status = msg);
    AppSnackBars.success(context, msg);
  }

  Future<void> _setLanguage(String code) async {
    await LocaleScope.of(context).setLanguage(code);
    await _persist((x) => x.language = code);
  }

  void _signOut() {
    SessionCoordinator.signOut(widget.api);
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
        child: SectionCard(
          child: Text(
            _error ?? AppLocalizations.of(context).settingsLoadError,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      );
    }

    final loc = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.settings_outlined,
            title: loc.settingsTitle,
            subtitle: loc.settingsSubtitle,
            actions: [
              _NeoActionButton(
                icon: Icons.logout_rounded,
                label: loc.signOut,
                danger: true,
                onPressed: _signOut,
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            _NeoBanner(text: _status!, tone: _BannerTone.success),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _NeoBanner(text: _error!, tone: _BannerTone.danger),
          ],
          const SizedBox(height: 18),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _SecurityCard(api: widget.api),
                    const SizedBox(height: 20),
                    _AiCard(
                      shade: s.autoShade,
                      scanQuality: s.autoScanQuality,
                      scanBody: s.autoScanBody,
                      onShade: (v) => _persist((x) => x.autoShade = v),
                      onScanQuality: (v) =>
                          _persist((x) => x.autoScanQuality = v),
                      onScanBody: (v) => _persist((x) => x.autoScanBody = v),
                    ),
                    const SizedBox(height: 20),
                    _NotificationsCard(
                      enabled: s.notificationsEnabled,
                      onChanged: (v) =>
                          _persist((x) => x.notificationsEnabled = v),
                    ),
                    const SizedBox(height: 20),
                    _LanguageCard(
                      language: s.language,
                      onChanged: _setLanguage,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section cards ───────────────────────────────────────────────────────────

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SectionCard(
      depth: 1.05,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.notifications_none_rounded,
            title: loc.settingsNotificationsTitle,
            subtitle: loc.settingsNotificationsSub,
          ),
          const SizedBox(height: 14),
          NeoInset(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: _NeoToggleRow(
              title: loc.settingsNotifyMaster,
              subtitle: loc.settingsNotifyMasterSub,
              value: enabled,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.language,
    required this.onChanged,
  });

  final String language;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SectionCard(
      depth: 1.05,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.language_rounded,
            title: loc.settingsLanguageTitle,
            subtitle: loc.settingsLanguageSub,
          ),
          const SizedBox(height: 16),
          SectionLabel(loc.settingsAppLanguage),
          const SizedBox(height: 12),
          NeoInset(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SoftFilterChip(
                  label: loc.languageEnglish,
                  selected: language == 'en',
                  onTap: () => onChanged('en'),
                ),
                SoftFilterChip(
                  label: loc.languageGerman,
                  selected: language == 'de',
                  onTap: () => onChanged('de'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SectionCard(
      depth: 1.05,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.lock_outline_rounded,
            title: loc.security,
            subtitle: loc.securitySub,
          ),
          const SizedBox(height: 14),
          NeoInset(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadii.borderSm,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChangePasswordScreen(api: api),
                    ),
                  );
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.password_rounded,
                        color: AppColors.dentalBlue,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          loc.updatePassword,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
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

class _AiCard extends StatelessWidget {
  const _AiCard({
    required this.shade,
    required this.scanQuality,
    required this.scanBody,
    required this.onShade,
    required this.onScanQuality,
    required this.onScanBody,
  });

  final bool shade;
  final bool scanQuality;
  final bool scanBody;
  final ValueChanged<bool> onShade;
  final ValueChanged<bool> onScanQuality;
  final ValueChanged<bool> onScanBody;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SectionCard(
      depth: 1.05,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.auto_awesome_outlined,
            title: loc.settingsAiTitle,
            subtitle: loc.settingsAiSub,
            iconColor: AppColors.aiPurple,
          ),
          const SizedBox(height: 14),
          NeoInset(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                _NeoToggleRow(
                  title: loc.settingsAutoShade,
                  subtitle: loc.settingsAutoShadeSub,
                  value: shade,
                  onChanged: onShade,
                ),
                const _NeoDivider(),
                _NeoToggleRow(
                  title: loc.settingsAutoQuality,
                  subtitle: loc.settingsAutoQualitySub,
                  value: scanQuality,
                  onChanged: onScanQuality,
                ),
                const _NeoDivider(),
                _NeoToggleRow(
                  title: loc.settingsAutoScanBody,
                  subtitle: loc.settingsAutoScanBodySub,
                  value: scanBody,
                  onChanged: onScanBody,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Neumorphic primitives ───────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NeoIconBadge(
          icon: icon,
          size: 44,
          iconSize: 20,
          color: iconColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NeoToggleRow extends StatelessWidget {
  const _NeoToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _NeoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NeoSwitch extends StatelessWidget {
  const _NeoSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 54,
        height: 32,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: value ? AppColors.sidebarActive : AppColors.inset,
          borderRadius: BorderRadius.circular(20),
          boxShadow: value ? NeoShadows.pressed() : NeoShadows.soft(depth: 0.5),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: value ? AppColors.dentalBlue : AppColors.neo,
              shape: BoxShape.circle,
              boxShadow: NeoShadows.soft(depth: 0.65),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeoActionButton extends StatelessWidget {
  const _NeoActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = danger ? AppColors.danger : AppColors.navy;
    final bg = danger ? AppColors.dangerSoft : AppColors.neo;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: AppRadii.borderSm,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: enabled ? NeoShadows.soft(depth: 0.4) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: enabled ? fg : AppColors.muted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? fg : AppColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeoDivider extends StatelessWidget {
  const _NeoDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppColors.border.withValues(alpha: 0.7),
    );
  }
}

enum _BannerTone { success, danger }

class _NeoBanner extends StatelessWidget {
  const _NeoBanner({required this.text, required this.tone});

  final String text;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = tone == _BannerTone.success
        ? AppColors.successSoft
        : AppColors.dangerSoft;
    final fg =
        tone == _BannerTone.success ? AppColors.success : AppColors.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.borderSm,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/offline/sync_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SyncService _sync = SyncService(api: widget.api);

  AppSettings? _settings;
  bool _loading = true;
  bool _syncing = false;
  bool _clearing = false;
  String? _status;
  String? _error;

  int _pending = 0;
  bool? _online;
  String _apiStatus = '—';
  String _appVersion = '—';

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
      final pending = await _sync.queue.pendingCount();
      final online = await _sync.isOnline;
      final api = await _pingApi();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _pending = pending;
        _online = online;
        _appVersion = '1.0.0+1';
        _apiStatus = api;
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

  Future<String> _pingApi() async {
    try {
      final res = await http
          .get(Uri.parse('${widget.api.baseUrl}/health'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map && body['status'] == 'ok') {
          return 'Online';
        }
      }
      return 'Unhealthy (${res.statusCode})';
    } catch (_) {
      return 'Unreachable';
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
    setState(() => _status = AppLocalizations.of(context).preferenceSaved);
  }

  Future<void> _setLanguage(String code) async {
    await LocaleScope.of(context).setLanguage(code);
    await _persist((x) => x.language = code);
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _error = null;
      _status = null;
    });
    try {
      final online = await _sync.isOnline;
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      if (!online) {
        setState(() => _error = loc.settingsOfflineError);
        return;
      }
      final n = await _sync.flush();
      final pending = await _sync.queue.pendingCount();
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _online = true;
        _status = n == 0 ? loc.settingsQueueEmpty : loc.settingsSynced(n);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _clearCache() async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.border),
        title: Text(loc.settingsClearCacheTitle),
        content: Text(loc.settingsClearCacheBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.settingsClearCache),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _clearing = true;
      _error = null;
      _status = null;
    });
    try {
      final n = await (_settings ?? await AppSettings.load()).clearEncryptedCache();
      setState(() => _status = loc.settingsCleared(n));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SectionCard(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(color: AppColors.dentalBlue),
          ),
        ),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: (context) {
            final loc = AppLocalizations.of(context);
            return PageHeader(
            icon: Icons.settings_outlined,
            title: loc.settingsTitle,
            subtitle: loc.settingsSubtitle,
            actions: [
              _NeoActionButton(
                icon: Icons.refresh_rounded,
                label: loc.refresh,
                onPressed: _bootstrap,
              ),
            ],
          );
          }),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 960;
                final left = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _OfflineCard(
                      online: _online,
                      pending: _pending,
                      autoSync: s.autoSync,
                      syncing: _syncing,
                      clearing: _clearing,
                      onAutoSync: (v) => _persist((x) => x.autoSync = v),
                      onSyncNow: _syncNow,
                      onClearCache: _clearCache,
                    ),
                    const SizedBox(height: 16),
                    _NotificationsCard(
                      messages: s.notifyMessages,
                      caseStatus: s.notifyCaseStatus,
                      scanQuality: s.notifyScanQuality,
                      onMessages: (v) => _persist((x) => x.notifyMessages = v),
                      onCaseStatus: (v) =>
                          _persist((x) => x.notifyCaseStatus = v),
                      onScanQuality: (v) =>
                          _persist((x) => x.notifyScanQuality = v),
                    ),
                    const SizedBox(height: 16),
                    _LanguageCard(
                      language: s.language,
                      onChanged: _setLanguage,
                    ),
                  ],
                );
                final right = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AiCard(
                      shade: s.autoShade,
                      scanQuality: s.autoScanQuality,
                      scanBody: s.autoScanBody,
                      onShade: (v) => _persist((x) => x.autoShade = v),
                      onScanQuality: (v) =>
                          _persist((x) => x.autoScanQuality = v),
                      onScanBody: (v) => _persist((x) => x.autoScanBody = v),
                    ),
                    const SizedBox(height: 16),
                    _AboutCard(
                      version: _appVersion,
                      apiStatus: _apiStatus,
                      baseUrl: widget.api.baseUrl,
                      online: _online,
                    ),
                  ],
                );

                if (!wide) {
                  return ListView(
                    children: [left, const SizedBox(height: 16), right],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: ListView(children: [left])),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: ListView(children: [right])),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section cards ───────────────────────────────────────────────────────────

class _OfflineCard extends StatelessWidget {
  const _OfflineCard({
    required this.online,
    required this.pending,
    required this.autoSync,
    required this.syncing,
    required this.clearing,
    required this.onAutoSync,
    required this.onSyncNow,
    required this.onClearCache,
  });

  final bool? online;
  final int pending;
  final bool autoSync;
  final bool syncing;
  final bool clearing;
  final ValueChanged<bool> onAutoSync;
  final VoidCallback onSyncNow;
  final VoidCallback onClearCache;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final onlineLabel = online == null
        ? '…'
        : online!
            ? loc.online
            : loc.offline;
    final onlineColor = online == true
        ? AppColors.success
        : (online == false ? AppColors.danger : AppColors.muted);

    return SectionCard(
      depth: 1.05,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.cloud_sync_outlined,
            title: loc.settingsOfflineTitle,
            subtitle: loc.settingsOfflineSubtitle,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _NeoStatTile(
                  label: loc.settingsConnection,
                  value: onlineLabel,
                  valueColor: onlineColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NeoStatTile(
                  label: loc.settingsPending,
                  value: '$pending',
                  valueColor: pending > 0 ? AppColors.warning : AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          NeoInset(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: _NeoToggleRow(
              title: loc.settingsAutoSync,
              subtitle: loc.settingsAutoSyncSub,
              value: autoSync,
              onChanged: onAutoSync,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _NeoActionButton(
                icon: Icons.sync_rounded,
                label: syncing ? loc.settingsSyncing : loc.settingsSyncNow,
                primary: true,
                busy: syncing,
                onPressed: syncing ? null : onSyncNow,
              ),
              _NeoActionButton(
                icon: Icons.delete_outline_rounded,
                label: clearing ? loc.settingsClearing : loc.settingsClearCache,
                danger: true,
                busy: clearing,
                onPressed: clearing ? null : onClearCache,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({
    required this.messages,
    required this.caseStatus,
    required this.scanQuality,
    required this.onMessages,
    required this.onCaseStatus,
    required this.onScanQuality,
  });

  final bool messages;
  final bool caseStatus;
  final bool scanQuality;
  final ValueChanged<bool> onMessages;
  final ValueChanged<bool> onCaseStatus;
  final ValueChanged<bool> onScanQuality;

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
            child: Column(
              children: [
                _NeoToggleRow(
                  title: loc.settingsNotifyMessages,
                  subtitle: loc.settingsNotifyMessagesSub,
                  value: messages,
                  onChanged: onMessages,
                ),
                const _NeoDivider(),
                _NeoToggleRow(
                  title: loc.settingsNotifyCase,
                  subtitle: loc.settingsNotifyCaseSub,
                  value: caseStatus,
                  onChanged: onCaseStatus,
                ),
                const _NeoDivider(),
                _NeoToggleRow(
                  title: loc.settingsNotifyScan,
                  subtitle: loc.settingsNotifyScanSub,
                  value: scanQuality,
                  onChanged: onScanQuality,
                ),
              ],
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

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.version,
    required this.apiStatus,
    required this.baseUrl,
    required this.online,
  });

  final String version;
  final String apiStatus;
  final String baseUrl;
  final bool? online;

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
            icon: Icons.info_outline_rounded,
            title: loc.settingsAboutTitle,
            subtitle: loc.settingsAboutSub,
          ),
          const SizedBox(height: 14),
          NeoInset(
            child: Column(
              children: [
                _InfoRow(label: loc.settingsVersion, value: version),
                const _NeoDivider(),
                _InfoRow(
                  label: loc.settingsApi,
                  value: online == true
                      ? loc.online
                      : (online == false ? loc.offline : apiStatus),
                  valueColor: online == true
                      ? AppColors.success
                      : (online == false ? AppColors.danger : AppColors.navy),
                ),
                const _NeoDivider(),
                _InfoRow(label: loc.settingsBaseUrl, value: baseUrl),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.neo,
              borderRadius: AppRadii.borderSm,
              boxShadow: NeoShadows.soft(depth: 0.4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, size: 18, color: AppColors.dentalBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loc.settingsPrivacyNote,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
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

class _NeoStatTile extends StatelessWidget {
  const _NeoStatTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: AppRadii.borderSm,
        boxShadow: NeoShadows.soft(depth: 0.55),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: valueColor ?? AppColors.navy,
            ),
          ),
        ],
      ),
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

/// Soft raised / pressed toggle — matches Elite Dent neumorphism (not Material).
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
    this.primary = false,
    this.danger = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final Color fg;
    final Color bg;
    if (primary) {
      fg = Colors.white;
      bg = AppColors.navy;
    } else if (danger) {
      fg = AppColors.danger;
      bg = AppColors.dangerSoft;
    } else {
      fg = AppColors.navy;
      bg = AppColors.neo;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: AppRadii.borderSm,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadii.borderSm,
            boxShadow: enabled && !primary
                ? NeoShadows.soft(depth: 0.55)
                : (primary ? NeoShadows.soft(depth: 0.35) : null),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              else
                Icon(icon, size: 18, color: enabled ? fg : AppColors.muted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? fg : AppColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final icon = tone == _BannerTone.success
        ? Icons.check_circle_outline
        : Icons.error_outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.borderSm,
        boxShadow: NeoShadows.soft(depth: 0.35),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeoDivider extends StatelessWidget {
  const _NeoDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: AppColors.border.withValues(alpha: 0.55),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.navy,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.api,
    this.onNavigate,
    this.onUnreadChanged,
  });

  final ApiClient api;
  final ValueChanged<AppNavItem>? onNavigate;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  bool _markingAll = false;
  String? _error;
  String _filter = 'all';
  List<Map<String, dynamic>> _items = [];
  AppSettings? _prefs;

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
      final prefs = await AppSettings.load();
      final items = await widget.api.listNotifications();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _items = items;
        _loading = false;
      });
      _emitUnread();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _emitUnread() {
    final n = _visible.where((e) => e['read'] != true).length;
    widget.onUnreadChanged?.call(n);
  }

  bool _allowedBySettings(String type) {
    final p = _prefs;
    if (p == null) return true;
    switch (type) {
      case 'message':
        return p.notifyMessages;
      case 'case_status':
        return p.notifyCaseStatus;
      case 'scan_quality':
        return p.notifyScanQuality;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _visible {
    return _items.where((n) {
      final type = '${n['type'] ?? ''}';
      if (!_allowedBySettings(type)) return false;
      if (_filter == 'all') return true;
      if (_filter == 'unread') return n['read'] != true;
      return type == _filter;
    }).toList();
  }

  int get _unreadCount =>
      _items.where((n) => n['read'] != true && _allowedBySettings('${n['type']}')).length;

  Future<void> _markOne(Map<String, dynamic> n) async {
    final id = n['id'];
    if (id is! int || n['read'] == true) return;
    try {
      await widget.api.markNotificationRead(id);
      setState(() => n['read'] = true);
      _emitUnread();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _markAll() async {
    setState(() {
      _markingAll = true;
      _error = null;
    });
    try {
      await widget.api.markAllNotificationsRead();
      setState(() {
        for (final n in _items) {
          n['read'] = true;
        }
      });
      _emitUnread();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _open(Map<String, dynamic> n) {
    _markOne(n);
    final nav = widget.onNavigate;
    if (nav == null) return;
    switch ('${n['type']}') {
      case 'message':
        nav(AppNavItem.messages);
      case 'scan_quality':
        nav(AppNavItem.scans);
      case 'shade':
        nav(AppNavItem.shade);
      case 'scan_body':
        nav(AppNavItem.scanBody);
      case 'sync':
        nav(AppNavItem.settings);
      case 'export':
      case 'case_status':
        nav(AppNavItem.patients);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final visible = _visible;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.notifications_none_rounded,
            title: loc.notificationsTitle,
            subtitle: loc.notificationsSubtitle,
            actions: [
              if (_unreadCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 10),
                  child: Text(
                    loc.notificationsUnreadCount(_unreadCount),
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              _NeoIconAction(
                icon: Icons.refresh_rounded,
                tooltip: loc.refresh,
                onPressed: _loading ? null : _bootstrap,
              ),
              const SizedBox(width: 8),
              _NeoTextAction(
                label: _markingAll ? loc.notificationsMarking : loc.notificationsMarkAll,
                icon: Icons.done_all_rounded,
                enabled: !_markingAll && _unreadCount > 0,
                onPressed: _markAll,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in [
                ('all', loc.filterAll),
                ('unread', loc.notificationsFilterUnread),
                ('message', loc.notificationsFilterMessages),
                ('case_status', loc.notificationsFilterCases),
                ('scan_quality', loc.notificationsFilterScans),
              ])
                SoftFilterChip(
                  label: f.$2,
                  selected: _filter == f.$1,
                  onTap: () => setState(() => _filter = f.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.dentalBlue))
                : visible.isEmpty
                    ? Center(
                        child: SectionCard(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NeoIconBadge(
                                icon: Icons.notifications_off_outlined,
                                size: 52,
                                iconSize: 24,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                loc.notificationsEmpty,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SectionCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        depth: 1.05,
                        child: ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                          itemBuilder: (context, i) {
                            final n = visible[i];
                            return _NotificationTile(
                              item: n,
                              onTap: () => _open(n),
                              onMarkRead: () => _markOne(n),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onMarkRead,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final type = '${item['type'] ?? ''}';
    final unread = item['read'] != true;
    final patient = '${item['patient_name'] ?? ''}'.trim();
    final meta = <String>[
      loc.notificationTypeLabel(type),
      if (patient.isNotEmpty) patient,
      _relative(item['created_at']?.toString()),
    ].where((e) => e.isNotEmpty).join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: unread ? AppColors.sidebarActive.withValues(alpha: 0.55) : Colors.transparent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypeIcon(type: type, unread: unread),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['message'] ?? ''}',
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.navy,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                IconButton(
                  tooltip: loc.notificationsMarkRead,
                  onPressed: onMarkRead,
                  icon: const Icon(Icons.circle, size: 10, color: AppColors.dentalBlue),
                )
              else
                const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }

  static String _relative(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final local = dt.isUtc ? dt.toLocal() : dt;
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${local.day}.${local.month.toString().padLeft(2, '0')}';
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type, required this.unread});

  final String type;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'message' => (Icons.chat_bubble_outline, AppColors.dentalBlue),
      'case_status' => (Icons.assignment_outlined, AppColors.review),
      'scan_quality' => (Icons.warning_amber_rounded, AppColors.warning),
      'shade' => (Icons.palette_outlined, AppColors.aiPurple),
      'scan_body' => (Icons.radio_button_checked_outlined, AppColors.dentalBlue),
      'sync' => (Icons.cloud_sync_outlined, AppColors.success),
      'export' => (Icons.code, AppColors.navy),
      _ => (Icons.notifications_none_rounded, AppColors.muted),
    };

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(14),
        boxShadow: unread ? NeoShadows.soft(depth: 0.55) : NeoShadows.pressed(),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _NeoIconAction extends StatelessWidget {
  const _NeoIconAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadii.borderSm,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.neo,
              borderRadius: AppRadii.borderSm,
              boxShadow: NeoShadows.soft(depth: 0.5),
            ),
            child: Icon(icon, size: 20, color: AppColors.navy),
          ),
        ),
      ),
    );
  }
}

class _NeoTextAction extends StatelessWidget {
  const _NeoTextAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: AppRadii.borderSm,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: enabled ? AppColors.navy : AppColors.inset,
            borderRadius: AppRadii.borderSm,
            boxShadow: enabled ? NeoShadows.soft(depth: 0.4) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: enabled ? Colors.white : AppColors.muted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : AppColors.muted,
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

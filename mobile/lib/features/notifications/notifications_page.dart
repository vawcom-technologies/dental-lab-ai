import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/touchable.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';
import 'notification_inbox_controller.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.inbox,
    this.onNavigate,
    this.active = true,
  });

  final NotificationInboxController inbox;
  final ValueChanged<AppNavItem>? onNavigate;
  final bool active;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _markingAll = false;
  String? _markingId;
  String _filter = 'all';

  NotificationInboxController get _inbox => widget.inbox;

  @override
  void initState() {
    super.initState();
    _inbox.addListener(_onInbox);
    if (widget.active) {
      unawaited(_openAndMarkRead());
    } else {
      unawaited(_inbox.refresh(announce: false));
    }
  }

  @override
  void didUpdateWidget(covariant NotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inbox != widget.inbox) {
      oldWidget.inbox.removeListener(_onInbox);
      widget.inbox.addListener(_onInbox);
    }
    if (widget.active && !oldWidget.active) {
      unawaited(_openAndMarkRead());
    }
  }

  @override
  void dispose() {
    _inbox.removeListener(_onInbox);
    super.dispose();
  }

  void _onInbox() {
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _items => _inbox.items;

  bool _allowedBySettings(String type) => _inbox.allowedBySettings(type);

  List<Map<String, dynamic>> get _visible {
    return _items.where((n) {
      final type = '${n['type'] ?? ''}';
      if (type == 'message') return false;
      if (!_allowedBySettings(type)) return false;
      if (_filter == 'all' || _filter == 'message') return true;
      if (_filter == 'unread') return n['read'] != true;
      return type == _filter;
    }).toList();
  }

  int get _unreadCount => _items
      .where((n) => n['read'] != true && _allowedBySettings('${n['type']}'))
      .length;

  Future<void> _markOne(Map<String, dynamic> n) async {
    final id = '${n['id'] ?? ''}'.trim();
    if (id.isEmpty || n['read'] == true) return;
    if (_markingAll || _markingId != null) return;
    setState(() => _markingId = id);
    try {
      await _inbox.markRead(id);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _markingId = null);
    }
  }

  Future<void> _openAndMarkRead() async {
    await _inbox.refresh(announce: false);
    await _autoMarkAllRead();
  }

  Future<void> _autoMarkAllRead() async {
    try {
      await _inbox.markAllRead();
    } catch (_) {}
  }

  Future<void> _markAll() async {
    if (_markingAll || _markingId != null) return;
    setState(() => _markingAll = true);
    try {
      await _inbox.markAllRead();
      if (mounted) {
        AppSnackBars.success(context, 'All notifications marked as read');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _open(Map<String, dynamic> n) {
    AppHaptics.light();
    _markOne(n);
    final nav = widget.onNavigate;
    if (nav == null) return;
    final type = '${n['type']}';
    final statusRaw = '${n['case_status'] ?? ''}'.trim();
    final status =
        statusRaw.isEmpty ? null : CaseStatuses.normalize(statusRaw);
    switch (type) {
      case 'message':
        nav(AppNavItem.messages);
      case 'scan_quality':
        nav(AppNavItem.scans);
      case 'shade':
        nav(AppNavItem.shade);
      case 'appointment':
        nav(AppNavItem.appointments);
      // Scan body parked — restore when needed.
      // case 'scan_body':
      //   nav(AppNavItem.scanBody);
      case 'sync':
        nav(AppNavItem.settings);
      case 'export':
        nav(AppNavItem.patients);
      case 'case_status':
        if (status == CaseStatuses.pending || status == CaseStatuses.rejected) {
          nav(AppNavItem.scans);
        } else if (status == CaseStatuses.inReview) {
          nav(AppNavItem.messages);
        } else {
          nav(AppNavItem.patients);
        }
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
            subtitle: _unreadCount > 0
                ? loc.notificationsUnreadCount(_unreadCount)
                : loc.notificationsSubtitle,
            chromeActions: [
              _HeaderIconButton(
                icon: Icons.refresh_rounded,
                tooltip: loc.refresh,
                onPressed: () => _inbox.refresh(announce: false),
              ),
            ],
            actions: [
              if (_unreadCount > 0)
                _HeaderTextButton(
                  label: _markingAll
                      ? loc.notificationsMarking
                      : loc.notificationsMarkAll,
                  icon: Icons.done_all_rounded,
                  enabled: !_markingAll,
                  onPressed: _markAll,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in [
                ('all', loc.filterAll),
                ('unread', loc.notificationsFilterUnread),
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
          const SizedBox(height: 14),
          Expanded(
            child: AppSwitcher(
              child: KeyedSubtree(
                key: ValueKey('$_filter-${visible.length}'),
                child: visible.isEmpty
                    ? IpadRefresh.fill(
                        onRefresh: () => _inbox.refresh(announce: false),
                        child: Center(
                          child: SectionCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 22,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: 28,
                                  color: AppColors.muted.withValues(alpha: 0.7),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  loc.notificationsEmpty,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SectionCard(
                        padding: EdgeInsets.zero,
                        depth: 0.9,
                        child: IpadRefresh(
                          onRefresh: () => _inbox.refresh(announce: false),
                          slivers: [
                            SliverList.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                indent: 56,
                                endIndent: 14,
                                color: AppColors.border.withValues(alpha: 0.55),
                              ),
                              itemBuilder: (context, i) {
                                final n = visible[i];
                                return _NotificationTile(
                                  item: n,
                                  marking: _markingId == '${n['id']}',
                                  enabled: !_markingAll && _markingId == null,
                                  onTap: () => _open(n),
                                  onMarkRead: () {
                                    AppHaptics.selection();
                                    _markOne(n);
                                  },
                                );
                              },
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

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onMarkRead,
    this.marking = false,
    this.enabled = true,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;
  final bool marking;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final type = '${item['type'] ?? ''}';
    final unread = item['read'] != true;
    final patient = '${item['patient_name'] ?? ''}'.trim();
    final statusRaw = '${item['case_status'] ?? ''}'.trim();
    final status = statusRaw.isEmpty ? null : CaseStatuses.normalize(statusRaw);
    final meta = <String>[
      loc.notificationTypeLabel(type),
      if (patient.isNotEmpty) patient,
      _relative(item['created_at']?.toString()),
    ].where((e) => e.isNotEmpty).join(' · ');

    return Touchable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: BorderRadius.zero,
      minHeight: 0,
      scale: 0.995,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        color: unread
            ? AppColors.sidebarActive.withValues(alpha: 0.45)
            : Colors.transparent,
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                      color: AppColors.navy,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: 8),
                        StatusChip(statusKey: status),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (marking)
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 4, 8),
                child: ToothLoadingIndicator(size: 14, compact: true),
              )
            else if (unread)
              Tooltip(
                message: loc.notificationsMarkRead,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? onMarkRead : null,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 4, 4, 8),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.dentalBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 18),
          ],
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
      'appointment' => (Icons.event_outlined, AppColors.review),
      'scan_body' => (Icons.radio_button_checked_outlined, AppColors.dentalBlue),
      'sync' => (Icons.cloud_sync_outlined, AppColors.success),
      'export' => (Icons.code, AppColors.navy),
      _ => (Icons.notifications_none_rounded, AppColors.muted),
    };

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: unread ? color.withValues(alpha: 0.12) : AppColors.inset,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
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
      child: Touchable(
        onTap: onPressed,
        enabled: onPressed != null,
        borderRadius: BorderRadius.circular(10),
        minHeight: 34,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.neo,
            borderRadius: BorderRadius.circular(10),
            boxShadow: NeoShadows.soft(depth: 0.35),
          ),
          child: Icon(icon, size: 17, color: AppColors.navy),
        ),
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({
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
    return Touchable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      borderRadius: BorderRadius.circular(10),
      minHeight: 34,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.navy : AppColors.inset,
          borderRadius: BorderRadius.circular(10),
          boxShadow: enabled ? NeoShadows.soft(depth: 0.3) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: enabled ? Colors.white : AppColors.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : AppColors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

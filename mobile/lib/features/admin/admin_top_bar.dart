import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/auth/session_coordinator.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/date_formats.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';
import '../chat/models/chat_models.dart';
import '../chat/state/chat_controller.dart';
import '../notifications/notification_inbox_controller.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// What every admin page needs from the shell: the bell's inbox, chat, and
/// navigation. Provided once around the admin pages.
class AdminChrome extends InheritedWidget {
  const AdminChrome({
    super.key,
    required this.api,
    required this.inbox,
    required this.chat,
    required this.onOpen,
    required this.openChat,
    required super.child,
  });

  final ApiClient api;
  final NotificationInboxController inbox;
  final ChatController chat;
  final void Function(AppNavItem page, int tab) onOpen;
  final void Function(Conversation c) openChat;

  static AdminChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminChrome>();

  @override
  bool updateShouldNotify(AdminChrome old) => false;
}

// ── Popover ────────────────────────────────────────────────────────────────

/// iPad-style popover anchored under the widget at [anchor]: it grows out of
/// that corner with a spring and dismisses on an outside tap.
Future<T?> showAdminPopover<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 340,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  return Navigator.of(anchor).push(_PopoverRoute<T>(
    anchor: rect,
    width: width,
    builder: builder,
    barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
  ));
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.width,
    required this.builder,
    required this.barrierLabel,
  });

  final Rect anchor;
  final double width;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.06);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => AppMotion.normal;

  @override
  Duration get reverseTransitionDuration => AppMotion.fast;

  @override
  Widget buildPage(BuildContext context, Animation<double> a, Animation<double> s) {
    final screen = MediaQuery.sizeOf(context);
    final w = width.clamp(0.0, screen.width - 24);
    // Right edge under the anchor, kept on screen.
    final left = (anchor.right - w).clamp(12.0, screen.width - w - 12);
    final top = anchor.bottom + 8;
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: w,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screen.height - top - 24),
            // Plain white card (no Material tint) with a soft lift shadow.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.16),
                    offset: const Offset(0, 12),
                    blurRadius: 36,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Material(type: MaterialType.transparency, child: builder(context)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> a,
    Animation<double> s,
    Widget child,
  ) {
    final screen = MediaQuery.sizeOf(context);
    // Grow from the anchor's centre-x, expressed in the popover's frame.
    final w = width.clamp(0.0, screen.width - 24);
    final left = (anchor.right - w).clamp(12.0, screen.width - w - 12);
    final originX = ((anchor.center.dx - left) / w * 2 - 1).clamp(-1.0, 1.0);
    final curved = CurvedAnimation(parent: a, curve: AppMotion.spring, reverseCurve: AppMotion.easeIn);
    return FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: AppMotion.easeOut),
      child: ScaleTransition(
        alignment: Alignment(originX, -1),
        scale: Tween(begin: 0.86, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

// ── Bell + profile ─────────────────────────────────────────────────────────

/// Bell and profile chip for the top-right of every admin page.
class AdminTopActions extends StatelessWidget {
  const AdminTopActions({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = AdminChrome.maybeOf(context);
    if (chrome == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BellButton(chrome: chrome),
        const SizedBox(width: 8),
        _ProfileChip(chrome: chrome),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.child, required this.onTap, this.tooltip});

  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final b = Pressable(
      onTap: onTap,
      scale: 0.92,
      builder: (_, pressed) => AnimatedContainer(
        duration: AppMotion.fast,
        height: 44,
        constraints: const BoxConstraints(minWidth: 44),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed ? AppColors.sidebarActive : AppColors.card,
          borderRadius: BorderRadius.circular(22),
          boxShadow: NeoShadows.raised(depth: 0.6),
        ),
        child: child,
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.chrome});

  final AdminChrome chrome;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: chrome.inbox,
      builder: (context, _) {
        final unread = chrome.inbox.unreadCount;
        return Builder(
          builder: (anchor) => _RoundButton(
            tooltip: loc.navNotifications,
            onTap: () {
              chrome.inbox.refresh(announce: false);
              showAdminPopover<void>(
                anchor,
                width: 360,
                builder: (_) => _NotificationsPopover(chrome: chrome),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none_rounded, color: AppColors.navy, size: 22),
                Positioned(
                  right: -3,
                  top: -3,
                  child: AnimatedScale(
                    scale: unread > 0 ? 1 : 0,
                    duration: AppMotion.normal,
                    curve: AppMotion.spring,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationsPopover extends StatelessWidget {
  const _NotificationsPopover({required this.chrome});

  final AdminChrome chrome;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: chrome.inbox,
      builder: (context, _) {
        // Newest few only; the rest are one tap away on the Notifications page.
        final items = chrome.inbox.items.take(6).toList();
        final more = chrome.inbox.items.length - items.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
              child: Row(
                children: [
                  Expanded(child: _PopoverTitle(loc.navNotifications)),
                  if (chrome.inbox.unreadCount > 0)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      onPressed: chrome.inbox.markAllRead,
                      child: Text(
                        loc.tr('admin.markAllRead'),
                        style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dentalBlue),
                      ),
                    ),
                ],
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                child: Column(
                  children: [
                    const AdminIcon(icon: Icons.notifications_off_outlined, color: AppColors.muted, size: 48),
                    const SizedBox(height: 10),
                    Text(
                      loc.notificationsEmpty,
                      textAlign: TextAlign.center,
                      style: AppFonts.style(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(height: 1, indent: 52, color: AppColors.border.withValues(alpha: 0.5)),
                  itemBuilder: (context, i) {
                    final n = items[i];
                    final unread = !NotificationInboxController.isRead(n);
                    final text = loc.localizeNotificationMessage(
                      '${n['message'] ?? ''}',
                      type: '${n['type'] ?? ''}',
                      patientName: '${n['patient_name'] ?? ''}',
                    );
                    final at = DateTime.tryParse('${n['created_at'] ?? ''}')?.toLocal();
                    return Pressable(
                      scale: 0.98,
                      onTap: () {
                        final id = '${n['id'] ?? ''}';
                        if (id.isNotEmpty) chrome.inbox.markRead(id);
                      },
                      builder: (_, _) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AdminIcon(
                              icon: Icons.notifications_active_outlined,
                              size: 32,
                              color: unread ? AppColors.dentalBlue : AppColors.muted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    text,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppFonts.style(
                                      fontSize: 13.5,
                                      height: 1.3,
                                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  if (at != null)
                                    Text(adminWhen(context, at), style: AppFonts.style(fontSize: 11.5, color: AppColors.muted)),
                                ],
                              ),
                            ),
                            AnimatedOpacity(
                              opacity: unread ? 1 : 0,
                              duration: AppMotion.normal,
                              child: Container(
                                margin: const EdgeInsets.only(top: 6, left: 6),
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: AppColors.dentalBlue, shape: BoxShape.circle),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
            _PopoverRow(
              icon: Icons.inbox_outlined,
              label: more > 0
                  ? '${loc.tr('admin.allNotifications')} (${loc.trp('admin.moreCount', {'n': more})})'
                  : loc.tr('admin.allNotifications'),
              onTap: () {
                Navigator.pop(context);
                chrome.onOpen(AppNavItem.notifications, 0);
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.chrome});

  final AdminChrome chrome;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final roleLabel = AppRoles.label(chrome.api.role, loc);
    final name = (chrome.api.userName ?? '').trim().isEmpty ? roleLabel : chrome.api.userName!.trim();
    final compact = AppBreakpoints.isPhone(context);
    return Builder(
      builder: (anchor) => _RoundButton(
        tooltip: name,
        onTap: () => showAdminPopover<void>(
          anchor,
          width: 300,
          builder: (_) => _ProfileMenu(chrome: chrome, name: name),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, 4, compact ? 4 : 12, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: AvatarSource.changed,
                builder: (_, _, _) => UserAvatar(name: name, url: chrome.api.avatarUrl, size: 36),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppFonts.style(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    Text(roleLabel, style: AppFonts.style(fontSize: 11.5, color: AppColors.muted)),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.chrome, required this.name});

  final AdminChrome chrome;
  final String name;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final locale = LocaleScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            children: [
              UserAvatar(name: name, url: chrome.api.avatarUrl, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppFonts.style(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    Text(
                      chrome.api.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    AdminBadge(AppRoles.label(chrome.api.role, loc), color: AppColors.navy),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
        // Only the admin may change photos (users can't change their own).
        if (chrome.api.isAdmin)
        _PopoverRow(
          icon: Icons.photo_camera_outlined,
          label: loc.tr('avatar.changeMine'),
          onTap: () async {
            // The popover closes first; keep working from the app overlay.
            final host = Navigator.of(context).overlay!.context;
            Navigator.pop(context);
            final photo = await pickProfilePhoto(host);
            if (photo == null || !host.mounted) return;
            await adminRun(
              host,
              () => chrome.api.adminSetAvatar(
                chrome.api.userId ?? '',
                bytes: photo.bytes,
                contentType: photo.contentType,
              ),
              done: loc.tr('avatar.changedMine'),
            );
          },
        ),
        _PopoverRow(
          icon: Icons.settings_outlined,
          label: loc.navSettings,
          onTap: () {
            Navigator.pop(context);
            chrome.onOpen(AppNavItem.settings, 0);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.translate_rounded, size: 20, color: AppColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Text(loc.settingsLanguageTitle, style: AppFonts.style(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.navy)),
              ),
              CupertinoSlidingSegmentedControl<String>(
                groupValue: locale.code,
                children: const {
                  'en': Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('EN')),
                  'de': Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('DE')),
                },
                onValueChanged: (v) {
                  if (v != null) locale.setLanguage(v);
                },
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
        _PopoverRow(
          icon: Icons.logout_rounded,
          label: loc.signOut,
          color: AppColors.danger,
          onTap: () async {
            Navigator.pop(context);
            final ok = await AppDialogs.confirm(
              context,
              title: loc.tr('admin.signOutTitle'),
              confirmLabel: loc.signOut,
              isDestructive: true,
            );
            if (ok) SessionCoordinator.signOut(chrome.api);
          },
        ),
      ],
    );
  }
}

class _PopoverTitle extends StatelessWidget {
  const _PopoverTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy),
      );
}

class _PopoverRow extends StatelessWidget {
  const _PopoverRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.navy,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      builder: (_, pressed) => AnimatedContainer(
        duration: AppMotion.fast,
        color: pressed ? AppColors.surface : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: AppFonts.style(fontSize: 15, fontWeight: FontWeight.w500, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search ────────────────────────────────────────────────────────────────

/// Search field that opens [AdminSearchPage], growing out of the field.
class AdminSearchLauncher extends StatelessWidget {
  const AdminSearchLauncher({super.key, this.page, this.hint});

  /// Page to grow into; the admin's dentists/labs search by default.
  final Widget Function(AdminChrome chrome)? page;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final chrome = AdminChrome.maybeOf(context);
    return Builder(
      builder: (anchor) => Pressable(
        scale: 0.985,
        onTap: chrome == null
            ? null
            : () {
                final box = anchor.findRenderObject()! as RenderBox;
                final rect = box.localToGlobal(Offset.zero) & box.size;
                Navigator.of(context).push(_ExpandRoute(
                  from: rect,
                  page: page?.call(chrome) ?? AdminSearchPage(chrome: chrome),
                ));
              },
        builder: (_, _) => Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(23),
            boxShadow: NeoShadows.raised(depth: 0.6),
          ),
          child: Row(
            children: [
              const Icon(CupertinoIcons.search, size: 19, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hint ?? loc.tr('admin.searchHint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(fontSize: 15, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reveals the new page from [from] (the tapped field) to full screen, then
/// shrinks back into it on close.
class _ExpandRoute extends PageRoute<void> {
  _ExpandRoute({required this.from, required this.page});

  final Rect from;
  final Widget page;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 460);

  @override
  Duration get reverseTransitionDuration => AppMotion.normal;

  @override
  Widget buildPage(BuildContext context, Animation<double> a, Animation<double> s) => page;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> a, Animation<double> s, Widget child) {
    final curved = CurvedAnimation(parent: a, curve: AppMotion.spring, reverseCurve: AppMotion.easeIn);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final size = MediaQuery.sizeOf(context);
        final t = curved.value;
        final rect = Rect.lerp(from, Offset.zero & size, t)!;
        final radius = 23 * (1 - t);
        return Stack(
          children: [
            // Page behind dims a touch while the sheet grows.
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: AppColors.navy.withValues(alpha: 0.08 * t)),
              ),
            ),
            Positioned.fill(
              child: ClipPath(
                clipper: _RRectClipper(rect, radius),
                child: Opacity(
                  // Content fades in after the shape has started to grow.
                  opacity: ((t - 0.15) / 0.85).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RRectClipper extends CustomClipper<Path> {
  _RRectClipper(this.rect, this.radius);

  final Rect rect;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  bool shouldReclip(_RRectClipper old) => old.rect != rect || old.radius != radius;
}

/// Find any lab or dentist by name, clinic or email.
class AdminSearchPage extends StatefulWidget {
  const AdminSearchPage({super.key, required this.chrome});

  final AdminChrome chrome;

  @override
  State<AdminSearchPage> createState() => _AdminSearchPageState();
}

class _AdminSearchPageState extends State<AdminSearchPage> {
  final _tab = ValueNotifier(0);
  String _q = '';

  // ponytail: loads every lab and dentist and filters on device, same
  // ceiling as the Users page; move to the `q` param past a few thousand.
  late final Future<(List<AdminLab>, List<AdminDentist>)> _data = () async {
    final r = await Future.wait([widget.chrome.api.adminLabs(), widget.chrome.api.adminDentists()]);
    return (r[0].map(AdminLab.new).toList(), r[1].map(AdminDentist.new).toList());
  }();

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  bool _hit(String? s) => (s ?? '').toLowerCase().contains(_q);

  Future<void> _openDentist(AdminDentist d) async {
    final loc = AppLocalizations.of(context);
    final v = await adminChoose<String>(
      context,
      title: d.name,
      message: dentistPlace(loc, d.labName, d.clinicName),
      options: [
        ('msg', loc.labsMessage),
        ('users', loc.tr('admin.showInUsers')),
      ],
    );
    if (!mounted || v == null) return;
    Navigator.pop(context);
    if (v == 'msg') {
      final c = await widget.chrome.chat.openOrCreateWith(d.id);
      widget.chrome.openChat(c);
    } else {
      widget.chrome.onOpen(AppNavItem.laboratories, d.labId == null ? 1 : 0);
    }
  }

  Future<void> _openLab(AdminLab l) async {
    final loc = AppLocalizations.of(context);
    final v = await adminChoose<String>(
      context,
      title: l.name,
      message: dentistCount(loc, l.dentistCount),
      options: [
        ('msg', loc.labsMessage),
        ('users', loc.tr('admin.showInUsers')),
      ],
    );
    if (!mounted || v == null) return;
    Navigator.pop(context);
    if (v == 'msg') {
      final c = await widget.chrome.chat.openOrCreateWith(l.id);
      widget.chrome.openChat(c);
    } else {
      widget.chrome.onOpen(AppNavItem.laboratories, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: AppBreakpoints.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CupertinoSearchTextField(
                      autofocus: true,
                      placeholder: loc.tr('admin.searchHint'),
                      style: AppFonts.style(fontSize: 16, color: AppColors.navy),
                      backgroundColor: AppColors.card,
                      borderRadius: BorderRadius.circular(23),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 14),
                    onPressed: () => Navigator.pop(context),
                    child: Text(loc.cancel, style: AppFonts.style(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.dentalBlue)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AdminTabs(
                tab: _tab,
                labels: [loc.filterAll, loc.tr('admin.tile.dentists'), loc.tr('admin.tile.labs')],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<(List<AdminLab>, List<AdminDentist>)>(
                  future: _data,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return AdminEmpty(
                        icon: Icons.cloud_off_rounded,
                        title: loc.tr('admin.loadFailed'),
                        subtitle: friendlyError(snap.error!),
                      );
                    }
                    if (!snap.hasData) return const ToothPageLoader(inPlace: true);
                    return ValueListenableBuilder<int>(
                      valueListenable: _tab,
                      builder: (context, t, _) {
                        final labs = t == 1
                            ? <AdminLab>[]
                            : snap.data!.$1.where((l) => _hit(l.name) || _hit(l.email)).toList();
                        final dentists = t == 2
                            ? <AdminDentist>[]
                            : snap.data!.$2
                                .where((d) => _hit(d.name) || _hit(d.email) || _hit(d.clinicName) || _hit(d.labName))
                                .toList();
                        if (labs.isEmpty && dentists.isEmpty) {
                          return AdminEmpty(
                            icon: Icons.search_off_rounded,
                            title: loc.tr('admin.noMatches'),
                            subtitle: loc.tr('admin.noMatchesSub'),
                          );
                        }
                        return CustomScrollView(
                          slivers: [
                            if (labs.isNotEmpty) ...[
                              _header(loc.tr('admin.tile.labs'), labs.length),
                              adminSliverList<AdminLab>(
                                labs,
                                id: (l) => 'l${l.id}',
                                gap: 8,
                                (context, l) => AdminCard(
                                  onTap: () => _openLab(l),
                                  padding: const EdgeInsets.all(12),
                                  child: AdminRow(
                                    leading: UserAvatar(name: l.name, url: l.avatarUrl, size: 38),
                                    title: l.name,
                                    badges: [
                                      if (l.deleted) AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger),
                                    ],
                                    lines: [
                                      '${l.displayId} · ${dentistCount(loc, l.dentistCount)} · ${l.email}',
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (dentists.isNotEmpty) ...[
                              _header(loc.tr('admin.tile.dentists'), dentists.length),
                              adminSliverList<AdminDentist>(
                                dentists,
                                id: (d) => 'd${d.id}',
                                gap: 8,
                                (context, d) => AdminCard(
                                  onTap: () => _openDentist(d),
                                  padding: const EdgeInsets.all(12),
                                  child: AdminRow(
                                    leading: UserAvatar(name: d.name, url: d.avatarUrl, size: 38),
                                    title: d.name.isEmpty ? d.email : d.name,
                                    badges: [
                                      if (d.deleted) AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger),
                                    ],
                                    lines: [
                                      d.displayId,
                                      dentistPlace(loc, d.labName, d.clinicName),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
      ),
    );
  }

  Widget _header(String title, int n) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: SectionLabel('$title · $n'),
        ),
      );
}

/// Today's date chip for the dashboard bar.
class AdminDateChip extends StatelessWidget {
  const AdminDateChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: NeoShadows.raised(depth: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.calendar, size: 18, color: AppColors.navy),
          const SizedBox(width: 8),
          Text(
            formatAppDate(context, DateTime.now(), 'EEE, MMM d, yyyy'),
            style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
          ),
        ],
      ),
    );
  }
}

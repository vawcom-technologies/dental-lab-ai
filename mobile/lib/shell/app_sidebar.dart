import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/haptics/app_haptics.dart';
import '../core/l10n/app_localizations.dart';
import '../core/navigation/app_page_routes.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand_logo.dart';
import '../core/widgets/touchable.dart';

enum AppNavItem {
  dashboard,
  patients,
  newPatient,
  appointments,
  camera,
  scans,
  shade,
  smilePreview,
  interpreter,
  scanBody,
  messages,
  laboratories,
  adminSignups,
  review,
  lab,
  notifications,
  reports,
  settings,
}

/// iPad: navy logo circle over a navy icon rail. The page background cuts a
/// notch into the rail's right edge around the active icon.
/// Phone ([asDrawer]): full-height labelled menu.
/// [admin] swaps the clinical tools for the admin pages.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.active,
    required this.onSelect,
    this.messageBadge = 0,
    this.notificationBadge = 0,
    this.labBadge = 0,
    this.admin = false,
    this.lab = false,
    this.asDrawer = false,
  });

  final AppNavItem active;
  final ValueChanged<AppNavItem> onSelect;
  final int messageBadge;
  final int notificationBadge;

  /// Items waiting on the lab (transfers, joins, sharing tickets).
  final int labBadge;
  final bool admin;

  /// Lab accounts also get the review queue.
  final bool lab;
  final bool asDrawer;

  /// Rail (and logo circle) width at scale 1. [_bubbleRoom] to its right
  /// keeps the notch lip and shadows from touching the page.
  static const railWidth = 64.0;
  static const _bubbleRoom = 6.0;

  /// Space between the rail's rounded ends and the first/last icon.
  static const _railEndPad = 20.0;
  static const _drawerHeader = 104.0;
  // Divider block above Settings: 4 + 1 + 10.
  static const _footerGap = 15.0;
  static const _drawerBottomPad = 22.0;

  /// Rail size multiplier from the iPad's short side (stable across
  /// rotation): mini ≈ 0.9, 11" = 1, 12.9"/13" ≈ 1.15.
  static double railScale(Size screen) =>
      (screen.shortestSide / 834).clamp(0.9, 1.15);

  /// Full rail width including room for the bubble, before the left margin.
  static double railExtent(Size screen) =>
      (railWidth + _bubbleRoom) * railScale(screen);

  static const _railGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF26446B), AppColors.navy],
  );

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    if (asDrawer) return _navBody(context, s, 1);
    final k = railScale(MediaQuery.sizeOf(context));
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 0, 12),
        child: SizedBox(
          width: (railWidth + _bubbleRoom) * k,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: railWidth * k,
                height: railWidth * k,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _railGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.18),
                      offset: const Offset(0, 6),
                      blurRadius: 16,
                    ),
                  ],
                ),
                // Wordmark is dark ink; show it white on navy.
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                  child: BrandLogo(height: 28 * k, width: 46 * k),
                ),
              ),
              SizedBox(height: 10 * k),
              Expanded(child: _navBody(context, s, k)),
            ],
          ),
        ),
      ),
    );
  }

  /// [k] scales the rail; the drawer always passes 1.
  Widget _navBody(BuildContext context, AppLocalizations s, double k) {
    final messages = _NavEntry(
      AppNavItem.messages,
      Icons.chat_bubble_outline,
      s.navMessages,
      badge: messageBadge,
      badgeColor: AppColors.danger,
    );
    final notifications = _NavEntry(
      AppNavItem.notifications,
      Icons.notifications_none_rounded,
      s.navNotifications,
      badge: notificationBadge,
      badgeColor: AppColors.warning,
    );
    final items = <_NavEntry>[
      _NavEntry(AppNavItem.dashboard, Icons.grid_view_rounded, s.navDashboard),
      if (admin) ...[
        _NavEntry(
          AppNavItem.adminSignups,
          Icons.how_to_reg_outlined,
          s.navSignups,
        ),
        _NavEntry(
          AppNavItem.laboratories,
          Icons.manage_accounts_outlined,
          s.navLaboratories,
        ),
        _NavEntry(AppNavItem.patients, Icons.people_outline, s.navPatients),
        messages,
        notifications,
      ] else ...[
        _NavEntry(AppNavItem.patients, Icons.people_outline, s.navPatients),
        if (lab) _NavEntry(AppNavItem.review, Icons.fact_check_outlined, s.navReview),
        if (lab) _NavEntry(AppNavItem.lab, Icons.apartment_rounded, s.navLab, badge: labBadge, badgeColor: AppColors.warning),
        _NavEntry(
          AppNavItem.appointments,
          Icons.calendar_today_outlined,
          s.navAppointments,
        ),
        // Camera / scans / shade / smile are chairside dentist work; labs
        // review from the patient record and the Review queue.
        if (!lab) ...[
          _NavEntry(AppNavItem.camera, Icons.photo_camera_outlined, s.navCamera),
          _NavEntry(AppNavItem.scans, Icons.view_in_ar_outlined, s.navScans),
          _NavEntry(AppNavItem.shade, Icons.palette_outlined, s.navShade),
          _NavEntry(
            AppNavItem.smilePreview,
            Icons.sentiment_satisfied_alt_outlined,
            s.navSmilePreview,
          ),
        ],
        _NavEntry(
          AppNavItem.interpreter,
          Icons.translate_rounded,
          s.navInterpreter,
        ),
        // Scan body parked — restore when needed.
        // _NavEntry(AppNavItem.scanBody, Icons.radio_button_checked_outlined,
        //     s.navScanBody),
        messages,
        notifications,
        _NavEntry(AppNavItem.reports, Icons.bar_chart_rounded, s.navReports),
      ],
    ];
    final settings = _NavEntry(
      AppNavItem.settings,
      Icons.settings_outlined,
      s.navSettings,
    );
    final selectedId = active == AppNavItem.newPatient
        ? AppNavItem.patients
        : active;
    final index = active == AppNavItem.settings
        ? items.length
        : items.indexWhere((e) => e.id == selectedId);
    // The rail is already inside a SafeArea (built below this context), so
    // only the full-height drawer pads for the notch / home indicator.
    final inset = asDrawer ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    final header = asDrawer ? _drawerHeader : 0.0;
    final minTopPad = asDrawer ? 0.0 : _railEndPad * k;
    final minBottomPad = asDrawer ? _drawerBottomPad : _railEndPad * k;
    final bubble = asDrawer ? _NavPainter.pill : _NavPainter.railBubble * k;
    final divider = asDrawer
        ? AppColors.border.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.12);

    return LayoutBuilder(
      builder: (context, box) {
        // The first/last icons always keep clear of the rail's rounded ends
        // (endExtra), however many pages are listed, so the active notch
        // never bites into a corner and both ends look the same. Rows share
        // what's left: 42–60pt. Very short windows scroll.
        final minFixed =
            inset.top +
            header +
            minTopPad +
            _footerGap +
            minBottomPad +
            inset.bottom;
        final rows = items.length + 1;
        double slotFor(double extra) =>
            ((box.maxHeight - minFixed - 2 * extra) / rows).clamp(42.0 * k, 60.0 * k);
        double extraFor(double slot) => asDrawer
            ? 0.0
            : math.max(0.0, _NavPainter.flareReach(k) - slot / 2 - minTopPad);
        // Reserve the ends first, then fit the rows (a smaller row needs a
        // touch more end room, so settle once more).
        var slot = slotFor(extraFor(60.0 * k));
        final endExtra = extraFor(slot);
        slot = slotFor(endExtra);
        final topPad = minTopPad + endExtra;
        final bottomPad = minBottomPad + endExtra;
        final content = minFixed + 2 * endExtra + rows * slot;
        // Rail and drawer are full height: Settings pins to the bottom.
        final height = math.max(box.maxHeight, content);
        final slotTop = index == items.length
            ? height - inset.bottom - bottomPad - slot
            : inset.top + header + topPad + index * slot;
        return SingleChildScrollView(
          primary: false,
          // Let shadows and the bubble paint past the scroll bounds.
          clipBehavior: Clip.none,
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _NavBackdrop(
                    index: index,
                    top: slotTop + (slot - bubble) / 2,
                    rail: !asDrawer,
                    left: inset.left,
                    scale: k,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    inset.left,
                    inset.top,
                    asDrawer ? 0 : _bubbleRoom * k,
                    inset.bottom,
                  ),
                  child: Column(
                    children: [
                      if (asDrawer)
                        SizedBox(height: header, child: _drawerHeaderView(s)),
                      SizedBox(height: topPad),
                      for (final e in items) _item(e, selectedId, slot, k),
                      const Spacer(),
                      Container(
                        height: 1,
                        margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                        color: divider,
                      ),
                      _item(settings, selectedId, slot, k),
                      SizedBox(height: bottomPad),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _drawerHeaderView(AppLocalizations s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(height: 48),
          const SizedBox(height: 8),
          Text(
            s.proEdition,
            style: AppFonts.style(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(_NavEntry e, AppNavItem selectedId, double slot, double k) {
    final selected = selectedId == e.id;
    // New patient lives under Patients; tapping Patients still goes back.
    final reselect = selected && active == e.id;
    final idle = asDrawer
        ? AppColors.muted
        : Colors.white.withValues(alpha: 0.62);
    final fg = selected ? Colors.white : idle;
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: fg),
          duration: AppMotion.normal,
          curve: AppMotion.easeOut,
          builder: (_, color, _) => Icon(e.icon, size: 22 * k, color: color),
        ),
        if (e.badge != null && e.badge! > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: e.badgeColor ?? AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(
                  color: asDrawer ? Colors.white : AppColors.navy,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
    final Widget content = asDrawer
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.normal,
                    curve: AppMotion.easeOut,
                    style: AppFonts.style(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                    child: Text(
                      e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          )
        // Active icon rides out with the bubble into the notch. Translate,
        // not padding: padding would squeeze the icon in the narrow rail.
        : Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: selected ? _NavPainter.railShift * k : 0),
              duration: AppMotion.page,
              curve: AppMotion.easeOut,
              builder: (_, dx, child) =>
                  Transform.translate(offset: Offset(dx, 0), child: child),
              child: icon,
            ),
          );
    final row = Touchable(
      onTap: () {
        if (reselect) {
          AppHaptics.light();
          return;
        }
        AppHaptics.selection();
        onSelect(e.id);
      },
      haptic: false,
      borderRadius: BorderRadius.circular(slot / 2),
      minHeight: slot,
      child: SizedBox(height: slot, child: content),
    );
    // Icon-only rail: the label lives in the tooltip and screen reader.
    return asDrawer
        ? row
        : Tooltip(message: e.label, preferBelow: false, child: row);
  }
}

class _NavEntry {
  const _NavEntry(
    this.id,
    this.icon,
    this.label, {
    this.badge,
    this.badgeColor,
  });

  final AppNavItem id;
  final IconData icon;
  final String label;
  final int? badge;
  final Color? badgeColor;
}

/// Animates the active bubble (and, on the rail, the notch) between rows.
/// The leading edge runs ahead of the trailing one, so the bubble stretches
/// into a capsule mid-flight and settles back round.
class _NavBackdrop extends StatefulWidget {
  const _NavBackdrop({
    required this.index,
    required this.top,
    required this.rail,
    required this.left,
    required this.scale,
  });

  /// Active row, or -1 when nothing in the nav is active.
  final int index;
  final double top;
  final bool rail;
  final double left;
  final double scale;

  @override
  State<_NavBackdrop> createState() => _NavBackdropState();
}

class _NavBackdropState extends State<_NavBackdrop>
    with SingleTickerProviderStateMixin {
  static const _lead = AppMotion.easeOut;
  static const _trail = Curves.easeInOutCubic;

  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  late double _fromLead = widget.top;
  late double _fromTrail = widget.top;

  /// Current (lead, trail) edges heading for [to]. The stretch is capped so
  /// long jumps stay a capsule, not a slab.
  (double, double) _edges(double to) {
    final a = _fromLead + (to - _fromLead) * _lead.transform(_c.value);
    final b = _fromTrail + (to - _fromTrail) * _trail.transform(_c.value);
    return (a, b.clamp(a - 56, a + 56));
  }

  @override
  void didUpdateWidget(_NavBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.index == old.index) {
      // Layout shift only (resize, rotation): follow it, don't animate.
      if (!_c.isAnimating) _fromLead = _fromTrail = widget.top;
      return;
    }
    if (old.index < 0) {
      // Nothing to slide from — appear in place.
      _fromLead = _fromTrail = widget.top;
      _c.value = 1;
      return;
    }
    // Start from wherever the bubble is now, even mid-flight.
    final (a, b) = _edges(old.top);
    _fromLead = a;
    _fromTrail = b;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final (a, b) = _edges(widget.top);
        return CustomPaint(
          painter: _NavPainter(
            rail: widget.rail,
            left: widget.left,
            scale: widget.scale,
            bubbleTop: widget.index < 0 ? null : math.min(a, b),
            stretch: (a - b).abs(),
          ),
        );
      },
    );
  }
}

class _NavPainter extends CustomPainter {
  _NavPainter({
    required this.rail,
    required this.left,
    required this.scale,
    required this.bubbleTop,
    required this.stretch,
  });

  final bool rail;
  final double left;

  /// Rail geometry multiplier (see [AppSidebar.railScale]).
  final double scale;
  final double? bubbleTop;
  final double stretch;

  /// Drawer: full-width pill height.
  static const pill = 44.0;

  /// Rail (at scale 1): active circle diameter.
  static const railBubble = 44.0;

  /// How far right of the rail centre the active circle sits.
  static const railShift = 8.0;

  /// Page-coloured gap between the active circle and the rail.
  static const _gap = 4.0;

  /// Radius of the rounded lips where the notch meets the rail's edge; large
  /// so the notch flares open into the page.
  static const _fillet = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final top = bubbleTop;
    final w = AppSidebar.railWidth * scale;
    final cx = w / 2 + railShift * scale;
    final r = railBubble * scale / 2;

    if (rail) {
      final body = _railPath(
        size.height,
        top == null ? null : (top + r, top + r + stretch),
      );
      canvas.drawPath(
        body.shift(const Offset(0, 6)),
        Paint()
          ..color = AppColors.navy.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawPath(
        body,
        Paint()
          ..shader = AppSidebar._railGradient.createShader(
            Offset.zero & Size(w, size.height),
          ),
      );
    }
    if (top == null) return;

    final h = rail ? r * 2 : pill;
    final rect = rail
        ? Rect.fromLTRB(cx - r, top, cx + r, top + h + stretch)
        : Rect.fromLTRB(left + 10, top, size.width - 10, top + h + stretch);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
    canvas.drawRRect(
      shape.shift(const Offset(0, 4)),
      Paint()
        ..color = (rail ? AppColors.dentalBlue : AppColors.navy).withValues(
          alpha: 0.28,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: rail
              ? [
                  Color.lerp(AppColors.dentalBlue, Colors.white, 0.15)!,
                  AppColors.dentalBlue,
                ]
              : [
                  Color.lerp(AppColors.navy, AppColors.dentalBlue, 0.28)!,
                  AppColors.navy,
                ],
        ).createShader(rect),
    );
  }

  /// Distance from the rail's end to the notch centre at which a full-size
  /// lip still lands on the straight edge (not the rounded end).
  static double flareReach(double scale) {
    final w = AppSidebar.railWidth * scale;
    final cx = w / 2 + railShift * scale;
    final nr = (railBubble / 2 + _gap) * scale;
    final f = _fillet * scale;
    final dx = w - f - cx;
    return w / 2 + math.sqrt((nr + f) * (nr + f) - dx * dx);
  }

  /// Pill-shaped rail with a notch bitten out of its right edge around the
  /// active circle, whose centres run from y = [notch].$1 to [notch].$2.
  /// Wide rounded lips flare the notch open where it meets the page.
  Path _railPath(double h, (double, double)? notch) {
    final w = AppSidebar.railWidth * scale;
    final rail = Path()
      ..addRRect(RRect.fromLTRBR(0, 0, w, h, Radius.circular(w / 2)));
    if (notch == null) return rail;
    final cx = w / 2 + railShift * scale;
    final nr = (railBubble / 2 + _gap) * scale;
    final (ya, yb) = notch;
    // Both lips share the smaller radius so the notch stays symmetric when
    // one lip is squeezed by the rail's rounded end.
    final fMax = math.min(
      _lip(w, h, cx, nr, ya, flip: false).$3,
      _lip(w, h, cx, nr, yb, flip: true).$3,
    );
    final (topEdge, topNotch, ft) = _lip(
      w,
      h,
      cx,
      nr,
      ya,
      flip: false,
      maxF: fMax,
    );
    final (botEdge, botNotch, fb) = _lip(
      w,
      h,
      cx,
      nr,
      yb,
      flip: true,
      maxF: fMax,
    );
    final cut = Path()
      ..moveTo(w + nr, topEdge.dy)
      ..lineTo(topEdge.dx, topEdge.dy)
      ..arcToPoint(topNotch, radius: Radius.circular(ft))
      ..arcToPoint(
        Offset(cx - nr, ya),
        radius: Radius.circular(nr),
        clockwise: false,
      )
      ..lineTo(cx - nr, yb)
      ..arcToPoint(botNotch, radius: Radius.circular(nr), clockwise: false)
      ..arcToPoint(botEdge, radius: Radius.circular(fb))
      ..lineTo(w + nr, botEdge.dy)
      ..close();
    return Path.combine(PathOperation.difference, rail, cut);
  }

  /// One rounded lip of the notch for the notch circle centred at y = [y]:
  /// (where it leaves the rail outline, where it meets the notch, radius).
  /// The lip circle sits inside the rail, tangent to the notch and to the
  /// straight edge — or, near the rail's ends, to the rounded end cap, with
  /// the radius shrunk to fit so the outline stays smooth. Worked in top-end
  /// coordinates; [flip] mirrors it for the bottom lip.
  (Offset, Offset, double) _lip(
    double w,
    double h,
    double cx,
    double nr,
    double y, {
    required bool flip,
    double maxF = double.infinity,
  }) {
    final cr = w / 2;
    final c = Offset(cx, flip ? h - y : y);
    var f = math.min(_fillet * scale, maxF);
    final dx = w - f - cx;
    final d = math.sqrt(math.max(0, (nr + f) * (nr + f) - dx * dx));
    Offset centre;
    Offset edge;
    if (c.dy - d >= cr) {
      centre = Offset(w - f, c.dy - d);
      edge = Offset(w, c.dy - d);
    } else {
      // Lip tangent to the end cap (centre q, radius cr): |centre-q| = cr-f
      // and |centre-c| = nr+f; shrink f until those circles meet.
      final q = Offset(cr, cr);
      final dist = (c - q).distance;
      f = math.max(1, math.min(f, 0.95 * (dist + cr - nr) / 2));
      final r0 = cr - f;
      final r1 = nr + f;
      final u = (c - q) / dist;
      final a = (r0 * r0 - r1 * r1 + dist * dist) / (2 * dist);
      final off = math.sqrt(math.max(0, r0 * r0 - a * a));
      final mid = q + u * a;
      final perp = Offset(-u.dy, u.dx) * off;
      final p1 = mid + perp;
      final p2 = mid - perp;
      centre = p1.dx > p2.dx ? p1 : p2;
      edge = q + (centre - q) * (cr / r0);
    }
    final onNotch = c + (centre - c) * (nr / (nr + f));
    Offset map(Offset o) => flip ? Offset(o.dx, h - o.dy) : o;
    return (map(edge), map(onNotch), f);
  }

  @override
  bool shouldRepaint(_NavPainter old) =>
      old.bubbleTop != bubbleTop ||
      old.stretch != stretch ||
      old.rail != rail ||
      old.left != left ||
      old.scale != scale;
}

/// Page kit shared by admin, lab and dentist screens: page chrome, async
/// lists with loading / empty / error states, cards, rows, badges, the tab
/// pill and swap, entrance motion. (Started on the admin side, hence the
/// Admin* names.)
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../auth/app_roles.dart';
import '../l10n/app_localizations.dart';
import '../l10n/date_formats.dart';
import '../haptics/app_haptics.dart';
import '../layout/adaptive.dart';
import '../navigation/app_page_routes.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';
import '../../features/admin/admin_top_bar.dart';

String adminWhen(BuildContext context, DateTime? at) =>
    at == null ? '—' : formatAppDateTime(context, at);

/// Shared admin page chrome: header, optional toolbar, body.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    this.toolbar = const [],
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> toolbar;
  final List<Widget> actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppBreakpoints.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            actions: [...actions, const AdminTopActions()],
          ),
          for (final w in toolbar) ...[const SizedBox(height: 14), w],
          const SizedBox(height: 16),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Loads [load], then shows [builder]'s slivers with pull-to-refresh, or the
/// loading / error / [empty] state. Reloads in place (old rows stay on
/// screen) when [query] changes, and quietly when [active] turns on: pages
/// stay mounted in the shell and other admin pages change the data.
class AdminFuture<T> extends StatefulWidget {
  const AdminFuture({
    super.key,
    required this.load,
    required this.builder,
    required this.empty,
    this.isEmpty,
    this.active = true,
    this.query,
    this.bottomPadding = 24,
  });

  /// Space after the content; 0 lets a screen-filling page fit exactly.
  final double bottomPadding;

  final Future<T> Function() load;
  final List<Widget> Function(BuildContext context, T data, VoidCallback reload)
      builder;
  final bool Function(T data)? isEmpty;
  final Widget empty;
  final bool active;

  /// Filters / search behind [load]; a change triggers a reload.
  final Object? query;

  @override
  State<AdminFuture<T>> createState() => _AdminFutureState<T>();
}

class _AdminFutureState<T> extends State<AdminFuture<T>> {
  T? _data;
  Object? _error;

  /// Only the newest request may land (typing fires several).
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(AdminFuture<T> old) {
    super.didUpdateWidget(old);
    if (widget.query != old.query || (widget.active && !old.active)) _reload();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    try {
      final data = await widget.load();
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      // Keep stale data on screen; only a first load shows the error state.
      if (_data != null) AppSnackBars.error(context, friendlyError(e));
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final Widget body;
    final String state;
    if (data == null && _error == null) {
      state = 'loading';
      body = const ToothPageLoader();
    } else if (data == null) {
      state = 'error';
      body = IpadRefresh.fill(
        onRefresh: _reload,
        child: AdminEmpty(
          icon: Icons.cloud_off_rounded,
          title: AppLocalizations.of(context).tr('admin.loadFailed'),
          subtitle: friendlyError(_error!),
          action: AppButtons.secondary(
            onPressed: _reload,
            icon: Icons.refresh_rounded,
            label: AppLocalizations.of(context).tr('admin.retry'),
          ),
        ),
      );
    } else if (widget.isEmpty?.call(data) ?? (data is List && data.isEmpty)) {
      state = 'empty';
      body = IpadRefresh.fill(onRefresh: _reload, child: widget.empty);
    } else {
      state = 'data';
      body = IpadRefresh(
        onRefresh: _reload,
        slivers: [
          ...widget.builder(context, data, _reload),
          if (widget.bottomPadding > 0)
            SliverToBoxAdapter(child: SizedBox(height: widget.bottomPadding)),
        ],
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.normal,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey(state), child: body),
    );
  }
}

/// iOS-style empty / error state: icon in a tinted circle, no box.
class AdminEmpty extends StatelessWidget {
  const AdminEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdminIcon(icon: icon, size: 64, color: AppColors.muted),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppFonts.style(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppFonts.style(color: AppColors.muted, fontSize: 14, height: 1.35),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon in a soft tinted circle (no neumorphic shadow).
class AdminIcon extends StatelessWidget {
  const AdminIcon({
    super.key,
    required this.icon,
    this.color = AppColors.dentalBlue,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.46, color: color),
    );
  }
}

/// Solid white card used on every admin surface. With [onTap] it springs
/// down on press like the rest of the app's controls.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(18, 14, 14, 14),
    this.selected = false,
    this.height,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool selected;
  final double? height;

  static final radius = BorderRadius.circular(20);

  @override
  Widget build(BuildContext context) {
    Widget card(bool pressed) => AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.spring,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF2F7FE) : AppColors.card,
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.dentalBlue : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: NeoShadows.raised(depth: pressed ? 0.5 : 0.8),
          ),
          child: child,
        );
    if (onTap == null) return card(false);
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      builder: (context, pressed) => card(pressed),
    );
  }
}

/// Card body: avatar, title + subtitle lines, and trailing actions that wrap
/// under the text when the card is narrow.
class AdminRow extends StatelessWidget {
  const AdminRow({
    super.key,
    required this.title,
    this.leading,
    this.badges = const [],
    this.lines = const [],
    this.actions = const [],
  });

  final Widget? leading;
  final String title;
  final List<Widget> badges;
  final List<String> lines;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final identity = Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                          letterSpacing: -0.2,
                        ),
                      ),
                      ...badges,
                    ],
                  ),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        l,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(fontSize: 13, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
        if (actions.isEmpty) return identity;
        final buttons = Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        );
        if (c.maxWidth >= 640) {
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              buttons,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: buttons),
          ],
        );
      },
    );
  }
}

class AdminBadge extends StatelessWidget {
  const AdminBadge(this.label, {super.key, this.color = AppColors.dentalBlue});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppFonts.style(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

AdminBadge roleBadge(BuildContext context, String role) => AdminBadge(
      AppRoles.label(role, AppLocalizations.of(context)),
      color: AppRoles.isLaboratory(role) ? AppColors.review : AppColors.dentalBlue,
    );

/// `{n}` string with a singular form: uses `<key>One` when n is 1 and
/// that key exists.
String plural(AppLocalizations loc, String key, int n) {
  final one = '${key}One';
  final k = n == 1 && loc.tr(one) != one ? one : key;
  return loc.trp(k, {'n': n});
}

String dentistCount(AppLocalizations loc, int n) =>
    loc.trp(n == 1 ? 'admin.dentistCountOne' : 'admin.dentistCount', {'n': n});

/// "Lab · Clinic" — how dentists are always shown (docs/roadmap.md).
String dentistPlace(AppLocalizations loc, String? lab, String? clinic) =>
    '${lab ?? loc.tr('admin.noLab')} · ${clinic ?? loc.tr('admin.noClinic')}';

/// Section switcher: a navy pill springs between segments, like the rail's
/// active bubble.
class AdminTabs extends StatelessWidget {
  const AdminTabs({
    super.key,
    required this.tab,
    required this.labels,
  });

  final ValueNotifier<int> tab;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tab,
      builder: (context, value, _) => Container(
        height: 42,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.inset.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: AppMotion.page,
              curve: AppMotion.spring,
              alignment: Alignment(
                labels.length == 1 ? 0 : -1 + 2 * value / (labels.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / labels.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF26446B), AppColors.navy],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.22),
                        offset: const Offset(0, 3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (tab.value == i) return;
                        AppHaptics.selection();
                        tab.value = i;
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: AppMotion.normal,
                          curve: AppMotion.easeOut,
                          style: AppFonts.style(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: i == value ? Colors.white : AppColors.muted,
                          ),
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab bodies that stay alive once visited (no reload, scroll kept). The
/// active one slides in from the side it lives on and fades up; the others
/// fade out and stop painting.
class AdminSwap extends StatefulWidget {
  const AdminSwap({super.key, required this.index, required this.builder});

  final int index;
  final Widget Function(int index) builder;

  @override
  State<AdminSwap> createState() => _AdminSwapState();
}

class _AdminSwapState extends State<AdminSwap> {
  late final Set<int> _visited = {widget.index};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    final current = widget.index;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in _visited.toList()..sort())
          KeyedSubtree(
            key: ValueKey(i),
            child: IgnorePointer(
              ignoring: i != current,
              // The slide/fade must keep ticking while a tab hides (a muted
              // ticker here froze hidden tabs fully visible, on top of the
              // new one). Only the tab's own content is muted.
              child: AnimatedSlide(
                offset: i == current
                    ? Offset.zero
                    : Offset(i < current ? -0.04 : 0.04, 0),
                duration: AppMotion.page,
                curve: AppMotion.spring,
                child: AnimatedOpacity(
                  opacity: i == current ? 1 : 0,
                  duration: i == current ? AppMotion.page : AppMotion.fast,
                  curve: AppMotion.easeOut,
                  child: TickerMode(
                    enabled: i == current,
                    child: widget.builder(i),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fades and lifts a list item in, staggered by [index] (first load only:
/// a mounted item never replays).
class AdminAppear extends StatefulWidget {
  const AdminAppear({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<AdminAppear> createState() => _AdminAppearState();
}

class _AdminAppearState extends State<AdminAppear>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: AppMotion.page);
  late final _a = CurvedAnimation(parent: _c, curve: AppMotion.spring);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    // Cap the stagger so long lists don't trickle in.
    _delay = Timer(Duration(milliseconds: 35 * widget.index.clamp(0, 8)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(_a),
        child: widget.child,
      ),
    );
  }
}

/// Animated `SliverList` of cards with even spacing.
Widget adminSliverList<T>(
  List<T> rows,
  Widget Function(BuildContext context, T row) item, {
  Object Function(T row)? id,
  double gap = 12,
}) {
  return SliverList.separated(
    itemCount: rows.length,
    separatorBuilder: (_, _) => SizedBox(height: gap),
    itemBuilder: (context, i) => AdminAppear(
      key: id == null ? null : ValueKey(id(rows[i])),
      index: i,
      child: item(context, rows[i]),
    ),
  );
}

/// Number that counts up to [value] (and glides between values on reload).
class AdminCount extends StatelessWidget {
  const AdminCount(this.value, {super.key, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: AppMotion.spring,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Search field; reports the query after typing pauses.
class AdminSearchField extends StatefulWidget {
  const AdminSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;

  /// Pass one when the field can unmount (tab switch) but the query stays.
  final TextEditingController? controller;

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoSearchTextField(
      controller: widget.controller,
      placeholder: widget.hint,
      style: AppFonts.style(fontSize: 16, color: AppColors.navy),
      backgroundColor: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      onChanged: (v) {
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 300),
          () => widget.onChanged(v.trim()),
        );
      },
      onSuffixTap: () {
        widget.controller?.clear();
        _debounce?.cancel();
        widget.onChanged('');
      },
    );
  }
}

/// iOS action sheet listing [options]; returns the chosen value.
Future<T?> adminChoose<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<(T, String)> options,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final (value, label) in options)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, value),
            child: Text(label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(ctx),
        child: Text(AppLocalizations.of(context).cancel),
      ),
    ),
  );
}

/// Runs an admin mutation behind a loading dialog and reports the outcome.
/// Returns true on success.
Future<bool> adminRun(
  BuildContext context,
  Future<void> Function() action, {
  required String done,
}) async {
  try {
    await AppDialogs.runWithLoading(context, action: action);
    if (context.mounted) AppSnackBars.success(context, done);
    return true;
  } catch (e) {
    if (context.mounted) AppSnackBars.error(context, friendlyError(e));
    return false;
  }
}


/// Tinted count tile: icon and status pill on top, label and number below.
class KpiTile extends StatelessWidget {
  const KpiTile({
    required this.icon,
    required this.label,
    this.value,
    this.text,
    required this.tint,
    this.onTap,
    this.pill,
  });

  final IconData icon;
  final String label;
  /// A count (it counts up), or [text] for anything else ("3.2 d", "…").
  final int? value;
  final String? text;
  final Color tint;
  final (String, Color)? pill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      builder: (_, pressed) => LayoutBuilder(
        builder: (context, box) {
          final tight = box.maxHeight.isFinite && box.maxHeight < 88;
          final padV = tight ? 8.0 : 12.0;
          final valueSize = tight ? 22.0 : 28.0;
          return AnimatedContainer(
            duration: AppMotion.fast,
            padding: EdgeInsets.fromLTRB(16, padV, 14, padV),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  tint.withValues(alpha: pressed ? 0.16 : 0.10), Colors.white),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: tight ? 20 : 24, color: tint),
                    const SizedBox(width: 8),
                    if (pill != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              pill!.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: pill!.$2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                      fontSize: tight ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy.withValues(alpha: 0.7)),
                ),
                SizedBox(height: tight ? 0 : 2),
                value != null
                    ? AdminCount(
                        value!,
                        style: AppFonts.style(
                            fontSize: valueSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                            letterSpacing: -0.8),
                      )
                    : Text(
                        text ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(
                            fontSize: valueSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                            letterSpacing: -0.8),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }
}


/// White card with a title row; [child] fills the rest.
class PanelCard extends StatelessWidget {
  const PanelCard({required this.title, required this.child, this.subtitle, this.action, this.fill = true});

  /// True: [child] fills a fixed-height card. False: card hugs [child].
  final bool fill;
  final String title;
  final String? subtitle;
  final (String, VoidCallback)? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.3)),
                    if (subtitle != null)
                      Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
                  ],
                ),
              ),
              if (action != null)
                Pressable(
                  onTap: action!.$2,
                  scale: 0.94,
                  builder: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(action!.$1,
                        style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dentalBlue)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class PanelEmpty extends StatelessWidget {
  const PanelEmpty({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    // Panel cards can be short (iPad landscape flex). Shrink / drop the icon
    // instead of overflowing the Column.
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight.isFinite ? c.maxHeight : 200.0;
        final showIcon = h >= 56;
        final tight = h < 96;
        final iconSize = h < 72 ? 22.0 : (tight ? 28.0 : 48.0);
        return ClipRect(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: c.maxWidth.isFinite ? c.maxWidth : 280,
                    maxHeight: h,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showIcon) ...[
                        AdminIcon(icon: icon, color: color, size: iconSize),
                        SizedBox(height: tight ? 4 : 10),
                      ],
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        maxLines: tight ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(
                          fontSize: tight ? 12 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


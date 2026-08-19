import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/adaptive.dart';
import '../../../core/navigation/app_page_routes.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/touchable.dart';
import '../../../core/widgets/ui_kit.dart';
import '../appointment_service.dart';
import '../models/appointment.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.api,
    required this.patientSession,
    this.active = true,
    this.onInboxChanged,
  });

  final ApiClient api;
  final PatientSession patientSession;
  final bool active;
  final VoidCallback? onInboxChanged;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late final AppointmentService _service = AppointmentService(widget.api);

  List<Appointment> _items = [];
  String _statusFilter = 'all';
  String? _patientFilterId;
  String? _selectedId;
  bool _loading = true;
  bool _refreshing = false;
  bool _patientsRefreshing = false;
  int _listGen = 0;

  List<Map<String, dynamic>> get _patients => widget.patientSession.patients;

  Appointment? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<_DayGroup> get _groups {
    final map = <DateTime, List<Appointment>>{};
    for (final item in _items) {
      final t = item.startTime;
      final day = DateTime(t.year, t.month, t.day);
      map.putIfAbsent(day, () => []).add(item);
    }
    final days = map.keys.toList()..sort();
    return [for (final day in days) _DayGroup(day, map[day]!)];
  }

  void _syncSelection({String? preferId}) {
    if (_items.isEmpty) {
      _selectedId = null;
      return;
    }
    final preferred = preferId ?? _selectedId;
    if (preferred != null && _items.any((e) => e.id == preferred)) {
      _selectedId = preferred;
      return;
    }
    final now = DateTime.now();
    final upcoming = _items.where((e) => !e.startTime.isBefore(now));
    _selectedId = (upcoming.isEmpty ? _items.first : upcoming.first).id;
  }

  @override
  void initState() {
    super.initState();
    widget.patientSession.addListener(_onPatientsChanged);
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant AppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _onPageActivated();
    }
  }

  @override
  void dispose() {
    widget.patientSession.removeListener(_onPatientsChanged);
    super.dispose();
  }

  void _onPatientsChanged() {
    if (!mounted) return;
    // PatientSession may notify while a dialog is mounting — defer setState.
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringBuild = phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks;
    void apply() {
      if (!mounted) return;
      setState(() {});
      final id = _patientFilterId;
      if (id != null &&
          !_patients.any((p) => widget.patientSession.pidOf(p) == id)) {
        _patientFilterId = null;
        _loadAppointments(soft: true);
      }
    }

    if (duringBuild) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  Future<void> _onPageActivated() async {
    // Force a server re-fetch so patients created on other tabs appear.
    await _refreshPatients(showIndicator: false);
  }

  Future<void> _refreshPatients({bool showIndicator = true}) async {
    if (showIndicator && mounted) {
      setState(() => _patientsRefreshing = true);
    }
    try {
      await widget.patientSession.refresh(keepSelection: true);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted && showIndicator) {
        setState(() => _patientsRefreshing = false);
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
    });
    try {
      await widget.patientSession.refresh(keepSelection: true);
      if (!mounted) return;
      await _loadAppointments();
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAppointments({bool soft = false, bool forceRefresh = false}) async {
    final gen = ++_listGen;
    if (soft) {
      setState(() => _refreshing = true);
    }
    try {
      final rows = await _service.list(
        status: _statusFilter == 'all' ? null : _statusFilter,
        patientId: _patientFilterId,
        upcomingOnly: false,
        forceRefresh: forceRefresh,
      );
      if (!mounted || gen != _listGen) return;
      final sorted = List<Appointment>.from(rows)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      setState(() {
        _items = sorted;
        _syncSelection();
      });
    } catch (e) {
      if (!mounted || gen != _listGen) return;
      AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted && soft && gen == _listGen) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _refreshAll() async {
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        widget.patientSession.refresh(
          keepSelection: true,
          forceRefresh: true,
        ),
        _loadAppointments(forceRefresh: true),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _upsertLocal(Appointment appointment) {
    final matchesStatus = _statusFilter == 'all' ||
        AppointmentStatuses.normalize(appointment.status) == _statusFilter;
    final matchesPatient =
        _patientFilterId == null || appointment.patientId == _patientFilterId;

    setState(() {
      final idx = _items.indexWhere((e) => e.id == appointment.id);
      if (idx >= 0) {
        if (matchesStatus && matchesPatient) {
          _items = List<Appointment>.from(_items)..[idx] = appointment;
        } else {
          _items = _items.where((e) => e.id != appointment.id).toList();
        }
      } else if (matchesStatus && matchesPatient) {
        _items = [appointment, ..._items];
      }
      _items.sort((a, b) => a.startTime.compareTo(b.startTime));
      _syncSelection(preferId: appointment.id);
    });
  }

  Future<void> _openBookModal({Appointment? existing}) async {
    // Open immediately — do not block on a network patient refresh.
    // Create mode refreshes patients inside the modal after the first frame.
    final saved = await showCupertinoDialog<Appointment>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: BookAppointmentModal(
          api: widget.api,
          service: _service,
          patientSession: widget.patientSession,
          existing: existing,
        ),
      ),
    );
    if (saved == null || !mounted) return;

    _upsertLocal(saved);
    widget.onInboxChanged?.call();
    AppSnackBars.success(
      context,
      'Appointment saved. Email notification sent to patient via Resend.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final portrait = AppBreakpoints.isPortrait(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        portrait ? 16 : 28,
        portrait ? 16 : 22,
        portrait ? 16 : 28,
        portrait ? 16 : 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildFilterBar(),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedOpacity(
              duration: AppMotion.fast,
              curve: AppMotion.spring,
              opacity: _refreshing ? 0.62 : 1,
              child: AppSwitcher(
                child: KeyedSubtree(
                  key: ValueKey(
                    _loading
                        ? 'loading'
                        : '$_statusFilter|${_patientFilterId ?? 'all'}|${_items.length}',
                  ),
                  child: _loading
                      ? const ToothPageLoader(message: 'Loading appointments…')
                      : RefreshIndicator(
                          color: AppColors.dentalBlue,
                          onRefresh: _refreshAll,
                          child: _buildBody(),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final busy = _loading || _refreshing || _patientsRefreshing;
    return PageHeader(
      icon: Icons.calendar_today_outlined,
      title: 'Appointments',
      subtitle: 'Schedule visits and send confirmation emails',
      chromeActions: [
        AppButtons.icon(
          tooltip: 'Refresh',
          onPressed: busy ? null : _refreshAll,
          icon: Icons.refresh_rounded,
          busy: busy,
        ),
      ],
      actions: [
        AppButtons.primary(
          onPressed: _loading ? null : () => _openBookModal(),
          label: 'Book',
          icon: Icons.add_rounded,
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final patientIds = _patients.map(widget.patientSession.pidOf).toSet();
    final filterValue =
        _patientFilterId != null && patientIds.contains(_patientFilterId)
            ? _patientFilterId
            : null;
    final selectedPatient = () {
      if (filterValue == null) return null;
      for (final p in _patients) {
        if (widget.patientSession.pidOf(p) == filterValue) return p;
      }
      return null;
    }();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720 &&
            !AppBreakpoints.isPortrait(context);
        final filters = _StatusFilterBar(
          selected: _statusFilter,
          compact: !wide,
          onSelected: (key) {
            if (key == _statusFilter) return;
            AppHaptics.selection();
            setState(() => _statusFilter = key);
            _loadAppointments(soft: true);
          },
        );
        final patient = _PatientFilterButton(
          patients: _patients,
          selected: selectedPatient,
          pidOf: widget.patientSession.pidOf,
          onSelectAll: () {
            setState(() => _patientFilterId = null);
            _loadAppointments(soft: true);
          },
          onSelect: (p) {
            setState(
              () => _patientFilterId = widget.patientSession.pidOf(p),
            );
            _loadAppointments(soft: true);
          },
          onAdd: () => widget.patientSession.requestNavigateToNewPatient(),
          onRefresh: () => _refreshPatients(),
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: filters),
              const SizedBox(width: 12),
              patient,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filters,
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: patient),
          ],
        );
      },
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: mathMaxEmptyHeight(context),
            child: _AppointmentsEmpty(
              filtered: _statusFilter != 'all' || _patientFilterId != null,
              onBook: () => _openBookModal(),
            ),
          ),
        ],
      );
    }

    final list = _AppointmentsAgenda(
      groups: _groups,
      selectedId: _selectedId,
      onSelect: (item) {
        AppHaptics.selection();
        setState(() => _selectedId = item.id);
      },
      onEdit: (item) => _openBookModal(existing: item),
    );
    final detail = AppSwitcher(
      child: KeyedSubtree(
        key: ValueKey(_selectedId ?? 'none'),
        child: _AppointmentDetailPane(
          appointment: _selected,
          onEdit: _selected == null
              ? null
              : () => _openBookModal(existing: _selected),
          onBook: () => _openBookModal(),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < AppBreakpoints.stack ||
            (constraints.maxHeight > constraints.maxWidth &&
                constraints.maxWidth < 980);
        // Portrait / narrow: the agenda is a scroll view and must own the
        // viewport. Stacking it unbounded above the detail pane collapses
        // the list to zero height (blank schedule).
        if (stacked) {
          return list;
        }
        return AdaptiveSplit(
          panelFraction: 0.42,
          minPanelWidth: 320,
          maxPanelWidth: 460,
          gap: 16,
          content: detail,
          panel: list,
        );
      },
    );
  }

  double mathMaxEmptyHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.55).clamp(320.0, 560.0);
  }
}

class _DayGroup {
  const _DayGroup(this.day, this.items);
  final DateTime day;
  final List<Appointment> items;
}

String _dayHeading(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return 'Today';
  if (day == tomorrow) return 'Tomorrow';
  if (day == yesterday) return 'Yesterday';
  return DateFormat('EEEE, MMM d').format(day);
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in AppointmentStatuses.filters)
            SoftPillButton(
              label: f.label,
              selected: selected == f.key,
              compact: false,
              selectionHaptic: true,
              onPressed: () => onSelected(f.key),
            ),
        ],
      );
    }

    return GlassSurface(
      borderRadius: BorderRadius.circular(16),
      blur: 16,
      tint: Colors.white.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(6),
      child: CupertinoSlidingSegmentedControl<String>(
        groupValue: selected,
        backgroundColor: AppColors.inset,
        thumbColor: Colors.white,
        children: {
          for (final f in AppointmentStatuses.filters)
            f.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(
                f.label,
                textAlign: TextAlign.center,
                style: AppFonts.style(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ),
        },
        onValueChanged: (value) {
          if (value == null) return;
          onSelected(value);
        },
      ),
    );
  }
}

class _PatientFilterButton extends StatelessWidget {
  const _PatientFilterButton({
    required this.patients,
    required this.selected,
    required this.pidOf,
    required this.onSelectAll,
    required this.onSelect,
    required this.onAdd,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> patients;
  final Map<String, dynamic>? selected;
  final String Function(Map<String, dynamic>) pidOf;
  final VoidCallback onSelectAll;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;

  String _name(Map<String, dynamic> p) =>
      '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    final label = selected == null
        ? 'All patients'
        : (_name(selected).isEmpty ? 'Patient' : _name(selected));
    final subtitle = selected == null
        ? '${patients.length} in clinic'
        : 'Filtering schedule';

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(AppColors.card),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        padding:
            WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 6)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: AppRadii.borderSm),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: onSelectAll,
          leadingIcon: const Icon(Icons.groups_outlined, size: 18),
          trailingIcon: selected == null
              ? const Icon(Icons.check, size: 16, color: AppColors.dentalBlue)
              : null,
          child: const SizedBox(
            width: 180,
            child: Text('All patients'),
          ),
        ),
        const Divider(height: 8),
        ...patients.map((p) {
          final isSel = selected != null && pidOf(selected) == pidOf(p);
          final name = _name(p);
          return MenuItemButton(
            onPressed: () => onSelect(p),
            leadingIcon: InitialsAvatar(
              name: name.isEmpty ? '?' : name,
              size: 28,
            ),
            trailingIcon: isSel
                ? const Icon(
                    Icons.check,
                    size: 16,
                    color: AppColors.dentalBlue,
                  )
                : null,
            child: SizedBox(
              width: 180,
              child: Text(
                name.isEmpty ? 'Patient' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }),
        const Divider(height: 8),
        MenuItemButton(
          onPressed: () {
            WidgetsBinding.instance.addPostFrameCallback((_) => onAdd());
          },
          leadingIcon: const Icon(Icons.person_add_alt_1, size: 18),
          child: const Text('Add patient'),
        ),
        MenuItemButton(
          onPressed: () {
            WidgetsBinding.instance.addPostFrameCallback((_) => onRefresh());
          },
          leadingIcon: const Icon(Icons.refresh_rounded, size: 18),
          child: const Text('Refresh patients'),
        ),
      ],
      builder: (context, controller, child) {
        return SizedBox(
          width: 248,
          child: Touchable(
            borderRadius: AppRadii.borderSm,
            minHeight: 48,
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.neo,
                borderRadius: AppRadii.borderSm,
                boxShadow: controller.isOpen
                    ? NeoShadows.pressed()
                    : NeoShadows.soft(depth: 0.55),
              ),
              child: Row(
                children: [
                  Icon(
                    selected == null
                        ? Icons.groups_outlined
                        : Icons.person_outline,
                    size: 20,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.style(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.navy,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.style(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    controller.isOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AppointmentsEmpty extends StatelessWidget {
  const _AppointmentsEmpty({
    required this.filtered,
    required this.onBook,
  });

  final bool filtered;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(24),
          blur: 18,
          tint: Colors.white.withValues(alpha: 0.55),
          padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeoIconBadge(
                icon: filtered
                    ? Icons.filter_alt_off_outlined
                    : Icons.event_available_outlined,
                size: 64,
                iconSize: 30,
                color: AppColors.dentalBlue,
              ),
              const SizedBox(height: 18),
              Text(
                filtered ? 'Nothing matches this filter' : 'No visits yet',
                textAlign: TextAlign.center,
                style: AppFonts.style(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                filtered
                    ? 'Try another status or patient, or book a new visit.'
                    : 'Book a visit to send a confirmation email to the patient.',
                textAlign: TextAlign.center,
                style: AppFonts.style(
                  color: AppColors.muted,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              AppButtons.primary(
                onPressed: onBook,
                label: 'Book Appointment',
                icon: Icons.add_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentsAgenda extends StatelessWidget {
  const _AppointmentsAgenda({
    required this.groups,
    required this.selectedId,
    required this.onSelect,
    required this.onEdit,
  });

  final List<_DayGroup> groups;
  final String? selectedId;
  final ValueChanged<Appointment> onSelect;
  final ValueChanged<Appointment> onEdit;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(
                children: [
                  Text(
                    _dayHeading(group.day),
                    style: AppFonts.style(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMM d').format(group.day),
                    style: AppFonts.style(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${group.items.length}',
                    style: AppFonts.style(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < group.items.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 88, endIndent: 16),
                      _AppointmentRow(
                        appointment: group.items[i],
                        selected: group.items[i].id == selectedId,
                        onTap: () => onSelect(group.items[i]),
                        onEdit: () => onEdit(group.items[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.appointment,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final Appointment appointment;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  static final _timeFmt = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final style = AppointmentStatusStyle.of(appointment.status);
    final name = appointment.patientName.isEmpty
        ? 'Patient'
        : appointment.patientName;
    final notes = appointment.description.trim();

    return Touchable(
      onTap: onTap,
      minHeight: 76,
      borderRadius: BorderRadius.zero,
            child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        color: selected
            ? AppColors.dentalBlue.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timeFmt.format(appointment.startTime),
                    style: AppFonts.style(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _timeFmt.format(appointment.endTime),
                    style: AppFonts.style(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 3,
              height: 44,
              decoration: BoxDecoration(
                color: style.fg,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: style.bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          style.label,
                          style: AppFonts.style(
                            color: style.fg,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            notes,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.style(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            AppButtons.icon(
              tooltip: 'Edit appointment',
              onPressed: onEdit,
              icon: Icons.edit_outlined,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentDetailPane extends StatelessWidget {
  const _AppointmentDetailPane({
    required this.appointment,
    required this.onEdit,
    required this.onBook,
  });

  final Appointment? appointment;
  final VoidCallback? onEdit;
  final VoidCallback onBook;

  static final _dateFmt = DateFormat('EEEE, MMMM d');
  static final _timeFmt = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final appointment = this.appointment;
    if (appointment == null) {
      return _AppointmentsEmpty(filtered: false, onBook: onBook);
    }

    final style = AppointmentStatusStyle.of(appointment.status);
    final name = appointment.patientName.isEmpty
        ? 'Patient'
        : appointment.patientName;
    final notes = appointment.description.trim();
    final mins = appointment.duration.inMinutes;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InitialsAvatar(name: name, size: 52),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: style.bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        style.label,
                        style: AppFonts.style(
                          color: style.fg,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: _dateFmt.format(appointment.startTime),
          ),
          _DetailRow(
            icon: Icons.schedule_outlined,
            label: 'Time',
            value:
                '${_timeFmt.format(appointment.startTime)} – ${_timeFmt.format(appointment.endTime)} · $mins min',
          ),
          if (appointment.patientEmail.isNotEmpty)
            _DetailRow(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              value: appointment.patientEmail,
            ),
          _DetailRow(
            icon: Icons.notes_outlined,
            label: 'Notes',
            value: notes.isEmpty ? 'No notes' : notes,
          ),
          const Spacer(),
          AppButtons.primary(
            onPressed: onEdit,
            label: 'Edit Appointment',
            icon: Icons.edit_outlined,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.dentalBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppFonts.style(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppFonts.style(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                    height: 1.3,
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

class BookAppointmentModal extends StatefulWidget {
  const BookAppointmentModal({
    super.key,
    required this.api,
    required this.service,
    required this.patientSession,
    this.existing,
  });

  final ApiClient api;
  final AppointmentService service;
  final PatientSession patientSession;
  final Appointment? existing;

  @override
  State<BookAppointmentModal> createState() => _BookAppointmentModalState();
}

class _BookAppointmentModalState extends State<BookAppointmentModal> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();

  List<Map<String, dynamic>> _patients = [];
  String? _patientId;
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  int _durationMinutes = 30;
  String _status = AppointmentStatuses.scheduled;
  bool _loadingPatients = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  bool get _canSubmit {
    if (_saving || _loadingPatients) return false;
    if (!_isEdit && (_patientId == null || _patientId!.isEmpty)) return false;
    return true;
  }

  static const _durations = [15, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _patientId = existing.patientId;
      _start = existing.startTime;
      final mins = existing.duration.inMinutes;
      _durationMinutes = _durations.contains(mins) ? mins : mins.clamp(15, 180);
      _status = AppointmentStatuses.normalize(existing.status);
      _descriptionCtrl.text = existing.description;
    } else {
      _start = _roundToNextQuarter(DateTime.now().add(const Duration(hours: 1)));
    }
    // Seed from cache immediately; refresh after this frame so we never
    // notify PatientSession listeners while the dialog is still mounting.
    _patients =
        List<Map<String, dynamic>>.from(widget.patientSession.patients);
    if (!_isEdit && _patients.isNotEmpty) {
      _patientId = widget.patientSession.pidOf(_patients.first);
      if (_patientId != null && _patientId!.isEmpty) _patientId = null;
    }
    _loadingPatients = false;
    // Edit mode does not need the patient list (read-only name). Create mode
    // refreshes in the background without delaying the dialog open.
    if (!_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPatients();
      });
    }
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loadingPatients = true;
    });
    try {
      await widget.patientSession.refresh(keepSelection: true);
      if (!mounted) return;
      final rows =
          List<Map<String, dynamic>>.from(widget.patientSession.patients);
      setState(() {
        _patients = rows;
        _loadingPatients = false;
        if (!_isEdit) {
          final stillThere = _patientId != null &&
              rows.any((p) => widget.patientSession.pidOf(p) == _patientId);
          if (!stillThere) {
            _patientId = rows.isEmpty
                ? null
                : widget.patientSession.pidOf(rows.first);
            if (_patientId != null && _patientId!.isEmpty) _patientId = null;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPatients = false;
      });
      AppSnackBars.error(context, friendlyError(e));
    }
  }

  DateTime _roundToNextQuarter(DateTime dt) {
    final minute = ((dt.minute + 14) ~/ 15) * 15;
    if (minute >= 60) {
      return DateTime(dt.year, dt.month, dt.day, dt.hour + 1);
    }
    return DateTime(dt.year, dt.month, dt.day, dt.hour, minute);
  }

  DateTime get _end => _start.add(Duration(minutes: _durationMinutes));

  String _patientMenuLabel(Map<String, dynamic> row) {
    final name =
        '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Patient' : name;
  }

  Future<void> _pickDate() async {
    final picked = await DentalDatePickerDialog.showForAppointment(
      context: context,
      initialDate: _start,
      title: 'Select Appointment Date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _start.hour,
        _start.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    var minute = ((_start.minute / 5).round() * 5);
    var hour = _start.hour;
    if (minute >= 60) {
      minute = 0;
      hour = (hour + 1) % 24;
    }
    var pending = DateTime(
      _start.year,
      _start.month,
      _start.day,
      hour,
      minute,
    );
    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (ctx) {
        return Material(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 320,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Row(
                      children: [
                        AppButtons.ghost(
                          onPressed: () => Navigator.pop(ctx),
                          label: 'Cancel',
                          compact: true,
                        ),
                        const Spacer(),
                        Text(
                          'Start time',
                          style: AppFonts.style(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                        ),
                        const Spacer(),
                        AppButtons.primary(
                          onPressed: () => Navigator.pop(ctx, pending),
                          label: 'Done',
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      initialDateTime: pending,
                      minuteInterval: 5,
                      use24hFormat: false,
                      onDateTimeChanged: (value) => pending = value,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final patientId = _patientId;
    if (!_isEdit && (patientId == null || patientId.isEmpty)) {
      AppSnackBars.error(context, 'Select a patient');
      return;
    }
    if (_end.isBefore(_start) || _end.isAtSameMomentAs(_start)) {
      AppSnackBars.error(context, 'End time must be after start time');
      return;
    }

    setState(() {
      _saving = true;
    });
    try {
      final Appointment saved;
      if (_isEdit) {
        saved = await widget.service.update(
          appointmentId: widget.existing!.id,
          description: _descriptionCtrl.text.trim(),
          startTime: _start,
          endTime: _end,
          status: _status,
        );
      } else {
        saved = await widget.service.create(
          patientId: patientId!,
          startTime: _start,
          endTime: _end,
          description: _descriptionCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBars.error(context, friendlyError(e));
    }
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return Touchable(
      enabled: onTap != null,
      onTap: onTap,
      minHeight: 52,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.neo,
          borderRadius: BorderRadius.circular(14),
          boxShadow: NeoShadows.soft(depth: 0.4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.dentalBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppFonts.style(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE, MMM d, yyyy').format(_start);
    final timeLabel = DateFormat('h:mm a').format(_start);
    final endLabel = DateFormat('h:mm a').format(_end);
    Map<String, dynamic>? selectedPatient;
    for (final p in _patients) {
      if (widget.patientSession.pidOf(p) == _patientId) {
        selectedPatient = p;
        break;
      }
    }
    final patientLabel = _isEdit
        ? (widget.existing!.patientName.isEmpty
            ? 'Patient'
            : widget.existing!.patientName)
        : (selectedPatient == null
            ? 'Select patient'
            : _patientMenuLabel(selectedPatient));

    final portrait = AppBreakpoints.isPortrait(context);
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(
          horizontal: portrait ? 20 : 48,
          vertical: portrait ? 24 : 32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(24),
            blur: 28,
            tint: Colors.white.withValues(alpha: 0.82),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEdit ? 'Edit Appointment' : 'Book Appointment',
                  style: AppFonts.style(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 560),
                  child: Stack(
                    children: [
                      Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!_isEdit)
                                _sheetTile(
                                  icon: Icons.person_outline,
                                  label: 'Patient',
                                  value: _loadingPatients && _patients.isEmpty
                                      ? 'Loading…'
                                      : patientLabel,
                                  onTap: _saving || _loadingPatients
                                      ? null
                                      : () async {
                                          final chosen =
                                              await _pickPatientSheet();
                                          if (chosen == null || !mounted) {
                                            return;
                                          }
                                          setState(() => _patientId = chosen);
                                        },
                                )
                              else
                                _sheetTile(
                                  icon: Icons.person_outline,
                                  label: 'Patient',
                                  value: patientLabel,
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _sheetTile(
                                      icon: Icons.calendar_today_outlined,
                                      label: 'Date',
                                      value: dateLabel,
                                      onTap: _saving ? null : _pickDate,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _sheetTile(
                                      icon: Icons.schedule_outlined,
                                      label: 'Starts',
                                      value: timeLabel,
                                      onTap: _saving ? null : _pickTime,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Duration',
                                style: AppFonts.style(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 8),
                              CupertinoSlidingSegmentedControl<int>(
                                groupValue: _durations.contains(_durationMinutes)
                                    ? _durationMinutes
                                    : _durations.first,
                                backgroundColor: AppColors.inset,
                                thumbColor: Colors.white,
                                children: {
                                  for (final m in _durations)
                                    m: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        '$m min',
                                        style: AppFonts.style(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                    ),
                                },
                                onValueChanged: _saving
                                    ? (_) {}
                                    : (v) {
                                        if (v == null) return;
                                        AppHaptics.selection();
                                        setState(() => _durationMinutes = v);
                                      },
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ends at $endLabel',
                                style: AppFonts.style(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _descriptionCtrl,
                                enabled: !_saving,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Notes',
                                  hintText: 'Clinical notes / visit summary',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              if (_isEdit) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'Status',
                                  style: AppFonts.style(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppColors.navy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final s in AppointmentStatuses.all)
                                      SoftPillButton(
                                        label: AppointmentStatuses.label(s),
                                        selected: _status == s,
                                        compact: false,
                                        selectionHaptic: true,
                                        onPressed: _saving
                                            ? null
                                            : () => setState(() => _status = s),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_saving)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter:
                                  ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                              child: ColoredBox(
                                color: Colors.white.withValues(alpha: 0.45),
                                child: const Center(
                                  child: ToothLoadingIndicator(
                                    size: 40,
                                    loadingText: 'Saving appointment…',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    AppButtons.ghost(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      label: 'Cancel',
                    ),
                    const Spacer(),
                    AppButtons.primary(
                      onPressed: _canSubmit ? _submit : null,
                      label: _isEdit ? 'Save changes' : 'Book appointment',
                      busy: _saving,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _pickPatientSheet() async {
    final maxH =
        (MediaQuery.sizeOf(context).height * 0.55).clamp(280.0, 520.0);
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) {
        return Material(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: maxH,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Text(
                          'Select patient',
                          style: AppFonts.style(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const Spacer(),
                        AppButtons.icon(
                          tooltip: 'Refresh',
                          onPressed: _loadPatients,
                          icon: Icons.refresh_rounded,
                          busy: _loadingPatients,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _patients.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No patients yet',
                                style: AppFonts.style(
                                  color: AppColors.muted,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _patients.length,
                            itemBuilder: (context, i) {
                              final p = _patients[i];
                              final id = widget.patientSession.pidOf(p);
                              final name = _patientMenuLabel(p);
                              final selected = id == _patientId;
                              return ListTile(
                                leading: InitialsAvatar(name: name, size: 36),
                                title: Text(
                                  name,
                                  style: AppFonts.style(
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: AppColors.navy,
                                  ),
                                ),
                                trailing: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: AppColors.dentalBlue,
                                      )
                                    : null,
                                onTap: () => Navigator.pop(ctx, id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

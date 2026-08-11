import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../appointment_service.dart';
import '../models/appointment.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.api,
    required this.patientSession,
    this.active = true,
  });

  final ApiClient api;
  final PatientSession patientSession;
  final bool active;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late final AppointmentService _service = AppointmentService(widget.api);

  List<Appointment> _items = [];
  String _statusFilter = 'all';
  String? _patientFilterId;
  bool _loading = true;
  bool _refreshing = false;
  bool _patientsRefreshing = false;
  String? _error;

  List<Map<String, dynamic>> get _patients => widget.patientSession.patients;

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
    setState(() {});
    // Drop stale filter if patient was deleted / list refreshed without them.
    final id = _patientFilterId;
    if (id != null &&
        !_patients.any((p) => widget.patientSession.pidOf(p) == id)) {
      _patientFilterId = null;
      _loadAppointments(soft: true);
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
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && showIndicator) {
        setState(() => _patientsRefreshing = false);
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  String _patientLabel(Map<String, dynamic> row) {
    final name =
        '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Patient' : name;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.patientSession.refresh(keepSelection: true);
      if (!mounted) return;
      await _loadAppointments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAppointments({bool soft = false}) async {
    if (soft) {
      setState(() => _refreshing = true);
    }
    try {
      final rows = await _service.list(
        status: _statusFilter == 'all' ? null : _statusFilter,
        patientId: _patientFilterId,
        upcomingOnly: false,
      );
      if (!mounted) return;
      final sorted = List<Appointment>.from(rows)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      setState(() {
        _items = sorted;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && soft) setState(() => _refreshing = false);
    }
  }

  Future<void> _refreshAll() async {
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        widget.patientSession.refresh(keepSelection: true),
        _loadAppointments(),
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
    });
  }

  Future<void> _openBookModal({Appointment? existing}) async {
    // Always refresh patients before opening so newly created patients appear.
    await _refreshPatients(showIndicator: false);
    if (!mounted) return;

    final saved = await showDialog<Appointment>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BookAppointmentModal(
        api: widget.api,
        service: _service,
        patientSession: widget.patientSession,
        existing: existing,
      ),
    );
    if (saved == null || !mounted) return;

    _upsertLocal(saved);
    AppSnackBars.success(
      context,
      'Appointment saved. Email notification sent to patient via Resend.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildFilterBar(),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          Expanded(
            child: _loading
                ? const ToothPageLoader(message: 'Loading appointments…')
                : RefreshIndicator(
                    color: AppColors.dentalBlue,
                    onRefresh: _refreshAll,
                    child: _buildList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final busy = _loading || _refreshing || _patientsRefreshing;
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Appointments',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Schedule visits · email confirmations via Resend',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : () => _openBookModal(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Book Appointment'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Refresh',
          onPressed: busy ? null : _refreshAll,
          icon: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: ToothLoadingIndicator(size: 22, compact: true),
                )
              : const Icon(Icons.refresh, color: AppColors.muted),
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

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AppointmentStatuses.filters.map((f) {
                final selected = _statusFilter == f.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    selectedColor: AppColors.sidebarActive,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: selected ? AppColors.navy : AppColors.muted,
                    ),
                    onSelected: (_) {
                      setState(() => _statusFilter = f.key);
                      _loadAppointments(soft: true);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(
                    'patient-filter-${_patients.length}-$filterValue',
                  ),
                  initialValue: filterValue,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Patient',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All patients'),
                    ),
                    ..._patients.map(
                      (p) => DropdownMenuItem<String?>(
                        value: widget.patientSession.pidOf(p),
                        child: Text(
                          _patientLabel(p),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (id) {
                    setState(() => _patientFilterId = id);
                    _loadAppointments(soft: true);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.45,
            child: SectionCard(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_busy_outlined,
                        size: 48,
                        color: AppColors.muted.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No appointments found for this filter',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Book a visit to send a confirmation email to the patient.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () => _openBookModal(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Book Appointment'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _AppointmentCard(
        appointment: _items[i],
        onEdit: () => _openBookModal(existing: _items[i]),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.onEdit,
  });

  final Appointment appointment;
  final VoidCallback onEdit;

  static final _dateFmt = DateFormat('MMM d, yyyy');
  static final _timeFmt = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final style = AppointmentStatusStyle.of(appointment.status);
    final when =
        '${_dateFmt.format(appointment.startTime)} · ${_timeFmt.format(appointment.startTime)} - ${_timeFmt.format(appointment.endTime)}';
    final notes = appointment.description.trim();

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              color: style.fg,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  when,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      appointment.patientName.isEmpty
                          ? 'Patient'
                          : appointment.patientName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: style.bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        style.label,
                        style: TextStyle(
                          color: style.fg,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    notes,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit appointment',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: AppColors.muted,
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
  String? _error;

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
    _loadPatients();
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loadingPatients = true;
      _error = null;
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
        _error = e.toString().replaceFirst('Exception: ', '');
      });
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
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
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
      setState(() => _error = 'Select a patient');
      return;
    }
    if (_end.isBefore(_start) || _end.isAtSameMomentAs(_start)) {
      setState(() => _error = 'End time must be after start time');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
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
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE, MMM d, yyyy').format(_start);
    final timeLabel = DateFormat('h:mm a').format(_start);
    final endLabel = DateFormat('h:mm a').format(_end);

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(_isEdit ? 'Edit Appointment' : 'Book Appointment'),
        content: SizedBox(
          width: 480,
          child: Stack(
            children: [
              Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isEdit) ...[
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Patient *',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _saving || _loadingPatients
                                  ? null
                                  : _loadPatients,
                              icon: _loadingPatients
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: ToothLoadingIndicator(
                                        size: 14,
                                        compact: true,
                                      ),
                                    )
                                  : const Icon(Icons.refresh, size: 16),
                              label: Text(
                                _loadingPatients ? 'Loading…' : 'Refresh',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_loadingPatients && _patients.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: ToothLoadingIndicator(
                                size: 28,
                                compact: true,
                                loadingText: 'Loading patients…',
                              ),
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'book-patient-${_patients.length}-$_patientId',
                            ),
                            initialValue: _patientId != null &&
                                    _patients.any(
                                      (p) =>
                                          widget.patientSession.pidOf(p) ==
                                          _patientId,
                                    )
                                ? _patientId
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              hintText: 'Select patient',
                            ),
                            items: _patients
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: widget.patientSession.pidOf(p),
                                    child: Text(
                                      _patientMenuLabel(p),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .where((e) => (e.value ?? '').isNotEmpty)
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _patientId = v),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Patient is required'
                                : null,
                          ),
                      ] else
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Patient',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            widget.existing!.patientName.isEmpty
                                ? 'Patient'
                                : widget.existing!.patientName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _pickDate,
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                              ),
                              label: Text(
                                dateLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _pickTime,
                              icon: const Icon(
                                Icons.schedule_outlined,
                                size: 16,
                              ),
                              label: Text(timeLabel),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Duration',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final m in _durations)
                            ChoiceChip(
                              label: Text('${m}m'),
                              selected: _durationMinutes == m,
                              onSelected: _saving
                                  ? null
                                  : (_) =>
                                      setState(() => _durationMinutes = m),
                              selectedColor: AppColors.sidebarActive,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _durationMinutes == m
                                    ? AppColors.navy
                                    : AppColors.muted,
                              ),
                            ),
                          if (!_durations.contains(_durationMinutes))
                            ChoiceChip(
                              label: Text('${_durationMinutes}m'),
                              selected: true,
                              onSelected: null,
                              selectedColor: AppColors.sidebarActive,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ends at $endLabel',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descriptionCtrl,
                        enabled: !_saving,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Clinical notes / visit summary',
                          alignLabelWithHint: true,
                        ),
                      ),
                      if (_isEdit) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration:
                              const InputDecoration(labelText: 'Status'),
                          items: AppointmentStatuses.all
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(AppointmentStatuses.label(s)),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  setState(() => _status = v);
                                },
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                          ),
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
                      filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
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
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: ToothLoadingIndicator(
                      size: 20,
                      compact: true,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEdit ? 'Save changes' : 'Book appointment'),
          ),
        ],
      ),
    );
  }
}

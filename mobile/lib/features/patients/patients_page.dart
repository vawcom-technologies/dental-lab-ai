import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'patient_models.dart';
import 'patients_controller.dart';

class PatientsPage extends StatefulWidget {
  const PatientsPage({
    super.key,
    required this.api,
    required this.dentistName,
    this.patientSession,
    this.onNewPatient,
    this.onInboxChanged,
  });

  final ApiClient api;
  final String dentistName;
  final PatientSession? patientSession;
  final VoidCallback? onNewPatient;
  final VoidCallback? onInboxChanged;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  late final PatientsController _controller;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = PatientsController(api: widget.api);
    _controller.onAccessMutated = widget.onInboxChanged;
    _controller.load();
  }

  @override
  void didUpdateWidget(covariant PatientsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.onAccessMutated = widget.onInboxChanged;
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    if (error) {
      AppSnackBars.error(context, message);
    } else {
      AppSnackBars.success(context, message);
    }
  }

  String _friendlyError(Object e) {
    if (e is AgentApiException) {
      if (e.isForbidden) {
        final lower = e.message.toLowerCase();
        if (lower.contains('approve') || lower.contains('reject')) {
          return 'Permission Denied: Only the patient owner can approve or reject access requests.';
        }
        if (lower.contains('access')) {
          return e.message;
        }
        return 'Permission Denied: Only the creator of this record can modify patient details.';
      }
      return e.message;
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _syncSharedPatientSession() async {
    final session = widget.patientSession;
    if (session == null) return;
    try {
      await session.refresh(keepSelection: true);
    } catch (_) {
      // Appointments/media will re-fetch on focus if this fails.
    }
  }

  Future<void> _openCreate() async {
    if (_controller.mutating) return;
    final created = await showCupertinoDialog<GdprPatient>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: _PatientFormDialog(
          title: 'New Patient',
          submitLabel: 'Create patient',
          saving: false,
          onSubmit: (fields) => _controller.createPatient(
            firstName: fields.firstName,
            lastName: fields.lastName,
            dateOfBirth: fields.dateOfBirth,
            email: fields.email,
            address: fields.address,
            phone: fields.phone,
            healthInsurance: fields.healthInsurance,
            status: fields.status,
          ),
        ),
      ),
    );
    if (created == null || !mounted) return;
    await _syncSharedPatientSession();
    if (!mounted) return;
    _toast('Patient created successfully');
  }

  Future<void> _openEdit(GdprPatient patient) async {
    if (_controller.mutating) return;
    if (!_controller.isOwner(patient)) {
      _toast(
        'Permission Denied: Only the creator of this record can modify patient details.',
        error: true,
      );
      return;
    }
    try {
      final updated = await showCupertinoDialog<GdprPatient>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        builder: (ctx) => Material(
          type: MaterialType.transparency,
          child: _PatientFormDialog(
            title: 'Edit Patient',
            submitLabel: 'Save changes',
            initial: patient,
            onSubmit: (fields) => _controller.updatePatient(patient.id, {
              'first_name': fields.firstName,
              'last_name': fields.lastName,
              'date_of_birth': fields.dateOfBirth,
              'email': fields.email,
              'address': fields.address,
              'phone': fields.phone,
              'health_insurance': fields.healthInsurance,
              'status': fields.status,
            }),
          ),
        ),
      );
      if (updated == null || !mounted) return;
      await _syncSharedPatientSession();
      if (!mounted) return;
      _toast('Patient updated');
    } catch (e) {
      _toast(_friendlyError(e), error: true);
    }
  }

  Future<void> _confirmDelete(GdprPatient patient) async {
    if (_controller.mutating) return;
    if (!_controller.isOwner(patient)) {
      _toast(
        'Permission Denied: Only the creator of this record can modify patient details.',
        error: true,
      );
      return;
    }
    final hard = await showCupertinoDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: _DeletePatientDialog(patientName: patient.fullName),
      ),
    );
    if (hard == null || !mounted) return;
    try {
      await _controller.deletePatient(patient.id, hard: hard);
      await _syncSharedPatientSession();
      if (!mounted) return;
      _toast(hard ? 'Patient permanently deleted' : 'Patient archived');
    } catch (e) {
      _toast(_friendlyError(e), error: true);
    }
  }

  Future<void> _openShare(GdprPatient patient) async {
    if (_controller.mutating || _controller.loadingDetail) return;
    await AppDialogs.modalSheet<void>(
      context: context,
      builder: (ctx) => _ShareAccessSheet(
        patient: patient,
        controller: _controller,
        onToast: _toast,
        friendlyError: _friendlyError,
      ),
    );
  }

  Future<void> _openPendingRequests() async {
    await _controller.loadPendingRequests();
    if (!mounted) return;
    await AppDialogs.modalSheet<void>(
      context: context,
      builder: (ctx) => Material(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: _PendingAccessDrawer(
          controller: _controller,
          onToast: _toast,
          friendlyError: _friendlyError,
        ),
      ),
    );
  }

  Future<void> _changePatientStatus(GdprPatient patient, String status) async {
    if (_controller.mutating) return;
    if (!_controller.isOwner(patient)) {
      _toast(
        'Permission Denied: Only the creator of this record can modify patient details.',
        error: true,
      );
      return;
    }
    final next = CaseStatuses.normalize(status);
    if (CaseStatuses.normalize(patient.status) == next) return;
    try {
      await _controller.updatePatient(patient.id, {'status': next});
      if (!mounted) return;
      _toast('Status updated to ${StatusStyle.of(next).label}');
    } catch (e) {
      if (!mounted) return;
      _toast(_friendlyError(e), error: true);
    }
  }

  Future<void> _openDetails(GdprPatient patient, {int tab = 0}) async {
    if (_controller.loadingDetail || _controller.mutating) return;
    try {
      final detailed = await _controller.openPatient(patient.id);
      if (detailed == null || !mounted) return;
      await AppDialogs.modalSheet<void>(
        context: context,
        builder: (ctx) => _PatientDetailSheet(
          controller: _controller,
          patient: detailed,
          initialTab: tab,
          onEdit: () {
            Navigator.pop(ctx);
            _openEdit(detailed);
          },
          onShare: () {
            Navigator.pop(ctx);
            _openShare(detailed);
          },
          onDelete: () {
            Navigator.pop(ctx);
            _confirmDelete(detailed);
          },
          onToast: _toast,
          friendlyError: _friendlyError,
        ),
      );
      _controller.clearSelected();
    } catch (e) {
      _toast(_friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final rows = _controller.visiblePatients;
        final opening = _controller.loadingDetail;
        final blocked = _controller.mutating || opening;
        return BusyBarrier(
          busy: blocked,
          message: opening ? 'Opening patient…' : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  icon: Icons.people_alt_outlined,
                  title: loc.patientsTitle,
                  subtitle: loc.patientsSubtitle,
                  chromeActions: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${_controller.shownCount} shown · ${_controller.totalCount} total',
                        style: AppFonts.style(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    AppButtons.icon(
                      tooltip: loc.refresh,
                      onPressed: _controller.loading || blocked
                          ? null
                          : () => _controller.load(),
                      icon: Icons.refresh_rounded,
                      busy: _controller.loading,
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AppButtons.icon(
                          tooltip: 'Pending access requests',
                          onPressed: blocked ? null : _openPendingRequests,
                          icon: Icons.mark_email_unread_outlined,
                        ),
                        if (_controller.pendingCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_controller.pendingCount}',
                                style: AppFonts.style(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  actions: [
                    AppButtons.primary(
                      onPressed: blocked ? null : _openCreate,
                      icon: Icons.add_rounded,
                      label: 'New Patient',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: GlassSurface(
                        borderRadius: BorderRadius.circular(16),
                        blur: 14,
                        tint: Colors.white.withValues(alpha: 0.55),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: TextField(
                          controller: _search,
                          onChanged: _controller.setQuery,
                          enabled: !blocked,
                          style: AppFonts.style(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.navy,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search patients…',
                            hintStyle: AppFonts.style(
                              color: AppColors.muted,
                              fontSize: 15,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppColors.muted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: GlassSurface(
                        borderRadius: BorderRadius.circular(16),
                        blur: 14,
                        tint: Colors.white.withValues(alpha: 0.55),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _controller.statusFilter,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(14),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.muted,
                            ),
                            style: AppFonts.style(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                            items: [
                              for (final f in CaseStatuses.filters)
                                DropdownMenuItem<String>(
                                  value: f.key,
                                  child: Text(f.label),
                                ),
                            ],
                            onChanged: blocked
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    _controller.setStatusFilter(value);
                                  },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_controller.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _controller.error!,
                    style: AppFonts.style(
                      color: AppColors.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: AppSwitcher(
                    child: KeyedSubtree(
                      key: ValueKey(
                        '${_controller.statusFilter}|${_controller.query}|${rows.length}|${_controller.loading}',
                      ),
                      child: _controller.loading && rows.isEmpty
                          ? const ToothPageLoader(message: 'Loading patients…')
                          : rows.isEmpty
                              ? _EmptyPatients(
                                  filtered:
                                      _controller.statusFilter != 'all' ||
                                          _controller.query.trim().isNotEmpty,
                                )
                              : ListView.separated(
                                  itemCount: rows.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, i) {
                                    final p = rows[i];
                                    final owner = _controller.isOwner(p);
                                    return _PatientCard(
                                      patient: p,
                                      isOwner: owner,
                                      roleLabel:
                                          AppRoles.label(widget.api.role),
                                      enabled: !blocked,
                                      onOpen: () => _openDetails(p),
                                      onNotes: () => _openDetails(p, tab: 1),
                                      onEdit:
                                          owner ? () => _openEdit(p) : null,
                                      onShare: () => _openShare(p),
                                      onDelete: owner
                                          ? () => _confirmDelete(p)
                                          : null,
                                      onStatusChanged: owner
                                          ? (status) =>
                                              _changePatientStatus(p, status)
                                          : null,
                                    );
                                  },
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

class _EmptyPatients extends StatelessWidget {
  const _EmptyPatients({this.filtered = false});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassSurface(
        borderRadius: BorderRadius.circular(22),
        blur: 16,
        tint: Colors.white.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeoIconBadge(
              icon: filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.person_add_alt_1_outlined,
              size: 56,
              iconSize: 26,
              color: AppColors.muted,
            ),
            const SizedBox(height: 14),
            Text(
              filtered ? 'No matching patients' : 'No patients yet',
              textAlign: TextAlign.center,
              style: AppFonts.style(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Try another status or clear the search.'
                  : 'Add the first record to get started.',
              textAlign: TextAlign.center,
              style: AppFonts.style(
                color: AppColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({
    required this.patient,
    required this.isOwner,
    required this.onOpen,
    this.onNotes,
    this.roleLabel,
    this.enabled = true,
    this.onEdit,
    this.onShare,
    this.onDelete,
    this.onStatusChanged,
  });

  final GdprPatient patient;
  final bool isOwner;
  final String? roleLabel;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback? onNotes;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      blur: 16,
      tint: Colors.white.withValues(alpha: 0.52),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onOpen : null,
          borderRadius: BorderRadius.circular(20),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppColors.dentalBlue.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PatientAvatar(
                      name: patient.fullName,
                      isOwner: isOwner,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              patient.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          PatientStatusMenu(
                            status: patient.status,
                            enabled: enabled && onStatusChanged != null,
                            onSelected: onStatusChanged,
                          ),
                          const SizedBox(width: 10),
                          _AccessBadge(
                            isOwner: isOwner,
                            roleLabel: roleLabel,
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final actions = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    AppButtons.ghost(
                      onPressed: enabled ? (onNotes ?? onOpen) : null,
                      icon: Icons.notes_outlined,
                      label: 'Notes',
                      compact: true,
                    ),
                    AppButtons.ghost(
                      onPressed: enabled ? onEdit : null,
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      compact: true,
                    ),
                    AppButtons.ghost(
                      onPressed: enabled ? onShare : null,
                      icon: Icons.share_outlined,
                      label: isOwner ? 'Share' : 'Request',
                      compact: true,
                    ),
                    AppButtons.danger(
                      onPressed: enabled ? onDelete : null,
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      soft: true,
                      compact: true,
                    ),
                  ],
                );

                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.name, required this.isOwner});

  final String name;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final bg = isOwner
        ? AppColors.dentalBlue.withValues(alpha: 0.14)
        : AppColors.reviewSoft;
    final fg = isOwner ? AppColors.dentalBlue : AppColors.review;
    final initials = _initials(name);

    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: NeoShadows.soft(depth: 0.4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      ),
      child: Text(
        initials,
        style: AppFonts.style(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  static String _initials(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({
    required this.isOwner,
    this.roleLabel,
  });

  final bool isOwner;
  final String? roleLabel;

  @override
  Widget build(BuildContext context) {
    final color = isOwner ? AppColors.success : AppColors.review;
    final role = (roleLabel ?? '').trim();
    final prefix = isOwner ? 'Created by' : 'Access';
    final pill = isOwner
        ? (role.isNotEmpty ? role : 'Creator')
        : 'Shared';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          prefix,
          style: AppFonts.style(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                pill,
                style: AppFonts.style(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PatientFormFields {
  const _PatientFormFields({
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.email,
    required this.address,
    required this.phone,
    required this.healthInsurance,
    required this.status,
  });

  final String firstName;
  final String lastName;
  final String dateOfBirth;
  final String email;
  final String address;
  final String phone;
  final String healthInsurance;
  final String status;
}

class _PatientFormDialog extends StatefulWidget {
  const _PatientFormDialog({
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.initial,
    this.saving = false,
  });

  final String title;
  final String submitLabel;
  final GdprPatient? initial;
  final bool saving;
  final Future<GdprPatient> Function(_PatientFormFields fields) onSubmit;

  @override
  State<_PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<_PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _dob;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _insurance;
  late String _status;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _first = TextEditingController(text: p?.firstName ?? '');
    _last = TextEditingController(text: p?.lastName ?? '');
    _dob = TextEditingController(text: p?.dateOfBirth ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _phone = TextEditingController(text: PhoneNumbers.localDigits(p?.phone));
    _insurance = TextEditingController(text: p?.healthInsurance ?? '');
    _status = CaseStatuses.normalize(p?.status);
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _dob.dispose();
    _email.dispose();
    _address.dispose();
    _phone.dispose();
    _insurance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phoneLocal = _phone.text.trim();
    final phoneError = PhoneNumbers.validateRequired(phoneLocal);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    final fields = _PatientFormFields(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      dateOfBirth: _dob.text.trim(),
      email: _email.text.trim(),
      address: _address.text.trim(),
      phone: PhoneNumbers.compose(phoneLocal),
      healthInsurance: _insurance.text.trim(),
      status: CaseStatuses.normalize(_status),
    );
    if (fields.firstName.isEmpty ||
        fields.lastName.isEmpty ||
        fields.dateOfBirth.isEmpty ||
        fields.address.isEmpty ||
        fields.healthInsurance.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final patient = await widget.onSubmit(fields);
      if (!mounted) return;
      Navigator.pop(context, patient);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AgentApiException
            ? (e.isForbidden
                ? 'Permission Denied: Only the creator of this record can modify patient details.'
                : e.message)
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(24),
          blur: 28,
          tint: Colors.white.withValues(alpha: 0.78),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: AppFonts.style(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    children: [
                      _DialogField(
                        controller: _first,
                        label: 'First name',
                        requiredField: true,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const _InsetDivider(),
                      _DialogField(
                        controller: _last,
                        label: 'Last name',
                        requiredField: true,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const _InsetDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: DobPickerField(
                          controller: _dob,
                          labelText: 'Date of birth',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const _InsetDivider(),
                      _DialogField(
                        controller: _email,
                        label: 'Email',
                        requiredField: true,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        validator: validatePatientEmail,
                      ),
                      const _InsetDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: PhoneField(
                          controller: _phone,
                          labelText: 'Phone',
                        ),
                      ),
                      const _InsetDivider(),
                      _DialogField(
                        controller: _insurance,
                        label: 'Health insurance',
                        requiredField: true,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const _InsetDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: InputDecoration(
                            labelText: 'Status',
                            labelStyle: AppFonts.style(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          items: [
                            for (final key in CaseStatuses.all)
                              DropdownMenuItem<String>(
                                value: key,
                                child: Text(StatusStyle.of(key).label),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => _status = value);
                                },
                        ),
                      ),
                      const _InsetDivider(),
                      _DialogField(
                        controller: _address,
                        label: 'Address',
                        requiredField: true,
                        minLines: 2,
                        maxLines: 3,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: AppFonts.style(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButtons.ghost(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        label: 'Cancel',
                        compact: true,
                      ),
                      const SizedBox(width: 8),
                      AppButtons.primary(
                        onPressed: _saving ? null : _submit,
                        label: widget.submitLabel,
                        compact: true,
                        busy: _saving,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.requiredField = false,
    this.validator,
    this.keyboardType,
    this.autofillHints,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool requiredField;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        minLines: minLines,
        maxLines: maxLines,
        style: AppFonts.style(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.navy,
        ),
        decoration: InputDecoration(
          labelText: requiredField ? '$label *' : label,
          labelStyle: AppFonts.style(
            color: AppColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        validator: validator,
      ),
    );
  }
}

class _DeletePatientDialog extends StatefulWidget {
  const _DeletePatientDialog({required this.patientName});

  final String patientName;

  @override
  State<_DeletePatientDialog> createState() => _DeletePatientDialogState();
}

class _DeletePatientDialogState extends State<_DeletePatientDialog> {
  bool _hard = false;
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canHard = _confirm.text.trim().toUpperCase() == 'DELETE';
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(24),
          blur: 28,
          tint: Colors.white.withValues(alpha: 0.78),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Delete patient?',
                style: AppFonts.style(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how to remove ${widget.patientName}.',
                style: AppFonts.style(
                  fontSize: 14,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              _InsetGroup(
                children: [
                  _DeleteOptionRow(
                    selected: !_hard,
                    title: 'Archive patient',
                    subtitle: 'Soft delete — keeps data for recovery',
                    accent: AppColors.dentalBlue,
                    onTap: () => setState(() => _hard = false),
                  ),
                  const _InsetDivider(),
                  _DeleteOptionRow(
                    selected: _hard,
                    title: 'Delete forever',
                    subtitle: 'Hard delete — permanent GDPR Art. 17 erasure',
                    accent: AppColors.danger,
                    onTap: () => setState(() => _hard = true),
                  ),
                ],
              ),
              if (_hard) ...[
                const SizedBox(height: 12),
                _InsetGroup(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: TextField(
                    controller: _confirm,
                    onChanged: (_) => setState(() {}),
                    style: AppFonts.style(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.navy,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Type DELETE to confirm',
                      labelStyle: AppFonts.style(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButtons.ghost(
                    onPressed: () => Navigator.pop(context),
                    label: 'Cancel',
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  AppButtons.danger(
                    onPressed: (!_hard || canHard)
                        ? () => Navigator.pop(context, _hard)
                        : null,
                    label: _hard ? 'Delete forever' : 'Archive',
                    soft: true,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteOptionRow extends StatelessWidget {
  const _DeleteOptionRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: accent.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppFonts.style(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppFonts.style(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected ? accent : AppColors.border,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareAccessSheet extends StatefulWidget {
  const _ShareAccessSheet({
    required this.patient,
    required this.controller,
    required this.onToast,
    required this.friendlyError,
  });

  final GdprPatient patient;
  final PatientsController controller;
  final void Function(String message, {bool error}) onToast;
  final String Function(Object e) friendlyError;

  @override
  State<_ShareAccessSheet> createState() => _ShareAccessSheetState();
}

class _ShareAccessSheetState extends State<_ShareAccessSheet> {
  List<EligibleAccessUser> _users = [];
  bool _loading = true;
  String? _busyId;

  bool get _isOwner => widget.controller.isOwner(widget.patient);

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users =
          await widget.controller.listEligibleUsers(widget.patient.id);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _share(String userId) async {
    if (_busyId != null || _users.isEmpty) return;
    setState(() => _busyId = userId);
    try {
      final result = await widget.controller.shareAccess(
        patientId: widget.patient.id,
        targetUserId: userId,
      );
      if (result.immediate) {
        widget.onToast('Access successfully granted to staff member.');
      } else {
        widget.onToast(
          'Access request submitted to patient owner for review.',
        );
      }
      // Refresh eligible list so granted/requested users disappear.
      final users =
          await widget.controller.listEligibleUsers(widget.patient.id);
      if (mounted) setState(() => _users = users);
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final actionLabel = _isOwner ? 'Grant access' : 'Request access';
    final subtext = _users.isEmpty && !_loading
        ? 'All practice staff members already have access or pending requests for this patient.'
        : (_isOwner
            ? 'As owner, your invitation will immediately allow access.'
            : 'This request will be sent to the patient owner for approval.');

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: SizedBox(
        height: height,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(28),
          blur: 28,
          tint: Colors.white.withValues(alpha: 0.72),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PatientAvatar(
                      name: widget.patient.fullName,
                      isOwner: _isOwner,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Share ${widget.patient.fullName}',
                            style: AppFonts.style(
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: AppColors.navy,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtext,
                            style: AppFonts.style(
                              color: AppColors.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const ToothPageLoader(
                        message: 'Loading eligible staff…',
                      )
                    : _users.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                'No eligible staff available to invite.',
                                textAlign: TextAlign.center,
                                style: AppFonts.style(
                                  color: AppColors.muted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              20,
                              0,
                              20,
                              20,
                            ),
                            itemCount: _users.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final u = _users[i];
                              final busy = _busyId == u.userId;
                              final title = u.fullName.trim().isEmpty
                                  ? (u.email ?? 'Staff member')
                                  : u.fullName.trim();
                              final showEmail = u.email != null &&
                                  u.email!.trim().isNotEmpty &&
                                  u.email!.trim() != title;
                              return _InsetGroup(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  12,
                                  12,
                                ),
                                child: Row(
                                  children: [
                                    _StaffAvatar(name: title),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppFonts.style(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: AppColors.navy,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          if (showEmail) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              u.email!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppFonts.style(
                                                fontSize: 13,
                                                color: AppColors.muted,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    AppButtons.primary(
                                      onPressed: _busyId != null ||
                                              _users.isEmpty
                                          ? null
                                          : () => _share(u.userId),
                                      label: actionLabel,
                                      compact: true,
                                      busy: busy,
                                    ),
                                  ],
                                ),
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
}

class _StaffAvatar extends StatelessWidget {
  const _StaffAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.dentalBlue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      ),
      child: Text(
        initials,
        style: AppFonts.style(
          color: AppColors.dentalBlue,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }

  static String _initials(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '?';
    if (t.contains('@')) {
      final local = t.split('@').first;
      return local.isEmpty ? '?' : local[0].toUpperCase();
    }
    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _PendingAccessDrawer extends StatelessWidget {
  const _PendingAccessDrawer({
    required this.controller,
    required this.onToast,
    required this.friendlyError,
  });

  final PatientsController controller;
  final void Function(String message, {bool error}) onToast;
  final String Function(Object e) friendlyError;

  Future<void> _approve(BuildContext context, PendingAccessRequest req) async {
    try {
      await controller.approveAccessRequest(req.id);
      onToast(
        'Access approved. Staff member can now access this patient record.',
      );
    } catch (e) {
      onToast(friendlyError(e), error: true);
    }
  }

  Future<void> _reject(BuildContext context, PendingAccessRequest req) async {
    try {
      await controller.rejectAccessRequest(req.id);
      onToast('Access request rejected.');
    } catch (e) {
      onToast(friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return SizedBox(
      height: height,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final rows = controller.pendingRequests;
          final blocked = controller.mutating;
          return BusyBarrier(
            busy: blocked,
            blockInteraction: blocked,
            showSpinner: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Pending access requests',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rows.isEmpty
                        ? 'No pending requests right now.'
                        : '${rows.length} request${rows.length == 1 ? '' : 's'} awaiting your decision.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: controller.loadingPending && rows.isEmpty
                        ? const ToothPageLoader(
                            message: 'Loading access requests…',
                          )
                        : rows.isEmpty
                            ? const Center(
                                child: Text(
                                  'All caught up.',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final r = rows[i];
                                  final when = r.createdAt == null
                                      ? ''
                                      : DateFormat.yMMMd()
                                          .add_Hm()
                                          .format(r.createdAt!.toLocal());
                                  return SectionCard(
                                    padding: const EdgeInsets.all(14),
                                    depth: 0.45,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.patientName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.navy,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Target: ${r.targetUserName}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.text,
                                          ),
                                        ),
                                        Text(
                                          'Requested by: ${r.requestingUserName}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.text,
                                          ),
                                        ),
                                        if (when.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            when,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: FilledButton(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.success,
                                                ),
                                                onPressed: blocked
                                                    ? null
                                                    : () =>
                                                        _approve(context, r),
                                                child: const Text('Approve'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.danger,
                                                  side: const BorderSide(
                                                    color: AppColors.danger,
                                                  ),
                                                ),
                                                onPressed: blocked
                                                    ? null
                                                    : () => _reject(context, r),
                                                child: const Text('Reject'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AccessStatusBadge extends StatelessWidget {
  const _AccessStatusBadge.status(this.status) : label = null, owner = false;

  const _AccessStatusBadge.owner()
      : status = null,
        label = 'Owner',
        owner = true;

  final PatientAccessStatus? status;
  final String? label;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String text;
    if (owner) {
      bg = const Color(0xFFE3F0FF);
      fg = AppColors.dentalBlue;
      text = label ?? 'Owner';
    } else {
      switch (status!) {
        case PatientAccessStatus.approved:
          bg = AppColors.successSoft;
          fg = AppColors.success;
          text = status!.label;
        case PatientAccessStatus.pending:
          bg = AppColors.warningSoft;
          fg = AppColors.warning;
          text = status!.label;
        case PatientAccessStatus.rejected:
          bg = const Color(0xFFE8EDF4);
          fg = AppColors.muted;
          text = status!.label;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PatientDetailSheet extends StatefulWidget {
  const _PatientDetailSheet({
    required this.controller,
    required this.patient,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onToast,
    required this.friendlyError,
    this.initialTab = 0,
  });

  final PatientsController controller;
  final GdprPatient patient;
  final int initialTab;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final void Function(String message, {bool error}) onToast;
  final String Function(Object e) friendlyError;

  @override
  State<_PatientDetailSheet> createState() => _PatientDetailSheetState();
}

class _PatientDetailSheetState extends State<_PatientDetailSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _note = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    // Defer controller loads — notifyListeners during initState/build marks the
    // parent ListenableBuilder dirty mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.loadNotes(widget.patient.id);
      widget.controller.loadAccess(widget.patient.id);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = _note.text.trim();
    if (text.isEmpty || _adding || widget.controller.mutating) return;
    setState(() => _adding = true);
    try {
      await widget.controller.addNote(
        patientId: widget.patient.id,
        content: text,
      );
      _note.clear();
      widget.onToast('Note added');
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editNote(PatientNote note) async {
    if (widget.controller.mutating) return;
    final me = widget.controller.currentUserId;
    if (me == null || note.authorId != me) {
      widget.onToast(
        'Only the author can edit this clinical note.',
        error: true,
      );
      return;
    }
    final next = await AppDialogs.prompt(
      context,
      title: 'Edit note',
      initial: note.noteContent,
      placeholder: 'Clinical note',
      confirmLabel: 'Save',
      maxLines: 4,
    );
    if (next == null || next.trim().isEmpty) return;
    final trimmed = next.trim();
    try {
      await widget.controller.editNote(noteId: note.id, content: trimmed);
      widget.onToast('Note updated');
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _revokeAccess(PatientAccessEntry entry) async {
    if (widget.controller.mutating) return;
    try {
      await widget.controller.revokeAccess(
        patientId: widget.patient.id,
        targetUserId: entry.userId,
      );
      widget.onToast('Access revoked');
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _approveAccess(PatientAccessEntry entry) async {
    if (widget.controller.mutating) return;
    try {
      await widget.controller.approveAccessEntry(entry);
      widget.onToast('Access approved');
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _rejectAccess(PatientAccessEntry entry) async {
    if (widget.controller.mutating) return;
    try {
      await widget.controller.rejectAccessEntry(entry);
      widget.onToast('Access request rejected');
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _regrantAccess(PatientAccessEntry entry) async {
    if (widget.controller.mutating) return;
    try {
      final result = await widget.controller.shareAccess(
        patientId: widget.patient.id,
        targetUserId: entry.userId,
      );
      widget.onToast(
        result.immediate
            ? 'Access successfully re-granted.'
            : 'Access request submitted to patient owner for review.',
      );
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _deleteNote(PatientNote note) async {
    if (widget.controller.mutating) return;
    final me = widget.controller.currentUserId;
    if (me == null || note.authorId != me) {
      widget.onToast(
        'Only the author can delete this clinical note.',
        error: true,
      );
      return;
    }
    final ok = await AppDialogs.confirm(
      context,
      title: 'Delete note?',
      message: 'This clinical note will be permanently removed.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!ok) return;
    try {
      await widget.controller.deleteNote(note.id);
      widget.onToast('Note deleted');
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    final owner = widget.controller.isOwner(p);
    final height = MediaQuery.sizeOf(context).height * 0.62;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            height: height,
            child: GlassSurface(
          borderRadius: BorderRadius.circular(28),
          blur: 28,
          tint: Colors.white.withValues(alpha: 0.72),
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final notes = widget.controller.notes;
              final access = widget.controller.accessEntries;
              final accessOwner = widget.controller.accessOwner;
              final accessViewerIsOwner =
                  widget.controller.accessViewerIsOwner;
              final blocked = widget.controller.mutating;
              return BusyBarrier(
                busy: blocked,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.muted.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PatientAvatar(
                            name: p.fullName,
                            isOwner: owner,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.fullName,
                                  style: AppFonts.style(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.navy,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  p.email,
                                  style: AppFonts.style(
                                    fontSize: 14,
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _AccessBadge(
                            isOwner: owner,
                            roleLabel: AppRoles.label(
                              widget.controller.api.role,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (owner)
                            AppButtons.ghost(
                              onPressed: blocked ? null : widget.onEdit,
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                              compact: true,
                            ),
                          AppButtons.ghost(
                            onPressed: blocked ? null : widget.onShare,
                            icon: Icons.share_outlined,
                            label: owner ? 'Share' : 'Request',
                            compact: true,
                          ),
                          if (owner)
                            AppButtons.danger(
                              onPressed: blocked ? null : widget.onDelete,
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
                              soft: true,
                              compact: true,
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: AnimatedBuilder(
                        animation: _tabs,
                        builder: (context, _) {
                          return SizedBox(
                            width: double.infinity,
                            child: CupertinoSlidingSegmentedControl<int>(
                              groupValue: _tabs.index,
                              backgroundColor:
                                  AppColors.inset.withValues(alpha: 0.7),
                              thumbColor: Colors.white.withValues(alpha: 0.95),
                              children: {
                                0: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Info',
                                    style: AppFonts.style(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ),
                                1: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Notes',
                                    style: AppFonts.style(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ),
                                2: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Access',
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
                                _tabs.animateTo(value);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _buildDemographicsTab(p),
                          _buildNotesTab(
                            notes: notes,
                            blocked: blocked,
                          ),
                          _buildAccessTab(
                            access: access,
                            accessOwner: accessOwner,
                            accessViewerIsOwner: accessViewerIsOwner,
                            blocked: blocked,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          ),
        ),
        ),
        ),
      ),
    );
  }

  Widget _buildDemographicsTab(GdprPatient p) {
    final rows = [
      ('Date of birth', p.dateOfBirth),
      ('Email', p.email),
      ('Phone', p.phone),
      ('Health insurance', p.healthInsurance),
      ('Address', p.address),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _InsetGroup(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const _InsetDivider(),
              _DemoRow(label: rows[i].$1, value: rows[i].$2),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildNotesTab({
    required List<PatientNote> notes,
    required bool blocked,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          _InsetGroup(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _note,
                    enabled: !blocked && !_adding,
                    minLines: 1,
                    maxLines: 3,
                    style: AppFonts.style(
                      fontSize: 15,
                      color: AppColors.navy,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add a clinical note…',
                      hintStyle: AppFonts.style(
                        color: AppColors.muted,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppButtons.primary(
                  onPressed: blocked || _adding ? null : _addNote,
                  label: 'Add',
                  compact: true,
                  busy: _adding,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.controller.loadingNotes && notes.isEmpty
                ? const ToothPageLoader(
                    message: 'Loading notes…',
                    size: 40,
                  )
                : notes.isEmpty
                    ? Center(
                        child: Text(
                          'No clinical notes yet.',
                          style: AppFonts.style(
                            color: AppColors.muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: notes.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final n = notes[i];
                          final me = widget.controller.currentUserId;
                          final isAuthor =
                              me != null && n.authorId == me;
                          final canMutate = isAuthor && !blocked;
                          final when = n.createdAt == null
                              ? ''
                              : DateFormat.yMMMd()
                                  .add_Hm()
                                  .format(n.createdAt!.toLocal());
                          return _InsetGroup(
                            padding: const EdgeInsets.fromLTRB(
                              14,
                              12,
                              8,
                              12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.noteContent,
                                        style: AppFonts.style(
                                          color: AppColors.navy,
                                          fontSize: 15,
                                          height: 1.4,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        [
                                          n.displayAuthorName,
                                          if (when.isNotEmpty) when,
                                        ].join(' · '),
                                        style: AppFonts.style(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (canMutate)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppButtons.icon(
                                        tooltip: 'Edit note',
                                        onPressed: () => _editNote(n),
                                        icon: Icons.edit_outlined,
                                      ),
                                      AppButtons.icon(
                                        tooltip: 'Delete note',
                                        onPressed: () => _deleteNote(n),
                                        icon: Icons.delete_outline_rounded,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessTab({
    required List<PatientAccessEntry> access,
    required PatientAccessOwner? accessOwner,
    required bool accessViewerIsOwner,
    required bool blocked,
  }) {
    if (widget.controller.loadingAccess && accessOwner == null) {
      return const ToothPageLoader(message: 'Loading access…');
    }
    if (accessOwner == null) {
      return Center(
        child: Text(
          'No access information available.',
          style: AppFonts.style(color: AppColors.muted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _buildOwnerAccessCard(accessOwner),
        if (!accessViewerIsOwner) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Only the patient owner can view and manage full staff access permissions.',
              style: AppFonts.style(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ] else ...[
          for (final entry in access) ...[
            const SizedBox(height: 10),
            _buildAccessListCard(
              entry: entry,
              isOwner: true,
              blocked: blocked,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildOwnerAccessCard(PatientAccessOwner owner) {
    return _InsetGroup(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  owner.fullName,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const _AccessStatusBadge.owner(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessListCard({
    required PatientAccessEntry entry,
    required bool isOwner,
    required bool blocked,
  }) {
    final when = entry.createdAt == null
        ? ''
        : DateFormat.yMMMd().add_Hm().format(entry.createdAt!.toLocal());

    String? subtext;
    Widget? actions;

    switch (entry.status) {
      case PatientAccessStatus.approved:
        if (isOwner) {
          actions = AppButtons.danger(
            onPressed: blocked ? null : () => _revokeAccess(entry),
            label: 'Revoke',
            soft: true,
            compact: true,
          );
        }
      case PatientAccessStatus.pending:
        final requester = entry.requestedByName?.trim();
        final requestedBy = (requester != null && requester.isNotEmpty)
            ? 'Requested by $requester'
            : null;
        if (isOwner) {
          subtext = requestedBy;
          actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButtons.primary(
                onPressed: blocked ? null : () => _approveAccess(entry),
                label: 'Approve',
                compact: true,
              ),
              const SizedBox(width: 8),
              AppButtons.danger(
                onPressed: blocked ? null : () => _rejectAccess(entry),
                label: 'Reject',
                soft: true,
                compact: true,
              ),
            ],
          );
        } else {
          subtext = [
            ?requestedBy,
            'Waiting for owner review',
          ].join('\n');
        }
      case PatientAccessStatus.rejected:
        if (isOwner) {
          actions = AppButtons.ghost(
            onPressed: blocked ? null : () => _regrantAccess(entry),
            label: 'Re-grant',
            compact: true,
          );
        }
    }

    return _InsetGroup(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.userName,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    fontSize: 16,
                  ),
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    when,
                    style: AppFonts.style(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (subtext != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtext,
                    style: AppFonts.style(
                      fontSize: 13,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _AccessStatusBadge.status(entry.status),
              ],
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: 8),
            actions,
          ],
        ],
      ),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({
    this.child,
    this.children,
    this.padding,
  }) : assert(child != null || children != null);

  final Widget? child;
  final List<Widget>? children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9AADC4).withValues(alpha: 0.12),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child != null
          ? Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children!,
            ),
    );
  }
}

class _InsetDivider extends StatelessWidget {
  const _InsetDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 16,
      endIndent: 16,
      color: AppColors.border.withValues(alpha: 0.7),
    );
  }
}

class _DemoRow extends StatelessWidget {
  const _DemoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppFonts.style(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: AppFonts.style(
                fontSize: 15,
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

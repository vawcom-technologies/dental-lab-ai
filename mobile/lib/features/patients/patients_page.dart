import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'patient_models.dart';
import 'patients_controller.dart';

class PatientsPage extends StatefulWidget {
  const PatientsPage({
    super.key,
    required this.api,
    required this.dentistName,
    this.onNewPatient,
  });

  final ApiClient api;
  final String dentistName;
  final VoidCallback? onNewPatient;

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
    _controller.load();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  String _friendlyError(Object e) {
    if (e is AgentApiException) {
      if (e.isForbidden) {
        return 'Permission Denied: Only the creator of this record can modify patient details.';
      }
      return e.message;
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _openCreate() async {
    final created = await showDialog<GdprPatient>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PatientFormDialog(
        title: 'New Patient',
        submitLabel: 'Create patient',
        saving: false,
        onSubmit: (fields) => _controller.createPatient(
          firstName: fields.firstName,
          lastName: fields.lastName,
          dateOfBirth: fields.dateOfBirth,
          address: fields.address,
          phone: fields.phone,
          healthInsurance: fields.healthInsurance,
        ),
      ),
    );
    if (created == null || !mounted) return;
    AppHaptics.success();
    _toast('Patient created successfully');
  }

  Future<void> _openEdit(GdprPatient patient) async {
    if (!_controller.isOwner(patient)) {
      _toast(
        'Permission Denied: Only the creator of this record can modify patient details.',
        error: true,
      );
      return;
    }
    try {
      final updated = await showDialog<GdprPatient>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _PatientFormDialog(
          title: 'Edit Patient',
          submitLabel: 'Save changes',
          initial: patient,
          onSubmit: (fields) => _controller.updatePatient(patient.id, {
            'first_name': fields.firstName,
            'last_name': fields.lastName,
            'date_of_birth': fields.dateOfBirth,
            'address': fields.address,
            'phone': fields.phone,
            'health_insurance': fields.healthInsurance,
          }),
        ),
      );
      if (updated == null || !mounted) return;
      AppHaptics.success();
      _toast('Patient updated');
    } catch (e) {
      _toast(_friendlyError(e), error: true);
    }
  }

  Future<void> _confirmDelete(GdprPatient patient) async {
    if (!_controller.isOwner(patient)) {
      _toast(
        'Permission Denied: Only the creator of this record can modify patient details.',
        error: true,
      );
      return;
    }
    final hard = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeletePatientDialog(patientName: patient.fullName),
    );
    if (hard == null || !mounted) return;
    try {
      await _controller.deletePatient(patient.id, hard: hard);
      AppHaptics.warn();
      _toast(hard ? 'Patient permanently deleted' : 'Patient archived');
    } catch (e) {
      _toast(_friendlyError(e), error: true);
    }
  }

  Future<void> _openShare(GdprPatient patient) async {
    if (!_controller.isOwner(patient)) {
      _toast(
        'Permission Denied: Only the creator of this record can manage access.',
        error: true,
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _ShareAccessSheet(
        patient: patient,
        controller: _controller,
        onToast: _toast,
      ),
    );
  }

  Future<void> _openDetails(GdprPatient patient) async {
    try {
      final detailed = await _controller.openPatient(patient.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) => _PatientDetailSheet(
          controller: _controller,
          patient: detailed,
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

  Future<void> _exportDatev() async {
    final rows = _controller.visiblePatients;
    if (rows.isEmpty) {
      _toast('No patients to export', error: true);
      return;
    }
    try {
      final xml = await widget.api.exportDatevXml(rows.first.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('DATEV export'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: SelectableText(xml, style: const TextStyle(fontSize: 12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                icon: Icons.people_alt_outlined,
                title: loc.patientsTitle,
                subtitle: loc.patientsSubtitle,
                actions: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.sidebarActive,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_controller.shownCount} shown · ${_controller.totalCount} total',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: loc.refresh,
                    onPressed:
                        _controller.loading ? null : () => _controller.load(),
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                  FilledButton.icon(
                    onPressed: _openCreate,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Patient'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportDatev,
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('DATEV export'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SectionCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                depth: 0.7,
                child: TextField(
                  controller: _search,
                  onChanged: _controller.setQuery,
                  decoration: const InputDecoration(
                    hintText: 'Search patients…',
                    prefixIcon: Icon(Icons.search, color: AppColors.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              if (_controller.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _controller.error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: SectionCard(
                  padding: EdgeInsets.zero,
                  child: _controller.loading && rows.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : rows.isEmpty
                          ? const _EmptyPatients()
                          : ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: AppColors.border.withValues(alpha: 0.7),
                              ),
                              itemBuilder: (context, i) {
                                final p = rows[i];
                                final owner = _controller.isOwner(p);
                                return _PatientTile(
                                  patient: p,
                                  isOwner: owner,
                                  onOpen: () => _openDetails(p),
                                  onEdit: owner ? () => _openEdit(p) : null,
                                  onShare: owner ? () => _openShare(p) : null,
                                  onDelete:
                                      owner ? () => _confirmDelete(p) : null,
                                );
                              },
                            ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyPatients extends StatelessWidget {
  const _EmptyPatients();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_alt_1_outlined,
                size: 48, color: AppColors.muted),
            SizedBox(height: 12),
            Text(
              'No patients yet. Add the first record.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({
    required this.patient,
    required this.isOwner,
    required this.onOpen,
    this.onEdit,
    this.onShare,
    this.onDelete,
  });

  final GdprPatient patient;
  final bool isOwner;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onOpen,
      leading: CircleAvatar(
        backgroundColor: AppColors.dentalBlue.withValues(alpha: 0.15),
        child: Text(
          patient.fullName.isNotEmpty
              ? patient.fullName.characters.first.toUpperCase()
              : '?',
          style: const TextStyle(
            color: AppColors.dentalBlue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              patient.fullName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AccessBadge(isOwner: isOwner),
        ],
      ),
      subtitle: Text(
        [
          if (patient.dateOfBirth.isNotEmpty) 'DOB ${patient.dateOfBirth}',
          if (patient.phone.isNotEmpty) patient.phone,
          if (patient.healthInsurance.isNotEmpty) patient.healthInsurance,
        ].join(' · '),
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'View details / notes',
            onPressed: onOpen,
            icon: const Icon(Icons.notes_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: Icon(
              Icons.edit_outlined,
              size: 20,
              color: onEdit == null ? AppColors.border : AppColors.navy,
            ),
          ),
          IconButton(
            tooltip: 'Share access',
            onPressed: onShare,
            icon: Icon(
              Icons.share_outlined,
              size: 20,
              color: onShare == null ? AppColors.border : AppColors.navy,
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: onDelete == null ? AppColors.border : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOwner
            ? AppColors.successSoft
            : AppColors.reviewSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isOwner ? 'Owner' : 'Shared',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isOwner ? AppColors.success : AppColors.review,
        ),
      ),
    );
  }
}

class _PatientFormFields {
  const _PatientFormFields({
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.address,
    required this.phone,
    required this.healthInsurance,
  });

  final String firstName;
  final String lastName;
  final String dateOfBirth;
  final String address;
  final String phone;
  final String healthInsurance;
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
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _dob;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _insurance;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _first = TextEditingController(text: p?.firstName ?? '');
    _last = TextEditingController(text: p?.lastName ?? '');
    _dob = TextEditingController(text: p?.dateOfBirth ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _insurance = TextEditingController(text: p?.healthInsurance ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _dob.dispose();
    _address.dispose();
    _phone.dispose();
    _insurance.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_dob.text) ??
        DateTime(now.year - 30, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null) return;
    _dob.text = DateFormat('yyyy-MM-dd').format(picked);
  }

  Future<void> _submit() async {
    final fields = _PatientFormFields(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      dateOfBirth: _dob.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      healthInsurance: _insurance.text.trim(),
    );
    if (fields.firstName.isEmpty ||
        fields.lastName.isEmpty ||
        fields.dateOfBirth.isEmpty ||
        fields.address.isEmpty ||
        fields.phone.isEmpty ||
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
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _first,
                decoration: const InputDecoration(labelText: 'First name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _last,
                decoration: const InputDecoration(labelText: 'Last name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dob,
                readOnly: true,
                onTap: _pickDob,
                decoration: const InputDecoration(
                  labelText: 'Date of birth',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _insurance,
                decoration:
                    const InputDecoration(labelText: 'Health insurance'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _address,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.submitLabel),
        ),
      ],
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
    return AlertDialog(
      title: const Text('Delete patient?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose how to remove ${widget.patientName}.'),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            ListTile(
              selected: !_hard,
              onTap: () => setState(() => _hard = false),
              leading: Icon(
                !_hard
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: AppColors.dentalBlue,
              ),
              title: const Text('Soft Delete (Archive patient record)'),
              subtitle: const Text('Default — keeps data for recovery'),
            ),
            ListTile(
              selected: _hard,
              onTap: () => setState(() => _hard = true),
              leading: Icon(
                _hard
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: AppColors.danger,
              ),
              title: const Text(
                'Hard Delete (Permanent GDPR Art. 17 Erasure)',
              ),
            ),
            if (_hard) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _confirm,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: (!_hard || canHard)
              ? () => Navigator.pop(context, _hard)
              : null,
          child: Text(_hard ? 'Delete forever' : 'Archive'),
        ),
      ],
    );
  }
}

class _ShareAccessSheet extends StatefulWidget {
  const _ShareAccessSheet({
    required this.patient,
    required this.controller,
    required this.onToast,
  });

  final GdprPatient patient;
  final PatientsController controller;
  final void Function(String message, {bool error}) onToast;

  @override
  State<_ShareAccessSheet> createState() => _ShareAccessSheetState();
}

class _ShareAccessSheetState extends State<_ShareAccessSheet> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await widget.controller.api.listChatContacts();
      if (!mounted) return;
      setState(() {
        _users = users
            .where((u) => '${u['id']}' != widget.controller.currentUserId)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onToast(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _grant(String userId) async {
    setState(() => _busyId = userId);
    try {
      await widget.controller.grantAccess(
        patientId: widget.patient.id,
        targetUserId: userId,
      );
      widget.onToast('Access granted to staff member');
    } catch (e) {
      widget.onToast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _revoke(String userId) async {
    setState(() => _busyId = userId);
    try {
      await widget.controller.revokeAccess(
        patientId: widget.patient.id,
        targetUserId: userId,
      );
      widget.onToast('Access revoked');
    } catch (e) {
      widget.onToast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SizedBox(
      height: height,
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
            Text(
              'Share ${widget.patient.fullName}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Grant or revoke access for practice staff.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? const Center(
                          child: Text(
                            'No staff contacts found.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _users.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final u = _users[i];
                            final id = '${u['id']}';
                            final name = (u['name'] as String?)?.trim();
                            final email = (u['email'] as String?)?.trim() ?? '';
                            final label = (name != null && name.isNotEmpty)
                                ? name
                                : email;
                            final busy = _busyId == id;
                            return ListTile(
                              title: Text(label),
                              subtitle: name != null && name.isNotEmpty
                                  ? Text(email)
                                  : null,
                              trailing: busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Wrap(
                                      spacing: 6,
                                      children: [
                                        TextButton(
                                          onPressed: () => _grant(id),
                                          child: const Text('Grant'),
                                        ),
                                        TextButton(
                                          onPressed: () => _revoke(id),
                                          child: const Text(
                                            'Revoke',
                                            style: TextStyle(
                                              color: AppColors.danger,
                                            ),
                                          ),
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
  });

  final PatientsController controller;
  final GdprPatient patient;
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
    _tabs = TabController(length: 2, vsync: this);
    widget.controller.loadNotes(widget.patient.id);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = _note.text.trim();
    if (text.isEmpty) return;
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
    final controller = TextEditingController(text: note.noteContent);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit note'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Clinical note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty) return;
    try {
      await widget.controller.editNote(noteId: note.id, content: next);
      widget.onToast('Note updated');
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _deleteNote(PatientNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This clinical note will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
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
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return SizedBox(
      height: height,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final notes = widget.controller.notes;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.fullName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    _AccessBadge(isOwner: owner),
                  ],
                ),
                if (!owner)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Shared with you',
                      style: TextStyle(
                        color: AppColors.review,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (owner)
                      OutlinedButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      ),
                    if (owner)
                      OutlinedButton.icon(
                        onPressed: widget.onShare,
                        icon: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('Manage Access'),
                      ),
                    if (owner)
                      OutlinedButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline,
                            size: 16, color: AppColors.danger),
                        label: const Text(
                          'Delete',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabs,
                  labelColor: AppColors.navy,
                  tabs: const [
                    Tab(text: 'Demographics'),
                    Tab(text: 'Clinical Notes'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      ListView(
                        padding: const EdgeInsets.only(top: 12),
                        children: [
                          _info('Date of birth', p.dateOfBirth),
                          _info('Phone', p.phone),
                          _info('Health insurance', p.healthInsurance),
                          _info('Address', p.address),
                        ],
                      ),
                      Column(
                        children: [
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _note,
                                  minLines: 1,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    hintText: 'Add a clinical note…',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _adding ? null : _addNote,
                                child: _adding
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Add Note'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: widget.controller.loadingNotes &&
                                    notes.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : notes.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No clinical notes yet.',
                                          style:
                                              TextStyle(color: AppColors.muted),
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: notes.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (context, i) {
                                          final n = notes[i];
                                          final when = n.createdAt == null
                                              ? ''
                                              : DateFormat.yMMMd()
                                                  .add_Hm()
                                                  .format(
                                                      n.createdAt!.toLocal());
                                          return SectionCard(
                                            padding: const EdgeInsets.all(12),
                                            depth: 0.4,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  n.noteContent,
                                                  style: const TextStyle(
                                                    color: AppColors.navy,
                                                    height: 1.35,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Text(
                                                      when,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.muted,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    IconButton(
                                                      tooltip: 'Edit note',
                                                      onPressed: () =>
                                                          _editNote(n),
                                                      icon: const Icon(
                                                        Icons.edit_outlined,
                                                        size: 18,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Delete note',
                                                      onPressed: () =>
                                                          _deleteNote(n),
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                        size: 18,
                                                        color: AppColors.danger,
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
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

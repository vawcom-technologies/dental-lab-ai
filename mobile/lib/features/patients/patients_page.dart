import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../cases/case_panel.dart';
import '../cases/case_store.dart';
import '../lab/lab_pickers.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/date_formats.dart';
import '../../core/layout/adaptive.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_kit.dart';
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
    this.active = true,
  });

  final ApiClient api;
  final String dentistName;
  final PatientSession? patientSession;
  final VoidCallback? onNewPatient;
  final VoidCallback? onInboxChanged;
  final bool active;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  late final PatientsController _controller;
  final _search = TextEditingController();
  bool _openingMention = false;

  @override
  void initState() {
    super.initState();
    _controller = PatientsController(api: widget.api);
    _controller.onAccessMutated = widget.onInboxChanged;
    _controller.onError = (msg) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toast(msg, error: true);
      });
    };
    _controller.addListener(_onControllerChanged);
    widget.patientSession?.addListener(_onSessionChanged);
    _controller.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.active) _consumePendingPatientDetail();
    });
  }

  @override
  void didUpdateWidget(covariant PatientsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.onAccessMutated = widget.onInboxChanged;
    if (oldWidget.patientSession != widget.patientSession) {
      oldWidget.patientSession?.removeListener(_onSessionChanged);
      widget.patientSession?.addListener(_onSessionChanged);
    }
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _consumePendingPatientDetail();
      });
    }
  }

  @override
  void dispose() {
    widget.patientSession?.removeListener(_onSessionChanged);
    _controller.removeListener(_onControllerChanged);
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.active) _consumePendingPatientDetail();
  }

  void _onSessionChanged() {
    if (widget.active) _consumePendingPatientDetail();
  }

  Future<void> _consumePendingPatientDetail() async {
    final session = widget.patientSession;
    if (session == null || !mounted || _openingMention) return;
    final id = session.pendingPatientDetailId?.trim();
    if (id == null || id.isEmpty) return;
    session.takePendingPatientDetailId();
    _openingMention = true;
    try {
      await _presentPatientDetail(id);
    } catch (e) {
      if (mounted) _toast(_friendlyError(e), error: true);
    } finally {
      _openingMention = false;
      session.clearOpeningPatientDetail();
    }
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
          return AppLocalizations.of(context).patientsOnlyOwnerApprove;
        }
        if (lower.contains('creator') || lower.contains('created this')) {
          return AppLocalizations.of(context).tr('p.onlyCreatorEdit');
        }
      }
      return friendlyError(e.message);
    }
    return friendlyError(e);
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
          title: AppLocalizations.of(context).newPatientTitle,
          submitLabel: AppLocalizations.of(context).createPatient,
          saving: false,
          api: widget.api,
          onSubmit: (fields) => _controller.createPatient(
            target: fields.target,
            firstName: fields.firstName,
            lastName: fields.lastName,
            dateOfBirth: fields.dateOfBirth,
            email: fields.email,
            address: fields.address,
            phone: fields.phone,
            healthInsurance: fields.healthInsurance,
          ),
        ),
      ),
    );
    if (created == null || !mounted) return;
    await _syncSharedPatientSession();
    if (!mounted) return;
    _toast(AppLocalizations.of(context).patientsCreatedToast);
  }

  Future<void> _openEdit(GdprPatient patient) async {
    if (_controller.mutating) return;
    if (!_controller.isOwner(patient)) {
      _toast(
        AppLocalizations.of(context).tr('p.permDenied'),
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
            title: AppLocalizations.of(context).patientsEditTitle,
            submitLabel: AppLocalizations.of(context).patientsSaveChanges,
            initial: patient,
            onSubmit: (fields) => _controller.updatePatient(patient.id, {
              'first_name': fields.firstName,
              'last_name': fields.lastName,
              'date_of_birth': fields.dateOfBirth,
              'email': fields.email,
              'address': fields.address,
              'phone': fields.phone,
              'health_insurance': fields.healthInsurance,
            }),
          ),
        ),
      );
      if (updated == null || !mounted) return;
      await _syncSharedPatientSession();
      if (!mounted) return;
      _toast(AppLocalizations.of(context).patientsUpdatedToast);
    } catch (e) {
      _toast(_friendlyError(e), error: true);
    }
  }

  Future<void> _confirmDelete(GdprPatient patient) async {
    if (_controller.mutating) return;
    if (!_controller.isOwner(patient)) {
      _toast(
        AppLocalizations.of(context).tr('p.permDenied'),
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
      if (_inline?.id == patient.id && mounted) setState(() => _inline = null);
      await _syncSharedPatientSession();
      if (!mounted) return;
      _toast(hard ? AppLocalizations.of(context).tr('p.deleted') : AppLocalizations.of(context).tr('p.archived'));
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

  /// Wide screen: list on the left, the open patient on the right.
  bool _split = false;
  GdprPatient? _inline;
  int _inlineTab = 0;

  _PatientDetailSheet _detailFor(GdprPatient p, {required int tab, required bool embedded, VoidCallback? close}) {
    void then(VoidCallback next) {
      close?.call();
      next();
    }

    return _PatientDetailSheet(
      key: embedded ? ValueKey('inline-${p.id}-$tab') : null,
      controller: _controller,
      cases: widget.patientSession?.cases,
      patientSession: widget.patientSession,
      patient: p,
      initialTab: tab,
      embedded: embedded,
      onEdit: () => then(() => _openEdit(p)),
      onShare: () => then(() => _openShare(p)),
      onDelete: () => then(() => _confirmDelete(p)),
      onToast: _toast,
      friendlyError: _friendlyError,
    );
  }

  Future<void> _presentPatientDetail(String patientId, {int tab = 0}) async {
    final detailed = await _controller.openPatient(patientId);
    if (detailed == null || !mounted) return;
    // Drop the shell overlay before the sheet so the profile is tappable.
    widget.patientSession?.clearOpeningPatientDetail();
    if (_split) {
      setState(() {
        _inline = detailed;
        _inlineTab = tab;
      });
      return;
    }
    await AppDialogs.modalSheet<void>(
      context: context,
      builder: (ctx) => _detailFor(detailed, tab: tab, embedded: false, close: () => Navigator.pop(ctx)),
    );
    _controller.clearSelected();
  }

  Future<void> _openDetails(GdprPatient patient, {int tab = 0}) async {
    if (_controller.loadingDetail || _controller.mutating) return;
    try {
      await _presentPatientDetail(patient.id, tab: tab);
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
          message: opening ? loc.patientsOpening : null,
          child: Padding(
            padding: AppBreakpoints.pagePadding(context),
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
                        loc.patientsShownTotal(
                          _controller.shownCount,
                          _controller.totalCount,
                        ),
                        style: AppFonts.style(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ],
                  actions: [
                    AppButtons.primary(
                      onPressed: blocked ? null : _openCreate,
                      icon: Icons.add_rounded,
                      label: loc.newPatientTitle,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stackedSearch = AppBreakpoints.isPhone(context) ||
                        constraints.maxWidth < 560;
                    final search = AdminCard(
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
                            hintText: loc.searchPatients,
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
                      );
                    final filter = AdminCard(
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
                              for (final key in CaseStatuses.filterKeys)
                                DropdownMenuItem<String>(
                                  value: key,
                                  child: Text(
                                    AppLocalizations.of(context)
                                        .statusLabel(key),
                                  ),
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
                      );
                    if (stackedSearch) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          search,
                          const SizedBox(height: 10),
                          filter,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: 12),
                        SizedBox(width: 200, child: filter),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                  _split = box.maxWidth >= 860;
                  final list = AppSwitcher(
                    child: KeyedSubtree(
                      key: ValueKey(
                        '${_controller.statusFilter}|${_controller.query}|${rows.length}|${_controller.loading}',
                      ),
                      child: _controller.loading && rows.isEmpty
                          ? ToothPageLoader(message: loc.patientsLoading)
                          : rows.isEmpty
                              ? IpadRefresh.fill(
                                  onRefresh: () => _controller.load(
                                    forceRefresh: true,
                                    silent: true,
                                  ),
                                  child: _EmptyPatients(
                                    filtered:
                                        _controller.statusFilter != 'all' ||
                                            _controller.query.trim().isNotEmpty,
                                  ),
                                )
                              : IpadRefresh(
                                  onRefresh: () => _controller.load(
                                    forceRefresh: true,
                                    silent: true,
                                  ),
                                  slivers: [
                                    SliverList.separated(
                                      itemCount: rows.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (context, i) {
                                        final p = rows[i];
                                        final owner = _controller.isOwner(p);
                                        return _PatientCard(
                                          patient: p,
                                          compact: _split,
                                          selected: _split && _inline?.id == p.id,
                                          isOwner: owner,
                                          roleLabel: AppRoles.label(
                                            widget.api.role,
                                            loc,
                                          ),
                                          enabled: !blocked,
                                          onOpen: () => _openDetails(p),
                                          onOpenAccess: () =>
                                              _openDetails(p, tab: 2),
                                          onEdit:
                                              owner ? () => _openEdit(p) : null,
                                          onShare: () => _openShare(p),
                                          onDelete: owner
                                              ? () => _confirmDelete(p)
                                              : null,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                    ),
                  );
                  if (!_split) return list;
                  final open = _inline;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: list),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: AppSwitcher(
                          child: open == null
                              ? AdminCard(
                                  key: const ValueKey('pick'),
                                  child: AdminEmpty(
                                    icon: Icons.touch_app_outlined,
                                    title: loc.tr('p.pickTitle'),
                                    subtitle: loc.tr('p.pickSub'),
                                  ),
                                )
                              : _detailFor(open, tab: _inlineTab, embedded: true),
                        ),
                      ),
                    ],
                  );
                }),
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
    final loc = AppLocalizations.of(context);
    return Center(
      child: AdminCard(
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
              filtered ? loc.patientsNoMatching : loc.noPatientsYet,
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
                  ? AppLocalizations.of(context).tr('p.tryOtherStatus')
                  : AppLocalizations.of(context).tr('p.addFirst'),
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
    this.compact = false,
    this.selected = false,
    required this.isOwner,
    required this.onOpen,
    this.onOpenAccess,
    this.roleLabel,
    this.enabled = true,
    this.onEdit,
    this.onShare,
    this.onDelete,
  });

  final GdprPatient patient;

  /// Split view: name, access and status only; actions live in the detail.
  final bool compact;
  final bool selected;
  final bool isOwner;
  final String? roleLabel;
  final bool enabled;
  final VoidCallback onOpen;
  /// Opens the Access tab (who the patient is shared with).
  final VoidCallback? onOpenAccess;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return AdminCard(
      padding: EdgeInsets.zero,
      selected: selected,
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
                if (compact) {
                  return Row(
                    children: [
                      _PatientAvatar(name: patient.fullName, isOwner: isOwner, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patient.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy),
                            ),
                            const SizedBox(height: 4),
                            _AccessBadge(isOwner: isOwner, roleLabel: roleLabel),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(statusKey: patient.status),
                    ],
                  );
                }
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PatientAvatar(
                      name: patient.fullName,
                      isOwner: isOwner,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
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
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: enabled && onOpenAccess != null ? onOpenAccess : null,
                            behavior: HitTestBehavior.opaque,
                            child: _AccessBadge(
                              isOwner: isOwner,
                              roleLabel: roleLabel,
                            ),
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
                    // Read-only: the server moves the status (case flow).
                    StatusChip(statusKey: patient.status),
                    AppButtons.ghost(
                      onPressed: enabled ? onEdit : null,
                      icon: Icons.edit_outlined,
                      label: loc.commonEdit,
                      compact: true,
                    ),
                    // Only the owner shares (labs decide colleague tickets).
                    if (isOwner)
                    AppButtons.ghost(
                      onPressed: enabled ? onShare : null,
                      icon: Icons.share_outlined,
                      label: loc.commonShare,
                      compact: true,
                    ),
                    AppButtons.danger(
                      onPressed: enabled ? onDelete : null,
                      icon: Icons.delete_outline_rounded,
                      label: loc.commonDelete,
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
  const _PatientAvatar({required this.name, required this.isOwner, this.size = 56});

  final String name;
  final bool isOwner;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = isOwner
        ? AppColors.dentalBlue.withValues(alpha: 0.14)
        : AppColors.reviewSoft;
    final fg = isOwner ? AppColors.dentalBlue : AppColors.review;
    final initials = _initials(name);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: NeoShadows.soft(depth: 0.4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      ),
      child: Text(
        initials,
        style: AppFonts.style(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
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
    final loc = AppLocalizations.of(context);
    final role = (roleLabel ?? '').trim();
    final prefix = isOwner ? loc.patientsCreatedBy : loc.patientsAccessLabel;
    final pill = isOwner
        ? (role.isNotEmpty ? role : loc.patientsCreator)
        : loc.patientsShared;

    // Wraps rather than overflowing narrow cards.
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          prefix,
          style: AppFonts.style(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
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
    this.target,
  });

  /// Lab creating a patient: dentist or other lab (see [LabPatientTarget]).
  final Map<String, String>? target;

  final String firstName;
  final String lastName;
  final String dateOfBirth;
  final String email;
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
    this.api,
  });

  final String title;
  final String submitLabel;

  /// Set when creating: labs then choose who the patient is for.
  final ApiClient? api;
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
  final _labTarget = ValueNotifier<Map<String, String>?>(null);

  bool get _labCreate => widget.initial == null && (widget.api?.isLaboratory ?? false);
  bool _saving = false;

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
    _labTarget.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_labCreate && _labTarget.value == null) {
      AppSnackBars.error(context, AppLocalizations.of(context).tr('lab.targetRequired'));
      return;
    }

    final phoneLocal = _phone.text.trim();
    final phoneError = PhoneNumbers.validateRequired(phoneLocal);
    if (phoneError != null) {
      AppSnackBars.error(context, phoneError);
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
      target: _labCreate ? _labTarget.value : null,
    );
    if (fields.firstName.isEmpty ||
        fields.lastName.isEmpty ||
        fields.dateOfBirth.isEmpty ||
        fields.address.isEmpty ||
        fields.healthInsurance.isEmpty) {
      AppSnackBars.error(
          context, AppLocalizations.of(context).errAllFieldsRequired);
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final patient = await widget.onSubmit(fields);
      if (!mounted) return;
      Navigator.pop(context, patient);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is AgentApiException && e.isForbidden
          ? AppLocalizations.of(context).tr('p.onlyCreatorEdit')
          : friendlyError(e);
      AppSnackBars.error(context, msg);
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
        child: AdminCard(
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
                  if (_labCreate) ...[
                    LabPatientTarget(api: widget.api!, value: _labTarget, enabled: !_saving),
                    const SizedBox(height: 16),
                  ],
                  _DialogField(
                    controller: _first,
                    label: AppLocalizations.of(context).firstName,
                    requiredField: true,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? AppLocalizations.of(context).commonRequired
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _DialogField(
                    controller: _last,
                    label: AppLocalizations.of(context).lastName,
                    requiredField: true,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? AppLocalizations.of(context).commonRequired
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DobPickerField(
                    controller: _dob,
                    labelText: AppLocalizations.of(context).dateOfBirth,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _DialogField(
                    controller: _email,
                    label: AppLocalizations.of(context).email,
                    requiredField: true,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => validatePatientEmail(v, AppLocalizations.of(context)),
                  ),
                  const SizedBox(height: 12),
                  PhoneField(
                    controller: _phone,
                    labelText: AppLocalizations.of(context).phone,
                  ),
                  const SizedBox(height: 12),
                  _DialogField(
                    controller: _insurance,
                    label: AppLocalizations.of(context).healthInsurance,
                    requiredField: true,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? AppLocalizations.of(context).commonRequired
                        : null,
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 12),
                  _DialogField(
                    controller: _address,
                    label: AppLocalizations.of(context).address,
                    requiredField: true,
                    minLines: 2,
                    maxLines: 3,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? AppLocalizations.of(context).commonRequired
                        : null,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButtons.ghost(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        label: AppLocalizations.of(context).cancel,
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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: requiredField ? '$label *' : label,
      ),
      validator: validator,
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
    final loc = AppLocalizations.of(context);
    final canHard = _confirm.text.trim().toUpperCase() == 'DELETE';
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AdminCard(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.patientsDeleteTitle,
                style: AppFonts.style(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                loc.patientsDeleteBody(widget.patientName),
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
                    title: loc.patientsArchiveOption,
                    subtitle: loc.patientsArchiveOptionSub,
                    accent: AppColors.dentalBlue,
                    onTap: () => setState(() => _hard = false),
                  ),
                  const _InsetDivider(),
                  _DeleteOptionRow(
                    selected: _hard,
                    title: loc.patientsHardDeleteOption,
                    subtitle: loc.patientsHardDeleteOptionSub,
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
                      labelText: loc.patientsTypeDeleteConfirm,
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
                    label: loc.cancel,
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  AppButtons.danger(
                    onPressed: (!_hard || canHard)
                        ? () => Navigator.pop(context, _hard)
                        : null,
                    label: _hard
                        ? loc.patientsHardDeleteOption
                        : loc.commonArchive,
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

/// Owner-only share sheet: your lab (immediate), colleagues in your lab
/// (the lab approves), another lab (transfer), and who already has access.
class _ShareAccessSheetState extends State<_ShareAccessSheet> {
  List<EligibleAccessUser> _users = [];
  bool _loading = true;
  String? _busyId;

  PatientsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final r = await Future.wait([
        _c.listEligibleUsers(widget.patient.id),
        _c.loadAccess(widget.patient.id, silent: true),
      ]);
      if (!mounted) return;
      setState(() {
        _users = r[0] as List<EligibleAccessUser>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _share(EligibleAccessUser u) async {
    if (_busyId != null) return;
    final loc = AppLocalizations.of(context);
    setState(() => _busyId = u.userId);
    try {
      final result = await _c.shareAccess(patientId: widget.patient.id, targetUserId: u.userId);
      // Your lab: immediate. A colleague: the lab approves it.
      widget.onToast(result.immediate ? loc.patientsAccessGranted : loc.tr('share.sentToLab'));
      await _reload();
    } on AgentApiException catch (e) {
      // Someone in another lab: that goes through a lab transfer instead.
      widget.onToast(e.code == 'USE_TRANSFER' ? loc.tr('share.useTransfer') : widget.friendlyError(e), error: true);
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _shareWithLab() async {
    final loc = AppLocalizations.of(context);
    final api = _c.api;
    final lab = await pickOtherLab(context, api, title: loc.tr('share.otherLab'), message: loc.tr('share.otherLabMsg'));
    if (lab == null || !mounted) return;
    // 400 not linked to a lab, 409 one already open: the server says which.
    await adminRun(
      context,
      () => api.requestTransfer(widget.patient.id, toLabId: lab.id),
      done: loc.trp('share.transferSent', {'lab': lab.name}),
    );
  }

  Widget _section(String title, String hint) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            const SizedBox(height: 2),
            Text(hint, style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
          ],
        ),
      );

  Widget _row(EligibleAccessUser u, {required bool lab}) {
    final loc = AppLocalizations.of(context);
    final busy = _busyId == u.userId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AdminCard(
        padding: const EdgeInsets.all(12),
        child: AdminRow(
          leading: UserAvatar(name: u.fullName, url: u.avatarUrl, size: 38),
          title: u.fullName,
          badges: [if (lab) AdminBadge(loc.roleLaboratory, color: AppColors.review)],
          lines: [
            if (!lab) dentistPlace(loc, _c.api.labName, u.clinicName),
            if (lab && u.email != null) u.email!,
          ],
          actions: [
            lab
                ? AppButtons.primary(
                    onPressed: _busyId == null ? () => _share(u) : null,
                    icon: Icons.share_outlined,
                    label: busy ? loc.saving : loc.commonShare,
                    compact: true,
                  )
                : AppButtons.secondary(
                    onPressed: _busyId == null ? () => _share(u) : null,
                    icon: Icons.send_outlined,
                    label: busy ? loc.saving : loc.commonRequest,
                    compact: true,
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final labUsers = _users.where((u) => AppRoles.isLaboratory(u.role)).toList();
    final colleagues = _users.where((u) => !AppRoles.isLaboratory(u.role)).toList();
    final shared = _c.accessEntries;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: SizedBox(
        height: height,
        child: AdminCard(
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
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                child: Row(
                  children: [
                    UserAvatar(name: widget.patient.fullName, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        loc.patientsShareTitle(widget.patient.fullName),
                        style: AppFonts.style(fontWeight: FontWeight.w700, fontSize: 19, color: AppColors.navy, letterSpacing: -0.3),
                      ),
                    ),
                    AppButtons.icon(onPressed: () => Navigator.pop(context), icon: Icons.close_rounded, tooltip: loc.commonClose),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? ToothPageLoader(inPlace: true, message: loc.patientsLoadingStaff)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          _section(loc.tr('share.yourLab'), loc.tr('share.yourLabHint')),
                          if (labUsers.isEmpty)
                            _none(loc.tr('share.labHasAccess'))
                          else
                            for (final u in labUsers) _row(u, lab: true),
                          _section(loc.tr('share.colleagues'), loc.tr('share.colleaguesHint')),
                          if (colleagues.isEmpty)
                            _none(loc.tr('share.noColleagues'))
                          else
                            for (final u in colleagues) _row(u, lab: false),
                          _section(loc.tr('share.otherLab'), loc.tr('share.otherLabMsg')),
                          AdminCard(
                            onTap: _busyId == null ? _shareWithLab : null,
                            padding: const EdgeInsets.all(12),
                            child: AdminRow(
                              leading: const AdminIcon(icon: Icons.apartment_rounded, color: AppColors.review, size: 38),
                              title: loc.tr('lab.chooseLab'),
                              actions: const [Icon(Icons.chevron_right_rounded, color: AppColors.muted)],
                            ),
                          ),
                          if (shared.isNotEmpty) ...[
                            _section(loc.tr('share.alreadyShared'), loc.tr('share.alreadySharedHint')),
                            for (final e in shared)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: AdminCard(
                                  padding: const EdgeInsets.all(12),
                                  child: AdminRow(
                                    leading: UserAvatar(name: e.userName, size: 38),
                                    title: e.userName,
                                    badges: [
                                      AdminBadge(
                                        e.status == PatientAccessStatus.pending
                                            ? loc.tr('share.pendingLab')
                                            : e.status.labelOf(loc),
                                        color: switch (e.status) {
                                          PatientAccessStatus.pending => AppColors.warning,
                                          PatientAccessStatus.approved => AppColors.success,
                                          PatientAccessStatus.rejected => AppColors.danger,
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _none(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
        child: Text(text, style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
      );
}


class _AccessStatusBadge extends StatelessWidget {
  const _AccessStatusBadge.status(this.status) : label = null, owner = false;

  const _AccessStatusBadge.owner()
      : status = null,
        label = null,
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
      text = label ?? AppLocalizations.of(context).patientsOwner;
    } else {
      switch (status!) {
        case PatientAccessStatus.approved:
          bg = AppColors.successSoft;
          fg = AppColors.success;
          text = status!.labelOf(AppLocalizations.of(context));
        case PatientAccessStatus.pending:
          bg = AppColors.warningSoft;
          fg = AppColors.warning;
          text = status!.labelOf(AppLocalizations.of(context));
        case PatientAccessStatus.rejected:
          bg = const Color(0xFFE8EDF4);
          fg = AppColors.muted;
          text = status!.labelOf(AppLocalizations.of(context));
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
    super.key,
    required this.controller,
    this.cases,
    required this.patient,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onToast,
    required this.friendlyError,
    this.initialTab = 0,
    this.embedded = false,
    this.patientSession,
  });

  final PatientsController controller;

  /// Inline in the Patients split view instead of a bottom sheet.
  final bool embedded;

  /// Lets case items and records open Scans / Shade / Smile.
  final PatientSession? patientSession;

  /// Case flow for this patient (status, items, submit / review, history).
  final CaseStore? cases;
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
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: widget.cases == null ? 3 : 4,
      vsync: this,
      // Callers count tabs without Case. Case comes first and is the default.
      initialIndex: (widget.initialTab + (widget.cases != null && widget.initialTab > 0 ? 1 : 0))
          .clamp(0, widget.cases == null ? 2 : 3),
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

  /// Lab: move the patient to (or pick) one of the lab's dentists.
  Future<void> _assignDentist(GdprPatient p) async {
    final loc = AppLocalizations.of(context);
    final api = widget.controller.api;
    final d = await pickLabDentist(context, api,
        title: loc.tr('lab.assignDentist'), message: loc.trp('lab.assignMsg', {'p': p.fullName}));
    if (d == null || !mounted) return;
    try {
      await AppDialogs.runWithLoading(context, action: () => api.assignPatient(p.id, dentistId: d.id));
      widget.onToast(loc.trp('lab.assigned', {'p': p.fullName, 'd': d.name}));
      widget.cases?.refresh(p.id);
      await widget.controller.load(silent: true);
    } catch (e) {
      final msg = friendlyError(e);
      // 403: the lab wasn't given this patient.
      widget.onToast(msg == loc.errNoPermission ? loc.tr('lab.assignForbidden') : msg, error: true);
    }
  }

  Future<void> _addNote() async {
    final loc = AppLocalizations.of(context);
    final text = _note.text.trim();
    if (text.isEmpty || _adding || widget.controller.mutating) return;
    setState(() => _adding = true);
    try {
      await widget.controller.addNote(
        patientId: widget.patient.id,
        content: text,
      );
      _note.clear();
      widget.onToast(loc.patientsNoteAdded);
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editNote(PatientNote note) async {
    final loc = AppLocalizations.of(context);
    if (widget.controller.mutating) return;
    final me = widget.controller.currentUserId;
    if (me == null || note.authorId != me) {
      widget.onToast(
        loc.patientsOnlyAuthorEdit,
        error: true,
      );
      return;
    }
    final lab = widget.controller.api.isLaboratory;
    final next = await AppDialogs.prompt(
      context,
      title: loc.patientsEditNote,
      initial: note.noteContent,
      placeholder: loc.notePlaceholderForRole(laboratory: lab),
      confirmLabel: loc.save,
      maxLines: 4,
    );
    if (next == null || next.trim().isEmpty) return;
    final trimmed = next.trim();
    try {
      await widget.controller.editNote(noteId: note.id, content: trimmed);
      widget.onToast(loc.patientsNoteUpdated);
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    final loc = AppLocalizations.of(context);
    setState(() => _exporting = true);
    try {
      // Can take a while for patients with many scans — say so instead of a silent button.
      final file = await runWithToothLoadingDialog(
        context,
        message: loc.tr('p.exporting'),
        action: () => widget.controller.exportPatient(widget.patient.id),
      );
      if (!mounted) return;
      final saved = await FilePicker.saveFile(
        fileName: file.filename,
        bytes: file.bytes,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (saved != null || kIsWeb) widget.onToast(loc.tr('p.exported'));
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _revokeAccess(PatientAccessEntry entry) async {
    if (widget.controller.mutating) return;
    try {
      await widget.controller.revokeAccess(
        patientId: widget.patient.id,
        targetUserId: entry.userId,
      );
      widget.onToast(AppLocalizations.of(context).tr('p.accessRevoked'));
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _regrantAccess(PatientAccessEntry entry) async {
    if (widget.controller.mutating) return;
    final loc = AppLocalizations.of(context);
    try {
      final result = await widget.controller.shareAccess(
        patientId: widget.patient.id,
        targetUserId: entry.userId,
      );
      widget.onToast(
        result.immediate
            ? loc.patientsAccessGranted
            : loc.patientsAccessRequestSubmitted,
      );
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  Future<void> _deleteNote(PatientNote note) async {
    final loc = AppLocalizations.of(context);
    if (widget.controller.mutating) return;
    final me = widget.controller.currentUserId;
    if (me == null || note.authorId != me) {
      widget.onToast(
        AppLocalizations.of(context).tr('p.onlyAuthorDelete'),
        error: true,
      );
      return;
    }
    final lab = widget.controller.api.isLaboratory;
    final ok = await AppDialogs.confirm(
      context,
      title: loc.patientsDeleteNoteTitle,
      message: loc.deleteNoteBodyForRole(laboratory: lab),
      confirmLabel: loc.commonDelete,
      isDestructive: true,
    );
    if (!ok) return;
    try {
      await widget.controller.deleteNote(note.id);
      widget.onToast(AppLocalizations.of(context).tr('p.noteDeleted'));
    } catch (e) {
      widget.onToast(widget.friendlyError(e), error: true);
    }
  }

  GdprPatient _livePatient() {
    final id = widget.patient.id;
    for (final row in widget.controller.patients) {
      if (row.id == id) return row;
    }
    final selected = widget.controller.selected;
    if (selected?.id == id) return selected!;
    return widget.patient;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final embedded = widget.embedded;
    final api = widget.controller.api;

    final card = AdminCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final notes = widget.controller.notes;
            final access = widget.controller.accessEntries;
            final accessOwner = widget.controller.accessOwner;
            final accessViewerIsOwner = widget.controller.accessViewerIsOwner;
            final blocked = widget.controller.mutating;
            final p = _livePatient();
            final owner = widget.controller.isOwner(p);
            final lab = api.isLaboratory;
            final tabs = [
              if (widget.cases != null) (loc.tr('case.title'), () => _buildCaseTab(p)),
              (loc.tr('p.tabInfo'), () => _buildDetailsTab(p)),
              (
                loc.notesLabelForRole(laboratory: lab),
                () => _buildNotesTab(notes: notes, blocked: blocked),
              ),
              (
                loc.tr('p.tabAccess'),
                () => _buildAccessTab(
                      access: access,
                      accessOwner: accessOwner,
                      accessViewerIsOwner: accessViewerIsOwner,
                      blocked: blocked,
                    ),
              ),
            ];
            // Icon actions keep the header to one calm row; labels live in tooltips.
            final actions = [
              if (api.isLaboratory)
                AppButtons.secondary(
                  onPressed: blocked ? null : () => _assignDentist(p),
                  icon: Icons.person_pin_outlined,
                  label: loc.tr('lab.assignDentist'),
                  compact: true,
                ),
              if (owner) ...[
                AppButtons.icon(onPressed: blocked ? null : widget.onEdit, icon: Icons.edit_outlined, tooltip: loc.commonEdit),
                AppButtons.icon(
                  onPressed: blocked || _exporting ? null : _export,
                  icon: Icons.download_outlined,
                  tooltip: loc.tr('p.export'),
                ),
                AppButtons.icon(onPressed: blocked ? null : widget.onShare, icon: Icons.share_outlined, tooltip: loc.commonShare),
                AppButtons.icon(
                  onPressed: blocked ? null : widget.onDelete,
                  icon: Icons.delete_outline_rounded,
                  tooltip: loc.commonDelete,
                ),
              ],
              if (!embedded)
                AppButtons.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icons.close_rounded,
                  tooltip: loc.commonClose,
                ),
            ];
            return BusyBarrier(
              busy: blocked,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!embedded) ...[
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
                  ],
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, embedded ? 18 : 12, 12, 0),
                    child: Row(
                      children: [
                        _PatientAvatar(name: p.fullName, isOwner: owner),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.style(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusChip(statusKey: p.status),
                                  _AccessBadge(
                                    isOwner: owner,
                                    roleLabel: AppRoles.label(api.role, loc),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 12, 0),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actions,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: AnimatedBuilder(
                      animation: _tabs,
                      builder: (context, _) => SizedBox(
                        width: double.infinity,
                        child: CupertinoSlidingSegmentedControl<int>(
                          groupValue: _tabs.index,
                          backgroundColor: AppColors.inset.withValues(alpha: 0.7),
                          thumbColor: Colors.white.withValues(alpha: 0.95),
                          children: {
                            for (final (i, t) in tabs.indexed)
                              i: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: Text(
                                  t.$1,
                                  style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
                                ),
                              ),
                          },
                          onValueChanged: (value) {
                            if (value != null) _tabs.animateTo(value);
                          },
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [for (final t in tabs) t.$2()],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (embedded) return card;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.78, child: card),
        ),
      ),
    );
  }

  /// Case flow + records behind one loader; the lab's decision pinned under.
  Widget _buildCaseTab(GdprPatient p) => CaseReviewView(
        key: ValueKey('case-${p.id}'),
        store: widget.cases!,
        patientId: p.id,
        api: widget.controller.api,
        patients: widget.patientSession,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      );

  Widget _buildDetailsTab(GdprPatient p) {
    final loc = AppLocalizations.of(context);
    final rows = [
      (Icons.cake_outlined, loc.dateOfBirth, p.dateOfBirth),
      (Icons.mail_outline_rounded, loc.tr('p.email'), p.email),
      (Icons.phone_outlined, loc.tr('p.phone'), p.phone),
      (Icons.health_and_safety_outlined, loc.tr('patients.insurance'), p.healthInsurance),
      (Icons.home_outlined, loc.tr('patients.address'), p.address),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _InsetGroup(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const _InsetDivider(),
              _DemoRow(icon: rows[i].$1, label: rows[i].$2, value: rows[i].$3),
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
    final loc = AppLocalizations.of(context);
    final lab = widget.controller.api.isLaboratory;
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
                      hintText: loc.noteHintForRole(laboratory: lab),
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
                  label: loc.commonAdd,
                  compact: true,
                  busy: _adding,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.controller.loadingNotes && notes.isEmpty
                ? ToothPageLoader(
                    inPlace: true,
                    message: loc.patientsLoadingNotes,
                    size: 40,
                  )
                : notes.isEmpty
                    ? Center(
                        child: Text(
                          loc.noNotesForRole(laboratory: lab),
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
                              : formatAppDateTime(
                                  context,
                                  n.createdAt!.toLocal(),
                                );
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
                                          n.displayAuthorName(loc),
                                          ?n.authorRoleLabel(loc),
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
                                        tooltip: loc.patientsEditNote,
                                        onPressed: () => _editNote(n),
                                        icon: Icons.edit_outlined,
                                      ),
                                      AppButtons.icon(
                                        tooltip: loc.patientsDeleteNoteTitle,
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
      return ToothPageLoader(inPlace: true, message: AppLocalizations.of(context).patientsLoadingAccess);
    }
    if (accessOwner == null) {
      return Center(
        child: Text(
          AppLocalizations.of(context).tr('p.noAccessInfo'),
          style: AppFonts.style(color: AppColors.muted),
        ),
      );
    }
    final loc = AppLocalizations.of(context);
    final approved = access
        .where((e) => e.status == PatientAccessStatus.approved)
        .toList();
    final pending = access
        .where((e) => e.status == PatientAccessStatus.pending)
        .toList();
    final other = access
        .where((e) =>
            e.status != PatientAccessStatus.approved &&
            e.status != PatientAccessStatus.pending)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            loc.tr('share.whoHasAccess'),
            style: AppFonts.style(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
        _accessSectionLabel(loc.tr('share.ownerSection')),
        _buildOwnerAccessCard(accessOwner),
        if (!accessViewerIsOwner) ...[
          const SizedBox(height: 14),
          _accessSectionLabel(loc.tr('share.yourAccess')),
          if (access.isEmpty)
            _InsetGroup(
              padding: const EdgeInsets.all(14),
              child: Text(
                loc.tr('share.youHaveAccess'),
                style: AppFonts.style(
                  color: AppColors.navy,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            for (final entry in access) ...[
              if (entry != access.first) const SizedBox(height: 10),
              _buildAccessListCard(
                entry: entry,
                isOwner: false,
                blocked: blocked,
              ),
            ],
        ] else ...[
          if (access.isEmpty) ...[
            const SizedBox(height: 14),
            _InsetGroup(
              padding: const EdgeInsets.all(14),
              child: Text(
                loc.tr('share.onlyOwner'),
                style: AppFonts.style(
                  color: AppColors.muted,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (approved.isNotEmpty) ...[
            const SizedBox(height: 14),
            _accessSectionLabel(
              '${loc.tr('share.sharedWithSection')} (${approved.length})',
            ),
            for (final entry in approved) ...[
              const SizedBox(height: 10),
              _buildAccessListCard(
                entry: entry,
                isOwner: true,
                blocked: blocked,
              ),
            ],
          ],
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 14),
            _accessSectionLabel(loc.tr('share.pendingLab')),
            for (final entry in pending) ...[
              const SizedBox(height: 10),
              _buildAccessListCard(
                entry: entry,
                isOwner: true,
                blocked: blocked,
              ),
            ],
          ],
          for (final entry in other) ...[
            const SizedBox(height: 10),
            _buildAccessListCard(
              entry: entry,
              isOwner: true,
              blocked: blocked,
            ),
          ],
        ],
        if (!accessViewerIsOwner) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              loc.patientsOnlyOwnerManage,
              style: AppFonts.style(
                color: AppColors.muted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _accessSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: AppFonts.style(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildOwnerAccessCard(PatientAccessOwner owner) {
    final meta = [
      if ((owner.clinicName ?? '').trim().isNotEmpty) owner.clinicName!.trim(),
      if ((owner.email ?? '').trim().isNotEmpty) owner.email!.trim(),
    ].join(' · ');
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
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: AppFonts.style(
                      fontSize: 13,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
        : formatAppDateTime(context, entry.createdAt!.toLocal());

    String? subtext;
    Widget? actions;

    switch (entry.status) {
      case PatientAccessStatus.approved:
        if (isOwner) {
          actions = AppButtons.danger(
            onPressed: blocked ? null : () => _revokeAccess(entry),
            label: AppLocalizations.of(context).patientsRevoke,
            soft: true,
            compact: true,
          );
        }
      case PatientAccessStatus.pending:
        final requester = entry.requestedByName?.trim();
        final requestedBy = (requester != null && requester.isNotEmpty)
            ? AppLocalizations.of(context).trp('p.requestedBy', {'n': requester})
            : null;
        // Sharing with a colleague waits for the lab; the owner can withdraw it.
        subtext = [?requestedBy, AppLocalizations.of(context).tr('p.waitingLab')].join('\n');
        if (isOwner) {
          actions = AppButtons.ghost(
            onPressed: blocked ? null : () => _revokeAccess(entry),
            label: AppLocalizations.of(context).tr('p.withdraw'),
            compact: true,
          );
        }
      case PatientAccessStatus.rejected:
        if (isOwner) {
          actions = AppButtons.ghost(
            onPressed: blocked ? null : () => _regrantAccess(entry),
            label: AppLocalizations.of(context).patientsRegrant,
            compact: true,
          );
        }
    }

    final roleLabel = AppRoles.label(entry.role, AppLocalizations.of(context));
    final meta = [
      if (roleLabel.trim().isNotEmpty) roleLabel.trim(),
      if ((entry.clinicName ?? '').trim().isNotEmpty) entry.clinicName!.trim(),
      if ((entry.email ?? '').trim().isNotEmpty) entry.email!.trim(),
      if (when.isNotEmpty) when,
    ].join(' · ');

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
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: AppFonts.style(
                      fontSize: 12.5,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
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
  const _DemoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
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

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'admin_models.dart';
import '../../core/widgets/patient_records.dart';
import 'admin_widgets.dart';

/// Every patient, with an Unassigned tab. Landscape shows the detail beside
/// the list, iPad portrait under it; phones push it.
class AdminPatientsPage extends StatefulWidget {
  const AdminPatientsPage({
    super.key,
    required this.api,
    required this.tab,
    required this.status,
    this.active = true,
  });

  final ApiClient api;

  /// 0 all patients, 1 unassigned.
  final ValueNotifier<int> tab;

  /// Status filter ('' = all), owned by the shell so the dashboard can
  /// open this page on one status.
  final ValueNotifier<String> status;
  final bool active;

  @override
  State<AdminPatientsPage> createState() => _AdminPatientsPageState();
}

class _AdminPatientsPageState extends State<AdminPatientsPage> {
  late final Future<List<AdminLab>> _labs = widget.api
      .adminLabs()
      .then((r) => r.map(AdminLab.new).toList(), onError: (_) => <AdminLab>[]);
  final _search = TextEditingController();
  String _q = '';
  AdminLab? _lab;
  String? _selected;

  /// Bumped after a change in the detail so the list reloads.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    widget.tab.addListener(_onTab);
    widget.status.addListener(_onStatus);
  }

  String get _status => widget.status.value;

  /// One key per status chip, so a preselected chip can be scrolled into view.
  final _chipKeys = {for (final s in ['', ...CaseStatuses.all]) s: GlobalKey()};

  void _onStatus() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _chipKeys[_status]?.currentContext;
      if (chip != null && chip.mounted) {
        Scrollable.ensureVisible(chip, alignment: 0.5, duration: AppMotion.normal, curve: AppMotion.easeOut);
      }
    });
  }

  @override
  void dispose() {
    widget.tab.removeListener(_onTab);
    widget.status.removeListener(_onStatus);
    _search.dispose();
    super.dispose();
  }

  void _onTab() => setState(() => _selected = null);

  void _changed() => setState(() => _version++);

  void _open(AdminPatient p, bool inPage) {
    if (inPage) {
      setState(() => _selected = p.id);
      return;
    }
    Navigator.of(context).push(
      AppPageRoutes.cupertino<void>(
        Scaffold(
          backgroundColor: AppColors.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: AdminPatientDetail(
                api: widget.api,
                patientId: p.id,
                onChanged: _changed,
                showBack: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: widget.tab,
      builder: (context, t, _) {
        final unassigned = t == 1;
        return AdminPage(
          icon: Icons.people_outline,
          title: loc.navPatients,
          subtitle: loc.tr('admin.patientsSub'),
          toolbar: [
            AdminTabs(
              tab: widget.tab,
              labels: [loc.tr('admin.allPatients'), loc.tr('admin.unassignedPatients')],
            ),
            AdminSearchField(
              controller: _search,
              hint: loc.tr('admin.searchPatients'),
              onChanged: (q) => setState(() => _q = q),
            ),
            // Filters fold away on the Unassigned tab instead of popping.
            AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.spring,
              alignment: Alignment.topLeft,
              child: AnimatedOpacity(
                opacity: unassigned ? 0 : 1,
                duration: AppMotion.fast,
                child: unassigned
                    ? const SizedBox(width: double.infinity)
                    : _filters(loc),
              ),
            ),
          ],
          body: LayoutBuilder(
            builder: (context, c) {
              // Landscape: detail beside the list. iPad portrait: detail
              // card under the list, same page. Phone: pushed page.
              final phone = AppBreakpoints.isPhone(context);
              // Any iPad in landscape keeps the side-by-side view (also the
              // 1024pt-wide ones, whose content is just under 900).
              final split = c.maxWidth >= 900 || (!phone && !AppBreakpoints.isPortrait(context));
              final stacked = !split && !phone;
              final inPage = split || stacked;
              final list = AdminSwap(index: t, builder: (i) => _list(loc, i == 1, inPage, widget.active && i == t));
              if (split) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: list),
                    const SizedBox(width: 16),
                    Expanded(flex: 6, child: _detailPanel(loc)),
                  ],
                );
              }
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: list),
                    const SizedBox(height: 16),
                    Expanded(flex: 3, child: _detailPanel(loc)),
                  ],
                );
              }
              return list;
            },
          ),
        );
      },
    );
  }

  /// Selected patient's detail (or a hint), crossfading on change.
  Widget _detailPanel(AppLocalizations loc) {
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      // Crossfade + slight rise when another patient is picked.
      child: AnimatedSwitcher(
        duration: AppMotion.page,
        switchInCurve: AppMotion.spring,
        switchOutCurve: AppMotion.easeIn,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(a),
            child: child,
          ),
        ),
        child: _selected == null
            ? AdminEmpty(
                key: const ValueKey('none'),
                icon: Icons.touch_app_outlined,
                title: loc.tr('admin.pickPatient'),
                subtitle: loc.tr('admin.pickPatientSub'),
              )
            : AdminPatientDetail(
                key: ValueKey(_selected),
                api: widget.api,
                patientId: _selected!,
                onChanged: _changed,
              ),
      ),
    );
  }

  Widget _filters(AppLocalizations loc) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final s in ['', ...CaseStatuses.all]) ...[
            SoftFilterChip(
              key: _chipKeys[s],
              label: s.isEmpty ? loc.filterAll : loc.statusLabel(s),
              selected: _status == s,
              onTap: () => widget.status.value = s,
            ),
            const SizedBox(width: 8),
          ],
          SoftPillButton(
            label: _lab?.name ?? loc.tr('admin.allLabs'),
            icon: Icons.apartment_rounded,
            selected: _lab != null,
            onPressed: () async {
              final labs = await _labs;
              if (!mounted) return;
              // Record wrapper: null means cancelled, (lab: null) means all.
              final pick = await adminChoose<({AdminLab? lab})>(
                context,
                title: loc.tr('admin.filterLab'),
                options: [
                  ((lab: null), loc.tr('admin.allLabs')),
                  for (final l in labs) ((lab: l), l.name),
                ],
              );
              if (pick != null) setState(() => _lab = pick.lab);
            },
          ),
        ],
      ),
    );
  }

  Widget _list(AppLocalizations loc, bool unassigned, bool inPage, bool on) {
    return AdminFuture<List<AdminPatient>>(
      query: unassigned ? '$_q|$_version' : '$_status|${_lab?.id}|$_q|$_version',
      active: on,
      load: () async => (await widget.api.adminPatients(
        status: unassigned ? '' : _status,
        labId: unassigned ? null : _lab?.id,
        unassigned: unassigned,
        q: _q,
      ))
          .map(AdminPatient.new)
          .toList(),
      empty: unassigned
          ? AdminEmpty(
              icon: Icons.task_alt_rounded,
              title: loc.tr('admin.noUnassignedPatients'),
              subtitle: loc.tr('admin.noUnassignedPatientsSub'),
            )
          : AdminEmpty(
              icon: Icons.people_outline,
              title: loc.tr('admin.noPatients'),
              subtitle: loc.tr('admin.noPatientsSub'),
            ),
      builder: (context, rows, reload) => [
        adminSliverList<AdminPatient>(
          rows,
          id: (p) => p.id,
          gap: 10,
          (context, p) {
            return AdminCard(
              selected: inPage && p.id == _selected,
              onTap: () => _open(p, inPage),
              child: AdminRow(
                leading: UserAvatar(name: p.name, size: 42),
                title: p.name.isEmpty ? '—' : p.name,
                badges: [
                  StatusChip(statusKey: p.status),
                  if (p.unassignedReason != null) unassignedBadge(loc, p.unassignedReason!),
                ],
                lines: [
                  if (p.waitingForLab) ...[
                    ownerLabel(loc, p),
                    loc.trp('admin.fromOwner', {'name': p.ownerName ?? '—'}),
                  ] else
                    '${loc.tr('admin.owner')}: ${ownerLabel(loc, p)} · ${loc.tr('admin.lab')}: ${p.labName ?? loc.tr('admin.noLab')}',
                  if (p.updatedAt != null)
                    loc.trp('admin.updated', {'when': adminWhen(context, p.updatedAt)}),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Owner as shown to the admin: patients sent to another lab show
/// "Waiting for {receiving lab}" until that lab picks a dentist.
String ownerLabel(AppLocalizations loc, AdminPatient p) => p.waitingForLab
    ? loc.trp('admin.waitingFor', {'lab': p.labName ?? '—'})
    : p.ownerName ?? '—';

AdminBadge unassignedBadge(AppLocalizations loc, String reason) => AdminBadge(
      loc.tr(reason == 'waiting_for_lab' ? 'admin.waitingForLab' : 'admin.ownerDeleted'),
      color: AppColors.warning,
    );

/// Patient detail for the admin: who owns it and can see it, the case
/// history, the clinical records (read-only), status override and reassign.
class AdminPatientDetail extends StatefulWidget {
  const AdminPatientDetail({
    super.key,
    required this.api,
    required this.patientId,
    required this.onChanged,
    this.showBack = false,
  });

  final ApiClient api;
  final String patientId;
  final VoidCallback onChanged;
  final bool showBack;

  @override
  State<AdminPatientDetail> createState() => _AdminPatientDetailState();
}

class _AdminPatientDetailState extends State<AdminPatientDetail> {
  int _version = 0;

  ApiClient get api => widget.api;

  void _changed() {
    setState(() => _version++);
    widget.onChanged();
  }

  Future<void> _override(AdminPatient p) async {
    final loc = AppLocalizations.of(context);
    final picked = await AppDialogs.sheet<(String, String)>(
      context: context,
      builder: (_) => _OverrideSheet(current: p.status),
    );
    if (picked == null || !mounted) return;
    final ok = await adminRun(
      context,
      () => api.adminOverrideStatus(p.id, picked.$1, picked.$2),
      done: loc.trp('admin.statusChanged', {'status': loc.statusLabel(picked.$1)}),
    );
    if (ok) _changed();
  }

  Future<void> _reassign(AdminPatient p) async {
    final loc = AppLocalizations.of(context);
    final pick = await pickLab(
      context,
      api,
      title: loc.trp('admin.reassignTitle', {'name': p.name}),
      message: loc.tr('admin.reassignMsg'),
    );
    final lab = pick?.lab;
    if (lab == null || !mounted) return;
    // Optional second step: one of the lab's dentists, or leave it to the lab.
    final List<AdminDentist> dentists;
    try {
      dentists = await AppDialogs.runWithLoading(
        context,
        action: () async =>
            (await api.adminDentists(labId: lab.id)).map(AdminDentist.new).where((d) => !d.deleted).toList(),
      );
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    AdminDentist? dentist;
    if (dentists.isNotEmpty) {
      final choice = await adminChoose<({AdminDentist? d})>(
        context,
        title: loc.trp('admin.pickDentistTitle', {'lab': lab.name}),
        message: loc.trp('admin.pickDentistMsg', {'lab': lab.name}),
        options: [
          ((d: null), loc.trp('admin.noDentistLabChooses', {'lab': lab.name})),
          for (final d in dentists) ((d: d), d.clinicName == null ? d.name : '${d.name} · ${d.clinicName}'),
        ],
      );
      if (choice == null || !mounted) return;
      dentist = choice.d;
    }
    final ok = await adminRun(
      context,
      () => api.adminReassignPatient(p.id, lab.id, dentistId: dentist?.id),
      done: dentist == null
          ? loc.trp('admin.reassigned', {'name': p.name, 'lab': lab.name})
          : loc.trp('admin.reassignedTo', {'name': p.name, 'dentist': dentist.name, 'lab': lab.name}),
    );
    if (ok) _changed();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return AdminFuture<AdminPatient>(
      query: _version,
      load: () async => AdminPatient(await api.adminPatient(widget.patientId)),
      isEmpty: (_) => false,
      empty: const SizedBox.shrink(),
      builder: (context, p, _) => [
        SliverToBoxAdapter(child: _header(loc, p)),
        SliverToBoxAdapter(child: _facts(loc, p)),
        SliverToBoxAdapter(child: PatientRecords(api: api, patientId: p.id)),
        SliverToBoxAdapter(child: _section(loc.tr('admin.history'))),
        if (p.events.isEmpty)
          SliverToBoxAdapter(
            child: Text(
              loc.tr('admin.noHistory'),
              style: AppFonts.style(color: AppColors.muted, fontSize: 14),
            ),
          )
        else
          SliverList.builder(
            itemCount: p.events.length,
            itemBuilder: (context, i) => _EventTile(
              event: p.events[i],
              last: i == p.events.length - 1,
            ),
          ),
      ],
    );
  }

  Widget _header(AppLocalizations loc, AdminPatient p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.showBack)
                AppButtons.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: loc.tr('admin.back'),
                ),
              UserAvatar(name: p.name, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name.isEmpty ? '—' : p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        StatusChip(statusKey: p.status),
                        if (p.unassignedReason != null)
                          unassignedBadge(loc, p.unassignedReason!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButtons.primary(
                onPressed: () => _override(p),
                icon: Icons.edit_note_rounded,
                label: loc.tr('admin.overrideStatus'),
                compact: true,
              ),
              if (p.unassignedReason != null)
                AppButtons.secondary(
                  onPressed: () => _reassign(p),
                  icon: Icons.move_down_rounded,
                  label: loc.tr('admin.reassignLab'),
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _facts(AppLocalizations loc, AdminPatient p) {
    Widget row(String k, String v, [String? sub]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(k, style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v,
                      style: AppFonts.style(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                    if (sub != null)
                      Text(sub, style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          row(
            loc.tr('admin.owner'),
            ownerLabel(loc, p),
            p.waitingForLab ? loc.trp('admin.fromOwner', {'name': p.ownerName ?? '—'}) : null,
          ),
          row(loc.tr('admin.lab'), p.labName ?? loc.tr('admin.noLab')),
          row(
            loc.tr('admin.sharedWith'),
            p.sharedWith.isEmpty
                ? loc.tr('admin.nobody')
                : p.sharedWith.map((s) => s.name).join(', '),
          ),
          row(loc.tr('admin.lastUpdate'), adminWhen(context, p.updatedAt)),
        ],
      ),
    );
  }
}

Widget _section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: SectionLabel(title),
    );

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.last});

  final CaseEvent event;
  final bool last;

  static const _icons = {
    'created': (Icons.add_circle_outline_rounded, AppColors.dentalBlue),
    'submitted': (Icons.send_rounded, AppColors.review),
    'approved': (Icons.verified_rounded, AppColors.success),
    'rejected': (Icons.cancel_outlined, AppColors.danger),
    'updated': (Icons.edit_outlined, AppColors.muted),
    'reassigned': (Icons.swap_horiz_rounded, AppColors.warning),
    'admin_override': (Icons.admin_panel_settings_outlined, AppColors.navy),
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final e = event;
    final (icon, color) = _icons[e.type] ?? (Icons.circle_outlined, AppColors.muted);
    final label = loc.tr('admin.event.${e.type}');
    final move = e.toStatus == null
        ? null
        : [?e.fromStatus, e.toStatus!].map(loc.statusLabel).join(' → ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: AppColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.startsWith('admin.event.') ? e.type : label,
                    style: AppFonts.style(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    [?e.actor, ?move, adminWhen(context, e.at)].join(' · '),
                    style: AppFonts.style(fontSize: 12, color: AppColors.muted),
                  ),
                  if (e.remarks != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border(left: BorderSide(color: color, width: 3)),
                      ),
                      child: Text(
                        e.remarks!,
                        style: AppFonts.style(fontSize: 13, color: AppColors.navy, height: 1.35),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick a status and write the required note. Pops `(status, note)`.
class _OverrideSheet extends StatefulWidget {
  const _OverrideSheet({required this.current});

  final String current;

  @override
  State<_OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends State<_OverrideSheet> {
  late String _status = CaseStatuses.normalize(widget.current);
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final canSave = _note.text.trim().isNotEmpty &&
        _status != CaseStatuses.normalize(widget.current);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.tr('admin.overrideStatus'),
            style: AppFonts.style(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy),
          ),
          const SizedBox(height: 6),
          Text(
            loc.tr('admin.overrideMsg'),
            style: AppFonts.style(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in CaseStatuses.all)
                SoftFilterChip(
                  label: loc.statusLabel(s),
                  selected: _status == s,
                  onTap: () => setState(() => _status = s),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: loc.tr('admin.noteRequired')),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButtons.ghost(onPressed: () => Navigator.pop(context), label: loc.cancel),
              const SizedBox(width: 8),
              AppButtons.primary(
                onPressed: canSave
                    ? () => Navigator.pop(context, (_status, _note.text.trim()))
                    : null,
                label: loc.save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

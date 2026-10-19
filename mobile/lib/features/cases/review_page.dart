import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../core/widgets/patient_records.dart';
import '../../core/widgets/page_kit.dart';
import 'case_panel.dart';
import 'case_store.dart';

/// Lab review queue: patients under review. Open one to see its records and
/// case panel, then Approve or Reject with remarks.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.api, required this.cases, this.active = true});

  final ApiClient api;
  final CaseStore cases;
  final bool active;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  String? _selected;

  /// Bumped after a decision so the queue reloads (the patient leaves it).
  int _version = 0;

  @override
  void initState() {
    super.initState();
    widget.cases.addListener(_onCase);
  }

  @override
  void dispose() {
    widget.cases.removeListener(_onCase);
    super.dispose();
  }

  void _onCase() {
    // Approved / rejected here: drop it from the queue.
    final id = _selected;
    final info = widget.cases.of(id);
    if (id != null && info != null && info.status != 'in_review' && mounted) {
      setState(() => _version++);
    }
  }

  String _name(Map<String, dynamic> p) => '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();

  void _open(Map<String, dynamic> p, bool inPage) {
    final id = '${p['id']}';
    if (inPage) {
      setState(() => _selected = id);
      return;
    }
    Navigator.of(context).push(AppPageRoutes.cupertino<void>(
      Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: Text(_name(p)), backgroundColor: AppColors.surface),
        body: SafeArea(child: _detail(id)),
      ),
    ));
  }

  Widget _detail(String id) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          CasePanel(key: ValueKey('case-$id'), store: widget.cases, patientId: id),
          PatientRecords(key: ValueKey('rec-$id'), api: widget.api, patientId: id),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return AdminPage(
      icon: Icons.fact_check_outlined,
      title: loc.tr('review.title'),
      subtitle: loc.tr('review.sub'),
      body: LayoutBuilder(
        builder: (context, c) {
          final phone = AppBreakpoints.isPhone(context);
          final split = c.maxWidth >= 900 || (!phone && !AppBreakpoints.isPortrait(context));
          final stacked = !split && !phone;
          final inPage = split || stacked;
          final list = AdminFuture<List<Map<String, dynamic>>>(
            active: widget.active,
            query: _version,
            load: () => widget.api.listPatients(status: 'in_review', forceRefresh: true),
            empty: AdminEmpty(
              icon: Icons.inbox_outlined,
              title: loc.tr('review.empty'),
              subtitle: loc.tr('review.emptySub'),
            ),
            builder: (context, rows, _) => [
              adminSliverList<Map<String, dynamic>>(
                rows,
                id: (p) => '${p['id']}',
                gap: 10,
                (context, p) => AdminCard(
                  selected: inPage && '${p['id']}' == _selected,
                  onTap: () => _open(p, inPage),
                  child: AdminRow(
                    leading: UserAvatar(name: _name(p), size: 42),
                    title: _name(p).isEmpty ? '—' : _name(p),
                    badges: [StatusChip(statusKey: '${p['status'] ?? ''}')],
                    lines: [
                      if (DateTime.tryParse('${p['updated_at'] ?? ''}') case final at?)
                        loc.trp('admin.updated', {'when': adminWhen(context, at.toLocal())}),
                    ],
                  ),
                ),
              ),
            ],
          );
          if (!inPage) return list;
          final detail = AdminCard(
            padding: EdgeInsets.zero,
            child: _selected == null
                ? AdminEmpty(
                    icon: Icons.touch_app_outlined,
                    title: loc.tr('review.pick'),
                    subtitle: loc.tr('review.pickSub'),
                  )
                : _detail(_selected!),
          );
          return split
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: list),
                    const SizedBox(width: 16),
                    Expanded(flex: 6, child: detail),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: list),
                    const SizedBox(height: 16),
                    Expanded(flex: 3, child: detail),
                  ],
                );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

/// A person or lab picked from a list.
typedef Picked = ({String id, String name});

/// One of the signed-in lab's dentists (action sheet). Null when cancelled
/// or the lab has none (a message says so).
Future<Picked?> pickLabDentist(
  BuildContext context,
  ApiClient api, {
  required String title,
  String? message,
}) async {
  final loc = AppLocalizations.of(context);
  final List<Map<String, dynamic>> rows;
  try {
    rows = await AppDialogs.runWithLoading(context, action: () => api.labDentists(api.userId ?? ''));
  } catch (e) {
    if (context.mounted) AppSnackBars.error(context, friendlyError(e));
    return null;
  }
  if (!context.mounted) return null;
  final dentists = rows.where((d) => d['deleted'] != true).toList();
  if (dentists.isEmpty) {
    await AppDialogs.alert(context, title: title, message: loc.tr('lab.noDentists'));
    return null;
  }
  return pickSearchable<Picked>(
    context,
    title: title,
    message: message,
    items: [
      for (final d in dentists)
        (
          value: (id: '${d['id']}', name: '${d['name'] ?? ''}'),
          name: '${d['name'] ?? ''}',
          detail: '${d['clinic_name'] ?? ''}',
          avatar: d['avatar_url']?.toString(),
        ),
    ],
  );
}

/// One row of [pickSearchable].
typedef PickItem<T> = ({T value, String name, String detail, String? avatar});

/// Searchable, scrolling list in a sheet — for lists that outgrow an action
/// sheet (a lab's dentists). Null when cancelled.
Future<T?> pickSearchable<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<PickItem<T>> items,
}) {
  return AppDialogs.sheet<T>(
    context: context,
    maxWidth: 520,
    builder: (_) => _SearchList<T>(title: title, message: message, items: items),
  );
}

class _SearchList<T> extends StatefulWidget {
  const _SearchList({super.key, required this.title, this.message, required this.items});

  final String title;
  final String? message;
  final List<PickItem<T>> items;

  @override
  State<_SearchList<T>> createState() => _SearchListState<T>();
}

class _SearchListState<T> extends State<_SearchList<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final q = _q.toLowerCase();
    final rows = [
      for (final it in widget.items)
        if (q.isEmpty || '${it.name} ${it.detail}'.toLowerCase().contains(q)) it,
    ];
    final height = (MediaQuery.sizeOf(context).height * 0.65).clamp(300.0, 560.0);
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: AppFonts.style(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
              if (widget.message != null) ...[
                const SizedBox(height: 6),
                Text(widget.message!, style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
              ],
              const SizedBox(height: 12),
              CupertinoSearchTextField(
                placeholder: loc.tr('pick.search'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: rows.isEmpty
                    ? Center(child: Text(loc.tr('pick.none'), style: AppFonts.style(color: AppColors.muted)))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final it = rows[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: UserAvatar(name: it.name, url: it.avatar, size: 36),
                            title: Text(it.name.isEmpty ? '—' : it.name,
                                style: AppFonts.style(fontWeight: FontWeight.w600, color: AppColors.navy)),
                            subtitle: it.detail.isEmpty
                                ? null
                                : Text(it.detail, style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
                            onTap: () => Navigator.pop(context, it.value),
                          );
                        },
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AppButtons.ghost(onPressed: () => Navigator.pop(context), label: loc.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Another lab, searched by name (`GET /api/labs?q=`). Null when cancelled.
Future<Picked?> pickOtherLab(
  BuildContext context,
  ApiClient api, {
  required String title,
  String? message,
}) {
  return AppDialogs.sheet<Picked>(
    context: context,
    maxWidth: 520,
    builder: (_) => _LabSearch(api: api, title: title, message: message),
  );
}

class _LabSearch extends StatefulWidget {
  const _LabSearch({required this.api, required this.title, this.message});

  final ApiClient api;
  final String title;
  final String? message;

  @override
  State<_LabSearch> createState() => _LabSearchState();
}

class _LabSearchState extends State<_LabSearch> {
  late Future<List<Map<String, dynamic>>> _rows = _load('');
  Timer? _debounce;

  // The signed-in lab can't send to itself.
  Future<List<Map<String, dynamic>>> _load(String q) async => (await widget.api.searchLabs(q: q))
      .where((l) => '${l['id']}' != widget.api.userId)
      .toList();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final height = (MediaQuery.sizeOf(context).height * 0.65).clamp(300.0, 560.0);
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: AppFonts.style(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
              if (widget.message != null) ...[
                const SizedBox(height: 6),
                Text(widget.message!, style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
              ],
              const SizedBox(height: 12),
              CupertinoSearchTextField(
                placeholder: loc.tr('admin.searchLabs'),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => _rows = _load(v.trim()));
                  });
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _rows,
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
                    if (!snap.hasData) return const Center(child: CupertinoActivityIndicator());
                    final labs = snap.data!;
                    if (labs.isEmpty) {
                      return Center(
                        child: Text(loc.tr('admin.noLabsFound'), style: AppFonts.style(color: AppColors.muted)),
                      );
                    }
                    return ListView.builder(
                      itemCount: labs.length,
                      itemBuilder: (context, i) {
                        final l = labs[i];
                        final name = '${l['name'] ?? ''}';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: UserAvatar(name: name, url: l['avatar_url']?.toString(), size: 36),
                          title: Text(name,
                              style: AppFonts.style(fontWeight: FontWeight.w600, color: AppColors.navy)),
                          onTap: () => Navigator.pop(context, (id: '${l['id']}', name: name)),
                        );
                      },
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AppButtons.ghost(onPressed: () => Navigator.pop(context), label: loc.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lab-only part of the create-patient form: the patient either goes to one
/// of the lab's dentists or is sent to another lab. Required.
class LabPatientTarget extends StatefulWidget {
  const LabPatientTarget({super.key, required this.api, required this.value, this.enabled = true});

  final ApiClient api;

  /// `{'dentist_id': …}` or `{'send_to_lab_id': …}`; null until chosen.
  final ValueNotifier<Map<String, String>?> value;
  final bool enabled;

  @override
  State<LabPatientTarget> createState() => _LabPatientTargetState();
}

class _LabPatientTargetState extends State<LabPatientTarget> {
  bool _toLab = false;
  Picked? _picked;

  Future<void> _pick() async {
    final loc = AppLocalizations.of(context);
    final p = _toLab
        ? await pickOtherLab(context, widget.api,
            title: loc.tr('lab.sendToLab'), message: loc.tr('lab.sendToLabMsg'))
        : await pickLabDentist(context, widget.api, title: loc.tr('lab.assignDentist'));
    if (p == null || !mounted) return;
    setState(() => _picked = p);
    widget.value.value = {_toLab ? 'send_to_lab_id' : 'dentist_id': p.id};
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(loc.tr('lab.patientFor')),
        const SizedBox(height: 10),
        CupertinoSlidingSegmentedControl<bool>(
          groupValue: _toLab,
          children: {
            false: Padding(padding: const EdgeInsets.all(6), child: Text(loc.tr('lab.assignDentist'))),
            true: Padding(padding: const EdgeInsets.all(6), child: Text(loc.tr('lab.sendToLab'))),
          },
          onValueChanged: (v) {
            if (v == null || !widget.enabled) return;
            setState(() {
              _toLab = v;
              _picked = null;
            });
            widget.value.value = null;
          },
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: widget.enabled ? _pick : null,
          icon: Icon(_toLab ? Icons.apartment_rounded : Icons.medical_services_outlined, size: 18),
          label: Text(
            _picked?.name ?? loc.tr(_toLab ? 'lab.chooseLab' : 'lab.chooseDentist'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_toLab)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(loc.tr('lab.sendToLabMsg'), style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
          ),
      ],
    );
  }
}

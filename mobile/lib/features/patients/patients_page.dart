import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class PatientsPage extends StatefulWidget {
  const PatientsPage({
    super.key,
    required this.api,
    required this.dentistName,
    required this.onNewPatient,
  });

  final ApiClient api;
  final String dentistName;
  final VoidCallback onNewPatient;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = widget.api.listPatients();
  }

  void _reload() => setState(() => _future = widget.api.listPatients());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Patients',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const Spacer(),
              FutureBuilder(
                future: _future,
                builder: (context, snap) {
                  final n = snap.data?.length ?? 0;
                  return Text(
                    '$n total',
                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                  );
                },
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: widget.onNewPatient,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Patient'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final patients = await widget.api.listPatients();
                  if (patients.isEmpty || !context.mounted) return;
                  final id = patients.first['id'] as int;
                  final xml = await widget.api.exportDatevXml(id);
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('DATEV XML skeleton'),
                      content: SizedBox(
                        width: 480,
                        height: 320,
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
                },
                icon: const Icon(Icons.code, size: 18),
                label: const Text('DATEV export'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Search patients, case IDs, dentists...',
              prefixIcon: Icon(Icons.search, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                label: 'All',
                selected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              _FilterChip(
                label: 'In Progress',
                selected: _filter == 'in_progress',
                onTap: () => setState(() => _filter = 'in_progress'),
              ),
              _FilterChip(
                label: 'Awaiting Scan',
                selected: _filter == 'awaiting_scan',
                onTap: () => setState(() => _filter = 'awaiting_scan'),
              ),
              _FilterChip(
                label: 'In Review',
                selected: _filter == 'in_review',
                onTap: () => setState(() => _filter = 'in_review'),
              ),
              _FilterChip(
                label: 'Complete',
                selected: _filter == 'complete',
                onTap: () => setState(() => _filter = 'complete'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SectionCard(
              padding: EdgeInsets.zero,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        snap.error.toString().replaceFirst('Exception: ', ''),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    );
                  }
                  var patients = snap.data ?? [];
                  if (_query.isNotEmpty) {
                    patients = patients.where((p) {
                      final name =
                          '${p['first_name']} ${p['last_name']}'.toLowerCase();
                      return name.contains(_query) ||
                          'pt-${p['id']}'.contains(_query);
                    }).toList();
                  }
                  if (patients.isEmpty) {
                    return const Center(
                      child: Text(
                        'No patients yet. Add the first record.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: patients.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, i) {
                      final p = patients[i];
                      final name = '${p['first_name']} ${p['last_name']}';
                      final statusKeys = [
                        'in_progress',
                        'awaiting_scan',
                        'complete',
                        'in_review',
                      ];
                      final status = statusKeys[i % statusKeys.length];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: InitialsAvatar(name: name),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'PT-${p['id']} · ${widget.dentistName}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusChip(statusKey: status),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () async {
                                await widget.api.deletePatient(p['id'] as int);
                                _reload();
                              },
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.danger, size: 20),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.muted,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/tooth_loader.dart';
import 'patient_form_screen.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({
    super.key,
    required this.api,
    required this.dentistName,
  });

  final ApiClient api;
  final String dentistName;

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listPatients();
  }

  void _reload() {
    setState(() => _future = widget.api.listPatients());
  }

  Future<void> _add() async {
    final created = await Navigator.of(context).push<bool>(
      AppPageRoutes.cupertino(PatientFormScreen(api: widget.api)),
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Patients · ${widget.dentistName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add patient'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ToothPageLoader(message: 'Loading patients…');
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.error.toString().replaceFirst('Exception: ', ''),
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final patients = snap.data ?? [];
          if (patients.isEmpty) {
            return const Center(
              child: Text(
                'No patients yet. Add the first record.',
                style: TextStyle(color: AppColors.muted),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: patients.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final p = patients[i];
              final name = '${p['first_name']} ${p['last_name']}';
              final phone = (p['phone'] as String?)?.trim();
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      if (phone != null && phone.isNotEmpty) phone,
                      if ((p['health_insurance'] as String?)?.isNotEmpty == true)
                        p['health_insurance'],
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () async {
                      await widget.api.deletePatient(p['id'] as int);
                      _reload();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

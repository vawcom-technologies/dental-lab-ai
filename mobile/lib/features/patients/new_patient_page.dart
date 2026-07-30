import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class NewPatientPage extends StatefulWidget {
  const NewPatientPage({super.key, required this.api, required this.onCreated});

  final ApiClient api;
  final VoidCallback onCreated;

  @override
  State<NewPatientPage> createState() => _NewPatientPageState();
}

class _NewPatientPageState extends State<NewPatientPage> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _insurance = TextEditingController();
  final _notes = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.createPatient({
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'health_insurance':
            _insurance.text.trim().isEmpty ? null : _insurance.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      widget.onCreated();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _address.dispose();
    _insurance.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.person_add_alt_1_rounded,
            title: 'New Patient',
            subtitle:
                'Create a GDPR-ready chairside record. Required fields are marked.',
            actions: [
              OutlinedButton(
                onPressed: _loading
                    ? null
                    : () {
                        _formKey.currentState?.reset();
                        _first.clear();
                        _last.clear();
                        _phone.clear();
                        _address.clear();
                        _insurance.clear();
                        _notes.clear();
                        setState(() => _error = null);
                      },
                child: const Text('Clear'),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _save,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_loading ? 'Saving…' : 'Save patient'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Expanded(
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  final identity = _IdentityCard(
                    first: _first,
                    last: _last,
                    phone: _phone,
                    insurance: _insurance,
                  );
                  final details = _DetailsCard(
                    address: _address,
                    notes: _notes,
                    error: _error,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: identity),
                        const SizedBox(width: 16),
                        Expanded(flex: 5, child: details),
                      ],
                    );
                  }
                  return ListView(
                    children: [
                      identity,
                      const SizedBox(height: 16),
                      details,
                      const SizedBox(height: 8),
                    ],
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

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.first,
    required this.last,
    required this.phone,
    required this.insurance,
  });

  final TextEditingController first;
  final TextEditingController last;
  final TextEditingController phone;
  final TextEditingController insurance;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListView(
        children: [
          Row(
            children: [
              const Expanded(child: SectionLabel('Identity')),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.sidebarActive,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'GDPR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Legal name as on insurance card',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: first,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'First name *',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: last,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Last name *',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: phone,
            decoration: const InputDecoration(
              labelText: 'Phone / mobile',
              hintText: '+49 …',
              prefixIcon: Icon(Icons.phone_outlined, size: 20),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: insurance,
            decoration: const InputDecoration(
              labelText: 'Health insurance',
              hintText: 'e.g. AOK Bayern, TK, DKV',
              prefixIcon: Icon(Icons.health_and_safety_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.inset,
              borderRadius: AppRadii.borderSm,
              boxShadow: NeoShadows.pressed(),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 18, color: AppColors.dentalBlue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Patient data stays in your clinic workspace and is shared with the lab only when a case is opened.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
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

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.address,
    required this.notes,
    required this.error,
  });

  final TextEditingController address;
  final TextEditingController notes;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: ListView(
        children: [
          const SectionLabel('Contact & clinical notes'),
          const SizedBox(height: 6),
          const Text(
            'Optional details that help the lab and billing',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: address,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'Street, PLZ, city',
              prefixIcon: Icon(Icons.location_on_outlined, size: 20),
              alignLabelWithHint: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: notes,
            decoration: const InputDecoration(
              labelText: 'Clinical notes',
              hintText: 'Tooth numbers, shade preference, urgency…',
              prefixIcon: Icon(Icons.notes_outlined, size: 20),
              alignLabelWithHint: true,
            ),
            maxLines: 5,
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: AppRadii.borderSm,
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.dentalBlue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'After saving, open Shade, Smile Preview, or Scan Body and attach this patient to a case.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'patient_models.dart';

class NewPatientPage extends StatefulWidget {
  const NewPatientPage({
    super.key,
    required this.api,
    required this.onCreated,
    this.patientSession,
  });

  final ApiClient api;
  final VoidCallback onCreated;
  final PatientSession? patientSession;

  @override
  State<NewPatientPage> createState() => _NewPatientPageState();
}

class _NewPatientPageState extends State<NewPatientPage> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _dob = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _insurance = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final created = await widget.api.createPatient({
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'date_of_birth': _dob.text.trim(),
        'email': _email.text.trim(),
        'phone': PhoneNumbers.compose(_phone.text),
        'address': _address.text.trim(),
        'health_insurance': _insurance.text.trim(),
      });
      final session = widget.patientSession;
      if (session != null) {
        await session.adoptCreatedPatient(created);
      }
      if (!mounted) return;
      widget.onCreated();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _dob.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _insurance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.person_add_alt_1_rounded,
            title: loc.newPatientTitle,
            subtitle: loc.newPatientSubtitle,
            actions: [
              AppButtons.secondary(
                onPressed: _loading
                    ? null
                    : () {
                        _formKey.currentState?.reset();
                        _first.clear();
                        _last.clear();
                        _dob.clear();
                        _email.clear();
                        _phone.clear();
                        _address.clear();
                        _insurance.clear();
                        setState(() => _error = null);
                      },
                label: 'Clear',
              ),
              AppButtons.primary(
                onPressed: _loading ? null : _save,
                icon: Icons.check_rounded,
                label: _loading ? 'Saving…' : loc.createPatient,
                busy: _loading,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Expanded(
            child: Form(
              key: _formKey,
              child: SectionCard(
                child: ListView(
                  children: [
                    const SectionLabel('Identity'),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _first,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: '${loc.firstName} *',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _last,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: '${loc.lastName} *',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DobPickerField(
                      controller: _dob,
                      labelText: '${loc.dateOfBirth} *',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                      ),
                      validator: validatePatientEmail,
                    ),
                    const SizedBox(height: 14),
                    PhoneField(
                      controller: _phone,
                      labelText: 'Phone *',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _insurance,
                      decoration: InputDecoration(
                        labelText: '${loc.healthInsurance} *',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _address,
                      minLines: 2,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: '${loc.address} *',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

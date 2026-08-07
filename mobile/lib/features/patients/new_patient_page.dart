import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
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
  final _dob = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _insurance = TextEditingController();
  bool _loading = false;
  String? _error;

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
    setState(() => _dob.text = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.createPatient({
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'date_of_birth': _dob.text.trim(),
        'phone': PhoneNumbers.compose(_phone.text),
        'address': _address.text.trim(),
        'health_insurance': _insurance.text.trim(),
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
    _dob.dispose();
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
              OutlinedButton(
                onPressed: _loading
                    ? null
                    : () {
                        _formKey.currentState?.reset();
                        _first.clear();
                        _last.clear();
                        _dob.clear();
                        _phone.clear();
                        _address.clear();
                        _insurance.clear();
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
                label: Text(_loading ? 'Saving…' : loc.createPatient),
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
                    TextFormField(
                      controller: _dob,
                      readOnly: true,
                      onTap: _pickDob,
                      decoration: InputDecoration(
                        labelText: '${loc.dateOfBirth} *',
                        suffixIcon:
                            const Icon(Icons.calendar_today_outlined, size: 18),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
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

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _clinic = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'dentist';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _clinic.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final loc = AppLocalizations.of(context);
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = loc.errNameEmailPassword);
      return;
    }
    if (password.length < 6) {
      setState(() => _error = loc.errPasswordShort);
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = loc.errPasswordMismatch);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.register(
        email: email,
        name: name,
        password: password,
        role: _role,
        clinicName: _clinic.text.trim().isEmpty ? null : _clinic.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(
            api: widget.api,
            dentistName: data['name'] as String? ?? name,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: SectionCard(
              padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLogo(height: 64, scale: 1.15)),
                const SizedBox(height: 16),
                Text(
                  loc.registerTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  loc.registerSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(labelText: loc.fullName),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: '${loc.email} *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clinic,
                  decoration: InputDecoration(labelText: loc.clinic),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: loc.phone),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: InputDecoration(labelText: loc.role),
                  items: [
                    DropdownMenuItem(value: 'dentist', child: Text(loc.roleDentist)),
                    DropdownMenuItem(value: 'lab', child: Text(loc.roleLab)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: '${loc.password} *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: InputDecoration(labelText: '${loc.confirmPassword} *'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? loc.saving : loc.createProfile),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(loc.alreadyHaveAccount),
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

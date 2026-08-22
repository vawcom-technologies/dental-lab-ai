import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/app_page_routes.dart';
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
  bool _loading = false;
  String _role = AppRoles.dentist;

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
    final clinic = _clinic.text.trim();
    final phoneLocal = _phone.text.trim();
    final password = _password.text;
    final loc = AppLocalizations.of(context);
    if (name.isEmpty ||
        email.isEmpty ||
        clinic.isEmpty ||
        phoneLocal.isEmpty ||
        password.isEmpty ||
        _confirm.text.isEmpty) {
      AppSnackBars.error(context, loc.errAllFieldsRequired);
      return;
    }
    final phoneError = PhoneNumbers.validateRequired(
      phoneLocal,
      message: loc.errPhoneInvalid,
    );
    if (phoneError != null) {
      AppSnackBars.error(context, phoneError);
      return;
    }
    final normalizedPhone = PhoneNumbers.compose(phoneLocal);
    if (!PasswordValidator.isValid(password)) {
      AppSnackBars.error(context, loc.errPasswordShort);
      return;
    }
    if (password != _confirm.text) {
      AppSnackBars.error(context, loc.errPasswordMismatch);
      return;
    }
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final data = await widget.api.signUp(
        email: email,
        name: name,
        password: password,
        clinicName: clinic,
        phone: normalizedPhone,
        role: _role,
      );
      if (!mounted) return;

      final needsConfirmation = data['email_confirmation_required'] == true;
      final accessToken = data['access_token'] as String?;
      if (needsConfirmation || accessToken == null || accessToken.isEmpty) {
        final message = data['message'] as String? ??
            loc.emailConfirmationRequired;
        if (mounted) AppSnackBars.success(context, message);
        // Pending admin verification / email confirm — return to login
        Navigator.of(context).pop(<String, String>{
          'message': message,
          'email': email,
        });
        return;
      }

      Navigator.of(context).pushReplacement(
        AppPageRoutes.fade(
          AppShell(
            api: widget.api,
            dentistName: data['name'] as String? ?? name,
          ),
        ),
      );
    } catch (e) {
      final msg = friendlyError(e, AppLocalizations.of(context));
      if (mounted) AppSnackBars.error(context, msg);
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
                Center(
                  child: Transform.translate(
                    offset: const Offset(10, 0),
                    child: const BrandLogo(height: 64, scale: 1.15),
                  ),
                ),
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
                Text(
                  loc.role,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SoftPillButton(
                        label: loc.roleDentist,
                        selected: _role == AppRoles.dentist,
                        onPressed: _loading
                            ? null
                            : () => setState(() => _role = AppRoles.dentist),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SoftPillButton(
                        label: loc.roleLaboratory,
                        selected: _role == AppRoles.laboratory,
                        onPressed: _loading
                            ? null
                            : () =>
                                setState(() => _role = AppRoles.laboratory),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clinic,
                  decoration: InputDecoration(labelText: loc.clinic),
                ),
                const SizedBox(height: 12),
                PhoneField(
                  controller: _phone,
                  labelText: loc.phone,
                  errorMessage: loc.errPhoneInvalid,
                ),
                const SizedBox(height: 12),
                AppPasswordField(
                  controller: _password,
                  labelText: '${loc.password} *',
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 10),
                PasswordChecklist(password: _password.text),
                const SizedBox(height: 12),
                AppPasswordField(
                  controller: _confirm,
                  labelText: '${loc.confirmPassword} *',
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ||
                          !PasswordValidator.isValid(_password.text) ||
                          _password.text != _confirm.text
                      ? null
                      : _submit,
                  child: _loading
                      ? const ToothLoadingIndicator(
                          size: 20,
                          compact: true,
                          color: Colors.white,
                        )
                      : Text(loc.createProfile),
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

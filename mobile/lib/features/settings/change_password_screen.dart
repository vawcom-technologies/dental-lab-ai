import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_coordinator.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/ui_kit.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context);
    final current = _current.text;
    final next = _next.text;
    final confirm = _confirm.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _error = loc.errEnterPasswords);
      AppSnackBars.error(context, loc.errEnterPasswords);
      return;
    }
    if (!PasswordValidator.isValid(next)) {
      setState(() => _error = loc.errNewPasswordShort);
      AppSnackBars.error(context, loc.errNewPasswordShort);
      return;
    }
    if (next != confirm) {
      setState(() => _error = loc.errNewPasswordMismatch);
      AppSnackBars.error(context, loc.errNewPasswordMismatch);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final message = await widget.api.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;

      AppSnackBars.success(
        context,
        message.isNotEmpty ? message : loc.changePasswordSuccessBody,
      );

      await AppDialogs.alert(
        context,
        title: loc.passwordUpdated,
        message: message.isNotEmpty ? message : loc.changePasswordSuccessBody,
        okLabel: loc.ok,
      );

      if (!mounted) return;
      SessionCoordinator.signOut(
        widget.api,
        message: 'Password updated. Please log in again.',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.navy,
        elevation: 0,
        title: Text(loc.updatePassword),
      ),
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
                  const Center(child: BrandLogo(height: 56, scale: 1.1)),
                  const SizedBox(height: 16),
                  Text(
                    loc.security,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc.securitySub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  AppPasswordField(
                    controller: _current,
                    labelText: loc.currentPassword,
                    onChanged: (_) => setState(() {}),
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: 12),
                  AppPasswordField(
                    controller: _next,
                    labelText: loc.newPassword,
                    onChanged: (_) => setState(() {}),
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  const SizedBox(height: 10),
                  PasswordChecklist(password: _next.text),
                  const SizedBox(height: 12),
                  AppPasswordField(
                    controller: _confirm,
                    labelText: loc.confirmNewPassword,
                    onChanged: (_) => setState(() {}),
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) {
                      if (!_loading &&
                          PasswordValidator.isValid(_next.text) &&
                          _next.text == _confirm.text) {
                        _submit();
                      }
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ||
                            !PasswordValidator.isValid(_next.text) ||
                            _next.text != _confirm.text ||
                            _current.text.isEmpty
                        ? null
                        : _submit,
                    child: _loading
                        ? const ToothLoadingIndicator(
                            size: 20,
                            compact: true,
                            color: Colors.white,
                          )
                        : Text(loc.updatePassword),
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

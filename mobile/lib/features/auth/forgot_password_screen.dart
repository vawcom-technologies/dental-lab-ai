import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/ui_kit.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.api, this.initialEmail});

  final ApiClient api;
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context);
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = loc.errEmailRequired;
        _success = null;
      });
      return;
    }
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      final data = await widget.api.forgotPassword(email);
      if (!mounted) return;
      final msg = data['message'] as String? ??
          'If an account exists for that email, a password reset link has been sent.';
      setState(() => _success = msg);
      AppSnackBars.success(context, msg);
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyError(e, AppLocalizations.of(context));
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: SectionCard(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(height: 64, scale: 1.15)),
                  const SizedBox(height: 16),
                  Text(
                    loc.forgotPasswordTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc.forgotPasswordSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_loading && _success == null,
                    decoration: InputDecoration(labelText: loc.email),
                    onSubmitted: (_) {
                      if (!_loading && _success == null) _submit();
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  if (_success == null)
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: ToothLoadingIndicator(size: 28, compact: true, color: Colors.white),
                            )
                          : Text(loc.sendResetLink),
                    ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(loc.backToSignIn),
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

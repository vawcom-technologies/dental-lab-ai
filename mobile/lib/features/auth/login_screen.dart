import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_shell.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (_loading) return;
    AppHaptics.light();
    setState(() {
      _loading = true;
    });
    try {
      final data = await widget.api.signIn(_email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        AppPageRoutes.fade(
          AppShell(
            api: widget.api,
            dentistName: data['name'] as String? ?? 'Dentist',
          ),
        ),
      );
    } catch (e) {
      final msg = friendlyError(e, AppLocalizations.of(context));
      if (mounted) AppSnackBars.error(context, msg, haptic: false);
      AppHaptics.warn();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegister() async {
    final result = await Navigator.of(context).push<Object?>(
      AppPageRoutes.cupertino(RegisterScreen(api: widget.api)),
    );
    if (!mounted || result == null) return;

    if (result is Map) {
      final message = result['message']?.toString();
      final email = result['email']?.toString();
      if (email != null && email.isNotEmpty) {
        setState(() => _email.text = email);
      }
      if (message != null && message.isNotEmpty) {
        AppSnackBars.success(context, message);
      }
      return;
    }

    if (result is String && result.isNotEmpty) {
      AppSnackBars.success(context, result);
    }
  }

  void _fillDemo() {
    AppHaptics.selection();
    setState(() {
      _email.text = 'dentist@elitedent.demo';
      _password.text = 'demo1234';
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _setLanguage(String code) async {
    AppHaptics.selection();
    await LocaleScope.of(context).setLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final locale = LocaleScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF4A90E2),
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: const Offset(22, 0),
                      child: const BrandLogo(height: 156, scale: 1.35),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      loc.proEdition,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.loginHero,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: SectionCard(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(
                                child: BrandLogo(height: 72, scale: 1.2),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                loc.signIn,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                loc.signInSubtitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                              const SizedBox(height: 28),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                decoration:
                                    InputDecoration(labelText: loc.email),
                              ),
                              const SizedBox(height: 12),
                              AppPasswordField(
                                controller: _password,
                                labelText: loc.password,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                                enabled: !_loading,
                                autofillHints: const [AutofillHints.password],
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          Navigator.of(context).push(
                                            AppPageRoutes.cupertino(
                                              ForgotPasswordScreen(
                                                api: widget.api,
                                                initialEmail:
                                                    _email.text.trim(),
                                              ),
                                            ),
                                          );
                                        },
                                  child: Text(
                                    loc.forgotPassword,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const ToothLoadingIndicator(
                                        size: 20,
                                        compact: true,
                                        color: Colors.white,
                                      )
                                    : Text(loc.signIn),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _loading ? null : _openRegister,
                                child: Text(loc.createProfile),
                              ),
                              const SizedBox(height: 14),
                              TextButton(
                                onPressed: _loading ? null : _fillDemo,
                                child: Text(
                                  loc.useDemo,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 30,
                  right: 20,
                  child: SizedBox(
                    width: 120,
                    child: CupertinoSlidingSegmentedControl<String>(
                      groupValue: locale.code == 'de' ? 'de' : 'en',
                      backgroundColor: AppColors.inset,
                      thumbColor: Colors.white,
                      children: const {
                        'en': Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'EN',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        'de': Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'DE',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      },
                      onValueChanged: (code) {
                        if (code == null || _loading) return;
                        _setLanguage(code);
                      },
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

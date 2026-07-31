import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_shell.dart';
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
  String? _error;

  Future<void> _submit() async {
    AppHaptics.light();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(
            api: widget.api,
            dentistName: data['name'] as String? ?? 'Dentist',
          ),
        ),
      );
    } catch (e) {
      AppHaptics.warn();
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillDemo() {
    AppHaptics.selection();
    setState(() {
      _email.text = 'dentist@elitedent.demo';
      _password.text = 'demo1234';
      _error = null;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEAF1F8),
              AppColors.surface,
              Color(0xFFDCE6F2),
            ],
          ),
        ),
        child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.navy, Color(0xFF2A4A73), AppColors.dentalBlue],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const BrandLogo(height: 120, scale: 1.25),
                    const SizedBox(height: 20),
                    Text(
                      loc.proEdition,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.loginHero,
                      style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
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
                        const Center(child: BrandLogo(height: 72, scale: 1.2)),
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
                          decoration: InputDecoration(labelText: loc.email),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: InputDecoration(labelText: loc.password),
                          onSubmitted: (_) => _submit(),
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
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(loc.signIn),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          RegisterScreen(api: widget.api),
                                    ),
                                  );
                                },
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
        ],
      ),
      ),
    );
  }
}

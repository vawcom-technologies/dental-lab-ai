import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/layout/adaptive.dart';
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
    final phone = AppBreakpoints.isPhone(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: phone ? _phoneBody(loc) : _tabletBody(loc),
    );
  }

  Widget _languageSwitcher({required bool onHero}) {
    final locale = LocaleScope.of(context);
    return SizedBox(
      width: 120,
      child: CupertinoSlidingSegmentedControl<String>(
        groupValue: locale.code == 'de' ? 'de' : 'en',
        backgroundColor: onHero
            ? Colors.white.withValues(alpha: 0.28)
            : AppColors.inset,
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
    );
  }

  Widget _formFields(AppLocalizations loc, {required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          const Center(child: BrandLogo(height: 64)),
          const SizedBox(height: 16),
        ],
        Text(
          loc.signIn,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 22 : 24,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          loc.signInSubtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.35),
        ),
        SizedBox(height: compact ? 20 : 28),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: loc.email),
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
                          initialEmail: _email.text.trim(),
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
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _heroCopy(AppLocalizations loc, {required bool compact}) {
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        BrandLogo(height: compact ? 56 : 96),
        SizedBox(height: compact ? 10 : 20),
        Text(
          loc.proEdition,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          loc.loginHero,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: compact ? 13.5 : 15,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _phoneBody(AppLocalizations loc) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return ColoredBox(
      color: const Color(0xFF4A90E2),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: _languageSwitcher(onHero: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: _heroCopy(loc, compact: true),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + bottomInset),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    SectionCard(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                      child: _formFields(loc, compact: true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabletBody(AppLocalizations loc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF4A90E2),
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: _heroCopy(loc, compact: false),
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
                        child: _formFields(loc, compact: false),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 30,
                right: 20,
                child: _languageSwitcher(onHero: false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

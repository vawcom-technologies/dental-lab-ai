import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
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

  /// Required for dentists, optional for labs; can't be changed after
  /// signup (only the admin can).
  ({Uint8List bytes, String contentType})? _avatar;

  Future<void> _pickAvatar() async {
    try {
      final photo = await pickProfilePhoto(context);
      if (photo != null && mounted) setState(() => _avatar = photo);
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
    }
  }

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
    if (_avatar == null && _role == AppRoles.dentist) {
      AppSnackBars.error(context, loc.tr('avatar.required'));
      return;
    }
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
        avatar: _avatar,
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
      final loc = AppLocalizations.of(context);
      final msg = friendlyError(e, loc);
      if (!mounted) return;
      if (msg == loc.errRegistrationRejected) {
        AppDialogs.alert(context, title: loc.authRejectedTitle, message: msg);
      } else {
        AppSnackBars.error(context, msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final phone = AppBreakpoints.isPhone(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                phone ? 16 : 28,
                phone ? 12 : 28,
                phone ? 16 : 28,
                (phone ? 16 : 28) + bottomInset,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: SectionCard(
                padding: EdgeInsets.fromLTRB(
                  phone ? 18 : 26,
                  phone ? 20 : 26,
                  phone ? 18 : 26,
                  phone ? 16 : 20,
                ),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: BrandLogo(height: phone ? 48 : 64)),
                const SizedBox(height: 16),
                Text(
                  loc.registerTitle,
                  
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: phone ? 22 : 24,
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
                _AvatarPicker(
                  optional: _role == AppRoles.laboratory,
                  avatar: _avatar?.bytes,
                  onTap: _loading ? null : _pickAvatar,
                ),
                const SizedBox(height: 18),
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
      ),
    );
  }
}

/// Round photo slot with a camera badge; shows the chosen photo.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.avatar, required this.onTap, this.optional = false});

  /// Labs may skip the photo.
  final bool optional;

  final Uint8List? avatar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    const size = 104.0;
    return Column(
      children: [
        Pressable(
          onTap: onTap,
          scale: 0.94,
          builder: (_, _) => SizedBox(
            width: size + 8,
            height: size + 8,
            child: Stack(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: const Cubic(0.22, 1.0, 0.36, 1.0),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: Tween(begin: 0.85, end: 1.0).animate(a),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: Container(
                    key: ValueKey(avatar?.length ?? 0),
                    width: size,
                    height: size,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.dentalBlue.withValues(alpha: 0.10),
                      border: Border.all(
                        color: avatar == null ? AppColors.dentalBlue.withValues(alpha: 0.35) : Colors.white,
                        width: 2,
                      ),
                      image: avatar == null
                          ? null
                          : DecorationImage(image: MemoryImage(avatar!), fit: BoxFit.cover),
                    ),
                    child: avatar == null
                        ? const Icon(Icons.person_rounded, size: 52, color: AppColors.dentalBlue)
                        : null,
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: Icon(
                      avatar == null ? Icons.photo_camera_rounded : Icons.edit_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          loc.tr(avatar == null ? 'avatar.add' : 'avatar.retake'),
          style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dentalBlue),
        ),
        const SizedBox(height: 2),
        Text(
          loc.tr(optional ? 'avatar.optionalLab' : 'avatar.permanent'),
          textAlign: TextAlign.center,
          style: AppFonts.style(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

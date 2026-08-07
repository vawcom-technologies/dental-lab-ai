import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.api,
    required this.onProfileUpdated,
    required this.onSignOut,
  });

  final ApiClient api;
  final ValueChanged<String> onProfileUpdated;
  final VoidCallback onSignOut;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _clinic = TextEditingController();
  final _phone = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  String _role = '—';
  String? _createdAt;
  String? _lastLogin;

  bool _loading = true;
  bool _saving = false;
  bool _changingPassword = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _clinic.dispose();
    _phone.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    if (s.length >= 19) return s.substring(0, 19).replaceFirst('T', ' ');
    return s;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await widget.api.fetchMe();
      _name.text = me['name']?.toString() ?? '';
      _email.text = me['email']?.toString() ?? '';
      _clinic.text = me['clinic_name']?.toString() ?? '';
      _phone.text = PhoneNumbers.localDigits(me['phone']?.toString());
      _role = AppRoles.label(me['role']?.toString());
      if (_role.isEmpty) _role = '—';
      _createdAt = _fmt(me['created_at']);
      _lastLogin = _fmt(me['last_login']);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty) {
      final msg = AppLocalizations.of(context).errNameEmailRequired;
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
      return;
    }
    final loc = AppLocalizations.of(context);
    final phoneError = PhoneNumbers.validateRequired(
      _phone.text,
      message: loc.errPhoneInvalid,
    );
    if (phoneError != null) {
      setState(() => _error = phoneError);
      AppSnackBars.error(context, phoneError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      final updated = await widget.api.updateProfile(
        name: name,
        email: email,
        clinicName: _clinic.text.trim(),
        phone: PhoneNumbers.compose(_phone.text),
      );
      if (!mounted) return;
      widget.onProfileUpdated(updated['name']?.toString() ?? name);
      final msg = AppLocalizations.of(context).profileSaved;
      setState(() => _status = msg);
      AppSnackBars.success(context, msg);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePassword() async {
    if (_changingPassword) return;
    final current = _currentPassword.text;
    final next = _newPassword.text;
    final confirm = _confirmPassword.text;
    if (current.isEmpty || next.isEmpty) {
      final msg = AppLocalizations.of(context).errEnterPasswords;
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
      return;
    }
    if (!PasswordValidator.isValid(next)) {
      final msg = AppLocalizations.of(context).errNewPasswordShort;
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
      return;
    }
    if (next != confirm) {
      final msg = AppLocalizations.of(context).errNewPasswordMismatch;
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
      return;
    }
    setState(() {
      _changingPassword = true;
      _error = null;
      _status = null;
    });
    try {
      await widget.api.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      final msg = AppLocalizations.of(context).passwordUpdated;
      setState(() => _status = msg);
      AppSnackBars.success(context, msg);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (_loading) return const ToothPageLoader(message: 'Loading profile…');

    final displayName = _name.text.trim().isEmpty ? 'User' : _name.text.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.person_outline,
            title: loc.profileTitle,
            subtitle: loc.profileSubtitle,
            actions: [
              OutlinedButton.icon(
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout, size: 18),
                label: Text(loc.signOut),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: const TextStyle(color: AppColors.success)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SectionCard(
                    child: ListView(
                      children: [
                        Row(
                          children: [
                            InitialsAvatar(name: displayName, size: 64),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _email.text,
                                    style: const TextStyle(color: AppColors.muted),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.sidebarActive,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _role.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _name,
                          decoration: InputDecoration(labelText: loc.fullName),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: '${loc.email} *'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _clinic,
                          decoration: InputDecoration(
                            labelText: loc.clinic,
                            hintText: loc.clinicHint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        PhoneField(
                          controller: _phone,
                          labelText: loc.phone,
                          errorMessage: loc.errPhoneInvalid,
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _saveProfile,
                            icon: _saving
                                ? const ToothLoadingIndicator(
                                    size: 18,
                                    compact: true,
                                    color: Colors.white,
                                  )
                                : const Icon(Icons.save_outlined, size: 18),
                            label: Text(
                              _saving ? loc.saving : loc.saveProfile,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: SectionCard(
                          child: ListView(
                            children: [
                              Text(
                                loc.security,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                loc.securitySub,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _currentPassword,
                                obscureText: true,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: loc.currentPassword,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _newPassword,
                                obscureText: true,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: loc.newPassword,
                                ),
                              ),
                              const SizedBox(height: 10),
                              PasswordChecklist(password: _newPassword.text),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPassword,
                                obscureText: true,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: loc.confirmNewPassword,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: _changingPassword ||
                                          !PasswordValidator.isValid(
                                            _newPassword.text,
                                          ) ||
                                          _newPassword.text !=
                                              _confirmPassword.text ||
                                          _currentPassword.text.isEmpty
                                      ? null
                                      : _savePassword,
                                  icon: _changingPassword
                                      ? const ToothLoadingIndicator(
                                          size: 16,
                                          compact: true,
                                          color: Colors.white,
                                        )
                                      : const Icon(Icons.lock_outline, size: 18),
                                  label: Text(
                                    _changingPassword
                                        ? loc.updating
                                        : loc.updatePassword,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    ],
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



class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

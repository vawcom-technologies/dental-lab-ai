import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Password complexity rules shared by registration and password update flows.
class PasswordValidator {
  PasswordValidator._();

  static bool hasMinLength(String password) => password.length >= 8;

  static bool hasUppercase(String password) =>
      RegExp(r'[A-Z]').hasMatch(password);

  static bool hasNumber(String password) =>
      RegExp(r'[0-9]').hasMatch(password);

  static bool isValid(String password) {
    return hasMinLength(password) &&
        hasUppercase(password) &&
        hasNumber(password);
  }
}

/// Real-time visual checklist for [PasswordValidator] rules.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({
    super.key,
    required this.password,
  });

  final String password;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RuleRow(
          label: 'At least 8 characters',
          met: PasswordValidator.hasMinLength(password),
        ),
        const SizedBox(height: 6),
        _RuleRow(
          label: 'At least one uppercase letter',
          met: PasswordValidator.hasUppercase(password),
        ),
        const SizedBox(height: 6),
        _RuleRow(
          label: 'At least one number',
          met: PasswordValidator.hasNumber(password),
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.success : AppColors.muted;
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.circle_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: met ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// German mobile numbers: fixed country code `+49` + exactly 11 subscriber digits.
class PhoneNumbers {
  PhoneNumbers._();

  static const prefix = '+49';
  static const digitCount = 11;
  static final RegExp fullPattern = RegExp(r'^\+49\d{11}$');
  static final RegExp _nonDigits = RegExp(r'\D');

  static String digitsOnly(String raw) => raw.replaceAll(_nonDigits, '');

  /// Digits for the input field (without the fixed `+49` prefix).
  static String localDigits(String? stored) {
    if (stored == null || stored.trim().isEmpty) return '';
    var digits = digitsOnly(stored);
    if (digits.startsWith('49') && digits.length > digitCount) {
      digits = digits.substring(2);
    }
    if (digits.length > digitCount) {
      digits = digits.substring(0, digitCount);
    }
    return digits;
  }

  /// Full E.164-style value stored/sent to the API: `+49` + 11 digits.
  static String compose(String local) => '$prefix${digitsOnly(local)}';

  static bool isValidLocal(String? local) =>
      RegExp(r'^\d{11}$').hasMatch(digitsOnly(local ?? ''));

  static bool isValidFull(String? value) {
    if (value == null) return false;
    final normalized = value.replaceAll(RegExp(r'[\s\-]'), '');
    return fullPattern.hasMatch(normalized);
  }

  static String? validateRequired(
    String? local, {
    String message =
        'Phone must start with +49 and have exactly 11 digits after',
  }) {
    if (!isValidLocal(local)) return message;
    return null;
  }

  static String? validateOptional(
    String? local, {
    String message =
        'Phone must start with +49 and have exactly 11 digits after',
  }) {
    final digits = digitsOnly(local ?? '');
    if (digits.isEmpty) return null;
    if (digits.length != digitCount) return message;
    return null;
  }
}

/// Phone input with a locked `+49` prefix; user enters exactly 11 digits.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.labelText = 'Phone',
    this.hintText = '17012345678',
    this.required = true,
    this.enabled = true,
    this.errorMessage =
        'Phone must start with +49 and have exactly 11 digits after',
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final bool required;
  final bool enabled;
  final String errorMessage;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(PhoneNumbers.digitCount),
      ],
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixText: '${PhoneNumbers.prefix} ',
        prefixStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
      ),
      onChanged: onChanged,
      validator: (value) => required
          ? PhoneNumbers.validateRequired(value, message: errorMessage)
          : PhoneNumbers.validateOptional(value, message: errorMessage),
    );
  }
}

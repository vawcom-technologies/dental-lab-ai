import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_buttons.dart';
import 'app_dialogs.dart';

/// Asks for text that must not be empty (rejection remarks, removal
/// reasons). The confirm button stays disabled until something is typed.
/// Returns the trimmed text, or null when cancelled.
Future<String?> askRequiredText(
  BuildContext context, {
  required String title,
  required String message,
  required String hint,
  required String confirmLabel,
  bool destructive = false,
}) {
  return AppDialogs.sheet<String>(
    context: context,
    builder: (_) => _RequiredTextSheet(
      title: title,
      message: message,
      hint: hint,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
}

class _RequiredTextSheet extends StatefulWidget {
  const _RequiredTextSheet({
    required this.title,
    required this.message,
    required this.hint,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title, message, hint, confirmLabel;
  final bool destructive;

  @override
  State<_RequiredTextSheet> createState() => _RequiredTextSheetState();
}

class _RequiredTextSheetState extends State<_RequiredTextSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final ok = _text.text.trim().isNotEmpty;
    void done() => Navigator.pop(context, _text.text.trim());
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title,
                style: AppFonts.style(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
            const SizedBox(height: 6),
            Text(widget.message, style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: widget.hint),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButtons.ghost(onPressed: () => Navigator.pop(context), label: loc.cancel),
                const SizedBox(width: 8),
                widget.destructive
                    ? AppButtons.danger(onPressed: ok ? done : null, icon: Icons.close_rounded, label: widget.confirmLabel)
                    : AppButtons.primary(onPressed: ok ? done : null, label: widget.confirmLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

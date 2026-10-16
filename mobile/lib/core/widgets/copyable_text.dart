import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../haptics/app_haptics.dart';
import '../l10n/app_localizations.dart';
import 'app_snackbar.dart';

/// Text that copies itself on long-press. Used instead of SelectableText,
/// whose long-press word selection can crash (null check in
/// RenderEditable.selectWord) inside single-line rows and animated sheets.
class CopyableText extends StatelessWidget {
  const CopyableText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: text));
        AppHaptics.light();
        if (context.mounted) {
          AppSnackBars.info(context, AppLocalizations.of(context).tr('c.copied'));
        }
      },
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

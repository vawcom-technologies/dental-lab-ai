import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/glass_surface.dart';

ButtonStyle compactActionFilled(Color bg, {double minH = 34, double fontSize = 11}) =>
    AppButtons.primaryStyle(compact: true).merge(
      FilledButton.styleFrom(
        backgroundColor: bg,
        minimumSize: Size(0, minH),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
        overlayColor: Colors.white.withValues(alpha: 0.14),
        textStyle: AppFonts.style(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );

ButtonStyle compactActionOutlined({
  required Color fg,
  required Color side,
  double minH = 34,
  double fontSize = 11,
}) =>
    AppButtons.secondaryStyle(compact: true).merge(
      OutlinedButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: Colors.white.withValues(alpha: 0.45),
        side: BorderSide(color: side),
        minimumSize: Size(0, minH),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
        overlayColor: fg.withValues(alpha: 0.08),
        textStyle: AppFonts.style(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );

class ShadeActionBar extends StatelessWidget {
  const ShadeActionBar({
    super.key,
    required this.editOutlineMode,
    required this.hasPreview,
    required this.canEditTooth,
    required this.onCancel,
    required this.onReset,
    required this.onApply,
    required this.onAdjustEdges,
    required this.onDelete,
    required this.onAddTooth,
    required this.onUpload,
    required this.maxWidth,
  });

  final bool editOutlineMode;
  final bool hasPreview;
  final bool canEditTooth;
  final VoidCallback onCancel;
  final VoidCallback onReset;
  final VoidCallback onApply;
  final VoidCallback onAdjustEdges;
  final VoidCallback onDelete;
  final VoidCallback onAddTooth;
  final VoidCallback onUpload;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final wide = maxWidth >= 520;
    final gap = wide ? 10.0 : 6.0;
    final iconSize = wide ? 16.0 : 14.0;
    final fontSize = wide ? 13.0 : 11.0;
    final minH = wide ? 42.0 : 36.0;
    final padH = wide ? 14.0 : 10.0;
    final padV = wide ? 10.0 : 8.0;

    Widget label(String text) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, maxLines: 1, softWrap: false),
        );

    final Row actions;
    if (editOutlineMode) {
      actions = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: compactActionOutlined(
                fg: AppColors.navy,
                side: AppColors.border,
                minH: minH,
                fontSize: fontSize,
              ),
              child: label('Cancel'),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: OutlinedButton(
              onPressed: onReset,
              style: compactActionOutlined(
                fg: AppColors.muted,
                side: AppColors.border,
                minH: minH,
                fontSize: fontSize,
              ),
              child: label('Reset'),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: onApply,
              icon: Icon(Icons.check, size: iconSize),
              label: label('Apply'),
              style: compactActionFilled(
                AppColors.dentalBlue,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      );
    } else {
      actions = Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: canEditTooth ? onAdjustEdges : null,
              icon: Icon(Icons.open_with, size: iconSize),
              label: label('Adjust edges'),
              style: compactActionFilled(
                AppColors.navy,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canEditTooth ? onDelete : null,
              icon: Icon(Icons.delete_outline, size: iconSize),
              label: label('Delete'),
              style: compactActionOutlined(
                fg: AppColors.danger,
                side: AppColors.danger,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onAddTooth,
              icon: Icon(Icons.add, size: iconSize),
              label: label('Add tooth'),
              style: compactActionOutlined(
                fg: AppColors.navy,
                side: AppColors.navy,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: FilledButton.icon(
              onPressed: onUpload,
              icon: Icon(Icons.upload_file, size: iconSize),
              label: label(hasPreview ? 'Re-upload' : 'Upload'),
              style: compactActionFilled(
                AppColors.dentalBlue,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      );
    }

    return GlassSurface(
      borderRadius: BorderRadius.circular(14),
      blur: 16,
      tint: Colors.white.withValues(alpha: 0.52),
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      child: actions,
    );
  }
}

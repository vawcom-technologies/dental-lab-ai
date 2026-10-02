import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_shared.dart';
import 'tooth_overlay.dart';
import '../../core/l10n/app_localizations.dart';

/// Claims drag on a vertex handle or mid-edge curve grip.
class OutlineEditDragRecognizer extends PanGestureRecognizer {
  OutlineEditDragRecognizer() {
    // Pick the handle where the finger landed, and start moving after ~8 px.
    // Default pan slop (~36 px) made handles feel stuck, and the grab was
    // resolved at the slop point — often a neighbouring handle.
    dragStartBehavior = DragStartBehavior.down;
    gestureSettings = const DeviceGestureSettings(touchSlop: 4);
  }

  /// 'v' = vertex index, 'e' = edge index.
  ({String kind, int index})? Function(Offset local)? hitAt;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      hitAt?.call(event.localPosition) != null &&
      super.isPointerAllowed(event);
}

class ShadePhotoPane extends StatelessWidget {
  const ShadePhotoPane({
    super.key,
    required this.previewBytes,
    required this.busy,
    required this.editOutlineMode,
    required this.teeth,
    required this.selectedToothIndex,
    required this.analysisImageSize,
    required this.focusZone,
    required this.editOutline,
    required this.editBulges,
    required this.activeHandleIndex,
    required this.activeEdgeIndex,
    required this.photoTransformController,
    required this.dragTick,
    required this.canUndo,
    required this.canRedo,
    required this.onUpload,
    required this.onClearPhoto,
    required this.onSelectTooth,
    required this.onHandleDragStart,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
    required this.onEdgeDoubleTap,
    required this.onUndo,
    required this.onRedo,
    this.guideLines = const {},
    this.symmetryView = false,
    this.onToggleSymmetry,
    this.focusSelected = false,
    this.onToggleFocus,
    this.fullscreen = false,
    this.onToggleFullscreen,
  });

  final Uint8List? previewBytes;
  final bool busy;
  final bool editOutlineMode;
  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  final Size analysisImageSize;
  final String focusZone;
  final Map<String, List<List<double>>> guideLines;
  final bool symmetryView;
  final VoidCallback? onToggleSymmetry;
  /// Photo shows only the selected tooth; null [onToggleFocus] = disabled.
  final bool focusSelected;
  final VoidCallback? onToggleFocus;
  /// Shown full screen (expand ↔ exit icon); null toggle = no photo yet.
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;
  final List<List<double>>? editOutline;
  final List<double>? editBulges;
  final int? activeHandleIndex;
  final int? activeEdgeIndex;
  final TransformationController photoTransformController;
  final ValueNotifier<int> dragTick;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUpload;
  final VoidCallback onClearPhoto;
  final ValueChanged<int> onSelectTooth;
  final void Function(Offset local, Size box) onHandleDragStart;
  final void Function(Offset local, Size box) onHandleDragUpdate;
  final VoidCallback onHandleDragEnd;
  final void Function(Offset local, Size box) onEdgeDoubleTap;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  Future<void> _showIpadPhotoActions(BuildContext context) async {
    AppHaptics.selection();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(AppLocalizations.of(context).shadePhotoTitle),
        message: Text(AppLocalizations.of(context).shadePhotoMessage),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              onUpload();
            },
            child: Text(AppLocalizations.of(context).shadeUploadAnother),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              onClearPhoto();
            },
            child: Text(AppLocalizations.of(context).shadeDeletePhoto),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(AppLocalizations.of(context).cancel),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      depth: 0,
      boxShadow: kShadeCardGlow,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.border,
        child: Container(
          color: const Color(0xFF15263F),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (previewBytes != null)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final box = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final imgSize = analysisImageSize == Size.zero
                          ? box
                          : analysisImageSize;

                      void selectAtViewport(Offset viewportLocal) {
                        if (editOutlineMode || busy || teeth.isEmpty) return;
                        // Tap is outside InteractiveViewer — map into scene.
                        final scene =
                            photoTransformController.toScene(viewportLocal);
                        final hit = hitTestTooth(
                          local: scene,
                          box: box,
                          imageSize: imgSize,
                          teeth: teeth,
                          preferIndex: selectedToothIndex,
                        );
                        if (hit != null) onSelectTooth(hit);
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: editOutlineMode || busy
                            ? null
                            : (details) =>
                                selectAtViewport(details.localPosition),
                        onLongPress: editOutlineMode || busy
                            ? null
                            : () => _showIpadPhotoActions(context),
                        child: InteractiveViewer(
                          transformationController: photoTransformController,
                          minScale: 1,
                          maxScale: 4,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                previewBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.high,
                              ),
                              if (teeth.isNotEmpty && !busy)
                                Positioned.fill(
                                  child: Builder(
                                    builder: (context) {
                                      ({String kind, int index})? hitAt(
                                        Offset local,
                                      ) {
                                        final outline = editOutline;
                                        if (outline == null) return null;
                                        final scale = photoTransformController
                                            .value
                                            .getMaxScaleOnAxis()
                                            .clamp(1.0, 4.0);
                                        if (hitTestGuideHandle(
                                              local: local,
                                              box: box,
                                              imageSize: imgSize,
                                              guides: guideLines,
                                              radius: 28 / scale,
                                            ) !=
                                            null) {
                                          return (kind: 'g', index: 0);
                                        }
                                        return hitTestOutlineEditTarget(
                                          local: local,
                                          box: box,
                                          imageSize: imgSize,
                                          outline: outline,
                                          bulges: editBulges,
                                          radius: 28 / scale,
                                        );
                                      }

                                      final paint = RepaintBoundary(
                                        child: CustomPaint(
                                          painter: ToothOverlayPainter(
                                            repaint: Listenable.merge([
                                              dragTick,
                                              photoTransformController,
                                            ]),
                                            teeth: teeth,
                                            selectedToothIndex:
                                                selectedToothIndex,
                                            imageSize: imgSize,
                                            focusZone: focusZone,
                                            guideLines: guideLines,
                                            symmetryView: symmetryView,
                                            focusSelected: focusSelected,
                                            editMode: editOutlineMode,
                                            editOutline: editOutline,
                                            editBulges: editBulges,
                                            activeHandleIndex: activeHandleIndex,
                                            activeEdgeIndex: activeEdgeIndex,
                                            transformationController:
                                                photoTransformController,
                                          ),
                                        ),
                                      );

                                      if (!editOutlineMode) return paint;

                                      return RawGestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        gestures: <Type,
                                            GestureRecognizerFactory>{
                                          OutlineEditDragRecognizer:
                                              GestureRecognizerFactoryWithHandlers<
                                                  OutlineEditDragRecognizer>(
                                            OutlineEditDragRecognizer.new,
                                            (r) => r
                                              ..hitAt = hitAt
                                              ..onStart = (details) {
                                                if (editOutline == null) {
                                                  return;
                                                }
                                                if (hitAt(
                                                      details.localPosition,
                                                    ) ==
                                                    null) {
                                                  return;
                                                }
                                                onHandleDragStart(
                                                  details.localPosition,
                                                  box,
                                                );
                                              }
                                              ..onUpdate = (details) {
                                                onHandleDragUpdate(
                                                  details.localPosition,
                                                  box,
                                                );
                                              }
                                              ..onEnd = (_) {
                                                onHandleDragEnd();
                                              }
                                              ..onCancel = onHandleDragEnd,
                                          ),
                                          DoubleTapGestureRecognizer:
                                              GestureRecognizerFactoryWithHandlers<
                                                  DoubleTapGestureRecognizer>(
                                            DoubleTapGestureRecognizer.new,
                                            (r) => r.onDoubleTapDown = (d) {
                                              // Double-tap adds outline points;
                                              // guides (midline/lips) don't.
                                              final h = hitAt(d.localPosition);
                                              if (h == null || h.kind == 'g') {
                                                return;
                                              }
                                              onEdgeDoubleTap(
                                                d.localPosition,
                                                box,
                                              );
                                            },
                                          ),
                                        },
                                        child: paint,
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Colors.white54,
                        size: 44,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        AppLocalizations.of(context).shadeUploadCloseUp,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              if (busy)
                Container(
                  color: Colors.black45,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ToothLoadingIndicator(
                            size: 48,
                            color: Colors.white,
                            compact: true,
                          ),
                          const SizedBox(height: 14),
                          RotatingLoadingText(
                            messages:
                                AppLocalizations.of(context).shadeWaitTips,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black54),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (teeth.isNotEmpty && !busy)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Text(
                    editOutlineMode
                        ? 'Hold inside the outline and drag to move it · corners reshape · mid-edge curves · Apply.'
                        : 'Pinch to zoom · Tap to select · Press & hold for photo actions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: editOutlineMode ? 13 : 12,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              if (!busy && (teeth.isEmpty || selectedToothIndex == null))
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: teeth.isEmpty ? 16 : 48,
                  child: FilledButton.icon(
                    onPressed: onUpload,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(
                      previewBytes == null
                          ? AppLocalizations.of(context).shadeUploadToothPhoto
                          : AppLocalizations.of(context).shadeUploadAnother,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.dentalBlue,
                    ),
                  ),
                ),
              if (teeth.isNotEmpty && !busy && !editOutlineMode)
                Positioned(
                  top: 10,
                  left: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ViewToggle(
                          on: symmetryView,
                          tooltip: AppLocalizations.of(context).shadeSymmetry,
                          icon: Icons.vertical_split_outlined,
                          onPressed: onToggleSymmetry,
                        ),
                        _ViewToggle(
                          on: focusSelected,
                          tooltip: AppLocalizations.of(context).shadeFocusTooth,
                          icon: Icons.center_focus_strong_outlined,
                          onPressed: onToggleFocus,
                        ),
                        _ViewToggle(
                          on: false,
                          tooltip: fullscreen
                              ? AppLocalizations.of(context).commonExitFullscreen
                              : AppLocalizations.of(context).commonFullscreen,
                          icon: fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          onPressed: onToggleFullscreen,
                        ),
                      ],
                    ),
                  ),
                ),
              if (editOutlineMode || canUndo || canRedo)
                Positioned(
                  top: 10,
                  right: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: AppLocalizations.of(context).commonUndo,
                          onPressed: canUndo ? onUndo : null,
                          icon: const Icon(Icons.undo_rounded),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                        ),
                        if (editOutlineMode)
                          IconButton(
                            tooltip: AppLocalizations.of(context).commonRedo,
                            onPressed: canRedo ? onRedo : null,
                            icon: const Icon(Icons.redo_rounded),
                            color: Colors.white,
                            disabledColor: Colors.white38,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Photo view toggle (symmetry / selected tooth): blue when on.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.on,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final bool on;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: Colors.white,
        disabledColor: Colors.white38,
        style: on
            ? IconButton.styleFrom(
                backgroundColor: AppColors.dentalBlue.withValues(alpha: 0.85),
              )
            : null,
      );
}

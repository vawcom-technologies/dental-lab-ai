import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_shared.dart';
import 'tooth_overlay.dart';

/// Claims drag on a vertex handle or mid-edge curve grip.
class OutlineEditDragRecognizer extends PanGestureRecognizer {
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
    required this.photoMenuVisible,
    required this.editOutlineMode,
    required this.teeth,
    required this.selectedToothIndex,
    this.isolatedToothIndex,
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
    required this.onShowPhotoMenu,
    required this.onHidePhotoMenu,
    required this.onUpload,
    required this.onClearPhoto,
    required this.onSelectTooth,
    required this.onHandleDragStart,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
    required this.onEdgeDoubleTap,
    required this.onUndo,
    required this.onRedo,
  });

  final Uint8List? previewBytes;
  final bool busy;
  final bool photoMenuVisible;
  final bool editOutlineMode;
  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  final int? isolatedToothIndex;
  final Size analysisImageSize;
  final String focusZone;
  final List<List<double>>? editOutline;
  final List<double>? editBulges;
  final int? activeHandleIndex;
  final int? activeEdgeIndex;
  final TransformationController photoTransformController;
  final ValueNotifier<int> dragTick;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onShowPhotoMenu;
  final VoidCallback onHidePhotoMenu;
  final VoidCallback onUpload;
  final VoidCallback onClearPhoto;
  final ValueChanged<int> onSelectTooth;
  final void Function(Offset local, Size box) onHandleDragStart;
  final void Function(Offset local, Size box) onHandleDragUpdate;
  final VoidCallback onHandleDragEnd;
  final void Function(Offset local, Size box) onEdgeDoubleTap;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

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
                            : () {
                                AppHaptics.selection();
                                onShowPhotoMenu();
                              },
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
                                filterQuality: FilterQuality.low,
                              ),
                              if (teeth.isNotEmpty && !busy)
                                Positioned.fill(
                                  child: Builder(
                                    builder: (context) {
                                      int? handleAt(Offset local) {
                                        final outline = editOutline;
                                        if (outline == null) return null;
                                        final scale = photoTransformController
                                            .value
                                            .getMaxScaleOnAxis()
                                            .clamp(1.0, 4.0);
                                        return hitTestOutlineHandle(
                                          local: local,
                                          box: box,
                                          imageSize: imgSize,
                                          outline: outline,
                                          radius: 32 / scale,
                                        );
                                      }

                                      ({String kind, int index})? hitAt(
                                        Offset local,
                                      ) {
                                        final outline = editOutline;
                                        if (outline == null) return null;
                                        final scale = photoTransformController
                                            .value
                                            .getMaxScaleOnAxis()
                                            .clamp(1.0, 4.0);
                                        final hi = handleAt(local);
                                        if (hi != null) {
                                          return (kind: 'v', index: hi);
                                        }
                                        final ei = hitTestOutlineEdge(
                                          local: local,
                                          box: box,
                                          imageSize: imgSize,
                                          outline: outline,
                                          maxDist: 22 / scale,
                                        );
                                        if (ei != null) {
                                          return (kind: 'e', index: ei);
                                        }
                                        return null;
                                      }

                                      final paint = CustomPaint(
                                        painter: ToothOverlayPainter(
                                          repaint: Listenable.merge([
                                            dragTick,
                                            photoTransformController,
                                          ]),
                                          teeth: teeth,
                                          selectedToothIndex:
                                              selectedToothIndex,
                                          isolatedToothIndex:
                                              isolatedToothIndex,
                                          imageSize: imgSize,
                                          focusZone: focusZone,
                                          editMode: editOutlineMode,
                                          editOutline: editOutline,
                                          editBulges: editBulges,
                                          activeHandleIndex: activeHandleIndex,
                                          activeEdgeIndex: activeEdgeIndex,
                                          transformationController:
                                              photoTransformController,
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
                                              if (hitAt(d.localPosition) ==
                                                  null) {
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
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Colors.white54,
                        size: 44,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Upload a close-up tooth/smile photo',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              if (busy)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Analyzing shade…',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (photoMenuVisible && previewBytes != null && !busy)
                Positioned.fill(
                  child: Material(
                    color: Colors.black54,
                    child: InkWell(
                      onTap: onHidePhotoMenu,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton.icon(
                                onPressed: () {
                                  onHidePhotoMenu();
                                  onUpload();
                                },
                                icon: const Icon(Icons.upload_file, size: 18),
                                label: const Text('Upload another'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.dentalBlue,
                                  minimumSize: const Size.fromHeight(44),
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: onClearPhoto,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                label: const Text('Delete photo'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  minimumSize: const Size.fromHeight(44),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                        ? 'Drag corners · hold mid-edge to curve · double-tap edge to add a point · Apply.'
                        : 'Pinch to zoom · Tap to select · Triple-tap to show only that tooth.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
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
                          ? 'Upload tooth photo'
                          : 'Upload another',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.dentalBlue,
                    ),
                  ),
                ),
              if (editOutlineMode)
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
                          tooltip: 'Undo',
                          onPressed: canUndo ? onUndo : null,
                          icon: const Icon(Icons.undo_rounded),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                        ),
                        IconButton(
                          tooltip: 'Redo',
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

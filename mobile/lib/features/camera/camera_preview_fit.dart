import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Same orientation source [CameraPreview] uses for its inner AspectRatio.
DeviceOrientation applicableCameraOrientation({
  required DeviceOrientation deviceOrientation,
  required bool isRecordingVideo,
  DeviceOrientation? recordingOrientation,
  DeviceOrientation? previewPauseOrientation,
  DeviceOrientation? lockedCaptureOrientation,
}) {
  if (isRecordingVideo && recordingOrientation != null) {
    return recordingOrientation;
  }
  return previewPauseOrientation ??
      lockedCaptureOrientation ??
      deviceOrientation;
}

bool isLandscapeDeviceOrientation(DeviceOrientation orientation) {
  return orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;
}

/// Size of the live feed after [CameraPreview] swaps axes in portrait.
///
/// [previewSize] is the camera plugin's sensor/preview size (usually landscape).
Size displayedPreviewSize(Size previewSize, {required bool landscape}) {
  if (previewSize.width <= 0 || previewSize.height <= 0) return previewSize;
  return landscape
      ? previewSize
      : Size(previewSize.height, previewSize.width);
}

/// Uniform scale-to-cover box: at least as large as [viewport], same aspect as
/// [source], so the feed fills 11" / 13" iPads without stretching.
Size coverDestinationSize(Size source, Size viewport) {
  if (source.width <= 0 ||
      source.height <= 0 ||
      viewport.width <= 0 ||
      viewport.height <= 0) {
    return viewport;
  }
  final scale = math.max(
    viewport.width / source.width,
    viewport.height / source.height,
  );
  return Size(source.width * scale, source.height * scale);
}

/// Fraction of [source] visible after BoxFit.cover into [viewport] (centered).
Rect coverVisibleFraction(Size source, Size viewport) {
  final dest = coverDestinationSize(source, viewport);
  if (dest.width <= 0 || dest.height <= 0) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  final left = ((dest.width - viewport.width) / 2).clamp(0.0, dest.width);
  final top = ((dest.height - viewport.height) / 2).clamp(0.0, dest.height);
  return Rect.fromLTWH(
    left / dest.width,
    top / dest.height,
    (viewport.width / dest.width).clamp(0.0, 1.0),
    (viewport.height / dest.height).clamp(0.0, 1.0),
  );
}

/// Map a viewport-normalized guide onto the full oriented image.
Rect mapGuideToImage({required Rect guide, required Rect visible}) {
  return Rect.fromLTRB(
    visible.left + guide.left * visible.width,
    visible.top + guide.top * visible.height,
    visible.left + guide.right * visible.width,
    visible.top + guide.bottom * visible.height,
  );
}

/// Center-crop [size] to [targetAspect] (width / height).
Rect centerCropToAspect(Size size, double targetAspect) {
  if (size.width < 1 || size.height < 1 || targetAspect <= 0) {
    return Offset.zero & size;
  }
  final current = size.width / size.height;
  if ((current - targetAspect).abs() < 0.01) {
    return Offset.zero & size;
  }
  if (current > targetAspect) {
    final w = size.height * targetAspect;
    return Rect.fromLTWH((size.width - w) / 2, 0, w, size.height);
  }
  final h = size.width / targetAspect;
  return Rect.fromLTWH(0, (size.height - h) / 2, size.width, h);
}

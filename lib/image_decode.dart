import 'dart:math' as math;

/// Returns a bounded pixel dimension suitable for a thumbnail decode.
int thumbnailDecodeDimension({
  required double logicalWidth,
  required double logicalHeight,
  required double devicePixelRatio,
  int minDimension = 64,
  int maxDimension = 1600,
}) {
  final width = logicalWidth.isFinite ? logicalWidth : 0;
  final height = logicalHeight.isFinite ? logicalHeight : 0;
  final dpr = devicePixelRatio.isFinite ? devicePixelRatio : 1;
  final logicalMax = math.max(width, height);
  final requested = (logicalMax * dpr).round();
  return requested.clamp(minDimension, maxDimension).toInt();
}

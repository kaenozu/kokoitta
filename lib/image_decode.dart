import 'dart:math' as math;

/// Returns a bounded pixel dimension suitable for a thumbnail decode.
int thumbnailDecodeDimension({
  required double logicalWidth,
  required double logicalHeight,
  required double devicePixelRatio,
  int minDimension = 64,
  int maxDimension = 1600,
}) => _boundedDecodeDimension(
  logicalWidth: logicalWidth,
  logicalHeight: logicalHeight,
  devicePixelRatio: devicePixelRatio,
  minDimension: minDimension,
  maxDimension: maxDimension,
);

/// Returns a bounded decode dimension for a zoomable fullscreen viewer.
///
/// The 4096px ceiling keeps a single RGBA decode near 64MiB while still
/// providing detail beyond the physical display resolution for moderate zoom.
int fullscreenDecodeDimension({
  required double logicalWidth,
  required double logicalHeight,
  required double devicePixelRatio,
  int minDimension = 256,
  int maxDimension = 4096,
}) => _boundedDecodeDimension(
  logicalWidth: logicalWidth,
  logicalHeight: logicalHeight,
  devicePixelRatio: devicePixelRatio,
  minDimension: minDimension,
  maxDimension: maxDimension,
);

int _boundedDecodeDimension({
  required double logicalWidth,
  required double logicalHeight,
  required double devicePixelRatio,
  required int minDimension,
  required int maxDimension,
}) {
  if (minDimension <= 0 || maxDimension < minDimension) {
    throw ArgumentError('Invalid decode dimension bounds');
  }
  final width = logicalWidth.isFinite ? logicalWidth : 0;
  final height = logicalHeight.isFinite ? logicalHeight : 0;
  final dpr = devicePixelRatio.isFinite ? devicePixelRatio : 1;
  final logicalMax = math.max(width, height);
  final requested = (logicalMax * dpr).round();
  return requested.clamp(minDimension, maxDimension).toInt();
}

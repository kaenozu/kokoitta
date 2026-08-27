import 'package:flutter/foundation.dart';

/// Ad identifiers are deliberately limited to Google's public test units.
///
/// Production identifiers must be supplied through the release handoff and
/// must never be committed to this repository.
abstract final class AdConfig {
  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const androidBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const iosAppId = 'ca-app-pub-3940256099942544~1458002511';
  static const iosBannerId = 'ca-app-pub-3940256099942544/2934735716';

  static String get bannerId => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => iosBannerId,
    _ => androidBannerId,
  };
}

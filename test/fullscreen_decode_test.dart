import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/image_decode.dart';

void main() {
  group('fullscreenDecodeDimension', () {
    test('uses physical display size when below the ceiling', () {
      expect(
        fullscreenDecodeDimension(
          logicalWidth: 1080,
          logicalHeight: 2400,
          devicePixelRatio: 1,
        ),
        2400,
      );
    });

    test('caps extreme display requests at 4096 pixels', () {
      expect(
        fullscreenDecodeDimension(
          logicalWidth: 1440,
          logicalHeight: 3200,
          devicePixelRatio: 3,
        ),
        4096,
      );
    });

    test('handles invalid dimensions without unbounded allocation', () {
      expect(
        fullscreenDecodeDimension(
          logicalWidth: double.infinity,
          logicalHeight: double.nan,
          devicePixelRatio: double.infinity,
        ),
        256,
      );
    });

    test('rejects invalid bounds', () {
      expect(
        () => fullscreenDecodeDimension(
          logicalWidth: 100,
          logicalHeight: 100,
          devicePixelRatio: 1,
          minDimension: 512,
          maxDimension: 256,
        ),
        throwsArgumentError,
      );
    });
  });
}

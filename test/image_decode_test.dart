import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/image_decode.dart';

void main() {
  test('scales with DPR and clamps safely', () {
    expect(
      thumbnailDecodeDimension(
        logicalWidth: 100,
        logicalHeight: 80,
        devicePixelRatio: 1,
      ),
      100,
    );
    expect(
      thumbnailDecodeDimension(
        logicalWidth: 100,
        logicalHeight: 80,
        devicePixelRatio: 3,
      ),
      300,
    );
    expect(
      thumbnailDecodeDimension(
        logicalWidth: 0,
        logicalHeight: 0,
        devicePixelRatio: 3,
      ),
      64,
    );
    expect(
      thumbnailDecodeDimension(
        logicalWidth: 10_000,
        logicalHeight: 10_000,
        devicePixelRatio: 3,
      ),
      1600,
    );
  });
}

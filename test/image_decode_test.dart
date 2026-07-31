import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/image_decode.dart';

void main() {
  group('thumbnailDecodeDimension', () {
    test('DPR 1.0/2.0/3.0 で大きい方の論理寸法をスケールする', () {
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
          devicePixelRatio: 2,
        ),
        200,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 100,
          logicalHeight: 80,
          devicePixelRatio: 3,
        ),
        300,
      );
    });

    test('高さが幅より大きい場合は高さ側が使われる', () {
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 80,
          logicalHeight: 120,
          devicePixelRatio: 2,
        ),
        240,
      );
    });

    test('小数の論理寸法は丸められる', () {
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 113.4,
          logicalHeight: 113.4,
          devicePixelRatio: 1,
        ),
        113,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 113.5,
          logicalHeight: 113.5,
          devicePixelRatio: 1,
        ),
        114,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 250.67,
          logicalHeight: 250.67,
          devicePixelRatio: 1,
        ),
        251,
      );
    });

    test('表示寸法0は最小値にクランプされる', () {
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 0,
          logicalHeight: 0,
          devicePixelRatio: 3,
        ),
        64,
      );
    });

    test('負数の表示寸法は最小値にクランプされる', () {
      expect(
        thumbnailDecodeDimension(
          logicalWidth: -100,
          logicalHeight: -50,
          devicePixelRatio: 3,
        ),
        64,
      );
    });

    test('NaN と Infinity は0扱いで安全に処理される', () {
      expect(
        thumbnailDecodeDimension(
          logicalWidth: double.nan,
          logicalHeight: 50,
          devicePixelRatio: 2,
        ),
        100,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: double.infinity,
          logicalHeight: double.infinity,
          devicePixelRatio: 2,
        ),
        64,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 50,
          logicalHeight: double.negativeInfinity,
          devicePixelRatio: 2,
        ),
        100,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 100,
          logicalHeight: 100,
          devicePixelRatio: double.nan,
        ),
        100,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 100,
          logicalHeight: 100,
          devicePixelRatio: double.infinity,
        ),
        100,
      );
    });

    test('極端に大きい寸法は上限にクランプされる', () {
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 10_000,
          logicalHeight: 10_000,
          devicePixelRatio: 3,
        ),
        1600,
      );
    });

    test('下限境界は最小値へ、上限境界は最大値へ収まる', () {
      // 丸め後が下限未満 → 最小値。
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 20,
          logicalHeight: 20,
          devicePixelRatio: 3,
        ),
        64,
      );
      // ちょうど最小値。
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 64,
          logicalHeight: 64,
          devicePixelRatio: 1,
        ),
        64,
      );
      // 最小値の直上。
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 22,
          logicalHeight: 22,
          devicePixelRatio: 3,
        ),
        66,
      );
      // ちょうど最大値。
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 1600,
          logicalHeight: 1600,
          devicePixelRatio: 1,
        ),
        1600,
      );
      // 丸め後に最大値をわずかに超える → 最大値。
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 533.3,
          logicalHeight: 533.3,
          devicePixelRatio: 3,
        ),
        1600,
      );
      // 最大値を超える → 最大値。
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 600,
          logicalHeight: 600,
          devicePixelRatio: 3,
        ),
        1600,
      );
    });

    test('カスタムの最小・最大値を尊重する', () {
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 10,
          logicalHeight: 10,
          devicePixelRatio: 1,
          minDimension: 16,
          maxDimension: 512,
        ),
        16,
      );
      expect(
        thumbnailDecodeDimension(
          logicalWidth: 300,
          logicalHeight: 300,
          devicePixelRatio: 3,
          minDimension: 16,
          maxDimension: 512,
        ),
        512,
      );
    });
  });
}

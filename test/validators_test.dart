import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/validators.dart';

void main() {
  group('normalizeTripTitle', () {
    test('通常の文字列はそのまま返す', () {
      expect(normalizeTripTitle('東京旅行'), '東京旅行');
    });

    test('前後空白をtrimする', () {
      expect(normalizeTripTitle('  東京旅行  '), '東京旅行');
    });

    test('改行をスペースに置換し連続空白を整理する', () {
      expect(normalizeTripTitle('東京\n旅行'), '東京 旅行');
    });

    test('タブをスペースに置換し連続空白を整理する', () {
      expect(normalizeTripTitle('東京\t旅行'), '東京 旅行');
    });

    test('改行とタブが混在する場合を整理する', () {
      expect(normalizeTripTitle('東京\n\t旅行'), '東京 旅行');
    });

    test('連続空白を単一スペースに整理する', () {
      expect(normalizeTripTitle('東京  旅行'), '東京 旅行');
    });

    test('空白のみの文字列はnullを返す', () {
      expect(normalizeTripTitle('   '), isNull);
    });

    test('空文字列はnullを返す', () {
      expect(normalizeTripTitle(''), isNull);
    });

    test('制御文字を除去する', () {
      expect(normalizeTripTitle('東京\x00旅行'), '東京 旅行');
    });

    test('200文字を超える場合は切り詰める', () {
      final longTitle = 'A' * 250;
      final result = normalizeTripTitle(longTitle);
      expect(result, isNotNull);
      expect(result!.length, 200);
    });

    test('正確に200文字はそのまま返す', () {
      final exactTitle = 'B' * 200;
      expect(normalizeTripTitle(exactTitle), exactTitle);
    });
  });

  group('normalizePrefectureState', () {
    test('有効な状態値はそのまま返す', () {
      expect(normalizePrefectureState('unvisited'), 'unvisited');
      expect(normalizePrefectureState('visited'), 'visited');
      expect(normalizePrefectureState('transit'), 'transit');
    });

    test('不正な状態値はunvisitedに正規化する', () {
      expect(normalizePrefectureState('unknown'), 'unvisited');
      expect(normalizePrefectureState(''), 'unvisited');
      expect(normalizePrefectureState('visited '), 'unvisited');
    });
  });

  group('isValidPrefecture', () {
    test('有効な都道府県名はtrueを返す', () {
      expect(isValidPrefecture('北海道'), isTrue);
      expect(isValidPrefecture('東京'), isTrue);
      expect(isValidPrefecture('沖縄'), isTrue);
    });

    test('無効な都道府県名はfalseを返す', () {
      expect(isValidPrefecture('未知県'), isFalse);
      expect(isValidPrefecture(''), isFalse);
      expect(isValidPrefecture('東京都'), isFalse);
    });
  });

  group('normalizePrefectureStates', () {
    test('有効なエントリのみ保持する', () {
      final input = <String, String>{
        '北海道': 'visited',
        '未知県': 'visited',
        '東京': 'invalid',
      };
      final result = normalizePrefectureStates(input);
      expect(result.containsKey('北海道'), isTrue);
      expect(result.containsKey('未知県'), isFalse);
      expect(result.containsKey('東京'), isTrue);
      expect(result['東京'], 'unvisited');
      expect(result['北海道'], 'visited');
    });

    test('空のMapを渡すと空のMapを返す', () {
      expect(normalizePrefectureStates(<String, String>{}), isEmpty);
    });
  });

  group('validPrefectures', () {
    test('47件の都道府県が定義されている', () {
      expect(validPrefectures.length, 47);
    });

    test('日本の主要な都道府県が含まれている', () {
      expect(validPrefectures.contains('北海道'), isTrue);
      expect(validPrefectures.contains('東京都'), isFalse);
      expect(validPrefectures.contains('神奈川'), isTrue);
    });
  });

  group('validPrefectureStates', () {
    test('3つの状態が定義されている', () {
      expect(validPrefectureStates.length, 3);
    });

    test('3つの有効な状態が含まれている', () {
      expect(validPrefectureStates.contains('unvisited'), isTrue);
      expect(validPrefectureStates.contains('visited'), isTrue);
      expect(validPrefectureStates.contains('transit'), isTrue);
    });
  });
}

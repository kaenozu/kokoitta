import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('kokoitta-store');
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('JSON保存は区切り文字を含む旅行名を保持する', () async {
    final photo = File('${temporaryDirectory.path}/photo.jpg');
    await photo.writeAsBytes(<int>[1, 2, 3]);
    final store = TripStore();
    final data = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '夏|旅;;2026',
          photos: <File>[photo],
        ),
      ],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{'埼玉': 'visited'},
    );

    await store.save(data);
    final loaded = await store.load();

    expect(loaded.trips.single.title, '夏|旅;;2026');
    expect(loaded.trips.single.photos.single.path, photo.path);
    expect(loaded.prefectureStates['埼玉'], 'visited');
  });

  test('旧形式を新形式へ移行する', () async {
    final photo = File('${temporaryDirectory.path}/legacy.jpg');
    await photo.writeAsBytes(<int>[1]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.legacyTripsKey: <String>['旧旅行|${photo.path}'],
      TripStore.legacyPrefectureStatesKey: <String>['東京|transit'],
    });
    final store = TripStore();

    final loaded = await store.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.trips.single.title, '旧旅行');
    expect(loaded.trips.single.photos.single.path, photo.path);
    expect(loaded.prefectureStates['東京'], 'transit');
    expect(preferences.getString(TripStore.dataKey), isNotNull);
    expect(preferences.getStringList(TripStore.legacyTripsKey), isNull);
  });

  test('中間JSON形式を新形式へ移行する', () async {
    final photo = File('${temporaryDirectory.path}/intermediate.jpg');
    await photo.writeAsBytes(<int>[1, 2]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.intermediateTripsKey: jsonEncode(<Object>[
        <String, Object>{
          'title': '中間形式の旅行',
          'photos': <String>[photo.path],
        },
      ]),
      TripStore.intermediatePrefectureStatesKey:
          jsonEncode(<String, String>{'埼玉': 'visited'}),
    });
    final store = TripStore();

    final loaded = await store.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.trips.single.title, '中間形式の旅行');
    expect(loaded.trips.single.photos.single.path, photo.path);
    expect(loaded.prefectureStates['埼玉'], 'visited');
    expect(preferences.getString(TripStore.dataKey), isNotNull);
    expect(preferences.getString(TripStore.intermediateTripsKey), isNull);
    expect(
      preferences.getString(TripStore.intermediatePrefectureStatesKey),
      isNull,
    );
  });

  test('未完了書き込みから最新データを回復する', () async {
    final pending = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': const <Object>[],
      'unassignedPhotos': const <String>[],
      'prefectureStates': const <String, String>{'北海道': 'visited'},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.pendingKey: pending,
    });
    final store = TripStore();

    final loaded = await store.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.prefectureStates['北海道'], 'visited');
    expect(preferences.getString(TripStore.dataKey), isNotNull);
    expect(preferences.getString(TripStore.pendingKey), isNull);
  });

  test('不明な都道府県キーを読み込んでも訪問数が47を超えない', () async {
    final store = TripStore();
    final data = AppData(
      trips: const <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: <String, String>{
        '北海道': 'visited',
        '未知県': 'visited',
        '東京': 'visited',
      },
    );
    await store.save(data);

    final loaded = await store.load();
    expect(loaded.prefectureStates.containsKey('未知県'), isFalse);
    expect(loaded.prefectureStates.values.where((s) => s == 'visited').length,
        lessThanOrEqualTo(47));
  });

  test('不正な状態値をunvisitedに正規化する', () async {
    final store = TripStore();
    final data = AppData(
      trips: const <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{
        '北海道': 'invalid',
        '東京': 'unknown',
      },
    );
    await store.save(data);

    final loaded = await store.load();
    expect(loaded.prefectureStates['北海道'], 'unvisited');
    expect(loaded.prefectureStates['東京'], 'unvisited');
  });

  test('正規化後にprefectureStatesからunvisitedエントリが除外される',
      () async {
    final store = TripStore();
    final data = AppData(
      trips: const <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{
        '北海道': 'unvisited',
        '東京': 'visited',
      },
    );
    await store.save(data);

    final loaded = await store.load();
    expect(loaded.prefectureStates.containsKey('北海道'), isFalse);
    expect(loaded.prefectureStates.containsKey('東京'), isTrue);
  });

  test('空白のみの旅行名を持つトリップは読み込み時にスキップされる',
      () async {
    final store = TripStore();
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': <Object>[
        <String, Object>{'title': '   ', 'photos': <String>[]},
        <String, Object>{'title': '有効な旅行', 'photos': <String>[]},
      ],
      'unassignedPhotos': const <String>[],
      'prefectureStates': const <String, String>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });

    final loaded = await store.load();
    expect(loaded.trips.length, 1);
    expect(loaded.trips.single.title, '有効な旅行');
  });

  test('前後空白と制御文字を含む旅行名が正規化される', () async {
    final store = TripStore();
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': <Object>[
        <String, Object>{
          'title': ' \n東京\t旅行\r ',
          'photos': <String>[],
        },
      ],
      'unassignedPhotos': const <String>[],
      'prefectureStates': const <String, String>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });

    final loaded = await store.load();
    expect(loaded.trips.single.title, '東京 旅行');
  });

  test('同じ写真の重複所属を保存しない', () async {
    final photo = File('${temporaryDirectory.path}/duplicate.jpg');
    await photo.writeAsBytes(<int>[1]);
    final store = TripStore();
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行', photos: <File>[photo]),
      ],
      unassignedPhotos: <File>[photo],
      prefectureStates: const <String, String>{},
    );

    await expectLater(store.save(data), throwsStateError);
  });
}

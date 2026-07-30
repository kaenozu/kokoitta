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
    expect(preferences.getString(TripStore.dataKey), pending);
    expect(preferences.getString(TripStore.pendingKey), isNull);
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

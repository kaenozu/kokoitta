import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Photo photoOf(File file) => Photo.fromFile(file);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'kokoitta-store',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<File> createPhotoFile(String name) async {
    final file = File('${temporaryDirectory.path}/$name');
    await file.writeAsBytes(<int>[1, 2, 3]);
    return file;
  }

  test('JSON保存は区切り文字を含む旅行名を保持する', () async {
    final photo = await createPhotoFile('photo.jpg');
    final store = TripStore();
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '夏|旅;;2026', photos: <Photo>[photoOf(photo)]),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{'埼玉': 'visited'},
    );

    await store.save(data);
    final loaded = await store.load();

    expect(loaded.trips.single.title, '夏|旅;;2026');
    expect(loaded.trips.single.photos.single.file.path, photo.path);
    expect(loaded.prefectureStates['埼玉'], 'visited');
  });

  test('旧形式を新形式へ移行する', () async {
    final photo = await createPhotoFile('legacy.jpg');
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.legacyTripsKey: <String>['旧旅行|${photo.path}'],
      TripStore.legacyPrefectureStatesKey: <String>['東京|transit'],
    });
    final store = TripStore();

    final loaded = await store.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.trips.single.title, '旧旅行');
    expect(loaded.trips.single.photos.single.file.path, photo.path);
    expect(
      loaded.trips.single.photos.single.id,
      TripStore.legacyPhotoId(photo.path),
    );
    expect(loaded.prefectureStates['東京'], 'transit');
    expect(preferences.getString(TripStore.dataKey), isNotNull);
    expect(preferences.getStringList(TripStore.legacyTripsKey), isNull);
  });

  test('中間JSON形式を新形式へ移行する', () async {
    final photo = await createPhotoFile('intermediate.jpg');
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.intermediateTripsKey: jsonEncode(<Object>[
        <String, Object>{
          'title': '中間形式の旅行',
          'photos': <String>[photo.path],
        },
      ]),
      TripStore.intermediatePrefectureStatesKey: jsonEncode(<String, String>{
        '埼玉': 'visited',
      }),
    });
    final store = TripStore();

    final loaded = await store.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.trips.single.title, '中間形式の旅行');
    expect(loaded.trips.single.photos.single.file.path, photo.path);
    expect(loaded.prefectureStates['埼玉'], 'visited');
    expect(preferences.getString(TripStore.dataKey), isNotNull);
    expect(preferences.getString(TripStore.intermediateTripsKey), isNull);
    expect(
      preferences.getString(TripStore.intermediatePrefectureStatesKey),
      isNull,
    );
  });

  test('v2形式の保存データをv3へ無損失で移行する', () async {
    final photo = await createPhotoFile('v2.jpg');
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.legacySchemaVersion,
      'trips': <Object>[
        <String, Object>{
          'id': 'trip-old',
          'title': 'v2の旅行',
          'photos': <String>[photo.path],
        },
      ],
      'unassignedPhotos': <String>[photo.path],
      'prefectureStates': <String, String>{'大阪': 'visited'},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });
    final store = TripStore();

    final loaded = await store.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.trips.single.title, 'v2の旅行');
    expect(loaded.trips.single.photos, hasLength(1));
    expect(
      loaded.trips.single.photos.single.id,
      TripStore.legacyPhotoId(photo.path),
    );
    expect(loaded.unassignedPhotos, isEmpty, reason: '重複パスは最初の1件へ集約');
    expect(loaded.prefectureStates['大阪'], 'visited');

    final stored =
        jsonDecode(preferences.getString(TripStore.dataKey)!)
            as Map<String, dynamic>;
    expect(stored['schemaVersion'], TripStore.schemaVersion);
    final storedPhotos =
        (stored['trips'] as List).single['photos'] as List<dynamic>;
    expect(storedPhotos.single, isA<Map<String, dynamic>>());
    expect(
      (storedPhotos.single as Map)['id'],
      TripStore.legacyPhotoId(photo.path),
    );
    expect((storedPhotos.single as Map)['path'], photo.path);
  });

  test('再migrationしてもv2由来の写真IDは変わらない', () async {
    final photo = await createPhotoFile('stable.jpg');
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.legacySchemaVersion,
      'trips': <Object>[
        <String, Object>{
          'id': 'trip-old',
          'title': '安定IDの旅行',
          'photos': <String>[photo.path],
        },
      ],
      'unassignedPhotos': const <String>[],
      'prefectureStates': const <String, String>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });
    final store = TripStore();

    final first = await store.load();
    final firstId = first.trips.single.photos.single.id;

    await store.save(first);
    final second = await store.load();
    final secondId = second.trips.single.photos.single.id;

    expect(firstId, TripStore.legacyPhotoId(photo.path));
    expect(secondId, firstId);
  });

  test('legacyPhotoIdはパスの正規化と決定性を保証する', () {
    final idA = TripStore.legacyPhotoId('C:\\photos\\a.jpg');
    final idB = TripStore.legacyPhotoId('C:/photos/a.jpg');
    expect(idA, idB, reason: 'バックスラッシュはスラッシュへ正規化される');
    expect(idA, startsWith('photo-'));
    expect(TripStore.legacyPhotoId('C:/photos/a.jpg'), idA);
  });

  test('v3のmetadataは保存・再読込で保持される', () async {
    final photo = await createPhotoFile('meta.jpg');
    final capturedAt = DateTime(2026, 7, 15, 10, 30);
    final store = TripStore();
    final data = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: 'metadata旅行',
          photos: <Photo>[
            Photo(
              id: 'photo-meta-1',
              file: photo,
              capturedAt: capturedAt,
              location: '東京都',
              originalName: 'dsc_001.jpg',
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await store.save(data);
    final loaded = await store.load();
    final loadedPhoto = loaded.trips.single.photos.single;

    expect(loadedPhoto.id, 'photo-meta-1');
    expect(loadedPhoto.capturedAt, capturedAt);
    expect(loadedPhoto.location, '東京都');
    expect(loadedPhoto.originalName, 'dsc_001.jpg');
    expect(loadedPhoto.mimeType, 'image/jpeg');
  });

  test('metadataをnullへ消去すると保存JSONからも消える', () async {
    final photo = await createPhotoFile('cleared.jpg');
    final store = TripStore();
    final withMetadata = Photo(
      id: 'photo-clear-1',
      file: photo,
      capturedAt: DateTime(2026, 7, 15),
      location: '東京都',
      originalName: 'a.jpg',
      mimeType: 'image/jpeg',
    );
    final cleared = withMetadata.copyWith(
      capturedAt: null,
      location: null,
      originalName: null,
      mimeType: null,
    );
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行', photos: <Photo>[cleared]),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await store.save(data);
    final loaded = await store.load();
    final loadedPhoto = loaded.trips.single.photos.single;

    expect(loadedPhoto.capturedAt, isNull);
    expect(loadedPhoto.location, isNull);
    expect(loadedPhoto.originalName, isNull);
    expect(loadedPhoto.mimeType, isNull);

    final preferences = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(preferences.getString(TripStore.dataKey)!)
            as Map<String, dynamic>;
    final storedPhoto =
        ((stored['trips'] as List).single['photos'] as List).single
            as Map<String, dynamic>;
    expect(storedPhoto.keys, containsAll(<String>['id', 'path']));
    expect(storedPhoto.keys, isNot(contains('capturedAt')));
    expect(storedPhoto.keys, isNot(contains('location')));
  });

  test('壊れたmetadataはnullへ正規化して読み込む', () async {
    final photo = await createPhotoFile('broken.jpg');
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': <Object>[
        <String, Object>{
          'id': 'trip-1',
          'title': '壊れたmetadata',
          'photos': <Object>[
            <String, Object>{
              'id': 'photo-broken-1',
              'path': photo.path,
              'capturedAt': 'not-a-date',
              'location': 123,
              'originalName': <Object>[],
            },
          ],
        },
      ],
      'unassignedPhotos': const <Object>[],
      'prefectureStates': const <String, String>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });
    final store = TripStore();

    final loaded = await store.load();
    final loadedPhoto = loaded.trips.single.photos.single;

    expect(loadedPhoto.capturedAt, isNull);
    expect(loadedPhoto.location, isNull);
    expect(loadedPhoto.originalName, isNull);
    expect(loadedPhoto.mimeType, isNull);
    expect(loadedPhoto.file.path, photo.path);
  });

  test('v3で同じIDやパスの重複は読み込み時に最初の1件へ集約する', () async {
    final photo = await createPhotoFile('dup-read.jpg');
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': <Object>[
        <String, Object>{
          'id': 'trip-1',
          'title': '重複データ',
          'photos': <Object>[
            <String, Object>{'id': 'photo-dup-1', 'path': photo.path},
            <String, Object>{'id': 'photo-dup-1', 'path': photo.path},
          ],
        },
      ],
      'unassignedPhotos': <Object>[
        <String, Object>{'id': 'photo-dup-1', 'path': photo.path},
      ],
      'prefectureStates': const <String, String>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });
    final store = TripStore();

    final loaded = await store.load();

    expect(loaded.trips.single.photos, hasLength(1));
    expect(loaded.unassignedPhotos, isEmpty);
  });

  test('v3でIDやパスが壊れたレコードは読み込みエラーになる', () async {
    final photo = await createPhotoFile('bad-record.jpg');
    for (final photoRecord in <Object>[
      <String, Object>{'path': photo.path},
      <String, Object>{'id': '', 'path': photo.path},
      <String, Object>{'id': 'photo-bad-1'},
    ]) {
      final raw = jsonEncode(<String, Object>{
        'schemaVersion': TripStore.schemaVersion,
        'trips': <Object>[
          <String, Object>{
            'id': 'trip-1',
            'title': '壊れたレコード',
            'photos': <Object>[photoRecord],
          },
        ],
        'unassignedPhotos': const <Object>[],
        'prefectureStates': const <String, String>{},
      });
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: raw,
      });
      final store = TripStore();
      await expectLater(store.load(), throwsFormatException);
    }
  });

  test('v2で欠損ファイルの写真は読み込み時に無視される', () async {
    final missing = File('${temporaryDirectory.path}/missing.jpg');
    final existing = await createPhotoFile('present.jpg');
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.legacySchemaVersion,
      'trips': <Object>[
        <String, Object>{
          'id': 'trip-1',
          'title': '欠損写真',
          'photos': <String>[missing.path, existing.path],
        },
      ],
      'unassignedPhotos': const <String>[],
      'prefectureStates': const <String, String>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });
    final store = TripStore();

    final loaded = await store.load();

    expect(loaded.trips.single.photos, hasLength(1));
    expect(loaded.trips.single.photos.single.file.path, existing.path);
  });

  test('未完了書き込みから最新データを回復する', () async {
    final pending = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': const <Object>[],
      'unassignedPhotos': const <Object>[],
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
      unassignedPhotos: const <Photo>[],
      prefectureStates: <String, String>{
        '北海道': 'visited',
        '未知県': 'visited',
        '東京': 'visited',
      },
    );
    await store.save(data);

    final loaded = await store.load();
    expect(loaded.prefectureStates.containsKey('未知県'), isFalse);
    expect(
      loaded.prefectureStates.values.where((s) => s == 'visited').length,
      lessThanOrEqualTo(47),
    );
  });

  test('不正な状態値は保存時にunvisitedに正規化されprunedされる', () async {
    final store = TripStore();
    final data = AppData(
      trips: const <Trip>[],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{
        '北海道': 'invalid',
        '東京': 'unknown',
      },
    );
    await store.save(data);

    final loaded = await store.load();
    expect(loaded.prefectureStates.containsKey('北海道'), isFalse);
    expect(loaded.prefectureStates.containsKey('東京'), isFalse);
  });

  test('正規化後にprefectureStatesからunvisitedエントリが除外される', () async {
    final store = TripStore();
    final data = AppData(
      trips: const <Trip>[],
      unassignedPhotos: const <Photo>[],
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

  test('空白のみの旅行名を持つトリップは読み込み時にスキップされる', () async {
    final store = TripStore();
    final raw = jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': <Object>[
        <String, Object>{'title': '   ', 'photos': <Object>[]},
        <String, Object>{'title': '有効な旅行', 'photos': <Object>[]},
      ],
      'unassignedPhotos': const <Object>[],
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
        <String, Object>{'title': ' \n東京\t旅行\r ', 'photos': <Object>[]},
      ],
      'unassignedPhotos': const <Object>[],
      'prefectureStates': const <String, String>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: raw,
    });

    final loaded = await store.load();
    expect(loaded.trips.single.title, '東京 旅行');
  });

  test('同じ写真IDの重複所属を保存しない', () async {
    final photo = await createPhotoFile('dup-id.jpg');
    final photoEntity = photoOf(photo);
    final store = TripStore();
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行', photos: <Photo>[photoEntity]),
      ],
      unassignedPhotos: <Photo>[photoEntity],
      prefectureStates: const <String, String>{},
    );

    await expectLater(store.save(data), throwsStateError);
  });

  test('同じパスを別IDで持つ写真の重複所属を保存しない', () async {
    final photo = await createPhotoFile('dup-path.jpg');
    final store = TripStore();
    final data = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '旅行',
          photos: <Photo>[Photo(id: 'photo-a', file: photo)],
        ),
      ],
      unassignedPhotos: <Photo>[Photo(id: 'photo-b', file: photo)],
      prefectureStates: const <String, String>{},
    );

    await expectLater(store.save(data), throwsStateError);
  });

  test('保存JSONは常にcanonical化される', () async {
    final photo = await createPhotoFile('canon.jpg');
    final store = TripStore();
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'bad-trip', title: '  ', photos: <Photo>[photoOf(photo)]),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{
        '北海道': 'visited',
        '未知県': 'invalid',
      },
    );
    await store.save(data);

    final preferences = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(preferences.getString(TripStore.dataKey)!)
            as Map<String, dynamic>;

    expect(stored['trips'], isEmpty);
    final storedPhoto =
        (stored['unassignedPhotos'] as List).single as Map<String, dynamic>;
    expect(storedPhoto['path'], photo.path);
    expect(storedPhoto['id'], isNotEmpty);
    expect(
      (stored['prefectureStates'] as Map<String, dynamic>).keys,
      containsAll(<String>['北海道']),
    );
    expect(
      (stored['prefectureStates'] as Map<String, dynamic>).keys,
      isNot(contains('未知県')),
    );
  });
}

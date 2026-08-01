import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/storage_cleanup.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Issue #45: タイトル欠損・非文字列・空白のみ等の無効タイトルを持つ旅行
/// レコードでも、有効なPhoto参照とmetadataを失わず「旅行未設定」へ救済し、
/// canonical rewriteとstartup cleanupによる物理写真消失を防ぐ。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'kokoitta-recovery',
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

  String v3Raw({
    required List<Object> trips,
    List<Object> unassignedPhotos = const <Object>[],
  }) {
    return jsonEncode(<String, Object>{
      'schemaVersion': TripStore.schemaVersion,
      'trips': trips,
      'unassignedPhotos': unassignedPhotos,
      'prefectureStates': <String, String>{},
    });
  }

  group('v3: 無効タイトルの旅行から写真を救済する', () {
    test('空白タイトルと有効写真は旅行が除外され写真が旅行未設定へ移る', () async {
      final photo = await createPhotoFile('blank-title.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': '   ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-r-1', 'path': photo.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, hasLength(1));
      expect(loaded.unassignedPhotos.single.id, 'photo-r-1');
      expect(loaded.unassignedPhotos.single.file.path, photo.path);
    });

    test('タイトル欠損と有効写真は救済される', () async {
      final photo = await createPhotoFile('missing-title.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'photos': <Object>[
                <String, Object>{'id': 'photo-r-2', 'path': photo.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos.single.id, 'photo-r-2');
    });

    test('非文字列タイトルと有効写真は救済される', () async {
      final photo = await createPhotoFile('numeric-title.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': 123,
              'photos': <Object>[
                <String, Object>{'id': 'photo-r-3', 'path': photo.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos.single.id, 'photo-r-3');
    });

    test('無効タイトルの写真はmetadata付きで救済される', () async {
      final photo = await createPhotoFile('metadata.jpg');
      final capturedAt = DateTime(2026, 7, 15, 10, 30);
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': '  ',
              'photos': <Object>[
                <String, Object>{
                  'id': 'photo-meta-1',
                  'path': photo.path,
                  'capturedAt': capturedAt.toIso8601String(),
                  'location': '東京都',
                  'originalName': 'dsc_001.jpg',
                  'mimeType': 'image/jpeg',
                },
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();
      final rescued = loaded.unassignedPhotos.single;

      expect(rescued.id, 'photo-meta-1');
      expect(rescued.capturedAt, capturedAt);
      expect(rescued.location, '東京都');
      expect(rescued.originalName, 'dsc_001.jpg');
      expect(rescued.mimeType, 'image/jpeg');
    });

    test('無効タイトルでもcanonical保存・再読込で枚数と所属が維持される', () async {
      final photo = await createPhotoFile('canonical.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': ' \n ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-canon-1', 'path': photo.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();
      await store.save(loaded);
      final reloaded = await store.load();

      expect(reloaded.trips, isEmpty);
      expect(reloaded.unassignedPhotos, hasLength(1));
      expect(reloaded.unassignedPhotos.single.id, 'photo-canon-1');
      expect(reloaded.unassignedPhotos.single.file.path, photo.path);

      final preferences = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(preferences.getString(TripStore.dataKey)!)
              as Map<String, dynamic>;
      expect(stored['trips'], isEmpty);
      expect((stored['unassignedPhotos'] as List), hasLength(1));
    });

    test('救済後もmetadataがcanonical保存・再読込で維持される', () async {
      final photo = await createPhotoFile('canonical-meta.jpg');
      final capturedAt = DateTime(2026, 7, 15, 10, 30);
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': <Object>[
                <String, Object>{
                  'id': 'photo-canon-meta',
                  'path': photo.path,
                  'capturedAt': capturedAt.toIso8601String(),
                  'location': '京都府',
                  'originalName': 'dsc_002.jpg',
                  'mimeType': 'image/png',
                },
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();
      await store.save(loaded);
      final reloaded = await store.load();
      final rescued = reloaded.unassignedPhotos.single;

      expect(rescued.capturedAt, capturedAt);
      expect(rescued.location, '京都府');
      expect(rescued.originalName, 'dsc_002.jpg');
      expect(rescued.mimeType, 'image/png');
    });

    test('複数の破損旅行の写真はリスト順に救済される', () async {
      final photoA = await createPhotoFile('multi-a.jpg');
      final photoB = await createPhotoFile('multi-b.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken-1',
              'title': '  ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-a', 'path': photoA.path},
              ],
            },
            <String, Object>{
              'id': 'trip-broken-2',
              'photos': <Object>[
                <String, Object>{'id': 'photo-b', 'path': photoB.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, hasLength(2));
      expect(loaded.unassignedPhotos[0].id, 'photo-a');
      expect(loaded.unassignedPhotos[1].id, 'photo-b');
    });
  });

  group('v3: 重複の優先順位は決定的である', () {
    test('有効旅行と破損旅行の同じPhoto IDは有効旅行が優先され複製しない', () async {
      final photo = await createPhotoFile('dup-id.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-valid',
              'title': '有効な旅行',
              'photos': <Object>[
                <String, Object>{'id': 'photo-shared', 'path': photo.path},
              ],
            },
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-shared', 'path': photo.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips.single.photos, hasLength(1));
      expect(loaded.trips.single.photos.single.id, 'photo-shared');
      expect(loaded.unassignedPhotos, isEmpty);
    });

    test('有効旅行と破損旅行の表記違いの同一パスは有効旅行が優先される', () async {
      final photo = await createPhotoFile('dup-path.jpg');
      final slashPath = photo.path.replaceAll('\\', '/');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-valid',
              'title': '有効な旅行',
              'photos': <Object>[
                <String, Object>{'id': 'photo-a', 'path': photo.path},
              ],
            },
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-b', 'path': slashPath},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips.single.photos, hasLength(1));
      expect(loaded.trips.single.photos.single.id, 'photo-a');
      expect(loaded.unassignedPhotos, isEmpty);
    });

    test('旅行未設定と破損旅行の同じ写真は旅行未設定が優先される', () async {
      final photo = await createPhotoFile('dup-unassigned.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-x', 'path': photo.path},
              ],
            },
          ],
          unassignedPhotos: <Object>[
            <String, Object>{'id': 'photo-x', 'path': photo.path},
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.unassignedPhotos, hasLength(1));
      expect(loaded.unassignedPhotos.single.id, 'photo-x');
    });

    test('重複旅行IDは先勝ちで後続には新しいIDが付与される', () async {
      final photoA = await createPhotoFile('trip-id-a.jpg');
      final photoB = await createPhotoFile('trip-id-b.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-same',
              'title': '先',
              'photos': <Object>[
                <String, Object>{'id': 'photo-t1', 'path': photoA.path},
              ],
            },
            <String, Object>{
              'id': 'trip-same',
              'title': '後',
              'photos': <Object>[
                <String, Object>{'id': 'photo-t2', 'path': photoB.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, hasLength(2));
      expect(loaded.trips[0].id, 'trip-same');
      expect(loaded.trips[1].id, isNot('trip-same'));
      expect(loaded.trips[1].id, startsWith('trip-'));
      expect(loaded.trips[0].photos.single.id, 'photo-t1');
      expect(loaded.trips[1].photos.single.id, 'photo-t2');
    });
  });

  group('v3: fail-closed境界（救済不能）', () {
    test('無効タイトルと一部不正Photoは読み込みエラーになり推測しない', () async {
      final photo = await createPhotoFile('partial-broken.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': '  ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-ok', 'path': photo.path},
                <String, Object>{'id': 123, 'path': photo.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      await expectLater(store.load(), throwsFormatException);
    });

    test('無効タイトルで写真一覧自体が非Listは読み込みエラーになる', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': 'not-a-list',
            },
          ],
        ),
      });
      final store = TripStore();

      await expectLater(store.load(), throwsFormatException);
    });

    test('無効タイトルで欠損ファイルの写真は救済されない', () async {
      final missing = File('${temporaryDirectory.path}/missing.jpg');
      final existing = await createPhotoFile('existing.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-missing', 'path': missing.path},
                <String, Object>{'id': 'photo-existing', 'path': existing.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.unassignedPhotos, hasLength(1));
      expect(loaded.unassignedPhotos.single.id, 'photo-existing');
    });

    test('欠損ファイルは同一IDでも後続の実在写真をclaimしない', () async {
      final missing = File('${temporaryDirectory.path}/missing-id.jpg');
      final existing = await createPhotoFile('existing-same-id.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-shared', 'path': missing.path},
                <String, Object>{'id': 'photo-shared', 'path': existing.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.unassignedPhotos, hasLength(1));
      expect(loaded.unassignedPhotos.single.id, 'photo-shared');
      expect(loaded.unassignedPhotos.single.file.path, existing.path);
    });
  });

  group('migration経路でも無効タイトルの写真を救済する', () {
    test('schema v2の無効タイトルと有効写真は救済される', () async {
      final photo = await createPhotoFile('v2-recovery.jpg');
      final raw = jsonEncode(<String, Object>{
        'schemaVersion': TripStore.legacySchemaVersion,
        'trips': <Object>[
          <String, Object>{
            'id': 'trip-broken',
            'title': '   ',
            'photos': <String>[photo.path],
          },
        ],
        'unassignedPhotos': <String>[],
        'prefectureStates': <String, String>{},
      });
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: raw,
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, hasLength(1));
      expect(
        loaded.unassignedPhotos.single.id,
        TripStore.legacyPhotoId(photo.path),
      );
      expect(loaded.unassignedPhotos.single.file.path, photo.path);
    });

    test('intermediate形式の無効タイトルと有効写真は救済される', () async {
      final photo = await createPhotoFile('intermediate-recovery.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.intermediateTripsKey: jsonEncode(<Object>[
          <String, Object>{
            'title': '  ',
            'photos': <String>[photo.path],
          },
        ]),
        TripStore.intermediatePrefectureStatesKey: jsonEncode(
          <String, String>{},
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, hasLength(1));
      expect(
        loaded.unassignedPhotos.single.id,
        TripStore.legacyPhotoId(photo.path),
      );
    });

    test('legacy形式の空白タイトルと有効写真は救済される', () async {
      final photo = await createPhotoFile('legacy-recovery.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.legacyTripsKey: <String>['   |${photo.path}'],
        TripStore.legacyPrefectureStatesKey: const <String>[],
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, hasLength(1));
      expect(
        loaded.unassignedPhotos.single.id,
        TripStore.legacyPhotoId(photo.path),
      );
      expect(loaded.unassignedPhotos.single.file.path, photo.path);
    });

    test('legacy形式のタイトル欠損（|で始まる）でも写真は救済される', () async {
      final photo = await createPhotoFile('legacy-missing-title.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.legacyTripsKey: <String>['|${photo.path}'],
        TripStore.legacyPrefectureStatesKey: const <String>[],
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, hasLength(1));
      expect(
        loaded.unassignedPhotos.single.id,
        TripStore.legacyPhotoId(photo.path),
      );
    });

    test('legacy形式で区切り文字がないレコードは救済せずスキップする', () async {
      final photo = await createPhotoFile('legacy-no-separator.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.legacyTripsKey: <String>[photo.path],
        TripStore.legacyPrefectureStatesKey: const <String>[],
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, isEmpty);
    });

    test('intermediate: 無効タイトルが先でも有効旅行が同一写真を優先保持する', () async {
      final photo = await createPhotoFile('intermediate-priority.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.intermediateTripsKey: jsonEncode(<Object>[
          <String, Object>{
            'title': '  ',
            'photos': <String>[photo.path],
          },
          <String, Object>{
            'title': '有効な旅行',
            'photos': <String>[photo.path],
          },
        ]),
        TripStore.intermediatePrefectureStatesKey: jsonEncode(
          <String, String>{},
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, hasLength(1));
      expect(loaded.trips.single.title, '有効な旅行');
      expect(loaded.trips.single.photos, hasLength(1));
      expect(loaded.trips.single.photos.single.file.path, photo.path);
      expect(loaded.unassignedPhotos, isEmpty, reason: '無効タイトル旅行へは重複写真を救済しない');
    });

    test('intermediate: 複数の無効タイトル旅行間では先勝ちで1件だけ救済する', () async {
      final photo = await createPhotoFile('intermediate-invalid-first.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.intermediateTripsKey: jsonEncode(<Object>[
          <String, Object>{
            'title': ' ',
            'photos': <String>[photo.path],
          },
          <String, Object>{
            'title': '',
            'photos': <String>[photo.path],
          },
        ]),
        TripStore.intermediatePrefectureStatesKey: jsonEncode(
          <String, String>{},
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, isEmpty);
      expect(loaded.unassignedPhotos, hasLength(1));
      expect(
        loaded.unassignedPhotos.single.id,
        TripStore.legacyPhotoId(photo.path),
      );
    });

    test('intermediate: 欠損ファイルの参照は後続の実在写真を不当にclaimしない', () async {
      final missing = File('${temporaryDirectory.path}/missing.jpg');
      final existing = await createPhotoFile('intermediate-existing.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.intermediateTripsKey: jsonEncode(<Object>[
          <String, Object>{
            'title': ' ',
            'photos': <String>[missing.path],
          },
          <String, Object>{
            'title': '有効な旅行',
            'photos': <String>[missing.path, existing.path],
          },
        ]),
        TripStore.intermediatePrefectureStatesKey: jsonEncode(
          <String, String>{},
        ),
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, hasLength(1));
      expect(loaded.trips.single.title, '有効な旅行');
      expect(loaded.trips.single.photos, hasLength(1));
      expect(loaded.trips.single.photos.single.file.path, existing.path);
      expect(loaded.unassignedPhotos, isEmpty);
    });

    test('legacy: 空白タイトルが先でも有効旅行が同一写真を優先保持する', () async {
      final photo = await createPhotoFile('legacy-priority.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.legacyTripsKey: <String>[
          '  |${photo.path}',
          '有効な旅行|${photo.path}',
        ],
        TripStore.legacyPrefectureStatesKey: const <String>[],
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, hasLength(1));
      expect(loaded.trips.single.title, '有効な旅行');
      expect(loaded.trips.single.photos, hasLength(1));
      expect(loaded.trips.single.photos.single.file.path, photo.path);
      expect(loaded.unassignedPhotos, isEmpty, reason: '無効タイトル旅行へは重複写真を救済しない');
    });

    test('legacy: パス表記違い（\\と/）でも有効旅行が同一写真を優先保持する', () async {
      final photo = await createPhotoFile('legacy-separator-priority.jpg');
      final slashPath = photo.path.replaceAll('\\', '/');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.legacyTripsKey: <String>[
          '  |$slashPath',
          '有効な旅行|${photo.path}',
        ],
        TripStore.legacyPrefectureStatesKey: const <String>[],
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, hasLength(1));
      expect(loaded.trips.single.title, '有効な旅行');
      expect(loaded.trips.single.photos, hasLength(1));
      expect(loaded.trips.single.photos.single.file.path, photo.path);
      expect(
        loaded.unassignedPhotos,
        isEmpty,
        reason: '表記違いの同一パスは正規化され無効旅行へは重複救済しない',
      );
    });

    test('legacy: 欠損ファイルの参照は後続の実在写真を不当にclaimしない', () async {
      final missing = File('${temporaryDirectory.path}/missing-legacy.jpg');
      final existing = await createPhotoFile('legacy-existing.jpg');
      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.legacyTripsKey: <String>[
          '  |${missing.path}',
          '有効な旅行|${missing.path};;${existing.path}',
        ],
        TripStore.legacyPrefectureStatesKey: const <String>[],
      });
      final store = TripStore();

      final loaded = await store.load();

      expect(loaded.trips, hasLength(1));
      expect(loaded.trips.single.title, '有効な旅行');
      expect(loaded.trips.single.photos, hasLength(1));
      expect(loaded.trips.single.photos.single.file.path, existing.path);
      expect(loaded.unassignedPhotos, isEmpty);
    });
  });

  group('cleanup: 救済写真は孤児として削除されない', () {
    test('startup cleanup相当の処理後も救済写真の物理ファイルが残る', () async {
      final photosDir = Directory('${temporaryDirectory.path}/photos');
      await photosDir.create(recursive: true);
      final photoFile = File('${photosDir.path}/recovered.jpg');
      await photoFile.writeAsBytes(<int>[1, 2, 3]);

      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': ' ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-kept', 'path': photoFile.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();
      expect(loaded.unassignedPhotos.single.id, 'photo-kept');

      final deleted = <String>[];
      await StorageCleanup.run(
        appData: loaded,
        documentsDirectory: temporaryDirectory,
        deleteFileFn: (path) async {
          deleted.add(path);
          await File(path).delete();
        },
      );

      expect(deleted, isNot(contains(photoFile.path)));
      expect(await photoFile.exists(), isTrue);
    });

    test('救済写真が参照集合に含まれればcleanup後の再読込でも残る', () async {
      final photosDir = Directory('${temporaryDirectory.path}/photos');
      await photosDir.create(recursive: true);
      final photoFile = File('${photosDir.path}/recovered-2.jpg');
      await photoFile.writeAsBytes(<int>[1, 2, 3]);

      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: v3Raw(
          trips: <Object>[
            <String, Object>{
              'id': 'trip-broken',
              'title': '  ',
              'photos': <Object>[
                <String, Object>{'id': 'photo-kept-2', 'path': photoFile.path},
              ],
            },
          ],
        ),
      });
      final store = TripStore();

      final loaded = await store.load();
      await store.save(loaded);
      await StorageCleanup.run(
        appData: loaded,
        documentsDirectory: temporaryDirectory,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        TripStore.dataKey: (await SharedPreferences.getInstance()).getString(
          TripStore.dataKey,
        )!,
      });
      final reloaded = await TripStore().load();

      expect(await photoFile.exists(), isTrue);
      expect(reloaded.unassignedPhotos, hasLength(1));
      expect(reloaded.unassignedPhotos.single.file.path, photoFile.path);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/backup_service.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/photo.dart';

Photo photoOf(File file) => Photo.fromFile(file);

/// v2/v3用に手組みのバックアップZIPを作る。
List<int> backupArchiveBytes({
  required Object trips,
  Object? unassignedPhotos,
  int formatVersion = BackupService.currentFormatVersion,
  Map<String, String>? checksums,
  int? tripCount,
  int? photoCount,
  int totalUncompressedBytes = 0,
}) {
  final resolvedUnassigned =
      unassignedPhotos ?? (formatVersion == 1 ? null : <Object>[]);
  final manifest = <String, Object>{
    'appId': BackupService.appId,
    'backupFormatVersion': formatVersion,
    'tripCount': tripCount ?? (trips as List).length,
    'photoCount': photoCount ?? 0,
    'totalUncompressedBytes': totalUncompressedBytes,
    if (formatVersion >= 2) 'checksumsAlgorithm': 'sha-256',
    if (formatVersion >= 2) 'checksums': checksums ?? <String, String>{},
  };
  final records = <String, Object>{
    'trips': trips,
    'unassignedPhotos': ?resolvedUnassigned,
    'prefectureStates': const <String, String>{},
  };
  final manifestContent = utf8.encode(jsonEncode(manifest));
  final recordsContent = utf8.encode(jsonEncode(records));
  final archive = Archive()
    ..addFile(
      ArchiveFile('manifest.json', manifestContent.length, manifestContent),
    )
    ..addFile(ArchiveFile('trips.json', recordsContent.length, recordsContent));
  return ZipEncoder().encode(archive);
}

AppData appDataWithTrips(int count, {List<Photo>? photosPerTrip}) {
  return AppData(
    trips: List<Trip>.generate(
      count,
      (i) => Trip(
        id: 'trip-$i',
        title: '旅行$i',
        photos: photosPerTrip ?? const <Photo>[],
      ),
    ),
    unassignedPhotos: const <Photo>[],
    prefectureStates: const <String, String>{},
  );
}

Future<void> expectNoBackupArtifacts(Directory temporaryDirectory) async {
  expect(
    await Directory('${temporaryDirectory.path}/backups').exists(),
    isFalse,
    reason: 'バックアップZIP保存ディレクトリが作成されていないこと',
  );
  expect(
    await Directory('${temporaryDirectory.path}/safety-backups').exists(),
    isFalse,
    reason: 'safety snapshot保存ディレクトリが作成されていないこと',
  );
  expect(
    await Directory('${temporaryDirectory.path}/backup-staging').exists(),
    isFalse,
    reason: 'staging directoryが残っていないこと',
  );
}

void main() {
  late Directory temporaryDirectory;
  late BackupService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'kokoitta-backup',
    );
    service = BackupService(
      documentsDirectoryProvider: () async => temporaryDirectory,
      backupFilePicker: () async => null,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('バックアップを検証用領域へ展開してからコミットする', () async {
    final photo = File('${temporaryDirectory.path}/source.jpg');
    await photo.writeAsBytes(<int>[1, 2, 3, 4]);
    final original = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行', photos: <Photo>[photoOf(photo)]),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{'埼玉': 'visited'},
    );

    final backup = await service.createBackup(original);
    final prepared = await service.prepareRestoreFile(backup);

    expect(prepared.tripCount, 1);
    expect(prepared.photoCount, 1);
    expect(await prepared.stagingDirectory.exists(), isTrue);

    final committed = await prepared.commit();

    expect(committed.data.trips.single.title, '旅行');
    expect(
      await committed.data.trips.single.photos.single.file.exists(),
      isTrue,
    );
    expect(committed.data.prefectureStates['埼玉'], 'visited');
    expect(await prepared.stagingDirectory.exists(), isFalse);
  });

  test('復元キャンセルで一時領域を削除する', () async {
    final empty = AppData.empty();
    final backup = await service.createBackup(empty);
    final prepared = await service.prepareRestoreFile(backup);
    final stagingPath = prepared.stagingDirectory.path;

    await prepared.discard();

    expect(await Directory(stagingPath).exists(), isFalse);
  });

  test('v3バックアップで写真IDとmetadataが保持される', () async {
    final photo = File('${temporaryDirectory.path}/meta.jpg');
    await photo.writeAsBytes(<int>[9, 9, 9]);
    final capturedAt = DateTime(2026, 7, 15, 12, 0);
    final original = AppData(
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

    final backup = await service.createBackup(original);
    final prepared = await service.prepareRestoreFile(backup);
    final committed = await prepared.commit();

    final restored = committed.data.trips.single.photos.single;
    expect(restored.id, 'photo-meta-1');
    expect(restored.capturedAt, capturedAt);
    expect(restored.location, '東京都');
    expect(restored.originalName, 'dsc_001.jpg');
    expect(restored.mimeType, 'image/jpeg');
    expect(await restored.file.exists(), isTrue);
  });

  test('同一写真IDを2箇所に持つデータはバックアップ作成を拒否する', () async {
    final photo = File('${temporaryDirectory.path}/dup.jpg');
    await photo.writeAsBytes(<int>[1, 2, 3]);
    final photoEntity = photoOf(photo);
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行', photos: <Photo>[photoEntity]),
      ],
      unassignedPhotos: <Photo>[photoEntity],
      prefectureStates: const <String, String>{},
    );

    await expectLater(service.createBackup(data), throwsStateError);
  });

  test('写真が改変されたバックアップを拒否する', () async {
    final photo = File('${temporaryDirectory.path}/tamper.jpg');
    await photo.writeAsBytes(<int>[10, 20, 30]);
    final backup = await service.createBackup(
      AppData(
        trips: <Trip>[
          Trip(id: 'trip-1', title: '旅行', photos: <Photo>[photoOf(photo)]),
        ],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    final original = ZipDecoder().decodeBytes(await backup.readAsBytes());
    final tampered = Archive();
    for (final entry in original.files) {
      final bytes = entry.readBytes();
      if (bytes == null) continue;
      final copied = List<int>.from(bytes);
      if (entry.name.startsWith('photos/') && copied.isNotEmpty) {
        copied[0] = copied[0] ^ 0xff;
      }
      tampered.addFile(ArchiveFile(entry.name, copied.length, copied));
    }

    await expectLater(
      service.prepareRestoreBytes(ZipEncoder().encode(tampered)),
      throwsA(isA<FormatException>()),
    );
  });

  test('上限超過のmanifest.jsonをreadBytes()前に拒否する', () async {
    final validBackup = await service.createBackup(
      AppData(
        trips: <Trip>[],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files.firstWhere((f) => f.name == 'manifest.json').size =
        BackupService.maxManifestBytes + 1;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('上限超過のtrips.jsonをreadBytes()前に拒否する', () async {
    final validBackup = await service.createBackup(
      AppData(
        trips: <Trip>[],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files.firstWhere((f) => f.name == 'trips.json').size =
        BackupService.maxTripsBytes + 1;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('サイズ0のmanifest.jsonを展開前に拒否する', () async {
    final validBackup = await service.createBackup(
      AppData(
        trips: <Trip>[],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files.firstWhere((f) => f.name == 'manifest.json').size = 0;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('サイズ0のtrips.jsonを展開前に拒否する', () async {
    final validBackup = await service.createBackup(
      AppData(
        trips: <Trip>[],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files.firstWhere((f) => f.name == 'trips.json').size = 0;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('負数サイズが上限超過として拒否される', () async {
    final validBackup = await service.createBackup(
      AppData(
        trips: <Trip>[],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files.firstWhere((f) => f.name == 'manifest.json').size = -1;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('高圧縮率の巨大JSONを模したZIPを拒否する', () async {
    final archive = Archive();
    final hugeDeclaredSize = BackupService.maxTripsBytes + 100;
    final tripsContent = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': <Object>[],
        'unassignedPhotos': <Object>[],
        'prefectureStates': const <String, String>{},
      }),
    );
    final manifestContent = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': BackupService.currentFormatVersion,
        'tripCount': 0,
        'photoCount': 0,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    archive
      ..addFile(ArchiveFile('trips.json', hugeDeclaredSize, tripsContent))
      ..addFile(
        ArchiveFile('manifest.json', manifestContent.length, manifestContent),
      );
    final encoded = ZipEncoder().encode(archive);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('ディレクトリエントリを拒否する', () async {
    final validBackup = await service.createBackup(
      AppData(
        trips: <Trip>[],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    final dirEntry = ArchiveFile('photos/', 0, [])..isFile = false;
    decoded.addFile(dirEntry);
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('過大な旅行名を200文字に切り詰めて復元する', () async {
    final archive = Archive();
    final longTitle = 'あ' * 250;
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': 1,
        'tripCount': 1,
        'photoCount': 0,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<Object>[
        <String, Object>{'title': longTitle, 'photos': <String>[]},
      ]),
    );
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    final prepared = await service.prepareRestoreBytes(bytes);
    expect(prepared.trips.single.title.length, 200);
    expect(prepared.trips.single.title, 'あ' * 200);
  });

  test('未知の都道府県キーを安全に無視して復元する', () async {
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': 2,
        'tripCount': 0,
        'photoCount': 0,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': const <Object>[],
        'unassignedPhotos': const <String>[],
        'prefectureStates': <String, String>{
          '北海道': 'visited',
          '未知県': 'visited',
        },
      }),
    );
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    final prepared = await service.prepareRestoreBytes(bytes);
    expect(prepared.prefectureStates.containsKey('未知県'), isFalse);
    expect(prepared.prefectureStates['北海道'], 'visited');
  });

  test('不正な状態値をunvisitedに正規化して復元する', () async {
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': 2,
        'tripCount': 0,
        'photoCount': 0,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': const <Object>[],
        'unassignedPhotos': const <String>[],
        'prefectureStates': <String, String>{'東京': 'invalid_state'},
      }),
    );
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    final prepared = await service.prepareRestoreBytes(bytes);
    expect(prepared.prefectureStates['東京'], 'unvisited');
  });

  test('制御文字を含む旅行名を正規化して復元する', () async {
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': 2,
        'tripCount': 1,
        'photoCount': 0,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': <Object>[
          <String, Object>{
            'id': 'test-trip-1',
            'title': '東京\n旅行',
            'photos': <String>[],
          },
        ],
        'unassignedPhotos': const <String>[],
        'prefectureStates': const <String, String>{},
      }),
    );
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    final prepared = await service.prepareRestoreBytes(bytes);
    expect(prepared.trips.single.title, '東京 旅行');
  });

  test('過大なリストまたはMapを拒否する', () async {
    final archive = Archive();
    final manyPhotos = List<String>.generate(
      600,
      (i) => 'photos/trip-0-${i.toString().padLeft(3, '0')}.jpg',
    );
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': BackupService.currentFormatVersion,
        'tripCount': 1,
        'photoCount': manyPhotos.length,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': <Object>[
          <String, Object>{
            'id': 'trip-1',
            'title': '旅行',
            'photos': manyPhotos
                .map(
                  (p) => <String, Object>{
                    'id': 'photo-dup-$p',
                    'archivePath': p,
                  },
                )
                .toList(),
          },
        ],
        'unassignedPhotos': <Object>[],
        'prefectureStates': const <String, String>{},
      }),
    );
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('正常なv1バックアップを復元できる', () async {
    final archive = Archive();
    final photoContent = <int>[1, 2, 3, 4];
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': 1,
        'tripCount': 1,
        'photoCount': 1,
        'totalUncompressedBytes': photoContent.length,
      }),
    );
    final records = utf8.encode(
      jsonEncode(<Object>[
        <String, Object>{
          'title': 'v1旅行',
          'photos': <String>['photos/trip-0-000.jpg'],
        },
      ]),
    );
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records))
      ..addFile(
        ArchiveFile('photos/trip-0-000.jpg', photoContent.length, photoContent),
      );

    final bytes = ZipEncoder().encode(archive);

    final prepared = await service.prepareRestoreBytes(bytes);
    expect(prepared.tripCount, 1);
    expect(prepared.photoCount, 1);
    expect(prepared.trips.single.photos.single.id, startsWith('photo-'));

    final committed = await prepared.commit();
    expect(
      await committed.data.trips.single.photos.single.file.exists(),
      isTrue,
    );
    expect(committed.data.trips.single.photos.single.originalName, isNull);
  });

  test('正常なv2バックアップを復元できる（写真は新規IDで復元）', () async {
    final photoContent = <int>[5, 6, 7, 8];
    final checksum = sha256.convert(photoContent).toString();
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': 2,
        'tripCount': 1,
        'photoCount': 1,
        'totalUncompressedBytes': photoContent.length,
        'checksumsAlgorithm': 'sha-256',
        'checksums': <String, String>{'photos/trip-0-000.jpg': checksum},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': <Object>[
          <String, Object>{
            'id': 'trip-v2',
            'title': 'v2旅行',
            'photos': <String>['photos/trip-0-000.jpg'],
          },
        ],
        'unassignedPhotos': <String>[],
        'prefectureStates': <String, String>{'東京': 'visited'},
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records))
      ..addFile(
        ArchiveFile('photos/trip-0-000.jpg', photoContent.length, photoContent),
      );

    final bytes = ZipEncoder().encode(archive);

    final prepared = await service.prepareRestoreBytes(bytes);
    final committed = await prepared.commit();

    expect(committed.data.trips.single.title, 'v2旅行');
    expect(committed.data.trips.single.photos.single.id, startsWith('photo-'));
    expect(committed.data.trips.single.photos.single.originalName, isNull);
    expect(
      await committed.data.trips.single.photos.single.file.exists(),
      isTrue,
    );
    expect(committed.data.prefectureStates['東京'], 'visited');
  });

  test('v3バックアップの重複写真IDを拒否する', () async {
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': BackupService.currentFormatVersion,
        'tripCount': 1,
        'photoCount': 2,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': <Object>[
          <String, Object>{
            'id': 'trip-1',
            'title': '重複ID',
            'photos': <Object>[
              <String, Object>{
                'id': 'photo-x',
                'archivePath': 'photos/trip-0-000.jpg',
              },
              <String, Object>{
                'id': 'photo-x',
                'archivePath': 'photos/trip-0-001.jpg',
              },
            ],
          },
        ],
        'unassignedPhotos': const <Object>[],
        'prefectureStates': const <String, String>{},
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('未来のバックアップ形式を拒否する', () async {
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': BackupService.appId,
        'backupFormatVersion': BackupService.currentFormatVersion + 1,
        'tripCount': 0,
        'photoCount': 0,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': const <Object>[],
        'unassignedPhotos': const <Object>[],
        'prefectureStates': const <String, String>{},
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('別アプリのバックアップを拒否する', () async {
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode(<String, Object>{
        'appId': 'com.example.other',
        'backupFormatVersion': 2,
        'tripCount': 0,
        'photoCount': 0,
        'totalUncompressedBytes': 0,
        'checksumsAlgorithm': 'sha-256',
        'checksums': const <String, String>{},
      }),
    );
    final records = utf8.encode(
      jsonEncode(<String, Object>{
        'trips': const <Object>[],
        'unassignedPhotos': const <String>[],
        'prefectureStates': const <String, String>{},
      }),
    );
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('0旅行・0写真のバックアップが作成からコミットまで往復できる', () async {
    final backup = await service.createBackup(AppData.empty());
    final prepared = await service.prepareRestoreFile(backup);

    expect(prepared.tripCount, 0);
    expect(prepared.photoCount, 0);

    final committed = await prepared.commit();
    expect(committed.data.trips, isEmpty);
    expect(committed.data.unassignedPhotos, isEmpty);
  });

  test('10旅行のバックアップが作成から復元コミットまで往復できる', () async {
    final data = appDataWithTrips(BackupService.maxTrips);
    final backup = await service.createBackup(data);
    final prepared = await service.prepareRestoreFile(backup);
    final committed = await prepared.commit();

    expect(committed.data.trips.length, BackupService.maxTrips);
    expect(
      committed.data.trips.map((trip) => trip.id).toSet(),
      data.trips.map((trip) => trip.id).toSet(),
    );
  });

  test('11旅行を含むAppDataはZIP・staging作成前に明示的に失敗する', () async {
    final data = appDataWithTrips(BackupService.maxTrips + 1);

    await expectLater(
      service.createBackup(data),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('旅行数'),
        ),
      ),
    );
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('300写真（10旅行×30枚）が作成から復元コミットまで往復できる', () async {
    final photos = <Photo>[];
    for (var i = 0; i < BackupService.maxPhotos; i++) {
      final file = File('${temporaryDirectory.path}/photos/p$i.jpg');
      await file.create(recursive: true);
      await file.writeAsBytes(<int>[i & 0xff, (i >> 8) & 0xff]);
      photos.add(Photo(id: 'photo-$i', file: file, originalName: 'p$i.jpg'));
    }
    final data = AppData(
      trips: List<Trip>.generate(
        10,
        (i) => Trip(
          id: 'trip-$i',
          title: '旅行$i',
          photos: photos.sublist(i * 30, (i + 1) * 30),
        ),
      ),
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    final backup = await service.createBackup(data);
    final prepared = await service.prepareRestoreFile(backup);
    expect(prepared.tripCount, 10);
    expect(prepared.photoCount, BackupService.maxPhotos);

    final committed = await prepared.commit();
    final restoredIds = committed.data.allPhotos
        .map((photo) => photo.id)
        .toSet();
    expect(restoredIds, {for (var i = 0; i < 300; i++) 'photo-$i'});
    for (final photo in committed.data.allPhotos) {
      expect(await photo.file.exists(), isTrue);
    }
  });

  test('301写真は作成前に失敗し成果物を残さない', () async {
    final photos = List<Photo>.generate(
      BackupService.maxPhotos + 1,
      (i) => Photo(
        id: 'photo-$i',
        file: File('${temporaryDirectory.path}/missing/p$i.jpg'),
      ),
    );
    final data = AppData(
      trips: <Trip>[Trip(id: 'trip-1', title: '旅行', photos: photos)],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await expectLater(
      service.createBackup(data),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('写真枚数'),
        ),
      ),
    );
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('同一写真IDが別の旅行に重複しても作成を拒否する', () async {
    final photo = Photo(
      id: 'photo-dup',
      file: File('${temporaryDirectory.path}/dup.jpg'),
    );
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行A', photos: <Photo>[photo]),
        Trip(id: 'trip-2', title: '旅行B', photos: <Photo>[photo]),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await expectLater(service.createBackup(data), throwsStateError);
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('同一ファイルを旅行と旅行未設定の両方に持つデータは作成を拒否する', () async {
    final photo = Photo(
      id: 'photo-both',
      file: File('${temporaryDirectory.path}/both.jpg'),
    );
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行', photos: <Photo>[photo]),
      ],
      unassignedPhotos: <Photo>[photo],
      prefectureStates: const <String, String>{},
    );

    await expectLater(service.createBackup(data), throwsStateError);
  });

  test('IDが異なっても同一正規化パスを参照する写真は作成を拒否する', () async {
    final photoA = Photo(
      id: 'photo-a',
      file: File('${temporaryDirectory.path}/dir/photo.jpg'),
    );
    final photoB = Photo(
      id: 'photo-b',
      file: File('${temporaryDirectory.path}/dir/./photo.jpg'),
    );
    final data = AppData(
      trips: <Trip>[
        Trip(id: 'trip-1', title: '旅行', photos: <Photo>[photoA, photoB]),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await expectLater(service.createBackup(data), throwsStateError);
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('空の旅行IDまたは写真IDは作成を拒否する', () async {
    final emptyTripId = AppData(
      trips: <Trip>[Trip(id: '', title: '旅行', photos: const <Photo>[])],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );
    await expectLater(service.createBackup(emptyTripId), throwsStateError);

    final emptyPhotoId = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '旅行',
          photos: <Photo>[
            Photo(id: '', file: File('${temporaryDirectory.path}/x.jpg')),
          ],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );
    await expectLater(service.createBackup(emptyPhotoId), throwsStateError);
  });

  test('欠損した写真ファイルを含むデータは作成を拒否する', () async {
    final data = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '旅行',
          photos: <Photo>[
            Photo(
              id: 'photo-missing',
              file: File('${temporaryDirectory.path}/not-there.jpg'),
            ),
          ],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await expectLater(
      service.createBackup(data),
      throwsA(isA<FileSystemException>()),
    );
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('単一写真の容量が上限直前・ちょうどなら作成・復元できる', () async {
    final sized = BackupService(
      documentsDirectoryProvider: () async => temporaryDirectory,
      backupFilePicker: () async => null,
      maxSinglePhotoBytes: 100,
    );
    for (final length in <int>[99, 100]) {
      final photo = File('${temporaryDirectory.path}/single-$length.jpg');
      await photo.writeAsBytes(List<int>.generate(length, (i) => i % 256));
      final data = AppData(
        trips: <Trip>[
          Trip(
            id: 'trip-1',
            title: '旅行',
            photos: <Photo>[Photo(id: 'photo-$length', file: photo)],
          ),
        ],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      );

      final backup = await sized.createBackup(data);
      final prepared = await sized.prepareRestoreFile(backup);
      expect(prepared.photoCount, 1);
      final committed = await prepared.commit();
      expect(
        await committed.data.trips.single.photos.single.file.length(),
        length,
      );
    }
  });

  test('単一写真の容量が上限を超えると作成前に失敗し成果物を残さない', () async {
    final sized = BackupService(
      documentsDirectoryProvider: () async => temporaryDirectory,
      backupFilePicker: () async => null,
      maxSinglePhotoBytes: 100,
    );
    final photo = File('${temporaryDirectory.path}/single-101.jpg');
    await photo.writeAsBytes(List<int>.generate(101, (i) => i % 256));
    final data = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '旅行',
          photos: <Photo>[Photo(id: 'photo-101', file: photo)],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await expectLater(
      sized.createBackup(data),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('写真1枚の容量'),
        ),
      ),
    );
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('合計容量が上限直前・ちょうどなら作成・復元できる', () async {
    final sized = BackupService(
      documentsDirectoryProvider: () async => temporaryDirectory,
      backupFilePicker: () async => null,
      maxUncompressedBytes: 100,
    );
    final cases = <String, List<int>>{
      'just-below': <int>[49, 50],
      'exact': <int>[100],
    };
    for (final entry in cases.entries) {
      final photos = <Photo>[];
      for (var i = 0; i < entry.value.length; i++) {
        final file = File(
          '${temporaryDirectory.path}/total-${entry.key}-$i.jpg',
        );
        await file.writeAsBytes(
          List<int>.generate(entry.value[i], (j) => j % 256),
        );
        photos.add(Photo(id: 'photo-${entry.key}-$i', file: file));
      }
      final data = AppData(
        trips: <Trip>[Trip(id: 'trip-1', title: '旅行', photos: photos)],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      );

      final backup = await sized.createBackup(data);
      final prepared = await sized.prepareRestoreFile(backup);
      expect(prepared.photoCount, photos.length);
      final committed = await prepared.commit();
      expect(committed.data.trips.single.photos.length, photos.length);
    }
  });

  test('合計容量が上限を超えると作成前に失敗し成果物を残さない', () async {
    final sized = BackupService(
      documentsDirectoryProvider: () async => temporaryDirectory,
      backupFilePicker: () async => null,
      maxUncompressedBytes: 100,
    );
    final photos = <Photo>[];
    for (final size in <int>[50, 51]) {
      final file = File('${temporaryDirectory.path}/total-over-$size.jpg');
      await file.writeAsBytes(List<int>.generate(size, (i) => i % 256));
      photos.add(Photo(id: 'photo-over-$size', file: file));
    }
    final data = AppData(
      trips: <Trip>[Trip(id: 'trip-1', title: '旅行', photos: photos)],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    await expectLater(
      sized.createBackup(data),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('写真容量'),
        ),
      ),
    );
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('写真メタデータが500文字ちょうどなら往復し、超過すると作成を拒否する', () async {
    final photoFile = File('${temporaryDirectory.path}/meta-boundary.jpg');
    await photoFile.writeAsBytes(<int>[1, 2, 3]);
    final boundaryData = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '旅行',
          photos: <Photo>[
            Photo(id: 'photo-meta-500', file: photoFile, location: 'x' * 500),
          ],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    final backup = await service.createBackup(boundaryData);
    final committed = await service
        .prepareRestoreFile(backup)
        .then((prepared) => prepared.commit());
    expect(committed.data.trips.single.photos.single.location, 'x' * 500);

    final overData = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '旅行',
          photos: <Photo>[
            Photo(id: 'photo-meta-501', file: photoFile, location: 'x' * 501),
          ],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );
    await expectLater(service.createBackup(overData), throwsFormatException);
  });

  test('safety snapshotも作成から復元コミットまで往復できる', () async {
    final photo = File('${temporaryDirectory.path}/snapshot.jpg');
    await photo.writeAsBytes(<int>[7, 8, 9]);
    final data = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: 'スナップショット旅行',
          photos: <Photo>[Photo(id: 'photo-snap', file: photo)],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{'東京': 'visited'},
    );

    final snapshot = await service.createSafetySnapshot(data);
    expect(snapshot.path, contains('safety-backups'));

    final prepared = await service.prepareRestoreFile(snapshot);
    final committed = await prepared.commit();
    expect(committed.data.trips.single.title, 'スナップショット旅行');
    expect(committed.data.trips.single.photos.single.id, 'photo-snap');
    expect(committed.data.prefectureStates['東京'], 'visited');
  });

  test('manual backupとsafety snapshotに同じ検証が適用される', () async {
    final invalid = appDataWithTrips(BackupService.maxTrips + 1);

    await expectLater(
      service.createBackup(invalid),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      service.createSafetySnapshot(invalid),
      throwsA(isA<FormatException>()),
    );
    await expectNoBackupArtifacts(temporaryDirectory);
  });

  test('v3バックアップで旅行数11件を拒否する', () async {
    final bytes = backupArchiveBytes(
      trips: List<Map<String, Object>>.generate(
        BackupService.maxTrips + 1,
        (i) => <String, Object>{
          'id': 'trip-$i',
          'title': '旅行$i',
          'photos': <Object>[],
        },
      ),
    );

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('旅行数'),
        ),
      ),
    );
  });

  test('v3バックアップで写真枚数301件を拒否する', () async {
    final bytes = backupArchiveBytes(
      trips: <Map<String, Object>>[
        <String, Object>{
          'id': 'trip-1',
          'title': '旅行',
          'photos': List<Map<String, Object>>.generate(
            BackupService.maxPhotos + 1,
            (i) => <String, Object>{
              'id': 'photo-$i',
              'archivePath':
                  'photos/trip-0-${i.toString().padLeft(3, '0')}.jpg',
            },
          ),
        },
      ],
      photoCount: BackupService.maxPhotos + 1,
    );

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('写真枚数'),
        ),
      ),
    );
  });

  test('v3バックアップの重複旅行IDを拒否する', () async {
    final bytes = backupArchiveBytes(
      trips: <Map<String, Object>>[
        <String, Object>{'id': 'trip-x', 'title': '旅行A', 'photos': <Object>[]},
        <String, Object>{'id': 'trip-x', 'title': '旅行B', 'photos': <Object>[]},
      ],
      tripCount: 2,
    );

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('旅行ID'),
        ),
      ),
    );
  });

  test('v3バックアップで同一archivePathの複数参照を拒否する', () async {
    final bytes = backupArchiveBytes(
      trips: <Map<String, Object>>[
        <String, Object>{
          'id': 'trip-a',
          'title': '旅行A',
          'photos': <Object>[
            <String, Object>{
              'id': 'photo-a',
              'archivePath': 'photos/trip-0-000.jpg',
            },
          ],
        },
        <String, Object>{
          'id': 'trip-b',
          'title': '旅行B',
          'photos': <Object>[
            <String, Object>{
              'id': 'photo-b',
              'archivePath': 'photos/trip-0-000.jpg',
            },
          ],
        },
      ],
      tripCount: 2,
      photoCount: 2,
    );

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('写真パス'),
        ),
      ),
    );
  });

  test('v2バックアップの重複旅行IDは新規IDへ振り直して復元できる', () async {
    final bytes = backupArchiveBytes(
      formatVersion: 2,
      trips: <Map<String, Object>>[
        <String, Object>{'id': 'trip-x', 'title': '旅行A', 'photos': <Object>[]},
        <String, Object>{'id': 'trip-x', 'title': '旅行B', 'photos': <Object>[]},
      ],
      tripCount: 2,
    );

    final prepared = await service.prepareRestoreBytes(bytes);
    expect(prepared.tripCount, 2);
    expect(
      prepared.trips.map((trip) => trip.id).toSet().length,
      2,
      reason: '重複した旅行IDは復元時に新規IDへ振り直される',
    );
  });

  test('restore prepare成功後のcommit失敗時は永続領域に部分成果物を残さない', () async {
    final photo = File('${temporaryDirectory.path}/commit-fail.jpg');
    await photo.writeAsBytes(<int>[1, 2, 3]);
    final data = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-1',
          title: '旅行',
          photos: <Photo>[Photo(id: 'photo-commit', file: photo)],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    final backup = await service.createBackup(data);
    final prepared = await service.prepareRestoreFile(backup);
    await prepared.stagingDirectory.delete(recursive: true);

    await expectLater(prepared.commit(), throwsA(isA<FileSystemException>()));

    final permanentRoot = Directory('${temporaryDirectory.path}/photo-sets');
    if (!await permanentRoot.exists()) return;
    final remaining = await permanentRoot
        .list()
        .where(
          (entity) =>
              entity.path.split(RegExp(r'[/\\]')).last.startsWith('restore-'),
        )
        .toList();
    expect(remaining, isEmpty);
  });
}

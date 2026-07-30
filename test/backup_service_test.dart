import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/backup_service.dart';
import 'package:kokoitta_app/models.dart';

void main() {
  late Directory temporaryDirectory;
  late BackupService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('kokoitta-backup');
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
        Trip(id: 'trip-1', title: '旅行', photos: <File>[photo]),
      ],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{'埼玉': 'visited'},
    );

    final backup = await service.createBackup(original);
    final prepared = await service.prepareRestoreFile(backup);

    expect(prepared.tripCount, 1);
    expect(prepared.photoCount, 1);
    expect(await prepared.stagingDirectory.exists(), isTrue);

    final committed = await prepared.commit();

    expect(committed.data.trips.single.title, '旅行');
    expect(await committed.data.trips.single.photos.single.exists(), isTrue);
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


  test('写真が改変されたバックアップを拒否する', () async {
    final photo = File('${temporaryDirectory.path}/tamper.jpg');
    await photo.writeAsBytes(<int>[10, 20, 30]);
    final backup = await service.createBackup(
      AppData(
        trips: <Trip>[
          Trip(id: 'trip-1', title: '旅行', photos: <File>[photo]),
        ],
        unassignedPhotos: const <File>[],
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
    final validBackup = await service.createBackup(AppData(
      trips: <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    ));
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files
        .firstWhere((f) => f.name == 'manifest.json')
        .size = BackupService.maxManifestBytes + 1;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('上限超過のtrips.jsonをreadBytes()前に拒否する', () async {
    final validBackup = await service.createBackup(AppData(
      trips: <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    ));
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files
        .firstWhere((f) => f.name == 'trips.json')
        .size = BackupService.maxTripsBytes + 1;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('サイズ0のmanifest.jsonを展開前に拒否する', () async {
    final validBackup = await service.createBackup(AppData(
      trips: <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    ));
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files
        .firstWhere((f) => f.name == 'manifest.json')
        .size = 0;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('サイズ0のtrips.jsonを展開前に拒否する', () async {
    final validBackup = await service.createBackup(AppData(
      trips: <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    ));
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files
        .firstWhere((f) => f.name == 'trips.json')
        .size = 0;
    final encoded = ZipEncoder().encode(decoded);

    await expectLater(
      service.prepareRestoreBytes(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('負数サイズが上限超過として拒否される', () async {
    final validBackup = await service.createBackup(AppData(
      trips: <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    ));
    final decoded = ZipDecoder().decodeBytes(await validBackup.readAsBytes());
    decoded.files
        .firstWhere((f) => f.name == 'manifest.json')
        .size = -1;
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
        'unassignedPhotos': <String>[],
        'prefectureStates': const <String, String>{},
      }),
    );
    final manifestContent = utf8.encode(jsonEncode(<String, Object>{
      'appId': BackupService.appId,
      'backupFormatVersion': BackupService.currentFormatVersion,
      'tripCount': 0,
      'photoCount': 0,
      'totalUncompressedBytes': 0,
      'checksumsAlgorithm': 'sha-256',
      'checksums': const <String, String>{},
    }));
    archive
      ..addFile(
        ArchiveFile('trips.json', hugeDeclaredSize, tripsContent),
      )
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
    final validBackup = await service.createBackup(AppData(
      trips: <Trip>[],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    ));
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
    final manifest = utf8.encode(jsonEncode(<String, Object>{
      'appId': BackupService.appId,
      'backupFormatVersion': 1,
      'tripCount': 1,
      'photoCount': 0,
      'totalUncompressedBytes': 0,
      'checksumsAlgorithm': 'sha-256',
      'checksums': const <String, String>{},
    }));
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
    final manifest = utf8.encode(jsonEncode(<String, Object>{
      'appId': BackupService.appId,
      'backupFormatVersion': 2,
      'tripCount': 0,
      'photoCount': 0,
      'totalUncompressedBytes': 0,
      'checksumsAlgorithm': 'sha-256',
      'checksums': const <String, String>{},
    }));
    final records = utf8.encode(jsonEncode(<String, Object>{
      'trips': const <Object>[],
      'unassignedPhotos': const <String>[],
      'prefectureStates': <String, String>{
        '北海道': 'visited',
        '未知県': 'visited',
      },
    }));
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
    final manifest = utf8.encode(jsonEncode(<String, Object>{
      'appId': BackupService.appId,
      'backupFormatVersion': 2,
      'tripCount': 0,
      'photoCount': 0,
      'totalUncompressedBytes': 0,
      'checksumsAlgorithm': 'sha-256',
      'checksums': const <String, String>{},
    }));
    final records = utf8.encode(jsonEncode(<String, Object>{
      'trips': const <Object>[],
      'unassignedPhotos': const <String>[],
      'prefectureStates': <String, String>{
        '東京': 'invalid_state',
      },
    }));
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    final prepared = await service.prepareRestoreBytes(bytes);
    expect(prepared.prefectureStates['東京'], 'unvisited');
  });

  test('制御文字を含む旅行名を正規化して復元する', () async {
    final archive = Archive();
    final manifest = utf8.encode(jsonEncode(<String, Object>{
      'appId': BackupService.appId,
      'backupFormatVersion': 2,
      'tripCount': 1,
      'photoCount': 0,
      'totalUncompressedBytes': 0,
      'checksumsAlgorithm': 'sha-256',
      'checksums': const <String, String>{},
    }));
    final records = utf8.encode(jsonEncode(<String, Object>{
      'trips': <Object>[
        <String, Object>{
          'id': 'test-trip-1',
          'title': '東京\n旅行',
          'photos': <String>[],
        },
      ],
      'unassignedPhotos': const <String>[],
      'prefectureStates': const <String, String>{},
    }));
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
    final manifest = utf8.encode(jsonEncode(<String, Object>{
      'appId': BackupService.appId,
      'backupFormatVersion': BackupService.currentFormatVersion,
      'tripCount': 1,
      'photoCount': manyPhotos.length,
      'totalUncompressedBytes': 0,
      'checksumsAlgorithm': 'sha-256',
      'checksums': <String, String>{},
    }));
    final records = utf8.encode(jsonEncode(<String, Object>{
      'trips': <Object>[
        <String, Object>{'id': 'trip-1', 'title': '旅行', 'photos': manyPhotos},
      ],
      'unassignedPhotos': <String>[],
      'prefectureStates': const <String, String>{},
    }));
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
    final manifest = utf8.encode(jsonEncode(<String, Object>{
      'appId': BackupService.appId,
      'backupFormatVersion': 1,
      'tripCount': 1,
      'photoCount': 1,
      'totalUncompressedBytes': photoContent.length,
    }));
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
  });

  test('正常なv2バックアップを復元できる', () async {
    final photo = File('${temporaryDirectory.path}/v2_photo.jpg');
    await photo.writeAsBytes(<int>[5, 6, 7, 8]);
    final original = AppData(
      trips: <Trip>[
        Trip(id: 'trip-v2', title: 'v2旅行', photos: <File>[photo]),
      ],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{'東京': 'visited'},
    );

    final backup = await service.createBackup(original);
    final prepared = await service.prepareRestoreFile(backup);

    expect(prepared.tripCount, 1);
    expect(prepared.photoCount, 1);
    expect(prepared.prefectureStates['東京'], 'visited');
  });

  test('別アプリのバックアップを拒否する', () async {
    final archive = Archive();
    final manifest = utf8.encode(jsonEncode(<String, Object>{
      'appId': 'com.example.other',
      'backupFormatVersion': 2,
      'tripCount': 0,
      'photoCount': 0,
      'totalUncompressedBytes': 0,
      'checksumsAlgorithm': 'sha-256',
      'checksums': const <String, String>{},
    }));
    final records = utf8.encode(jsonEncode(<String, Object>{
      'trips': const <Object>[],
      'unassignedPhotos': const <String>[],
      'prefectureStates': const <String, String>{},
    }));
    archive
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('trips.json', records.length, records));

    final bytes = ZipEncoder().encode(archive);

    await expectLater(
      service.prepareRestoreBytes(bytes),
      throwsA(isA<FormatException>()),
    );
  });
}

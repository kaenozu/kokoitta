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

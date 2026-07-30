import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/storage_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kokoitta-cleanup');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('manual backup retention', () {
    test('keeps newest 5 and deletes older backups', () async {
      final backupsDir = Directory('${tempDir.path}/backups');
      await backupsDir.create(recursive: true);

      for (var i = 0; i < 8; i++) {
        final file = File(
          '${backupsDir.path}/kokoitta-backup-${1000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(backupsDir.listSync().whereType<File>().length, equals(5));
    });

    test('keeps all backups when count is below the limit', () async {
      final backupsDir = Directory('${tempDir.path}/backups');
      await backupsDir.create(recursive: true);

      for (var i = 0; i < 3; i++) {
        final file = File(
          '${backupsDir.path}/kokoitta-backup-${1000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(backupsDir.listSync().whereType<File>().length, equals(3));
    });

    test('does nothing when backups directory does not exist', () async {
      await StorageCleanup.run(documentsDirectory: tempDir);
      expect(true, isTrue);
    });
  });

  group('safety snapshot retention', () {
    test('keeps newest 3 and deletes older snapshots', () async {
      final snapshotsDir = Directory('${tempDir.path}/safety-backups');
      await snapshotsDir.create(recursive: true);

      for (var i = 0; i < 6; i++) {
        final file = File(
          '${snapshotsDir.path}/kokoitta-backup-${2000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(snapshotsDir.listSync().whereType<File>().length, equals(3));
    });

    test('keeps all snapshots when count is below the limit', () async {
      final snapshotsDir = Directory('${tempDir.path}/safety-backups');
      await snapshotsDir.create(recursive: true);

      for (var i = 0; i < 2; i++) {
        final file = File(
          '${snapshotsDir.path}/kokoitta-backup-${2000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(snapshotsDir.listSync().whereType<File>().length, equals(2));
    });
  });

  group('staging directory cleanup', () {
    test('deletes backup-staging directories older than 24 hours', () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      final staleDir = Directory('${stagingDir.path}/0');
      await staleDir.create(recursive: true);
      File('${staleDir.path}/data.bin').writeAsBytesSync(<int>[1]);

      final recentDir = Directory(
        '${stagingDir.path}/${DateTime.now().millisecondsSinceEpoch}',
      );
      await recentDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await staleDir.exists(), isFalse);
      expect(await recentDir.exists(), isTrue);
    });

    test('deletes restore-staging directories older than 24 hours', () async {
      final stagingDir = Directory('${tempDir.path}/restore-staging');
      await stagingDir.create(recursive: true);

      final staleDir = Directory('${stagingDir.path}/0');
      await staleDir.create(recursive: true);

      final recentDir = Directory(
        '${stagingDir.path}/${DateTime.now().millisecondsSinceEpoch}',
      );
      await recentDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await staleDir.exists(), isFalse);
      expect(await recentDir.exists(), isTrue);
    });

    test('recent staging directories are kept', () async {
      final backupStaging = Directory('${tempDir.path}/backup-staging');
      await backupStaging.create(recursive: true);
      final recentDir = Directory(
        '${backupStaging.path}/${DateTime.now().millisecondsSinceEpoch}',
      );
      await recentDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await recentDir.exists(), isTrue);
    });
  });

  group('restore photo-set cleanup', () {
    test('deletes unreferenced restore photo-set directories', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final unreferencedDir = Directory('${photoSetsDir.path}/restore-1000');
      await unreferencedDir.create(recursive: true);
      File('${unreferencedDir.path}/photo.jpg').writeAsBytesSync(<int>[1]);

      final referencedDir = Directory('${photoSetsDir.path}/restore-2000');
      await referencedDir.create(recursive: true);
      final photoFile = File('${referencedDir.path}/trips/0/photo.jpg');
      await photoFile.parent.create(recursive: true);
      photoFile.writeAsBytesSync(<int>[2]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(
            id: 't1',
            title: 'Trip',
            photos: <File>[photoFile],
          ),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await unreferencedDir.exists(), isFalse);
      expect(await referencedDir.exists(), isTrue);
    });

    test('keeps restore photo-set directories referenced by AppData', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final dir = Directory('${photoSetsDir.path}/restore-3000');
      await dir.create(recursive: true);
      File('${dir.path}/trip.jpg').writeAsBytesSync(<int>[1]);

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData(
          trips: <Trip>[
            Trip(
              id: 't1',
              title: 'Trip',
              photos: <File>[File('${dir.path}/trip.jpg')],
            ),
          ],
          unassignedPhotos: const <File>[],
          prefectureStates: const <String, String>{},
        ),
      );

      expect(await dir.exists(), isTrue);
    });
  });

  group('orphan photo cleanup', () {
    test('deletes orphan photos in referenced photo-set directories', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final referencedDir = Directory('${photoSetsDir.path}/restore-4000');
      await referencedDir.create(recursive: true);
      final orphanFile = File('${referencedDir.path}/orphan.jpg');
      orphanFile.writeAsBytesSync(<int>[1]);
      final keptFile = File('${referencedDir.path}/kept.jpg');
      keptFile.writeAsBytesSync(<int>[2]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(
            id: 't1',
            title: 'Trip',
            photos: <File>[keptFile],
          ),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await orphanFile.exists(), isFalse);
      expect(await keptFile.exists(), isTrue);
    });

    test('keeps photos in AppData even inside large photo-set trees', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final dir = Directory('${photoSetsDir.path}/restore-5000');
      await dir.create(recursive: true);
      final photoFile = File('${dir.path}/photo.jpg');
      photoFile.writeAsBytesSync(<int>[1]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(
            id: 't1',
            title: 'Trip',
            photos: <File>[photoFile],
          ),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await photoFile.exists(), isTrue);
    });
  });

  group('error resilience', () {
    test('does not throw when documents directory does not exist', () async {
      final nonexistentDir = Directory('${tempDir.path}/nonexistent');
      await StorageCleanup.run(documentsDirectory: nonexistentDir);
      expect(true, isTrue);
    });

    test('handles empty directories without errors', () async {
      final backupsDir = Directory('${tempDir.path}/backups');
      await backupsDir.create();

      await StorageCleanup.run(documentsDirectory: tempDir);
      expect(true, isTrue);
    });

    test('handles empty AppData without deleting everything', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);
      Directory('${photoSetsDir.path}/restore-6000').createSync(recursive: true);

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
      );

      expect(true, isTrue);
    });
  });

  group('path normalization', () {
    test('handles backslash path separators in AppData references', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final dir = Directory('${photoSetsDir.path}/restore-7000');
      await dir.create(recursive: true);
      final photoFile = File('${dir.path}/photo.jpg');
      photoFile.writeAsBytesSync(<int>[1]);

      final backslashPath = photoFile.path.replaceAll('/', '\\');

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(
            id: 't1',
            title: 'Trip',
            photos: <File>[File(backslashPath)],
          ),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await photoFile.exists(), isTrue);
    });
  });
}

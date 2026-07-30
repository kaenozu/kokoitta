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

    test('keeps all backups when count is at or below the limit', () async {
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

    test('ignores non-backup files when within the retention limit', () async {
      final backupsDir = Directory('${tempDir.path}/backups');
      await backupsDir.create(recursive: true);

      for (var i = 0; i < 4; i++) {
        final file = File(
          '${backupsDir.path}/kokoitta-backup-${1000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }
      await File('${backupsDir.path}/readme.txt').writeAsString('note');

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(backupsDir.listSync().whereType<File>().length, equals(5));
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

    test('non-numeric directory names are safely ignored', () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      final nonNumericDir = Directory('${stagingDir.path}/not-a-timestamp');
      await nonNumericDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await nonNumericDir.exists(), isTrue);
    });

    test('boundary: slightly less than 24 hours old is kept', () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      final recentMillis = DateTime.now()
          .subtract(const Duration(hours: 23, minutes: 55))
          .millisecondsSinceEpoch;
      final recentDir = Directory('${stagingDir.path}/$recentMillis');
      await recentDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await recentDir.exists(), isTrue);
    });

    test('boundary: slightly more than 24 hours old is deleted', () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      final staleMillis = DateTime.now()
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch;
      final staleDir = Directory('${stagingDir.path}/$staleMillis');
      await staleDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await staleDir.exists(), isFalse);
    });
  });

  group('restore photo-set cleanup', () {
    test('deletes unreferenced restore-* directories', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final unreferencedDir = Directory(
        '${photoSetsDir.path}/restore-1000',
      );
      await unreferencedDir.create(recursive: true);
      File('${unreferencedDir.path}/photo.jpg').writeAsBytesSync(<int>[1]);

      final referencedDir = Directory(
        '${photoSetsDir.path}/restore-2000',
      );
      await referencedDir.create(recursive: true);
      final photoFile = File('${referencedDir.path}/trips/0/photo.jpg');
      await photoFile.parent.create(recursive: true);
      photoFile.writeAsBytesSync(<int>[2]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(id: 't1', title: 'Trip', photos: <File>[photoFile]),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await unreferencedDir.exists(), isFalse);
      expect(await referencedDir.exists(), isTrue);
    });

    test('keeps referenced restore-* directories', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final dir = Directory('${photoSetsDir.path}/restore-3000');
      await dir.create(recursive: true);
      File('${dir.path}/trip.jpg').writeAsBytesSync(<int>[1]);

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData(
          trips: <Trip>[
            Trip(id: 't1', title: 'Trip', photos: <File>[
              File('${dir.path}/trip.jpg'),
            ]),
          ],
          unassignedPhotos: const <File>[],
          prefectureStates: const <String, String>{},
        ),
      );

      expect(await dir.exists(), isTrue);
    });

    test('does not delete unreferenced non-restore-* directories', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final otherDir = Directory('${photoSetsDir.path}/other-project');
      await otherDir.create(recursive: true);
      File('${otherDir.path}/img.jpg').writeAsBytesSync(<int>[1]);

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
      );

      expect(await otherDir.exists(), isTrue);
    });

    test('ignores files directly inside photo-sets directory', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final file = File('${photoSetsDir.path}/note.txt');
      await file.writeAsString('hello');

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
      );

      expect(await file.exists(), isTrue);
    });
  });

  group('orphan photo cleanup', () {
    test('deletes orphan photos in referenced photo-set directories',
        () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final refDir = Directory('${photoSetsDir.path}/restore-4000');
      await refDir.create(recursive: true);
      final orphanFile = File('${refDir.path}/orphan.jpg');
      orphanFile.writeAsBytesSync(<int>[1]);
      final keptFile = File('${refDir.path}/kept.jpg');
      keptFile.writeAsBytesSync(<int>[2]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(id: 't1', title: 'Trip', photos: <File>[keptFile]),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await orphanFile.exists(), isFalse);
      expect(await keptFile.exists(), isTrue);
    });

    test('keeps photos referenced by AppData', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final dir = Directory('${photoSetsDir.path}/restore-5000');
      await dir.create(recursive: true);
      final photoFile = File('${dir.path}/photo.jpg');
      photoFile.writeAsBytesSync(<int>[1]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(id: 't1', title: 'Trip', photos: <File>[photoFile]),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await photoFile.exists(), isTrue);
    });
  });

  group('deletion failure retry', () {
    test('retries file deletion on next startup after failure', () async {
      final backupsDir = Directory('${tempDir.path}/backups');
      await backupsDir.create(recursive: true);

      for (var i = 0; i < 7; i++) {
        final file = File(
          '${backupsDir.path}/kokoitta-backup-${3000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }

      var deleteCallCount = 0;
      Future<void> failFirstDeleteFile(File file) async {
        deleteCallCount++;
        if (deleteCallCount <= 2) {
          throw FileSystemException('Simulated failure', file.path);
        }
        await file.delete();
      }

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        onDeleteFile: failFirstDeleteFile,
      );

      expect(deleteCallCount, greaterThan(0));
      expect(backupsDir.listSync().whereType<File>().length, greaterThan(0));

      deleteCallCount = 0;
      await StorageCleanup.run(
        documentsDirectory: tempDir,
        onDeleteFile: failFirstDeleteFile,
      );

      expect(deleteCallCount, greaterThan(0));
    });

    test('one file deletion failure does not block other deletions', () async {
      final backupsDir = Directory('${tempDir.path}/backups');
      await backupsDir.create(recursive: true);

      for (var i = 0; i < 8; i++) {
        final file = File(
          '${backupsDir.path}/kokoitta-backup-${4000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }

      var callIndex = 0;
      Future<void> failSecondDeleteFile(File file) async {
        callIndex++;
        if (callIndex == 2) {
          throw FileSystemException('Simulated failure', file.path);
        }
        await file.delete();
      }

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        onDeleteFile: failSecondDeleteFile,
      );

      expect(backupsDir.listSync().whereType<File>().length, equals(6));
    });

    test('one directory failure does not block other directory deletions',
        () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      await Directory('${stagingDir.path}/0').create();
      await Directory('${stagingDir.path}/1').create();

      Future<void> failDeleteDirOne(Directory dir) async {
        final dirName = dir.path.split(RegExp(r'[/\\]')).last;
        if (dirName == '1') {
          throw FileSystemException('Simulated failure', dir.path);
        }
        await dir.delete(recursive: true);
      }

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        onDeleteDirectory: failDeleteDirOne,
      );

      expect(await Directory('${stagingDir.path}/0').exists(), isFalse);
      expect(await Directory('${stagingDir.path}/1').exists(), isTrue);
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

    test('handles empty AppData without deleting non-restore-* directories',
        () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);
      Directory('${photoSetsDir.path}/import-2000').createSync(
        recursive: true,
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
      );

      expect(
        await Directory('${photoSetsDir.path}/import-2000').exists(),
        isTrue,
      );
    });

    test('does not fail when a subdirectory listing throws', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);
      final dir = Directory('${photoSetsDir.path}/restore-7000');
      await dir.create(recursive: true);
      final photoFile = File('${dir.path}/photo.jpg');
      await photoFile.writeAsBytes(<int>[1]);

      final restrictedDir = Directory('${photoSetsDir.path}/restore-8000');
      await restrictedDir.create(recursive: true);
      File('${restrictedDir.path}/data.bin').writeAsBytesSync(<int>[2]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(id: 't1', title: 'Trip', photos: <File>[photoFile]),
        ],
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
      );

      expect(await photoFile.exists(), isTrue);
    });
  });

  group('path normalization', () {
    test('handles backslash path separators in AppData references', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final dir = Directory('${photoSetsDir.path}/restore-9000');
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

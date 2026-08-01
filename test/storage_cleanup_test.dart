import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/storage_cleanup.dart';

Photo photoOf(File file) => Photo.fromFile(file);

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

    test('ignores non-backup files in backups directory', () async {
      final backupsDir = Directory('${tempDir.path}/backups');
      await backupsDir.create(recursive: true);

      for (var i = 0; i < 3; i++) {
        final file = File(
          '${backupsDir.path}/kokoitta-backup-${1000000 + i}.zip',
        );
        await file.writeAsBytes(<int>[i]);
      }

      final readme = File('${backupsDir.path}/readme.txt');
      await readme.writeAsBytes(<int>[0]);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(backupsDir.listSync().whereType<File>().length, equals(4));
      expect(await readme.exists(), isTrue);
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

    test('deletes staging directory with zero timestamp', () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      final zeroDir = Directory('${stagingDir.path}/0');
      await zeroDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await zeroDir.exists(), isFalse);
    });

    test('ignores non-numeric directory names in staging', () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      final nonNumericDir = Directory('${stagingDir.path}/abc-def');
      await nonNumericDir.create(recursive: true);

      await StorageCleanup.run(documentsDirectory: tempDir);

      expect(await nonNumericDir.exists(), isTrue);
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
          Trip(id: 't1', title: 'Trip', photos: <Photo>[photoOf(photoFile)]),
        ],
      );

      await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

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
              photos: <Photo>[photoOf(File('${dir.path}/trip.jpg'))],
            ),
          ],
          unassignedPhotos: const <Photo>[],
          prefectureStates: const <String, String>{},
        ),
      );

      expect(await dir.exists(), isTrue);
    });

    test(
      'does not delete non-restore directories even when unreferenced',
      () async {
        final photoSetsDir = Directory('${tempDir.path}/photo-sets');
        await photoSetsDir.create(recursive: true);

        final otherDir = Directory('${photoSetsDir.path}/import-1000');
        await otherDir.create(recursive: true);
        File('${otherDir.path}/photo.jpg').writeAsBytesSync(<int>[1]);

        final appData = AppData.empty();

        await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

        expect(await otherDir.exists(), isTrue);
        expect(await File('${otherDir.path}/photo.jpg').exists(), isTrue);
      },
    );

    test(
      'does not delete unknown directories even when unreferenced',
      () async {
        final photoSetsDir = Directory('${tempDir.path}/photo-sets');
        await photoSetsDir.create(recursive: true);

        final unknownDir = Directory('${photoSetsDir.path}/share-2000');
        await unknownDir.create(recursive: true);
        File('${unknownDir.path}/photo.jpg').writeAsBytesSync(<int>[1]);

        final appData = AppData.empty();

        await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

        expect(await unknownDir.exists(), isTrue);
        expect(await File('${unknownDir.path}/photo.jpg').exists(), isTrue);
      },
    );
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
          Trip(id: 't1', title: 'Trip', photos: <Photo>[photoOf(keptFile)]),
        ],
      );

      await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

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
          Trip(id: 't1', title: 'Trip', photos: <Photo>[photoOf(photoFile)]),
        ],
      );

      await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

      expect(await photoFile.exists(), isTrue);
    });

    test(
      'deletes orphan photos in documents/photos/ not referenced by AppData',
      () async {
        final photosDir = Directory('${tempDir.path}/photos');
        await photosDir.create(recursive: true);

        final orphanFile = File('${photosDir.path}/orphan.jpg');
        orphanFile.writeAsBytesSync(<int>[1]);
        final keptFile = File('${photosDir.path}/kept.jpg');
        keptFile.writeAsBytesSync(<int>[2]);

        final appData = AppData.empty().copyWith(
          trips: <Trip>[
            Trip(id: 't1', title: 'Trip', photos: <Photo>[photoOf(keptFile)]),
          ],
        );

        await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

        expect(await orphanFile.exists(), isFalse);
        expect(await keptFile.exists(), isTrue);
      },
    );

    test(
      'keeps photos in documents/photos/ that are referenced by AppData',
      () async {
        final photosDir = Directory('${tempDir.path}/photos');
        await photosDir.create(recursive: true);

        final photoFile = File('${photosDir.path}/trip-photo.jpg');
        photoFile.writeAsBytesSync(<int>[1]);

        final appData = AppData.empty().copyWith(
          trips: <Trip>[
            Trip(id: 't1', title: 'Trip', photos: <Photo>[photoOf(photoFile)]),
          ],
        );

        await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

        expect(await photoFile.exists(), isTrue);
      },
    );

    test(
      'does not delete photos in documents/photos/ when AppData is empty',
      () async {
        final photosDir = Directory('${tempDir.path}/photos');
        await photosDir.create(recursive: true);

        final photoFile = File('${photosDir.path}/some-photo.jpg');
        photoFile.writeAsBytesSync(<int>[1]);

        await StorageCleanup.run(
          documentsDirectory: tempDir,
          appData: AppData.empty(),
        );

        expect(await photoFile.exists(), isFalse);
      },
    );

    test(
      'handles mixed referenced and unreferenced photos in documents/photos/',
      () async {
        final photosDir = Directory('${tempDir.path}/photos');
        await photosDir.create(recursive: true);

        final orphanFile = File('${photosDir.path}/orphan.jpg');
        orphanFile.writeAsBytesSync(<int>[1]);
        final keptFile = File('${photosDir.path}/kept.jpg');
        keptFile.writeAsBytesSync(<int>[2]);
        final anotherOrphan = File('${photosDir.path}/another-orphan.jpg');
        anotherOrphan.writeAsBytesSync(<int>[3]);

        final appData = AppData.empty().copyWith(
          trips: <Trip>[
            Trip(id: 't1', title: 'Trip', photos: <Photo>[photoOf(keptFile)]),
          ],
        );

        await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

        expect(await orphanFile.exists(), isFalse);
        expect(await keptFile.exists(), isTrue);
        expect(await anotherOrphan.exists(), isFalse);
      },
    );

    test(
      'handles Windows-style paths in AppData references for photos/',
      () async {
        final photosDir = Directory('${tempDir.path}/photos');
        await photosDir.create(recursive: true);

        final photoFile = File('${photosDir.path}/trip-photo.jpg');
        photoFile.writeAsBytesSync(<int>[1]);

        final backslashPath = photoFile.path.replaceAll('/', '\\');

        final appData = AppData.empty().copyWith(
          trips: <Trip>[
            Trip(
              id: 't1',
              title: 'Trip',
              photos: <Photo>[photoOf(File(backslashPath))],
            ),
          ],
        );

        await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

        expect(await photoFile.exists(), isTrue);
      },
    );
  });

  group('deletion failure resilience', () {
    test(
      'does not throw when deletion fails and continues with other targets',
      () async {
        final stagingDir = Directory('${tempDir.path}/backup-staging');
        await stagingDir.create(recursive: true);

        final staleDir1 = Directory('${stagingDir.path}/0');
        await staleDir1.create(recursive: true);
        final staleDir2 = Directory('${stagingDir.path}/1');
        await staleDir2.create(recursive: true);

        var deleteCallCount = 0;
        await StorageCleanup.run(
          documentsDirectory: tempDir,
          deleteDirFn: (String path, {bool recursive = false}) async {
            deleteCallCount += 1;
            if (deleteCallCount == 1) {
              throw FileSystemException('Permission denied', path);
            }
            await Directory(path).delete(recursive: recursive);
          },
        );

        expect(await staleDir1.exists(), isTrue);
        expect(await staleDir2.exists(), isFalse);
      },
    );

    test(
      'retry succeeds on second cleanup attempt after initial failure',
      () async {
        final stagingDir = Directory('${tempDir.path}/backup-staging');
        await stagingDir.create(recursive: true);

        final staleDir = Directory('${stagingDir.path}/0');
        await staleDir.create(recursive: true);

        var deleteCallCount = 0;
        await StorageCleanup.run(
          documentsDirectory: tempDir,
          deleteDirFn: (String path, {bool recursive = false}) async {
            deleteCallCount += 1;
            if (deleteCallCount == 1) {
              throw FileSystemException('Permission denied', path);
            }
            await Directory(path).delete(recursive: recursive);
          },
        );

        expect(await staleDir.exists(), isTrue);
        expect(deleteCallCount, equals(1));

        deleteCallCount = 0;
        await StorageCleanup.run(
          documentsDirectory: tempDir,
          deleteDirFn: (String path, {bool recursive = false}) async {
            deleteCallCount += 1;
            await Directory(path).delete(recursive: recursive);
          },
        );

        expect(deleteCallCount, equals(1));
        expect(await staleDir.exists(), isFalse);
      },
    );

    test(
      'one deletion failure does not prevent other deletions from succeeding',
      () async {
        final stagingDir = Directory('${tempDir.path}/backup-staging');
        await stagingDir.create(recursive: true);

        final staleDir1 = Directory('${stagingDir.path}/0');
        await staleDir1.create(recursive: true);
        final staleDir2 = Directory('${stagingDir.path}/1');
        await staleDir2.create(recursive: true);

        var deleteCallCount = 0;
        await StorageCleanup.run(
          documentsDirectory: tempDir,
          deleteDirFn: (String path, {bool recursive = false}) async {
            deleteCallCount += 1;
            if (deleteCallCount == 1) {
              throw FileSystemException('Permission denied', path);
            }
            await Directory(path).delete(recursive: recursive);
          },
        );

        expect(await staleDir1.exists(), isTrue);
        expect(await staleDir2.exists(), isFalse);
      },
    );

    test('staging directory deletion failure is retried on next run', () async {
      final stagingDir = Directory('${tempDir.path}/backup-staging');
      await stagingDir.create(recursive: true);

      final staleDir = Directory('${stagingDir.path}/0');
      await staleDir.create(recursive: true);

      var deleteCallCount = 0;
      await StorageCleanup.run(
        documentsDirectory: tempDir,
        deleteDirFn: (String path, {bool recursive = false}) async {
          deleteCallCount += 1;
          if (deleteCallCount == 1) {
            throw FileSystemException('Permission denied', path);
          }
          await Directory(path).delete(recursive: recursive);
        },
      );

      expect(await staleDir.exists(), isTrue);

      deleteCallCount = 0;
      await StorageCleanup.run(
        documentsDirectory: tempDir,
        deleteDirFn: (String path, {bool recursive = false}) async {
          deleteCallCount += 1;
          await Directory(path).delete(recursive: recursive);
        },
      );

      expect(await staleDir.exists(), isFalse);
      expect(deleteCallCount, equals(1));
    });

    test('referenced data is never deleted even on retry', () async {
      final photoSetsDir = Directory('${tempDir.path}/photo-sets');
      await photoSetsDir.create(recursive: true);

      final restoreDir = Directory('${photoSetsDir.path}/restore-1000');
      await restoreDir.create(recursive: true);
      final keptFile = File('${restoreDir.path}/trip.jpg');
      keptFile.writeAsBytesSync(<int>[1]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(id: 't1', title: 'Trip', photos: <Photo>[photoOf(keptFile)]),
        ],
      );

      var deleteCallCount = 0;
      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: appData,
        deleteDirFn: (String path, {bool recursive = false}) async {
          deleteCallCount += 1;
          if (deleteCallCount == 1) {
            throw FileSystemException('Permission denied', path);
          }
          await Directory(path).delete(recursive: recursive);
        },
      );

      expect(await keptFile.exists(), isTrue);
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
            photos: <Photo>[photoOf(File(backslashPath))],
          ),
        ],
      );

      await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

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
      Directory(
        '${photoSetsDir.path}/restore-6000',
      ).createSync(recursive: true);

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
      );

      expect(true, isTrue);
    });
  });
}

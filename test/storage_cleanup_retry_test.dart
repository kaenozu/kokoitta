import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/storage_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kokoitta-cleanup-retry');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('retries file deletion on next run after failure', () async {
    final backupsDir = Directory('${tempDir.path}/backups');
    await backupsDir.create(recursive: true);

    for (var i = 0; i < 6; i++) {
      await File(
        '${backupsDir.path}/kokoitta-backup-${3000000 + i}.zip',
      ).writeAsBytes(<int>[i]);
    }

    var failOncePerFile = true;
    var deleteCallCount = 0;
    Future<void> deleteFile(String path) async {
      deleteCallCount += 1;
      if (failOncePerFile) {
        failOncePerFile = false;
        throw FileSystemException('Simulated failure', path);
      }
      await File(path).delete();
    }

    await StorageCleanup.run(
      documentsDirectory: tempDir,
      deleteFileFn: deleteFile,
    );

    expect(deleteCallCount, equals(1));
    expect(backupsDir.listSync().whereType<File>().length, equals(6));

    await StorageCleanup.run(
      documentsDirectory: tempDir,
      deleteFileFn: deleteFile,
    );

    expect(deleteCallCount, equals(2));
    expect(backupsDir.listSync().whereType<File>().length, equals(5));
  });

  test('staging directory deletion failure is retried on next run', () async {
    final stagingDir = Directory('${tempDir.path}/backup-staging');
    await stagingDir.create(recursive: true);

    final oldDir = Directory('${stagingDir.path}/0');
    await oldDir.create(recursive: true);

    var failOncePerDir = true;
    var deleteCallCount = 0;
    Future<void> deleteDirectory(String path, {bool recursive = false}) async {
      deleteCallCount += 1;
      if (failOncePerDir) {
        failOncePerDir = false;
        throw FileSystemException('Simulated failure', path);
      }
      await Directory(path).delete(recursive: recursive);
    }

    await StorageCleanup.run(
      documentsDirectory: tempDir,
      deleteDirFn: deleteDirectory,
    );

    expect(deleteCallCount, equals(1));
    expect(await oldDir.exists(), isTrue);

    await StorageCleanup.run(
      documentsDirectory: tempDir,
      deleteDirFn: deleteDirectory,
    );

    expect(deleteCallCount, equals(2));
    expect(await oldDir.exists(), isFalse);
  });

  group('expired pending deletion cleanup', () {
    test('期限切れでAppDataから消えている退避を確定削除する', () async {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final photosDir = Directory('${tempDir.path}/photos');
      await photosDir.create(recursive: true);
      final photo = File('${photosDir.path}/photo.jpg');
      await photo.writeAsBytes(<int>[1]);

      final store = PendingDeletionStore(now: () => past);
      await store.stage(
        Trip(id: 'trip-1', title: '古い旅行', photos: <File>[photo]),
        tempDir,
      );

      var deleteCallCount = 0;
      Future<void> deleteFile(String path) async {
        deleteCallCount += 1;
        await File(path).delete();
      }

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
        deleteFileFn: deleteFile,
      );

      expect(deleteCallCount, greaterThan(0));
      expect(
        await Directory('${tempDir.path}/pending-deletions/trip-1').exists(),
        isFalse,
      );
      expect(await photo.exists(), isFalse);
    });

    test('削除未確定（旅行が残っている）の退避は確定削除しない', () async {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final photosDir = Directory('${tempDir.path}/photos');
      await photosDir.create(recursive: true);
      final photo = File('${photosDir.path}/photo.jpg');
      await photo.writeAsBytes(<int>[1]);

      final store = PendingDeletionStore(now: () => past);
      await store.stage(
        Trip(id: 'trip-1', title: '残っている旅行', photos: <File>[photo]),
        tempDir,
      );

      var deleteCallCount = 0;
      Future<void> deleteFile(String path) async {
        deleteCallCount += 1;
        await File(path).delete();
      }

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData(
          trips: <Trip>[
            Trip(id: 'trip-1', title: '残っている旅行', photos: <File>[photo]),
          ],
          unassignedPhotos: const <File>[],
          prefectureStates: const <String, String>{},
        ),
        deleteFileFn: deleteFile,
      );

      expect(deleteCallCount, equals(0));
      expect(
        await Directory('${tempDir.path}/pending-deletions/trip-1').exists(),
        isTrue,
      );
      // 退避された写真は確定削除されず残っている。
      expect(
        await File(
          '${tempDir.path}/pending-deletions/trip-1/0-photo.jpg',
        ).exists(),
        isTrue,
      );
    });

    test('期限内の退避は確定削除しない', () async {
      final photosDir = Directory('${tempDir.path}/photos');
      await photosDir.create(recursive: true);
      final photo = File('${photosDir.path}/photo.jpg');
      await photo.writeAsBytes(<int>[1]);

      final store = PendingDeletionStore(now: () => DateTime.now());
      await store.stage(
        Trip(id: 'trip-1', title: '期限内の旅行', photos: <File>[photo]),
        tempDir,
      );

      var deleteCallCount = 0;
      Future<void> deleteFile(String path) async {
        deleteCallCount += 1;
        await File(path).delete();
      }

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
        deleteFileFn: deleteFile,
      );

      expect(deleteCallCount, equals(0));
      expect(
        await Directory('${tempDir.path}/pending-deletions/trip-1').exists(),
        isTrue,
      );
    });

    test('確定削除に失敗した退避は保持され次回のrunで再試行される', () async {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final photosDir = Directory('${tempDir.path}/photos');
      await photosDir.create(recursive: true);
      final photo = File('${photosDir.path}/photo.jpg');
      await photo.writeAsBytes(<int>[1]);

      final store = PendingDeletionStore(now: () => past);
      await store.stage(
        Trip(id: 'trip-1', title: '古い旅行', photos: <File>[photo]),
        tempDir,
      );

      var failOnce = true;
      Future<void> deleteFile(String path) async {
        if (failOnce) {
          failOnce = false;
          throw FileSystemException('Simulated failure', path);
        }
        await File(path).delete();
      }

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
        deleteFileFn: deleteFile,
      );

      expect(
        await Directory('${tempDir.path}/pending-deletions/trip-1').exists(),
        isTrue,
      );

      await StorageCleanup.run(
        documentsDirectory: tempDir,
        appData: AppData.empty(),
        deleteFileFn: deleteFile,
      );

      expect(
        await Directory('${tempDir.path}/pending-deletions/trip-1').exists(),
        isFalse,
      );
    });
  });
}

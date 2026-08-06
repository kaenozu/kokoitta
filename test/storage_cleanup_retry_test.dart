import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/operation_coordinator.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/storage_cleanup.dart';

void main() {
  group('startup cleanup serialization', () {
    late Directory tempDir;
    late Directory photosDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'kokoitta-cleanup-serial',
      );
      photosDir = Directory('${tempDir.path}/photos');
      await photosDir.create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> writePhoto(String name) async {
      final file = File('${photosDir.path}/$name');
      await file.writeAsBytes(<int>[1, 2, 3]);
      return file;
    }

    AppData appDataWith(File file) => AppData.empty().copyWith(
      trips: <Trip>[
        Trip(id: 't1', title: 'Trip', photos: <Photo>[Photo.fromFile(file)]),
      ],
    );

    test('cleanup実行中に通常写真追加をqueueするとcleanup完了後に実行され新規写真は残る', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      final existing = await writePhoto('existing.jpg');
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final order = <String>[];

      final cleanup = coordinator.runCleanup(() async {
        order.add('cleanup:start');
        cleanupStarted.complete();
        await releaseCleanup.future;
        await StorageCleanup.run(
          documentsDirectory: tempDir,
          appData: appDataWith(existing),
        );
        order.add('cleanup:end');
      });

      await cleanupStarted.future;

      final mutation = coordinator.runMutation(() async {
        order.add('mutation');
        return writePhoto('added.jpg');
      });

      releaseCleanup.complete();
      await cleanup;
      final added = await mutation;

      expect(order, <String>['cleanup:start', 'cleanup:end', 'mutation']);
      expect(await added.exists(), isTrue);
      expect(await existing.exists(), isTrue);
      expect(coordinator.status, OperationStatus.idle);
      expect(coordinator.isBusy, isFalse);
    });

    test('cleanup実行中にAndroid共有取り込み相当をqueueすると取り込みコピーが削除されない', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final order = <String>[];

      final cleanup = coordinator.runCleanup(() async {
        order.add('cleanup:start');
        cleanupStarted.complete();
        await releaseCleanup.future;
        await StorageCleanup.run(
          documentsDirectory: tempDir,
          appData: AppData.empty(),
        );
        order.add('cleanup:end');
      });

      await cleanupStarted.future;

      // Android共有取り込みの一時ファイルからphotos/への移送に相当する処理。
      final sharedSource = File('${tempDir.path}/shared-cache/incoming.jpg');
      await sharedSource.parent.create(recursive: true);
      await sharedSource.writeAsBytes(<int>[9]);
      final sharedImport = coordinator.runMutation(() async {
        order.add('share-import');
        final copied = await sharedSource.copy('${photosDir.path}/shared.jpg');
        await sharedSource.delete();
        return copied;
      });

      releaseCleanup.complete();
      await cleanup;
      final copied = await sharedImport;

      expect(order, <String>['cleanup:start', 'cleanup:end', 'share-import']);
      expect(await copied.exists(), isTrue);
      expect(await sharedSource.exists(), isFalse);
    });

    test('cleanup開始前後に複数操作をqueueすると順序が決定的である', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);
      final order = <String>[];

      final cleanup = coordinator.runCleanup(() async {
        order.add('cleanup');
      });
      final first = coordinator.runMutation(() async {
        order.add('mutation-1');
      });
      final second = coordinator.runMutation(() async {
        order.add('mutation-2');
      });
      final backup = coordinator.runBackup(() async {
        order.add('backup');
      });

      await Future.wait<void>([cleanup, first, second, backup]);

      expect(order, <String>['cleanup', 'mutation-1', 'mutation-2', 'backup']);
      expect(coordinator.status, OperationStatus.idle);
    });

    test('cleanup完了前にqueueされた操作はすべてcleanup後に順に実行される', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final order = <String>[];

      final cleanup = coordinator.runCleanup(() async {
        order.add('cleanup:start');
        cleanupStarted.complete();
        await releaseCleanup.future;
        order.add('cleanup:end');
      });

      await cleanupStarted.future;

      final m1 = coordinator.runMutation(() async => order.add('m1'));
      final m2 = coordinator.runMutation(() async => order.add('m2'));
      final m3 = coordinator.runMutation(() async => order.add('m3'));

      releaseCleanup.complete();
      await cleanup;
      await Future.wait<void>([m1, m2, m3]);

      expect(order, <String>['cleanup:start', 'cleanup:end', 'm1', 'm2', 'm3']);
    });

    test('cleanup中は復元開始を拒否し、復元セッション中はcleanupを拒否する', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final cleanup = coordinator.runCleanup(() async {
        cleanupStarted.complete();
        await releaseCleanup.future;
      });
      await cleanupStarted.future;

      expect(() => coordinator.beginRestorePrepare(), throwsStateError);

      releaseCleanup.complete();
      await cleanup;

      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      expect(() => coordinator.runCleanup(() async {}), throwsStateError);

      final holdCommit = Completer<void>();
      final commit = coordinator.runRestoreCommit(() async {
        await holdCommit.future;
      });
      await Future<void>.delayed(Duration.zero);
      expect(() => coordinator.runCleanup(() async {}), throwsStateError);

      holdCommit.complete();
      await commit;
      coordinator.endRestore();

      // 復元完了後はcleanupを実行できる。
      await coordinator.runCleanup(() async {});
      expect(coordinator.status, OperationStatus.idle);
    });

    test('cleanup失敗時にcoordinatorが解放されstatusがfailedになる', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final cleanup = coordinator.runCleanup(() async {
        cleanupStarted.complete();
        await releaseCleanup.future;
        throw FileSystemException('Simulated cleanup failure', '/tmp/x');
      });
      await cleanupStarted.future;
      expect(coordinator.isCleanupRunning, isTrue);
      expect(coordinator.isBusy, isTrue);

      releaseCleanup.complete();
      await expectLater(cleanup, throwsA(isA<FileSystemException>()));

      expect(coordinator.status, OperationStatus.failed);
      expect(coordinator.isBusy, isFalse);
      expect(coordinator.isCleanupRunning, isFalse);
    });

    test('cleanup失敗後に次のmutationを実行できる', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.runCleanup(() async {
          throw FileSystemException('Simulated cleanup failure', '/tmp/x');
        }),
        throwsA(isA<FileSystemException>()),
      );

      final result = await coordinator.runMutation(() async => 'ok');
      expect(result, 'ok');
      expect(coordinator.status, OperationStatus.idle);
      expect(coordinator.isBusy, isFalse);
    });

    test('同一のstartup cleanupは二重起動しない', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final cleanup = coordinator.runCleanup(() async {
        cleanupStarted.complete();
        await releaseCleanup.future;
      });
      await cleanupStarted.future;

      expect(() => coordinator.runCleanup(() async {}), throwsStateError);

      releaseCleanup.complete();
      await cleanup;

      // 完了後は再起動できる（次回起動の再試行に相当）。
      await coordinator.runCleanup(() async {});
      expect(coordinator.status, OperationStatus.idle);
    });

    test('cleanup後も新規写真は物理的に存在し保存済みPhotoは欠損パスを参照しない', () async {
      final coordinator = OperationCoordinator();
      addTearDown(coordinator.dispose);

      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      late AppData resultData;

      final cleanup = coordinator.runCleanup(() async {
        cleanupStarted.complete();
        await releaseCleanup.future;
        // 古いスナップショット（新規写真を未参照）でcleanupを実行する。
        await StorageCleanup.run(
          documentsDirectory: tempDir,
          appData: AppData.empty().copyWith(
            trips: <Trip>[Trip(id: 't1', title: 'Trip', photos: <Photo>[])],
          ),
        );
      });
      await cleanupStarted.future;

      final orphan = await writePhoto('orphan.jpg');
      final mutation = coordinator.runMutation(() async {
        final kept = await writePhoto('kept.jpg');
        resultData = appDataWith(kept);
        return kept;
      });

      releaseCleanup.complete();
      await cleanup;
      final kept = await mutation;

      // 新規写真はcleanupの走査後（mutation内）にコピーされるため残る。
      expect(await kept.exists(), isTrue);
      // 古いスナップショット基準のcleanupは、cleanup前に存在した孤児を削除する。
      expect(await orphan.exists(), isFalse);
      // 保存済みPhotoは実在するパスだけを参照する。
      for (final photo in resultData.allPhotos) {
        expect(
          await photo.file.exists(),
          isTrue,
          reason: '保存済みPhotoが欠損パスを参照しています: ${photo.file.path}',
        );
      }
    });
  });

  group('StorageCleanup reference snapshot safety', () {
    test('cleanup開始時点のAppData参照だけを削除対象にし、参照済みは保持する', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'kokoitta-cleanup-snapshot',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final photosDir = Directory('${tempDir.path}/photos');
      await photosDir.create(recursive: true);

      final referenced = File('${photosDir.path}/referenced.jpg');
      await referenced.writeAsBytes(<int>[1]);
      final orphan = File('${photosDir.path}/orphan.jpg');
      await orphan.writeAsBytes(<int>[2]);

      final appData = AppData.empty().copyWith(
        trips: <Trip>[
          Trip(
            id: 't1',
            title: 'Trip',
            photos: <Photo>[Photo.fromFile(referenced)],
          ),
        ],
      );

      await StorageCleanup.run(documentsDirectory: tempDir, appData: appData);

      expect(await referenced.exists(), isTrue);
      expect(await orphan.exists(), isFalse);
    });
  });
}

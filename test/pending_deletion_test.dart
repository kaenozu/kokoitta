import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/pending_deletion.dart';

void main() {
  late Directory tempDir;
  late Directory root;
  late Directory photosDir;
  late DateTime fakeNow;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kokoitta-pending');
    root = Directory('${tempDir.path}/docs');
    await root.create(recursive: true);
    photosDir = Directory('${root.path}/photos');
    await photosDir.create(recursive: true);
    fakeNow = DateTime.utc(2026, 1, 1, 0, 0, 0);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PendingDeletionStore makeStore({Duration? undoWindow}) {
    return PendingDeletionStore(now: () => fakeNow, undoWindow: undoWindow);
  }

  Future<List<File>> createPhotos(int count) async {
    final files = <File>[];
    for (var index = 0; index < count; index++) {
      final file = File('${photosDir.path}/photo-$index.jpg');
      await file.writeAsBytes(<int>[index]);
      files.add(file);
    }
    return files;
  }

  Trip tripWith(List<File> photos, {String id = 'trip-1'}) {
    return Trip(id: id, title: 'テスト旅行', photos: photos);
  }

  group('stage', () {
    test('退避とmanifestの永続化を実行し、期限付きのpending deletionを返す', () async {
      final photos = await createPhotos(2);
      final store = makeStore();
      final pending = await store.stage(tripWith(photos), root);

      expect(pending.trip.id, 'trip-1');
      expect(
        pending.expiresAt,
        fakeNow.add(PendingDeletionStore.defaultUndoWindow),
      );
      expect(pending.trashDirectory.path, contains('pending-deletions/trip-1'));

      expect(await File(photos[0].path).exists(), isFalse);
      expect(await File(photos[1].path).exists(), isFalse);
      expect(
        await File('${pending.trashDirectory.path}/0-photo-0.jpg').exists(),
        isTrue,
      );
      expect(
        await File('${pending.trashDirectory.path}/1-photo-1.jpg').exists(),
        isTrue,
      );

      final manifest = File('${pending.trashDirectory.path}/manifest.json');
      expect(await manifest.exists(), isTrue);
      final manifestJson = manifest.readAsStringSync();
      expect(manifestJson, contains('"tripId":"trip-1"'));
      expect(manifestJson, contains('"expiresAt"'));
    });

    test('元ファイルが既に存在しない場合はtrashPath nullで退避スキップ', () async {
      final photos = await createPhotos(1);
      final missing = File('${photosDir.path}/missing.jpg');
      final trip = tripWith(<File>[photos.first, missing]);
      final pending = await makeStore().stage(trip, root);

      expect(pending.records[0].trashPath, isNotNull);
      expect(pending.records[1].trashPath, isNull);
    });

    test('退避の途中で失敗した場合は移動済みファイルを元パスへ戻す', () async {
      final photos = await createPhotos(3);
      var moveCalls = 0;
      final store = PendingDeletionStore(
        now: () => fakeNow,
        moveFile: (File source, File destination) async {
          moveCalls += 1;
          if (moveCalls == 2) {
            throw const FileSystemException('Simulated failure');
          }
          await source.rename(destination.path);
        },
      );

      await expectLater(
        store.stage(tripWith(photos), root),
        throwsA(isA<FileSystemException>()),
      );

      // 先頭の1枚だけ移動済みだったものが元パスへ戻っている。
      expect(await File(photos[0].path).exists(), isTrue);
      expect(await File(photos[1].path).exists(), isTrue);
      expect(await File(photos[2].path).exists(), isTrue);
      // 退避ディレクトリは後始末される。
      expect(
        await Directory('${root.path}/pending-deletions/trip-1').exists(),
        isFalse,
      );
    });
  });

  group('restore', () {
    test('退避写真を元パスへ戻し、元の並び順の旅行を返す', () async {
      final photos = await createPhotos(3);
      final pending = await makeStore().stage(tripWith(photos), root);

      final restored = await makeStore().restore(pending);

      expect(
        restored.photos.map((file) => file.path).toList(),
        photos.map((file) => file.path).toList(),
      );
      for (final photo in photos) {
        expect(await File(photo.path).exists(), isTrue);
      }
      // commit後は退避ディレクトリが消える。
      await makeStore().commitRestore(pending);
      expect(
        await Directory('${root.path}/pending-deletions/trip-1').exists(),
        isFalse,
      );
    });

    test('部分復元の失敗時はPartialRestoreExceptionを投げ、再試行できる', () async {
      final photos = await createPhotos(2);
      final pending = await makeStore().stage(tripWith(photos), root);

      // 2枚目の元パスに別ファイルを置いて復元をブロックする。
      await File(photos[1].path).writeAsBytes(<int>[9]);

      await expectLater(
        makeStore().restore(pending),
        throwsA(isA<PartialRestoreException>()),
      );

      // 1枚目は一度元へ戻った後、部分失敗の巻き戻しで退避先へ戻っている。
      expect(await File(photos[0].path).exists(), isFalse);
      expect(await File(pending.records[0].trashPath!).exists(), isTrue);
      expect(await File(pending.records[1].trashPath!).exists(), isTrue);

      // ブロックを解除して再試行すると完全復元できる。
      await File(photos[1].path).delete();
      final restored = await makeStore().restore(pending);
      expect(restored.photos.length, 2);
      for (final photo in photos) {
        expect(await File(photo.path).exists(), isTrue);
      }
    });

    test('復元の失敗時に移動済みファイルを退避先へ戻す', () async {
      final photos = await createPhotos(2);
      final pending = await makeStore().stage(tripWith(photos), root);

      var restoreMoves = 0;
      final failingStore = PendingDeletionStore(
        now: () => fakeNow,
        moveFile: (File source, File destination) async {
          restoreMoves += 1;
          if (restoreMoves == 1) {
            throw const FileSystemException('Simulated failure');
          }
          await source.rename(destination.path);
        },
      );

      await expectLater(
        failingStore.restore(pending),
        throwsA(isA<PartialRestoreException>()),
      );

      // 失敗した1枚目は退避先に残る（巻き戻し成功）。
      expect(await File(pending.records[0].trashPath!).exists(), isTrue);
      expect(await File(pending.records[1].trashPath!).exists(), isTrue);
    });
  });

  group('finalize', () {
    test('退避写真とmanifestを物理削除し、ディレクトリごと消す', () async {
      final photos = await createPhotos(2);
      final pending = await makeStore().stage(tripWith(photos), root);

      await makeStore().finalize(pending);

      expect(
        await Directory('${root.path}/pending-deletions/trip-1').exists(),
        isFalse,
      );
      for (final photo in photos) {
        expect(await File(photo.path).exists(), isFalse);
      }
    });

    test('削除に失敗したファイルは残り、次回のfinalizeで再試行できる', () async {
      final photos = await createPhotos(2);
      final pending = await makeStore().stage(tripWith(photos), root);

      var deleteCalls = 0;
      final failingStore = PendingDeletionStore(
        now: () => fakeNow,
        deleteFile: (File file) async {
          deleteCalls += 1;
          if (deleteCalls == 1) {
            throw const FileSystemException('Simulated failure');
          }
          await file.delete();
        },
      );

      await expectLater(
        failingStore.finalize(pending),
        throwsA(isA<FileSystemException>()),
      );

      // 失敗した1枚は残っており、manifestも残っている。
      expect(
        (await pending.trashDirectory.list().toList()).whereType<File>().length,
        greaterThan(0),
      );

      await makeStore().finalize(pending);
      expect(await pending.trashDirectory.exists(), isFalse);
    });
  });

  group('recover', () {
    test('削除未確定（旅行が残っている）ものは元パスへ戻す', () async {
      final photos = await createPhotos(2);
      await makeStore().stage(tripWith(photos), root);

      final recovery = await makeStore().recover(root, tripExists: (_) => true);

      expect(recovery.active, isEmpty);
      expect(recovery.rolledBack.length, 1);
      expect(recovery.skipped, isEmpty);
      for (final photo in photos) {
        expect(await File(photo.path).exists(), isTrue);
      }
      expect(
        await Directory('${root.path}/pending-deletions/trip-1').exists(),
        isFalse,
      );
    });

    test('削除確定済みかつ期限内ならactiveとして返す', () async {
      final photos = await createPhotos(1);
      await makeStore().stage(tripWith(photos), root);

      final recovery = await makeStore().recover(
        root,
        tripExists: (_) => false,
      );

      expect(recovery.active.length, 1);
      expect(recovery.active.single.trip.id, 'trip-1');
      expect(recovery.rolledBack, isEmpty);
      // ファイルは退避先に残っている。
      final trashFile = File(
        '${root.path}/pending-deletions/trip-1/0-photo-0.jpg',
      );
      expect(await trashFile.exists(), isTrue);
    });

    test('期限切れのものはactiveにせずcleanupに任せる', () async {
      await makeStore().stage(tripWith(await createPhotos(1)), root);
      // 期限を過ぎさせる。
      fakeNow = fakeNow.add(const Duration(minutes: 1));

      final recovery = await makeStore().recover(
        root,
        tripExists: (_) => false,
      );

      expect(recovery.active, isEmpty);
      expect(recovery.rolledBack, isEmpty);
    });

    test('壊れたmanifestはデータ保護のため保持しskippedとして報告する', () async {
      final photos = await createPhotos(1);
      await makeStore().stage(tripWith(photos), root);
      await File(
        '${root.path}/pending-deletions/trip-1/manifest.json',
      ).writeAsString('{ broken json');

      final recovery = await makeStore().recover(
        root,
        tripExists: (_) => false,
      );

      expect(recovery.active, isEmpty);
      expect(recovery.skipped.length, 1);
      // 壊れた退避データは削除されない。
      expect(
        await File(
          '${root.path}/pending-deletions/trip-1/0-photo-0.jpg',
        ).exists(),
        isTrue,
      );
    });

    test('管理ディレクトリ外のパスを記録したmanifestはskippedにする', () async {
      final photos = await createPhotos(1);
      await makeStore().stage(tripWith(photos), root);
      final manifestPath =
          '${root.path}/pending-deletions/trip-1/manifest.json';
      final manifest =
          json.decode(await File(manifestPath).readAsString())
              as Map<String, dynamic>;
      final records = manifest['records'] as List<dynamic>;
      (records.first as Map<String, dynamic>)['originalPath'] =
          'C:/outside/x.jpg';
      await File(manifestPath).writeAsString(json.encode(manifest));

      final recovery = await makeStore().recover(
        root,
        tripExists: (_) => false,
      );

      expect(recovery.skipped.length, 1);
    });
  });

  group('restart相当（永続化と回収）', () {
    test('アプリ再起動後にmanifestから削除待ち状態を復元できる', () async {
      final photos = await createPhotos(2);
      await makeStore().stage(tripWith(photos), root);

      // 新しいインスタンス（=再起動）で読み直す。
      final freshStore = PendingDeletionStore(now: () => fakeNow);
      final recovery = await freshStore.recover(root, tripExists: (_) => false);

      expect(recovery.active.length, 1);
      final pending = recovery.active.single;
      expect(pending.trip.id, 'trip-1');
      expect(pending.trip.title, 'テスト旅行');
      expect(pending.records.length, 2);
      expect(pending.records[1].originalPath, photos[1].path);

      // 復元も再起動後で動作する。
      final restored = await freshStore.restore(pending);
      expect(restored.photos.length, 2);
      for (final photo in photos) {
        expect(await File(photo.path).exists(), isTrue);
      }
    });
  });

  group('revertRestore / rollback', () {
    test('AppData commit失敗時の復元巻き戻しで退避先へ戻す', () async {
      final photos = await createPhotos(2);
      final pending = await makeStore().stage(tripWith(photos), root);

      await makeStore().restore(pending);
      // 元パスへ戻った状態で、commitが失敗した想定。
      await makeStore().revertRestore(pending);

      for (final record in pending.records) {
        expect(await File(record.originalPath).exists(), isFalse);
        expect(await File(record.trashPath!).exists(), isTrue);
      }
    });

    test('rollbackはファイルとmanifestを後始末しtrueを返す', () async {
      final photos = await createPhotos(1);
      final pending = await makeStore().stage(tripWith(photos), root);

      final clean = await makeStore().rollback(pending);

      expect(clean, isTrue);
      expect(await File(photos.single.path).exists(), isTrue);
      expect(
        await Directory('${root.path}/pending-deletions/trip-1').exists(),
        isFalse,
      );
    });
  });
}

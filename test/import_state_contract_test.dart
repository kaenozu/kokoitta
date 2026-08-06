import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/import_progress.dart';
import 'package:kokoitta_app/import_state_contract.dart';

void main() {
  group('ImportUiSnapshot', () {
    test('maps busy phases without inventing percentages', () {
      final snapshot = ImportUiSnapshot.fromEvent(
        const ImportEvent(
          requestId: 'request-1',
          phase: ImportPhase.copying,
          processed: 2,
          total: 5,
          succeeded: 2,
          failed: 0,
          isTerminal: false,
        ),
      );

      expect(snapshot.state, ImportUiState.copying);
      expect(snapshot.isBusy, isTrue);
      expect(snapshot.canCancel, isTrue);
      expect(snapshot.processed, 2);
      expect(snapshot.total, 5);
      expect(snapshot.message, contains('2 / 5'));
      expect(snapshot.message, isNot(contains('%')));
    });

    test('keeps successful and failed counts separate for partial failure', () {
      final snapshot = ImportUiSnapshot.fromEvent(
        const ImportEvent(
          requestId: 'request-2',
          phase: ImportPhase.partialFailure,
          processed: 4,
          total: 4,
          succeeded: 3,
          failed: 1,
          isTerminal: true,
          successes: <ImportedFile>[
            ImportedFile(
              path: '/private/a',
              name: 'a.jpg',
              mimeType: 'image/jpeg',
              size: 1,
            ),
            ImportedFile(
              path: '/private/b',
              name: 'b.jpg',
              mimeType: 'image/jpeg',
              size: 1,
            ),
            ImportedFile(
              path: '/private/c',
              name: 'c.jpg',
              mimeType: 'image/jpeg',
              size: 1,
            ),
          ],
          failures: <ImportFailure>[
            ImportFailure(
              index: 3,
              errorCode: 'decode_failed',
              reason: '/private/device/path',
            ),
          ],
        ),
      );

      expect(snapshot.state, ImportUiState.partialFailure);
      expect(snapshot.succeeded, 3);
      expect(snapshot.failed, 1);
      expect(snapshot.message, contains('3件'));
      expect(snapshot.message, contains('1件'));
      expect(snapshot.message, isNot(contains('/private/')));
      expect(snapshot.isLiveRegion, isTrue);
    });

    test('maps quota failure without exposing internal failure details', () {
      final snapshot = ImportUiSnapshot.fromEvent(
        const ImportEvent(
          requestId: 'request-3',
          phase: ImportPhase.failed,
          processed: 1,
          total: 1,
          succeeded: 0,
          failed: 1,
          isTerminal: true,
          failures: <ImportFailure>[
            ImportFailure(
              index: 0,
              errorCode: 'photo_quota_exceeded',
              reason: 'internal path /data/user/0/example',
            ),
          ],
        ),
      );

      expect(snapshot.state, ImportUiState.quotaReached);
      expect(snapshot.message, isNot(contains('/data/user/0')));
      expect(snapshot.isTerminal, isTrue);
    });

    test('cancelled copy is result focused and privacy safe', () {
      final snapshot = ImportUiSnapshot.fromEvent(
        const ImportEvent(
          requestId: 'request-4',
          phase: ImportPhase.cancelled,
          processed: 0,
          total: 4,
          succeeded: 0,
          failed: 0,
          isTerminal: true,
        ),
      );

      expect(snapshot.state, ImportUiState.cancelled);
      expect(snapshot.title, '写真の追加を取り消しました');
      expect(snapshot.canCancel, isFalse);
      expect(snapshot.isTerminal, isTrue);
    });

    test('blocked state carries only the supplied user-facing reason', () {
      final snapshot = ImportUiSnapshot.blocked('バックアップ処理が完了すると追加できます。');

      expect(snapshot.state, ImportUiState.blocked);
      expect(snapshot.isBusy, isFalse);
      expect(snapshot.isTerminal, isFalse);
      expect(snapshot.isLiveRegion, isTrue);
    });
  });
}

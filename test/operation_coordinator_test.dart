import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/operation_coordinator.dart';

void main() {
  group('OperationCoordinator state machine', () {
    late OperationCoordinator coordinator;

    setUp(() {
      coordinator = OperationCoordinator();
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('starts in idle state', () {
      expect(coordinator.status, OperationStatus.idle);
      expect(coordinator.isBusy, isFalse);
      expect(coordinator.isBackingUp, isFalse);
      expect(coordinator.isRestoring, isFalse);
    });

    test('runMutation transitions through mutating and back to idle', () async {
      final result = await coordinator.runMutation(() async => 42);
      expect(result, 42);
      expect(coordinator.status, OperationStatus.idle);
    });

    test(
      'runMutation allows nested state inspection during execution',
      () async {
        final completer = Completer<void>();
        final mutation = coordinator.runMutation(() async {
          expect(coordinator.status, OperationStatus.mutating);
          expect(coordinator.isBusy, isTrue);
          completer.complete();
        });
        await completer.future;
        await mutation;
        expect(coordinator.status, OperationStatus.idle);
      },
    );

    test('serializes multiple mutations sequentially', () async {
      final order = <int>[];
      final f1 = coordinator.runMutation(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add(1);
      });
      final f2 = coordinator.runMutation(() async {
        order.add(2);
      });
      await Future.wait<void>([f1, f2]);
      expect(order, [1, 2]);
    });

    test('runBackup guards against double backup', () async {
      final started = Completer<void>();
      final hold = Completer<void>();
      final backup1 = coordinator.runBackup(() async {
        started.complete();
        await hold.future;
      });
      await started.future;
      expect(() => coordinator.runBackup(() async {}), throwsStateError);
      hold.complete();
      await backup1;
      expect(coordinator.status, OperationStatus.idle);
    });

    test('runBackup allows new backup after completion', () async {
      await coordinator.runBackup(() async {});
      await coordinator.runBackup(() async {});
      expect(coordinator.status, OperationStatus.idle);
    });

    test('beginRestorePrepare prevents double restore preparation', () {
      coordinator.beginRestorePrepare();
      expect(coordinator.status, OperationStatus.restorePrepare);
      expect(coordinator.isRestoring, isTrue);
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
    });

    test('restore lifecycle: prepare → confirm → commit → end', () async {
      coordinator.beginRestorePrepare();
      expect(coordinator.status, OperationStatus.restorePrepare);

      coordinator.enterRestoreConfirm();
      expect(coordinator.status, OperationStatus.restoreConfirm);

      await coordinator.runRestoreCommit(() async {
        expect(coordinator.status, OperationStatus.mutating);
      });

      coordinator.endRestore();
      expect(coordinator.status, OperationStatus.idle);
      expect(coordinator.isRestoring, isFalse);
    });

    test('restore lifecycle: prepare → cancel → idle', () async {
      coordinator.beginRestorePrepare();
      coordinator.endRestore();
      expect(coordinator.status, OperationStatus.idle);
      expect(coordinator.isRestoring, isFalse);
    });

    test('restore lifecycle: prepare → confirm → cancel → idle', () async {
      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      coordinator.endRestore();
      expect(coordinator.status, OperationStatus.idle);
    });

    test('error in runMutation transitions to failed state', () async {
      try {
        await coordinator.runMutation<int>(() async {
          throw StateError('test error');
        });
        fail('Expected exception');
      } on StateError {
        // expected
      }
      expect(coordinator.status, OperationStatus.failed);
    });

    test('error in runMutation allows subsequent mutation to run', () async {
      try {
        await coordinator.runMutation<int>(() async {
          throw StateError('test error');
        });
      } catch (_) {}
      expect(coordinator.status, OperationStatus.failed);

      final result = await coordinator.runMutation(() async => 'success');
      expect(result, 'success');
      expect(coordinator.status, OperationStatus.idle);
    });

    test('error in runBackup allows subsequent operations', () async {
      try {
        await coordinator.runBackup(() async {
          throw FormatException('test failure');
        });
      } catch (_) {}
      expect(coordinator.status, OperationStatus.failed);

      final result = await coordinator.runMutation(() async => 99);
      expect(result, 99);
      expect(coordinator.status, OperationStatus.idle);
    });

    test('statusStream emits status changes', () async {
      final statuses = <OperationStatus>[];
      final sub = coordinator.statusStream.listen(statuses.add);
      await coordinator.runMutation(() async {});
      await Future<void>.delayed(Duration.zero);
      expect(
        statuses,
        containsAllInOrder([OperationStatus.mutating, OperationStatus.idle]),
      );
      sub.cancel();
    });

    test('isBusy is true during mutating', () async {
      final busyCaptures = <bool>[];
      final completer = Completer<void>();
      final mutation = coordinator.runMutation(() async {
        busyCaptures.add(coordinator.isBusy);
        expect(coordinator.isBusy, isTrue);
        completer.complete();
      });
      await completer.future;
      expect(busyCaptures, [true]);
      await mutation;
      expect(coordinator.isBusy, isFalse);
    });

    test('isBusy is true during backup', () async {
      final completer = Completer<void>();
      final backup = coordinator.runBackup(() async {
        expect(coordinator.isBusy, isTrue);
        expect(coordinator.isBackingUp, isTrue);
        completer.complete();
      });
      await completer.future;
      await backup;
      expect(coordinator.isBusy, isFalse);
    });
  });

  group('OperationCoordinator concurrency correctness', () {
    test(
      'backup and mutation are serialized (mutation completes before backup)',
      () async {
        final coordinator = OperationCoordinator();
        final order = <String>[];

        await coordinator.runMutation(() async {
          order.add('mutation');
        });
        await coordinator.runBackup(() async {
          order.add('backup');
        });

        expect(order, ['mutation', 'backup']);
        expect(coordinator.status, OperationStatus.idle);
        coordinator.dispose();
      },
    );

    test('backup captures consistent snapshot after mutation', () async {
      final coordinator = OperationCoordinator();
      var data = <String>['a'];

      await coordinator.runMutation(() async {
        data.add('b');
        data.add('c');
      });

      final snapshot = await coordinator.runBackup(() async {
        return List<String>.from(data);
      });

      expect(snapshot, containsAllInOrder(<String>['a', 'b', 'c']));
      expect(coordinator.status, OperationStatus.idle);
      coordinator.dispose();
    });

    test(
      'failed operation does not block subsequent operations from status stream',
      () async {
        final coordinator = OperationCoordinator();
        final statuses = <OperationStatus>[];
        final sub = coordinator.statusStream.listen(statuses.add);

        try {
          await coordinator.runMutation(() async {
            throw StateError('boom');
          });
        } catch (_) {}

        await coordinator.runMutation(() async {});

        await Future<void>.delayed(Duration.zero);
        expect(statuses, contains(OperationStatus.failed));
        expect(statuses.last, OperationStatus.idle);
        sub.cancel();
        coordinator.dispose();
      },
    );
  });
}

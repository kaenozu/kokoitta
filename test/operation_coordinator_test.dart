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

    test('same-tick double backup rejects second call', () {
      coordinator.runBackup(() async {});
      expect(() => coordinator.runBackup(() async {}), throwsStateError);
    });

    test('same-tick double restore preparation rejects second call', () {
      coordinator.beginRestorePrepare();
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
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

    test('beginRestorePrepare rejects when backup queued', () {
      coordinator.runBackup(() async {});
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
    });

    test('beginRestorePrepare rejects during mutation', () async {
      final hold = Completer<void>();
      unawaited(
        coordinator.runMutation(() async {
          await hold.future;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
      hold.complete();
    });

    test('runBackup rejects during restore session', () {
      coordinator.beginRestorePrepare();
      expect(() => coordinator.runBackup(() async {}), throwsStateError);
      coordinator.endRestore();
    });

    test('runMutation rejects during restore session', () {
      coordinator.beginRestorePrepare();
      expect(() => coordinator.runMutation(() async {}), throwsStateError);
      coordinator.endRestore();
    });

    test('same-tick runMutation then beginRestorePrepare rejected', () {
      unawaited(coordinator.runMutation(() async {}));
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
    });

    test('queued mutation before execution blocks restore', () async {
      final hold = Completer<void>();
      unawaited(
        coordinator.runMutation(() async {
          await hold.future;
        }),
      );
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
      hold.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('mutation completion allows restore start', () async {
      await coordinator.runMutation(() async {});
      coordinator.beginRestorePrepare();
      coordinator.endRestore();
      expect(coordinator.status, OperationStatus.idle);
    });

    test(
      'all queued mutations block restore until the last completes',
      () async {
        final firstHold = Completer<void>();
        final secondHold = Completer<void>();
        final first = coordinator.runMutation(() => firstHold.future);
        final second = coordinator.runMutation(() => secondHold.future);

        firstHold.complete();
        await first;
        expect(() => coordinator.beginRestorePrepare(), throwsStateError);

        secondHold.complete();
        await second;
        coordinator.beginRestorePrepare();
        coordinator.endRestore();
      },
    );

    test('restore lifecycle: prepare to confirm to commit to end', () async {
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

    test('restore lifecycle: prepare to cancel to idle', () async {
      coordinator.beginRestorePrepare();
      coordinator.endRestore();
      expect(coordinator.status, OperationStatus.idle);
      expect(coordinator.isRestoring, isFalse);
    });

    test('restore lifecycle: prepare to confirm to cancel to idle', () async {
      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      coordinator.endRestore();
      expect(coordinator.status, OperationStatus.idle);
    });

    test('enterRestoreConfirm rejects from wrong state', () {
      coordinator.beginRestorePrepare();
      coordinator.endRestore();
      expect(() => coordinator.enterRestoreConfirm(), throwsStateError);
    });

    test('enterRestoreConfirm rejects from idle', () {
      expect(() => coordinator.enterRestoreConfirm(), throwsStateError);
    });

    test('runRestoreCommit rejects from wrong state', () {
      coordinator.beginRestorePrepare();
      expect(() => coordinator.runRestoreCommit(() async {}), throwsStateError);
      coordinator.endRestore();
    });

    test('endRestore rejects with no session', () {
      expect(() => coordinator.endRestore(), throwsStateError);
    });

    test('same-tick double runRestoreCommit rejects second', () {
      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      coordinator.runRestoreCommit(() async {});
      expect(() => coordinator.runRestoreCommit(() async {}), throwsStateError);
    });

    test('endRestore rejected while commit queued', () {
      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      coordinator.runRestoreCommit(() async {});
      expect(() => coordinator.endRestore(), throwsStateError);
    });

    test('endRestore rejected while commit running', () async {
      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      final hold = Completer<void>();
      unawaited(
        coordinator.runRestoreCommit(() async {
          await hold.future;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(() => coordinator.endRestore(), throwsStateError);
      hold.complete();
    });

    test('commit failure allows safe session end', () async {
      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      try {
        await coordinator.runRestoreCommit(() async {
          throw StateError('commit failed');
        });
      } catch (_) {}
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
      await sub.cancel();
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
      'backup waits for mutation when both are submitted same-tick',
      () async {
        final coordinator = OperationCoordinator();
        final order = <String>[];
        final mutationHold = Completer<void>();

        final mutation = coordinator.runMutation(() async {
          await mutationHold.future;
          order.add('mutation');
        });

        final backup = coordinator.runBackup(() async {
          order.add('backup');
        });

        mutationHold.complete();
        await mutation;
        await backup;

        expect(order, ['mutation', 'backup']);
        expect(coordinator.status, OperationStatus.idle);
        coordinator.dispose();
      },
    );

    test(
      'backup return value is available immediately queue is free',
      () async {
        final coordinator = OperationCoordinator();
        final backupFile = await coordinator.runBackup(() async => 'file.zip');
        expect(backupFile, 'file.zip');
        expect(coordinator.status, OperationStatus.idle);
        expect(coordinator.isBusy, isFalse);
        coordinator.dispose();
      },
    );

    test(
      'backup snapshot is not affected by mutation submitted during backup',
      () async {
        final coordinator = OperationCoordinator();
        final data = <String>['a'];
        final backupStarted = Completer<void>();

        final backup = coordinator.runBackup(() async {
          backupStarted.complete();
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return List<String>.from(data);
        });

        await backupStarted.future;
        final mutation = coordinator.runMutation(() async {
          data.add('b');
        });

        final snapshot = await backup;
        await mutation;

        expect(snapshot, ['a']);
        expect(data, ['a', 'b']);
        coordinator.dispose();
      },
    );

    test('mutation queued blocks restore start', () async {
      final coordinator = OperationCoordinator();
      final mutation = coordinator.runMutation(() async {});
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
      await mutation;
      coordinator.dispose();
    });

    test('mutation complete then restore commit are serialized', () async {
      final coordinator = OperationCoordinator();
      final order = <String>[];

      await coordinator.runMutation(() async {
        order.add('mutation');
      });

      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      await coordinator.runRestoreCommit(() async {
        order.add('restore');
      });
      coordinator.endRestore();

      expect(order, ['mutation', 'restore']);
      expect(coordinator.status, OperationStatus.idle);
      coordinator.dispose();
    });

    test('failed operation emits failed then idle on recovery', () async {
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
      await sub.cancel();
      coordinator.dispose();
    });
  });

  group('OperationCoordinator dispose safety', () {
    test('operations after dispose are rejected', () {
      final coordinator = OperationCoordinator();
      coordinator.dispose();
      expect(() => coordinator.runMutation(() async {}), throwsStateError);
      expect(() => coordinator.runBackup(() async {}), throwsStateError);
      expect(() => coordinator.beginRestorePrepare(), throwsStateError);
      expect(() => coordinator.enterRestoreConfirm(), throwsStateError);
      expect(() => coordinator.runRestoreCommit(() async {}), throwsStateError);
    });

    test('action completing after dispose does not throw', () async {
      final coordinator = OperationCoordinator();
      final actionHold = Completer<void>();

      final mutation = coordinator.runMutation(() async {
        await actionHold.future;
        return 42;
      });

      await Future<void>.delayed(Duration.zero);
      coordinator.dispose();
      actionHold.complete();

      await expectLater(mutation, completes);
    });

    test(
      'action queued but not started after dispose completes with error',
      () async {
        final coordinator = OperationCoordinator();
        final actionHold = Completer<void>();

        final mutation = coordinator.runMutation(() async {
          await actionHold.future;
          return 42;
        });

        actionHold.complete();
        coordinator.dispose();

        await expectLater(mutation, throwsA(isA<StateError>()));
      },
    );

    test(
      'dispose with queued backup does not hang or add to closed stream',
      () async {
        final coordinator = OperationCoordinator();
        final hold = Completer<void>();
        final mutation1 = coordinator.runMutation(() async {
          await hold.future;
        });
        final backup = coordinator.runBackup(() async {});
        coordinator.dispose();
        hold.complete();
        await expectLater(mutation1, throwsA(isA<StateError>()));
        await expectLater(backup, throwsA(isA<StateError>()));
      },
    );

    test('dispose with queued restore commit does not hang', () async {
      final coordinator = OperationCoordinator();
      coordinator.beginRestorePrepare();
      coordinator.enterRestoreConfirm();
      final commit = coordinator.runRestoreCommit(() async {});
      coordinator.dispose();
      await expectLater(commit, throwsA(isA<StateError>()));
    });
  });
}

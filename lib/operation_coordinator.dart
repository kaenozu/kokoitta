import 'dart:async';

enum OperationStatus {
  idle,
  mutating,
  backup,
  restorePrepare,
  restoreConfirm,
  failed,
}

class OperationCoordinator {
  final _statusController = StreamController<OperationStatus>.broadcast();
  Future<void> _queue = Future<void>.value();
  OperationStatus _status = OperationStatus.idle;
  int _pendingMutationCount = 0;
  bool _hasBackupQueued = false;
  bool _hasRestoreSession = false;
  bool _hasRestoreCommitQueued = false;
  bool _isDisposed = false;

  OperationStatus get status => _status;
  Stream<OperationStatus> get statusStream => _statusController.stream;

  bool get isBusy =>
      _pendingMutationCount > 0 ||
      _hasBackupQueued ||
      _status == OperationStatus.mutating ||
      _status == OperationStatus.backup ||
      _status == OperationStatus.restorePrepare ||
      _status == OperationStatus.restoreConfirm;

  bool get isRestoring =>
      _status == OperationStatus.restorePrepare ||
      _status == OperationStatus.restoreConfirm;

  bool get isBackingUp => _status == OperationStatus.backup;

  Future<T> runMutation<T>(Future<T> Function() action) {
    _ensureNotDisposed();
    if (_hasRestoreSession) {
      throw StateError('Cannot mutate during restore session');
    }
    _pendingMutationCount += 1;
    return _enqueue(
      OperationStatus.mutating,
      action,
      onFinally: () {
        _pendingMutationCount -= 1;
      },
    );
  }

  Future<T> runBackup<T>(Future<T> Function() action) {
    _ensureNotDisposed();
    if (_hasBackupQueued || _status == OperationStatus.backup) {
      throw StateError('Backup already in progress');
    }
    if (_hasRestoreSession) {
      throw StateError('Cannot backup during restore session');
    }
    _hasBackupQueued = true;
    return _enqueue(
      OperationStatus.backup,
      action,
      onFinally: () {
        _hasBackupQueued = false;
      },
    );
  }

  void beginRestorePrepare() {
    _ensureNotDisposed();
    if (isBusy) {
      throw StateError('Cannot begin restore preparation while busy');
    }
    if (_hasRestoreSession) {
      throw StateError('Restore session already in progress');
    }
    _hasRestoreSession = true;
    _updateStatus(OperationStatus.restorePrepare);
  }

  void enterRestoreConfirm() {
    _ensureNotDisposed();
    if (_status != OperationStatus.restorePrepare) {
      throw StateError('Must be in restorePrepare state to enter confirm');
    }
    _updateStatus(OperationStatus.restoreConfirm);
  }

  Future<T> runRestoreCommit<T>(Future<T> Function() action) {
    _ensureNotDisposed();
    if (_status != OperationStatus.restoreConfirm) {
      throw StateError('Must be in restoreConfirm state to commit');
    }
    if (_hasRestoreCommitQueued) {
      throw StateError('Restore commit already queued');
    }
    _hasRestoreCommitQueued = true;
    return _enqueue(
      OperationStatus.mutating,
      action,
      onFinally: () {
        _hasRestoreCommitQueued = false;
      },
    );
  }

  void endRestore() {
    _ensureNotDisposed();
    if (!_hasRestoreSession) {
      throw StateError('No restore session in progress');
    }
    if (_hasRestoreCommitQueued) {
      throw StateError('Cannot end restore while commit is queued or running');
    }
    _hasRestoreSession = false;
    _updateStatus(OperationStatus.idle);
  }

  void _ensureNotDisposed() {
    if (_isDisposed) throw StateError('Coordinator is disposed');
  }

  Future<T> _enqueue<T>(
    OperationStatus newStatus,
    Future<T> Function() action, {
    void Function()? onFinally,
  }) {
    final completer = Completer<T>();
    _queue = _queue
        .then((_) async {
          if (_isDisposed) {
            if (!completer.isCompleted) {
              completer.completeError(StateError('Coordinator is disposed'));
            }
            return;
          }
          _updateStatus(newStatus);
          try {
            final result = await action();
            _updateStatus(OperationStatus.idle);
            if (!completer.isCompleted) {
              completer.complete(result);
            }
          } catch (error, stackTrace) {
            _updateStatus(OperationStatus.failed);
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        })
        .whenComplete(() {
          onFinally?.call();
        });
    return completer.future;
  }

  void _updateStatus(OperationStatus newStatus) {
    _status = newStatus;
    if (!_isDisposed) {
      _statusController.add(newStatus);
    }
  }

  void dispose() {
    _isDisposed = true;
    _pendingMutationCount = 0;
    _hasBackupQueued = false;
    _hasRestoreSession = false;
    _hasRestoreCommitQueued = false;
    _statusController.close();
  }
}

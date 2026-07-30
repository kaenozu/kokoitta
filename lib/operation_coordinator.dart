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

  OperationStatus get status => _status;
  Stream<OperationStatus> get statusStream => _statusController.stream;

  bool get isBusy =>
      _status == OperationStatus.mutating ||
      _status == OperationStatus.backup ||
      _status == OperationStatus.restorePrepare ||
      _status == OperationStatus.restoreConfirm;

  bool get isRestoring =>
      _status == OperationStatus.restorePrepare ||
      _status == OperationStatus.restoreConfirm;

  bool get isBackingUp => _status == OperationStatus.backup;

  Future<T> runMutation<T>(Future<T> Function() action) {
    return _enqueue(OperationStatus.mutating, action);
  }

  Future<T> runBackup<T>(Future<T> Function() action) {
    if (_status == OperationStatus.backup) {
      throw StateError('Backup already in progress');
    }
    return _enqueue(OperationStatus.backup, action);
  }

  void beginRestorePrepare() {
    if (isRestoring) {
      throw StateError('Restore already in progress');
    }
    _updateStatus(OperationStatus.restorePrepare);
  }

  void enterRestoreConfirm() {
    _updateStatus(OperationStatus.restoreConfirm);
  }

  void endRestore() {
    _updateStatus(OperationStatus.idle);
  }

  Future<T> runRestoreCommit<T>(Future<T> Function() action) {
    return _enqueue(OperationStatus.mutating, action);
  }

  Future<T> _enqueue<T>(
    OperationStatus newStatus,
    Future<T> Function() action,
  ) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      _updateStatus(newStatus);
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        _updateStatus(OperationStatus.failed);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        return;
      }
      _updateStatus(OperationStatus.idle);
    });
    return completer.future;
  }

  void _updateStatus(OperationStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void dispose() {
    _statusController.close();
  }
}

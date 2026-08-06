import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'pending_deletion.dart';

/// 起動時にstaged削除を現在のAppDataと照合して回復する。
///
/// deleteTripは写真退避とstaged manifest保存後にAppDataをcommitし、その後で
/// manifestをpendingへ更新する。stagedが残っている場合、AppDataに旅行が
/// 存在するかでcommit前後を判定する。
///
/// - 旅行が存在する: commit前として写真を元pathへ戻し、manifestを除去する。
/// - 旅行が存在しない: commit後として写真をtrashに維持し、pendingへ進める。
/// - 物理状態が曖昧: 変更せずmanifestを保持する。
Future<List<PendingDeletionOperation>> recoverPendingDeletions({
  required PendingDeletionManager manager,
  required AppData data,
}) async {
  final operations = await manager.loadOperations();

  for (final operation in [...operations]) {
    if (operation.state != PendingDeletionState.staged) continue;

    final tripStillExists = data.trips.any(
      (trip) => trip.id == operation.trip.id,
    );
    if (!tripStillExists) {
      if (!_canPromoteStagedToPending(operation)) continue;
      operation.state = PendingDeletionState.pending;
      await _saveOperations(manager, operations);
      continue;
    }

    if (!_canResumeStagedRestore(operation)) continue;
    try {
      for (final item in operation.items.reversed) {
        final originalExists = File(item.originalPath).existsSync();
        final trashExists = File(item.trashPath).existsSync();

        if (item.physicalState == PendingDeletionPhysicalState.restored) {
          continue;
        }
        if (originalExists && !trashExists) {
          // rename完了後・manifest保存前に中断した境界を回収する。
          item.physicalState = PendingDeletionPhysicalState.restored;
          await _saveOperations(manager, operations);
          continue;
        }

        await manager.moveFile(item.trashPath, item.originalPath);
        item.physicalState = PendingDeletionPhysicalState.restored;
        // 複数写真の途中で停止しても復元済みitemをmanifestに保持する。
        await _saveOperations(manager, operations);
      }
    } catch (_) {
      // 成功済みitemのphysicalStateを保持したまま、次回起動で再開可能にする。
      await _saveOperations(manager, operations);
      rethrow;
    }

    operations.remove(operation);
    await _saveOperations(manager, operations);
  }

  await manager.finalizeExpired();
  return manager.loadOperations();
}

bool _canPromoteStagedToPending(PendingDeletionOperation operation) {
  for (final item in operation.items) {
    if (item.physicalState != PendingDeletionPhysicalState.staged) {
      return false;
    }
    if (File(item.originalPath).existsSync()) return false;
    if (!File(item.trashPath).existsSync()) return false;
  }
  return true;
}

bool _canResumeStagedRestore(PendingDeletionOperation operation) {
  for (final item in operation.items) {
    final originalExists = File(item.originalPath).existsSync();
    final trashExists = File(item.trashPath).existsSync();
    switch (item.physicalState) {
      case PendingDeletionPhysicalState.staged:
        if ((!originalExists && trashExists) ||
            (originalExists && !trashExists)) {
          continue;
        }
        return false;
      case PendingDeletionPhysicalState.restored:
        if (originalExists && !trashExists) continue;
        return false;
      case PendingDeletionPhysicalState.deleted:
        return false;
    }
  }
  return true;
}

Future<void> _saveOperations(
  PendingDeletionManager manager,
  List<PendingDeletionOperation> operations,
) async {
  if (operations.isEmpty) {
    await manager.store.save(null);
    return;
  }
  await manager.store.save(
    jsonEncode(<String, Object?>{
      'version': 1,
      'operations': operations.map((operation) => operation.toJson()).toList(),
    }),
  );
}

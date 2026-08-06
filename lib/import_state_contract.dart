import 'import_progress.dart';

/// UI-facing import states shared by picker and Android share flows.
enum ImportUiState {
  idle,
  selecting,
  validating,
  copying,
  saving,
  completed,
  partialFailure,
  failed,
  cancelled,
  quotaReached,
  blocked,
}

/// Privacy-safe presentation model for import progress and results.
///
/// It deliberately exposes counts and user-facing copy only. File paths,
/// content URIs, MIME details, and exception strings never cross this boundary.
class ImportUiSnapshot {
  const ImportUiSnapshot({
    required this.state,
    required this.title,
    required this.message,
    this.processed = 0,
    this.total = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.canCancel = false,
    this.isLiveRegion = false,
  });

  final ImportUiState state;
  final String title;
  final String message;
  final int processed;
  final int total;
  final int succeeded;
  final int failed;
  final bool canCancel;
  final bool isLiveRegion;

  bool get isBusy => switch (state) {
    ImportUiState.selecting ||
    ImportUiState.validating ||
    ImportUiState.copying ||
    ImportUiState.saving => true,
    _ => false,
  };

  bool get isTerminal => switch (state) {
    ImportUiState.completed ||
    ImportUiState.partialFailure ||
    ImportUiState.failed ||
    ImportUiState.cancelled ||
    ImportUiState.quotaReached => true,
    _ => false,
  };

  static ImportUiSnapshot idle() => const ImportUiSnapshot(
    state: ImportUiState.idle,
    title: '写真を追加できます',
    message: '端末から写真を選んで、旅の記録に追加します。',
  );

  static ImportUiSnapshot blocked(String reason) => ImportUiSnapshot(
    state: ImportUiState.blocked,
    title: '現在は写真を追加できません',
    message: reason,
    isLiveRegion: true,
  );

  static ImportUiSnapshot quotaReached({required int limit}) =>
      ImportUiSnapshot(
        state: ImportUiState.quotaReached,
        title: '写真の保存上限に達しています',
        message: '保存できる写真は$limit枚までです。不要な写真を整理してから再度お試しください。',
        isLiveRegion: true,
      );

  factory ImportUiSnapshot.fromEvent(ImportEvent event) {
    final state = switch (event.phase) {
      ImportPhase.idle => ImportUiState.idle,
      ImportPhase.preparing => ImportUiState.validating,
      ImportPhase.copying => ImportUiState.copying,
      ImportPhase.saving => ImportUiState.saving,
      ImportPhase.completed => ImportUiState.completed,
      ImportPhase.partialFailure => ImportUiState.partialFailure,
      ImportPhase.failed =>
        _containsQuotaFailure(event)
            ? ImportUiState.quotaReached
            : ImportUiState.failed,
      ImportPhase.cancelled => ImportUiState.cancelled,
    };

    final copy = switch (state) {
      ImportUiState.idle => ('写真を追加できます', '端末から写真を選べます。'),
      ImportUiState.validating => (
        event.total > 0
            ? '取り込み ${event.processed} / ${event.total}'
            : '写真を確認しています',
        '追加できる形式か安全に確認しています。',
      ),
      ImportUiState.copying => (
        '取り込み ${event.processed} / ${event.total}',
        '${event.processed} / ${event.total}件を処理しました。',
      ),
      ImportUiState.saving => (
        event.total > 0
            ? '取り込み ${event.processed} / ${event.total}'
            : '写真を保存しています',
        '端末内へ安全に保存しています。',
      ),
      ImportUiState.completed => ('写真を保存しました', '${event.succeeded}件を追加しました。'),
      ImportUiState.partialFailure => (
        '一部の写真を保存できませんでした',
        '${event.succeeded}件を保存し、${event.failed}件を保存できませんでした。成功した写真はそのまま利用できます。',
      ),
      ImportUiState.failed => (
        '写真を保存できませんでした',
        '写真は追加されていません。内容を確認して再度お試しください。',
      ),
      ImportUiState.cancelled => ('写真の追加を取り消しました', '新しい写真は保存されていません。'),
      ImportUiState.quotaReached => (
        '写真の保存上限に達しています',
        '不要な写真を整理してから再度お試しください。',
      ),
      ImportUiState.selecting || ImportUiState.blocked => throw StateError(
        'event does not map to this state',
      ),
    };

    return ImportUiSnapshot(
      state: state,
      title: copy.$1,
      message: copy.$2,
      processed: event.processed,
      total: event.total,
      succeeded: event.succeeded,
      failed: event.failed,
      canCancel:
          !event.isTerminal &&
          (event.phase == ImportPhase.preparing ||
              event.phase == ImportPhase.copying ||
              event.phase == ImportPhase.saving),
      isLiveRegion: state != ImportUiState.idle,
    );
  }

  static bool _containsQuotaFailure(ImportEvent event) => event.failures.any(
    (failure) => failure.errorCode == 'photo_quota_exceeded',
  );
}

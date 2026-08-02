/// Shared import progress/result contract used by the picker and Android share.
library;

enum ImportPhase {
  idle,
  preparing,
  copying,
  saving,
  completed,
  partialFailure,
  failed,
  cancelled,
}

class ImportedFile {
  const ImportedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.size,
  });

  final String path;
  final String name;
  final String mimeType;
  final int size;
}

class ImportFailure {
  const ImportFailure({
    required this.index,
    required this.errorCode,
    required this.reason,
  });

  final int index;
  final String errorCode;
  final String reason;
}

class ImportEvent {
  const ImportEvent({
    required this.requestId,
    required this.phase,
    required this.processed,
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.isTerminal,
    this.successes = const <ImportedFile>[],
    this.failures = const <ImportFailure>[],
  });

  final String requestId;
  final ImportPhase phase;
  final int processed;
  final int total;
  final int succeeded;
  final int failed;
  final bool isTerminal;
  final List<ImportedFile> successes;
  final List<ImportFailure> failures;

  ImportEvent copyWith({
    ImportPhase? phase,
    int? processed,
    int? succeeded,
    int? failed,
    bool? isTerminal,
  }) => ImportEvent(
    requestId: requestId,
    phase: phase ?? this.phase,
    processed: processed ?? this.processed,
    total: total,
    succeeded: succeeded ?? this.succeeded,
    failed: failed ?? this.failed,
    isTerminal: isTerminal ?? this.isTerminal,
    successes: successes,
    failures: failures,
  );
}

class ImportEventParser {
  /// Parses a value received from the Android MethodChannel.
  ///
  /// The platform boundary is dynamic, so it is intentionally accepted as
  /// [Object?] here rather than making the UI cast it to a Map first.
  static ImportEvent parseMethodCall(String method, Object? raw) {
    if (raw is! Map) {
      throw const FormatException('import event must be a map');
    }
    final arguments = Map<dynamic, dynamic>.from(raw);
    return switch (method) {
      'importProgress' => parseProgress(arguments),
      'importResult' => parseResult(arguments),
      _ => throw FormatException('unknown import method: $method'),
    };
  }

  /// Compatibility reader for the pre-#30 cold-start response. New Android
  /// code sends importProgress/importResult events instead.
  static ImportEvent parseLegacyResult(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('invalid legacy import result');
    }
    final arguments = Map<dynamic, dynamic>.from(raw);
    final rawSuccesses = arguments['successes'] ?? const <Object?>[];
    final rawFailures = arguments['failures'] ?? const <Object?>[];
    if (rawSuccesses is! List || rawFailures is! List) {
      throw const FormatException('invalid legacy import result');
    }
    final successes = rawSuccesses
        .map((item) {
          if (item is! Map || item['path'] is! String) {
            throw const FormatException('invalid legacy success record');
          }
          final path = item['path'] as String;
          final name = item['name'] is String
              ? item['name'] as String
              : path.split(RegExp(r'[/\\]')).last;
          return ImportedFile(
            path: path,
            name: name,
            mimeType: item['mimeType'] is String
                ? item['mimeType'] as String
                : 'application/octet-stream',
            size: item['size'] is int ? item['size'] as int : 0,
          );
        })
        .toList(growable: false);
    final failures = rawFailures
        .map((item) {
          if (item is Map &&
              item['index'] is int &&
              item['errorCode'] is String &&
              item['reason'] is String) {
            return ImportFailure(
              index: item['index'] as int,
              errorCode: item['errorCode'] as String,
              reason: item['reason'] as String,
            );
          }
          return const ImportFailure(
            index: 0,
            errorCode: 'shared_import_failed',
            reason: '共有写真の取り込みに失敗しました',
          );
        })
        .toList(growable: false);
    final total = successes.length + failures.length;
    return ImportEvent(
      requestId: 'legacy-initial-import',
      phase: failures.isEmpty
          ? ImportPhase.completed
          : successes.isEmpty
          ? ImportPhase.failed
          : ImportPhase.partialFailure,
      processed: total,
      total: total,
      succeeded: successes.length,
      failed: failures.length,
      isTerminal: true,
      successes: successes,
      failures: failures,
    );
  }

  static ImportEvent parseProgress(Map<dynamic, dynamic> raw) {
    final event = _parseBase(raw);
    if (event.isTerminal) {
      throw const FormatException('progress event must not be terminal');
    }
    if (event.phase == ImportPhase.idle ||
        event.phase == ImportPhase.completed ||
        event.phase == ImportPhase.partialFailure ||
        event.phase == ImportPhase.failed ||
        event.phase == ImportPhase.cancelled) {
      throw const FormatException('invalid progress phase');
    }
    return event;
  }

  static ImportEvent parseResult(Map<dynamic, dynamic> raw) {
    final event = _parseBase(raw);
    if (!event.isTerminal) {
      throw const FormatException('result event must be terminal');
    }
    if (event.phase != ImportPhase.completed &&
        event.phase != ImportPhase.partialFailure &&
        event.phase != ImportPhase.failed &&
        event.phase != ImportPhase.cancelled) {
      throw const FormatException('invalid result phase');
    }
    final successes = _parseSuccesses(raw['successes']);
    final failures = _parseFailures(raw['failures']);
    if (event.processed != event.total ||
        event.succeeded + event.failed != event.total ||
        event.succeeded != successes.length ||
        event.failed != failures.length) {
      throw const FormatException('result counters do not match records');
    }
    if (event.phase == ImportPhase.completed && failures.isNotEmpty) {
      throw const FormatException('completed result contains failures');
    }
    if (event.phase == ImportPhase.partialFailure &&
        (successes.isEmpty || failures.isEmpty)) {
      throw const FormatException('partial result must contain both outcomes');
    }
    if (event.phase == ImportPhase.failed && successes.isNotEmpty) {
      throw const FormatException('failed result contains successes');
    }
    return ImportEvent(
      requestId: event.requestId,
      phase: event.phase,
      processed: event.processed,
      total: event.total,
      succeeded: event.succeeded,
      failed: event.failed,
      isTerminal: event.isTerminal,
      successes: successes,
      failures: failures,
    );
  }

  static ImportEvent _parseBase(Map<dynamic, dynamic> raw) {
    final requestId = raw['requestId'];
    final phaseRaw = raw['phase'];
    final processed = raw['processed'];
    final total = raw['total'];
    final succeeded = raw['succeeded'];
    final failed = raw['failed'];
    final terminal = raw['terminal'];
    if (requestId is! String ||
        requestId.isEmpty ||
        phaseRaw is! String ||
        processed is! int ||
        total is! int ||
        succeeded is! int ||
        failed is! int ||
        terminal is! bool) {
      throw const FormatException('invalid import event fields');
    }
    final phase = _phaseFromString(phaseRaw);
    if (processed < 0 ||
        total < 0 ||
        succeeded < 0 ||
        failed < 0 ||
        processed > total ||
        succeeded + failed > processed) {
      throw const FormatException('invalid import event counters');
    }
    return ImportEvent(
      requestId: requestId,
      phase: phase,
      processed: processed,
      total: total,
      succeeded: succeeded,
      failed: failed,
      isTerminal: terminal,
    );
  }

  static ImportPhase _phaseFromString(String value) {
    for (final phase in ImportPhase.values) {
      if (phase.name == value) return phase;
    }
    throw FormatException('unknown import phase: $value');
  }

  static List<ImportedFile> _parseSuccesses(Object? raw) {
    if (raw is! List) throw const FormatException('successes is not a list');
    return raw
        .map((item) {
          if (item is! Map) {
            throw const FormatException('invalid success record');
          }
          final path = item['path'];
          final name = item['name'];
          final mimeType = item['mimeType'];
          final size = item['size'];
          if (path is! String ||
              path.isEmpty ||
              name is! String ||
              mimeType is! String ||
              mimeType.isEmpty ||
              size is! int ||
              size < 0) {
            throw const FormatException('invalid success record fields');
          }
          return ImportedFile(
            path: path,
            name: name,
            mimeType: mimeType,
            size: size,
          );
        })
        .toList(growable: false);
  }

  static List<ImportFailure> _parseFailures(Object? raw) {
    if (raw is! List) throw const FormatException('failures is not a list');
    return raw
        .map((item) {
          if (item is! Map) {
            throw const FormatException('invalid failure record');
          }
          final index = item['index'];
          final errorCode = item['errorCode'];
          final reason = item['reason'];
          if (index is! int ||
              index < 0 ||
              errorCode is! String ||
              errorCode.isEmpty ||
              reason is! String ||
              reason.isEmpty) {
            throw const FormatException('invalid failure record fields');
          }
          return ImportFailure(
            index: index,
            errorCode: errorCode,
            reason: reason,
          );
        })
        .toList(growable: false);
  }
}

class ImportRequestGate {
  String? _activeRequestId;

  bool get isActive => _activeRequestId != null;

  bool start(String requestId) {
    if (requestId.isEmpty || requestId == _activeRequestId) return false;
    _activeRequestId = requestId;
    return true;
  }

  bool accepts(String requestId) => requestId == _activeRequestId;

  void finish(String requestId) {
    if (accepts(requestId)) _activeRequestId = null;
  }
}

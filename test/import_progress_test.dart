import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/import_progress.dart';

void main() {
  group('ImportEventParser', () {
    test('parses a valid progress event', () {
      final event = ImportEventParser.parseProgress(<String, Object?>{
        'requestId': 'request-a',
        'phase': 'copying',
        'processed': 1,
        'total': 3,
        'succeeded': 1,
        'failed': 0,
        'terminal': false,
      });

      expect(event.requestId, 'request-a');
      expect(event.phase, ImportPhase.copying);
      expect(event.processed, 1);
      expect(event.total, 3);
      expect(event.isTerminal, isFalse);
    });

    test('rejects missing and invalid fields', () {
      expect(
        () => ImportEventParser.parseProgress(<String, Object?>{
          'requestId': 'request-a',
          'phase': 'copying',
          'processed': -1,
          'total': 3,
          'succeeded': 0,
          'failed': 0,
          'terminal': false,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ImportEventParser.parseProgress(<String, Object?>{
          'requestId': 'request-a',
          'phase': 'unknown',
          'processed': 0,
          'total': 3,
          'succeeded': 0,
          'failed': 0,
          'terminal': false,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects processed greater than total and unknown result shape', () {
      expect(
        () => ImportEventParser.parseProgress(<String, Object?>{
          'requestId': 'request-a',
          'phase': 'copying',
          'processed': 4,
          'total': 3,
          'succeeded': 3,
          'failed': 0,
          'terminal': false,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ImportEventParser.parseResult(<String, Object?>{
          'requestId': 'request-a',
          'phase': 'completed',
          'processed': 1,
          'total': 1,
          'succeeded': 1,
          'failed': 0,
          'terminal': false,
          'successes': const <Object?>[],
          'failures': const <Object?>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses partial result with typed file records', () {
      final result = ImportEventParser.parseResult(<String, Object?>{
        'requestId': 'request-a',
        'phase': 'partialFailure',
        'processed': 2,
        'total': 2,
        'succeeded': 1,
        'failed': 1,
        'terminal': true,
        'successes': <Object?>[
          <String, Object?>{
            'path': '/cache/photo.jpg',
            'name': 'photo.jpg',
            'mimeType': 'image/jpeg',
            'size': 12,
          },
        ],
        'failures': <Object?>[
          <String, Object?>{
            'index': 1,
            'errorCode': 'copy_failed',
            'reason': 'I/O error',
          },
        ],
      });

      expect(result.phase, ImportPhase.partialFailure);
      expect(result.successes.single.path, '/cache/photo.jpg');
      expect(result.failures.single.errorCode, 'copy_failed');
    });
  });

  group('ImportRequestGate', () {
    test('ignores stale progress and terminal events', () {
      final gate = ImportRequestGate();
      gate.start('request-a');
      gate.start('request-b');

      expect(gate.accepts('request-a'), isFalse);
      expect(gate.accepts('request-b'), isTrue);
      gate.finish('request-a');
      expect(gate.accepts('request-b'), isTrue);
      gate.finish('request-b');
      expect(gate.accepts('request-b'), isFalse);
    });

    test('does not start the same request twice', () {
      final gate = ImportRequestGate();

      expect(gate.start('request-a'), isTrue);
      expect(gate.start('request-a'), isFalse);
    });
  });
}

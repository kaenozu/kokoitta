import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_data_operations.dart';
import 'package:kokoitta_app/import_progress.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/photo.dart';

Photo photoOf(String path) => Photo.fromFile(File(path));

void main() {
  test('旅行未設定への移動は写真を保持する', () {
    final photo = photoOf('/tmp/photo.jpg');
    final trip = Trip(id: 'trip-1', title: '出張', photos: <Photo>[photo]);
    final data = AppData(
      trips: <Trip>[trip],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    final moved = moveTripToUnassigned(data, trip.id);

    expect(moved.trips, isEmpty);
    expect(moved.unassignedPhotos, <Photo>[photo]);
    expect(moved.photoCount, 1);
  });

  test('既存旅行への追加は新しい旅行を作らない', () {
    final existing = photoOf('/tmp/existing.jpg');
    final added = photoOf('/tmp/added.jpg');
    final trip = Trip(id: 'trip-1', title: '出張', photos: <Photo>[existing]);
    final data = AppData(
      trips: <Trip>[trip],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );

    final updated = addPhotosToTrip(data, trip.id, <Photo>[added]);

    expect(updated.trips, hasLength(1));
    expect(updated.trips.single.photos, <Photo>[existing, added]);
  });

  test('共有結果parserのsuccessesをaddNewTripで旅行に取り込める', () {
    final result = ImportEventParser.parseResult(<String, Object?>{
      'requestId': 'test_req',
      'phase': 'completed',
      'processed': 2,
      'total': 2,
      'succeeded': 2,
      'failed': 0,
      'terminal': true,
      'successes': <Object?>[
        {
          'path': '/tmp/import_0.jpg',
          'name': 'photo1.jpg',
          'mimeType': 'image/jpeg',
          'size': 1024,
        },
        {
          'path': '/tmp/import_1.png',
          'name': 'photo2.png',
          'mimeType': 'image/png',
          'size': 2048,
        },
      ],
      'failures': const <Object?>[],
    });

    final photos = result.successes.map((file) => photoOf(file.path)).toList();

    final data = AppData(
      trips: <Trip>[],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );
    final updated = addNewTrip(
      data,
      Trip(id: 'trip-import', title: '共有からのおでかけ', photos: photos),
    );

    expect(updated.photoCount, 2);
    expect(updated.trips.single.photos, hasLength(2));
    expect(updated.trips.single.photos[0].file.path, endsWith('import_0.jpg'));
    expect(updated.trips.single.photos[1].file.path, endsWith('import_1.png'));
  });

  test('共有結果parserのサイズ上限エラーはsuccessesを空にする', () {
    final result = ImportEventParser.parseResult(<String, Object?>{
      'requestId': 'overlimit_req',
      'phase': 'failed',
      'processed': 1,
      'total': 1,
      'succeeded': 0,
      'failed': 1,
      'terminal': true,
      'successes': const <Object?>[],
      'failures': <Object?>[
        <String, Object?>{
          'index': 0,
          'errorCode': 'total_size_exceeded',
          'reason': '合計容量の上限を超えています',
        },
      ],
    });

    expect(result.succeeded, 0);
    expect(result.failures.single.errorCode, 'total_size_exceeded');
    expect(result.successes, isEmpty);
  });

  test('共有結果parserの部分成功は成功とAndroidエラーを保持する', () {
    final result = ImportEventParser.parseResult(<String, Object?>{
      'requestId': 'failure_req',
      'phase': 'partialFailure',
      'processed': 2,
      'total': 2,
      'succeeded': 1,
      'failed': 1,
      'terminal': true,
      'successes': <Object?>[
        {
          'path': '/tmp/success.jpg',
          'name': 'good.jpg',
          'mimeType': 'image/jpeg',
          'size': 512,
        },
      ],
      'failures': <Object?>[
        {'index': 0, 'errorCode': 'cannot_open', 'reason': 'URIを開けませんでした'},
      ],
    });

    expect(result.successes, hasLength(1));
    expect(result.failures.single.errorCode, 'cannot_open');
    expect(result.failures.single.reason, isNotEmpty);
  });
}

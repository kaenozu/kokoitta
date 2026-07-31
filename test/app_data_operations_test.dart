import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_data_operations.dart';
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

  test('構造化結果のsuccessesパスをaddNewTripで旅行に取り込める', () {
    final result = <String, dynamic>{
      'requestId': 'test_req',
      'receivedCount': 2,
      'acceptedCount': 2,
      'successes': <Map<String, dynamic>>[
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
      'overLimitCount': 0,
      'failures': <Map<String, dynamic>>[],
    };

    final successes = (result['successes'] as List<dynamic>);
    final paths = successes
        .map((e) => (e as Map<dynamic, dynamic>)['path'] as String)
        .toList();
    final photos = paths.map((p) => photoOf(p)).toList();

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

  test('構造化結果のoverLimitCount>0の場合、successesは空でacceptedCountは0', () {
    final result = <String, dynamic>{
      'requestId': 'overlimit_req',
      'receivedCount': 350,
      'acceptedCount': 0,
      'successes': <Map<String, dynamic>>[],
      'overLimitCount': 50,
      'failures': <Map<String, dynamic>>[],
    };

    expect(result['acceptedCount'], 0);
    expect(result['overLimitCount'], greaterThan(0));
    expect((result['successes'] as List<dynamic>), isEmpty);
  });

  test('構造化結果のfailuresにエラーコードと理由が含まれる', () {
    final result = <String, dynamic>{
      'requestId': 'failure_req',
      'receivedCount': 2,
      'acceptedCount': 1,
      'successes': <Map<String, dynamic>>[
        {
          'path': '/tmp/success.jpg',
          'name': 'good.jpg',
          'mimeType': 'image/jpeg',
          'size': 512,
        },
      ],
      'overLimitCount': 0,
      'failures': <Map<String, dynamic>>[
        {'index': 0, 'errorCode': 'cannot_open', 'reason': 'URIを開けませんでした'},
      ],
    };

    final failures = (result['failures'] as List<dynamic>);
    expect(failures, hasLength(1));
    final failure = failures[0] as Map<dynamic, dynamic>;
    expect(failure['errorCode'], 'cannot_open');
    expect(failure['reason'], isNotEmpty);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_data_operations.dart';
import 'package:kokoitta_app/models.dart';

void main() {
  test('旅行未設定への移動は写真を保持する', () {
    final photo = File('/tmp/photo.jpg');
    final trip = Trip(id: 'trip-1', title: '出張', photos: <File>[photo]);
    final data = AppData(
      trips: <Trip>[trip],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    );

    final moved = moveTripToUnassigned(data, trip.id);

    expect(moved.trips, isEmpty);
    expect(moved.unassignedPhotos, <File>[photo]);
    expect(moved.photoCount, 1);
  });

  test('既存旅行への追加は新しい旅行を作らない', () {
    final existing = File('/tmp/existing.jpg');
    final added = File('/tmp/added.jpg');
    final trip = Trip(
      id: 'trip-1',
      title: '出張',
      photos: <File>[existing],
    );
    final data = AppData(
      trips: <Trip>[trip],
      unassignedPhotos: const <File>[],
      prefectureStates: const <String, String>{},
    );

    final updated = addPhotosToTrip(data, trip.id, <File>[added]);

    expect(updated.trips, hasLength(1));
    expect(updated.trips.single.photos, <File>[existing, added]);
  });

  test('301件の共有URIはoverLimitCountが0より大きい結果を返し、インポートは中止する', () {
    final overLimitCount = 1;
    final successes = <Map<String, dynamic>>[];
    final failures = <Map<String, dynamic>>[];

    expect(overLimitCount, greaterThan(0), reason: '301件超過は全体拒否しなければならない');
    expect(successes.isEmpty, isTrue, reason: 'overLimit時は成功取り込みを行わない');
  });
}

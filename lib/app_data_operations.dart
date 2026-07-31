import 'dart:io';

import 'models.dart';
import 'validators.dart';

AppData addNewTrip(AppData data, Trip trip, {int atIndex = -1}) {
  if (atIndex < 0 || atIndex > data.trips.length) {
    return data.copyWith(trips: <Trip>[...data.trips, trip]);
  }
  final trips = <Trip>[...data.trips];
  trips.insert(atIndex, trip);
  return data.copyWith(trips: trips);
}

AppData addPhotosToTrip(AppData data, String tripId, List<File> photos) {
  var found = false;
  final trips = data.trips.map((trip) {
    if (trip.id != tripId) return trip;
    found = true;
    return trip.copyWith(photos: <File>[...trip.photos, ...photos]);
  }).toList(growable: false);
  if (!found) throw StateError('追加先の旅行が見つかりません');
  return data.copyWith(trips: trips);
}

AppData moveTripToUnassigned(AppData data, String tripId) {
  final trip = data.trips.where((candidate) => candidate.id == tripId).firstOrNull;
  if (trip == null) throw StateError('移動する旅行が見つかりません');
  return data.copyWith(
    trips: data.trips.where((candidate) => candidate.id != tripId).toList(),
    unassignedPhotos: <File>[...data.unassignedPhotos, ...trip.photos],
  );
}

AppData removeTrip(AppData data, String tripId) {
  if (!data.trips.any((trip) => trip.id == tripId)) {
    throw StateError('削除する旅行が見つかりません');
  }
  return data.copyWith(
    trips: data.trips.where((trip) => trip.id != tripId).toList(),
  );
}

AppData createTripFromUnassigned(AppData data, Trip trip) {
  if (data.unassignedPhotos.isEmpty) {
    throw StateError('旅行未設定の写真がありません');
  }
  return data.copyWith(
    trips: <Trip>[...data.trips, trip],
    unassignedPhotos: const <File>[],
  );
}

AppData updatePrefectureState(
  AppData data,
  String prefecture,
  String state,
) {
  if (!validPrefectures.contains(prefecture)) {
    return data;
  }
  return data.copyWith(
    prefectureStates: normalizePrefectureStates(<String, String>{
      ...data.prefectureStates,
      prefecture: state,
    }),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

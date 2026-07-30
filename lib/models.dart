import 'dart:io';

int _entitySequence = 0;

String createEntityId(String prefix) {
  _entitySequence += 1;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_entitySequence';
}

class Trip {
  Trip({
    required this.id,
    required this.title,
    required List<File> photos,
  }) : photos = List<File>.unmodifiable(photos);

  final String id;
  final String title;
  final List<File> photos;

  Trip copyWith({
    String? id,
    String? title,
    List<File>? photos,
  }) {
    return Trip(
      id: id ?? this.id,
      title: title ?? this.title,
      photos: photos ?? this.photos,
    );
  }
}

class AppData {
  AppData({
    required List<Trip> trips,
    required List<File> unassignedPhotos,
    required Map<String, String> prefectureStates,
  })  : trips = List<Trip>.unmodifiable(trips),
        unassignedPhotos = List<File>.unmodifiable(unassignedPhotos),
        prefectureStates = Map<String, String>.unmodifiable(prefectureStates);

  factory AppData.empty() => AppData(
        trips: const <Trip>[],
        unassignedPhotos: const <File>[],
        prefectureStates: const <String, String>{},
      );

  final List<Trip> trips;
  final List<File> unassignedPhotos;
  final Map<String, String> prefectureStates;

  int get photoCount =>
      unassignedPhotos.length +
      trips.fold<int>(0, (sum, trip) => sum + trip.photos.length);

  Iterable<File> get allPhotos sync* {
    for (final trip in trips) {
      yield* trip.photos;
    }
    yield* unassignedPhotos;
  }

  AppData copyWith({
    List<Trip>? trips,
    List<File>? unassignedPhotos,
    Map<String, String>? prefectureStates,
  }) {
    return AppData(
      trips: trips ?? this.trips,
      unassignedPhotos: unassignedPhotos ?? this.unassignedPhotos,
      prefectureStates: prefectureStates ?? this.prefectureStates,
    );
  }
}

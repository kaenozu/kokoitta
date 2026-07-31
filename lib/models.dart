import 'photo.dart';

int _entitySequence = 0;

String createEntityId(String prefix) {
  _entitySequence += 1;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_entitySequence';
}

class Trip {
  Trip({required this.id, required this.title, required List<Photo> photos})
    : photos = List<Photo>.unmodifiable(photos);

  final String id;
  final String title;
  final List<Photo> photos;

  Trip copyWith({String? id, String? title, List<Photo>? photos}) {
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
    required List<Photo> unassignedPhotos,
    required Map<String, String> prefectureStates,
  }) : trips = List<Trip>.unmodifiable(trips),
       unassignedPhotos = List<Photo>.unmodifiable(unassignedPhotos),
       prefectureStates = Map<String, String>.unmodifiable(prefectureStates);

  factory AppData.empty() => AppData(
    trips: const <Trip>[],
    unassignedPhotos: const <Photo>[],
    prefectureStates: const <String, String>{},
  );

  final List<Trip> trips;
  final List<Photo> unassignedPhotos;
  final Map<String, String> prefectureStates;

  int get photoCount =>
      unassignedPhotos.length +
      trips.fold<int>(0, (sum, trip) => sum + trip.photos.length);

  Iterable<Photo> get allPhotos sync* {
    for (final trip in trips) {
      yield* trip.photos;
    }
    yield* unassignedPhotos;
  }

  AppData copyWith({
    List<Trip>? trips,
    List<Photo>? unassignedPhotos,
    Map<String, String>? prefectureStates,
  }) {
    return AppData(
      trips: trips ?? this.trips,
      unassignedPhotos: unassignedPhotos ?? this.unassignedPhotos,
      prefectureStates: prefectureStates ?? this.prefectureStates,
    );
  }
}

part of 'backup_service.dart';

/// 復元候補の1枚の写真。ID・metadataは新形式（v3）Backupから引き継ぎ、
/// 旧形式（v1/v2）からは復元時に新規生成する。
class PreparedPhoto {
  PreparedPhoto({
    required this.id,
    required this.relativePath,
    this.capturedAt,
    this.location,
    this.originalName,
    this.mimeType,
  });

  final String id;
  final String relativePath;
  final DateTime? capturedAt;
  final String? location;
  final String? originalName;
  final String? mimeType;
}

class PreparedRestore {
  PreparedRestore({
    required this.stagingDirectory,
    required this.permanentRoot,
    required this.trips,
    required this.unassignedPhotos,
    required this.prefectureStates,
  });

  final Directory stagingDirectory;
  final Directory permanentRoot;
  final List<PreparedTrip> trips;
  final List<PreparedPhoto> unassignedPhotos;
  final Map<String, String> prefectureStates;

  int get tripCount => trips.length;
  int get photoCount =>
      unassignedPhotos.length +
      trips.fold<int>(0, (sum, trip) => sum + trip.photos.length);

  Future<CommittedRestore> commit() async {
    await permanentRoot.create(recursive: true);
    final destination = Directory(
      '${permanentRoot.path}/restore-${DateTime.now().microsecondsSinceEpoch}',
    );
    final committedDirectory = await stagingDirectory.rename(destination.path);

    File resolve(String relativePath) =>
        File('${committedDirectory.path}/$relativePath');

    Photo toPhoto(PreparedPhoto prepared) => Photo(
      id: prepared.id,
      file: resolve(prepared.relativePath),
      capturedAt: prepared.capturedAt,
      location: prepared.location,
      originalName: prepared.originalName,
      mimeType: prepared.mimeType,
    );

    final data = AppData(
      trips: trips
          .map(
            (trip) => Trip(
              id: trip.id,
              title: trip.title,
              photos: trip.photos.map(toPhoto).toList(growable: false),
            ),
          )
          .toList(growable: false),
      unassignedPhotos: unassignedPhotos.map(toPhoto).toList(growable: false),
      prefectureStates: prefectureStates,
    );
    return CommittedRestore(data: data, directory: committedDirectory);
  }

  Future<void> discard() async {
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }
  }
}

class PreparedTrip {
  PreparedTrip({
    required this.id,
    required this.title,
    required List<PreparedPhoto> photos,
  }) : photos = List<PreparedPhoto>.unmodifiable(photos);

  final String id;
  final String title;
  final List<PreparedPhoto> photos;
}

class CommittedRestore {
  CommittedRestore({required this.data, required this.directory});

  final AppData data;
  final Directory directory;

  Future<void> rollback() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _ParsedBackup {
  _ParsedBackup({
    required this.trips,
    required this.unassignedPhotos,
    required this.prefectureStates,
  });

  final List<_ParsedTrip> trips;
  final List<_ParsedPhoto> unassignedPhotos;
  final Map<String, String> prefectureStates;

  int get photoCount =>
      unassignedPhotos.length +
      trips.fold<int>(0, (sum, trip) => sum + trip.photos.length);
}

class _ParsedTrip {
  _ParsedTrip({
    required this.id,
    required this.title,
    required List<_ParsedPhoto> photos,
  }) : photos = List<_ParsedPhoto>.unmodifiable(photos);

  final String id;
  final String title;
  final List<_ParsedPhoto> photos;
}

class _ParsedPhoto {
  _ParsedPhoto({
    required this.id,
    required this.archivePath,
    this.capturedAt,
    this.location,
    this.originalName,
    this.mimeType,
  });

  final String id;
  final String archivePath;
  final DateTime? capturedAt;
  final String? location;
  final String? originalName;
  final String? mimeType;
}

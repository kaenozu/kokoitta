part of 'backup_service.dart';

class PreparedRestore {
  PreparedRestore({
    required this.stagingDirectory,
    required this.permanentRoot,
    required this.trips,
    required this.unassignedRelativePhotoPaths,
    required this.prefectureStates,
  });

  final Directory stagingDirectory;
  final Directory permanentRoot;
  final List<PreparedTrip> trips;
  final List<String> unassignedRelativePhotoPaths;
  final Map<String, String> prefectureStates;

  int get tripCount => trips.length;
  int get photoCount =>
      unassignedRelativePhotoPaths.length +
      trips.fold<int>(
        0,
        (sum, trip) => sum + trip.relativePhotoPaths.length,
      );

  Future<CommittedRestore> commit() async {
    await permanentRoot.create(recursive: true);
    final destination = Directory(
      '${permanentRoot.path}/restore-${DateTime.now().microsecondsSinceEpoch}',
    );
    final committedDirectory = await stagingDirectory.rename(destination.path);

    File resolve(String relativePath) =>
        File('${committedDirectory.path}/$relativePath');

    final data = AppData(
      trips: trips
          .map(
            (trip) => Trip(
              id: trip.id,
              title: trip.title,
              photos: trip.relativePhotoPaths.map(resolve).toList(),
            ),
          )
          .toList(),
      unassignedPhotos:
          unassignedRelativePhotoPaths.map(resolve).toList(growable: false),
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
    required this.relativePhotoPaths,
  });

  final String id;
  final String title;
  final List<String> relativePhotoPaths;
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
    required this.unassignedPhotoPaths,
    required this.prefectureStates,
  });

  final List<_ParsedTrip> trips;
  final List<String> unassignedPhotoPaths;
  final Map<String, String> prefectureStates;

  int get photoCount =>
      unassignedPhotoPaths.length +
      trips.fold<int>(0, (sum, trip) => sum + trip.photoPaths.length);
}

class _ParsedTrip {
  _ParsedTrip({
    required this.id,
    required this.title,
    required this.photoPaths,
  });

  final String id;
  final String title;
  final List<String> photoPaths;
}

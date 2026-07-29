import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class BackupService {
  Future<File> createBackup(List<BackupTrip> trips) async {
    final archive = Archive();
    final records = <Map<String, Object>>[];
    var totalBytes = 0;
    for (var tripIndex = 0; tripIndex < trips.length; tripIndex++) {
      final trip = trips[tripIndex];
      final paths = <String>[];
      for (var photoIndex = 0; photoIndex < trip.photos.length; photoIndex++) {
        final file = trip.photos[photoIndex];
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        final archivePath = 'photos/$tripIndex-$photoIndex-${file.uri.pathSegments.last}';
        archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
        paths.add(archivePath);
        totalBytes += bytes.length;
      }
      records.add({'title': trip.title, 'photos': paths});
    }
    final manifest = {
      'appId': 'com.kaenozu.kokoitta_app',
      'backupFormatVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tripCount': records.length,
      'photoCount': records.fold<int>(0, (sum, trip) => sum + (trip['photos'] as List).length),
      'totalUncompressedBytes': totalBytes,
      'checksumsAlgorithm': 'sha-256',
    };
    archive.addFile(ArchiveFile('manifest.json', utf8.encode(jsonEncode(manifest)).length, utf8.encode(jsonEncode(manifest))));
    archive.addFile(ArchiveFile('trips.json', utf8.encode(jsonEncode(records)).length, utf8.encode(jsonEncode(records))));
    final encoded = ZipEncoder().encode(archive);
    final directory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory('${directory.path}/backups')..createSync(recursive: true);
    final file = File('${backupDirectory.path}/kokoitta-backup-${DateTime.now().millisecondsSinceEpoch}.zip');
    return file.writeAsBytes(encoded, flush: true);
  }

  Future<List<BackupTrip>> restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'], withData: true);
    if (result == null || result.files.single.bytes == null) return <BackupTrip>[];
    final archive = ZipDecoder().decodeBytes(result.files.single.bytes!);
    final manifestFile = archive.findFile('manifest.json');
    final tripsFile = archive.findFile('trips.json');
    if (manifestFile == null || tripsFile == null) throw const FormatException('manifest.json または trips.json がありません');
    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
    if (manifest['appId'] != 'com.kaenozu.kokoitta_app' || manifest['backupFormatVersion'] != 1) throw const FormatException('対応していないバックアップ形式です');
    final directory = await getApplicationDocumentsDirectory();
    final photoDirectory = Directory('${directory.path}/photos')..createSync(recursive: true);
    final records = (jsonDecode(utf8.decode(tripsFile.content as List<int>)) as List).cast<Map<String, dynamic>>();
    final restored = <BackupTrip>[];
    for (final record in records) {
      final photos = <File>[];
      for (final path in (record['photos'] as List).cast<String>()) {
        final entry = archive.findFile(path);
        if (entry == null) throw FormatException('写真が見つかりません: $path');
        final name = '${DateTime.now().microsecondsSinceEpoch}_${path.split('/').last}';
        photos.add(await File('${photoDirectory.path}/$name').writeAsBytes(entry.content as List<int>, flush: true));
      }
      restored.add(BackupTrip(record['title'] as String, photos));
    }
    return restored;
  }

  Future<void> shareBackup(File file) => SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'ここいったのバックアップ'));
}

class BackupTrip {
  BackupTrip(this.title, this.photos);
  final String title;
  final List<File> photos;
}


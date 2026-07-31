import 'dart:io';

/// Metadata-bearing photo contract used by future persistence/UI migration.
/// Existing File-based storage remains lossless through [Photo.fromFile].
class Photo {
  const Photo({
    required this.id,
    required this.file,
    this.capturedAt,
    this.location,
    this.originalName,
    this.mimeType,
  });

  factory Photo.fromFile(File file, {String? id}) => Photo(
    id: id ?? _stableId(file),
    file: file,
    originalName: file.uri.pathSegments.isEmpty
        ? null
        : file.uri.pathSegments.last,
  );

  final String id;
  final File file;
  final DateTime? capturedAt;
  final String? location;
  final String? originalName;
  final String? mimeType;

  Photo copyWith({
    String? id,
    File? file,
    DateTime? capturedAt,
    String? location,
    String? originalName,
    String? mimeType,
  }) => Photo(
    id: id ?? this.id,
    file: file ?? this.file,
    capturedAt: capturedAt ?? this.capturedAt,
    location: location ?? this.location,
    originalName: originalName ?? this.originalName,
    mimeType: mimeType ?? this.mimeType,
  );
}

String _stableId(File file) => file.absolute.path;

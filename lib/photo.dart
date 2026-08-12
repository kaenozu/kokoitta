import 'dart:io';

import 'package:flutter/foundation.dart';

int _photoSequence = 0;

/// 新しい写真へ一度だけ付与する、ファイルパスに依存しない永続IDを生成する。
///
/// IDは保存・再読込・Backup/Restoreを越えて維持される。写真の移動や
/// 復元後のパス変更では変化しない（同一写真判定とは別概念）。
String createPhotoId() {
  _photoSequence += 1;
  return 'photo-${DateTime.now().microsecondsSinceEpoch}-$_photoSequence';
}

/// Metadata-bearing photo entity with a path-independent persistent [id].
///
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

  /// [id]を省略した場合は新規IDを生成する。import時の1回だけ呼び、
  /// 以後は保存済みのIDを引き回すこと。
  factory Photo.fromFile(File file, {String? id}) => Photo(
    id: id ?? createPhotoId(),
    file: file,
    originalName: _originalNameOf(file),
  );

  /// nullable metadataを「未指定」と「nullで明示的に消去」を区別するための
  /// sentinel。copyWith()でnullを渡すと既存値が消去される。
  static const Object _unset = Object();

  final String id;
  final File file;
  final DateTime? capturedAt;
  final String? location;
  final String? originalName;
  final String? mimeType;

  Photo copyWith({
    String? id,
    File? file,
    Object? capturedAt = _unset,
    Object? location = _unset,
    Object? originalName = _unset,
    Object? mimeType = _unset,
  }) => Photo(
    id: id ?? this.id,
    file: file ?? this.file,
    capturedAt: identical(capturedAt, _unset)
        ? this.capturedAt
        : capturedAt as DateTime?,
    location: identical(location, _unset) ? this.location : location as String?,
    originalName: identical(originalName, _unset)
        ? this.originalName
        : originalName as String?,
    mimeType: identical(mimeType, _unset) ? this.mimeType : mimeType as String?,
  );
}

String? _originalNameOf(File file) {
  final segments = file.uri.pathSegments;
  return segments.isEmpty ? null : segments.last;
}

/// 保存データが参照しているが、ファイルが存在しない写真の情報。
///
/// 読み込み時は従来どおり読み飛ばす（実在写真を奪わない）ため、欠損写真は
/// [Photo] として AppData に含まれない。この欠損情報を別経路で保持し、
/// UI がユーザーへ通知・復旧手段を提示するために使う。
@immutable
class MissingPhoto {
  const MissingPhoto({
    required this.id,
    required this.path,
    required this.tripId,
    required this.tripTitle,
  });

  /// 保存データ内の写真ID。
  ///
  /// v3 レコードは保存済み ID。v2 形式（パス文字列のリスト）には ID が無いため、
  /// [TripStore.legacyPhotoId] と同じ規則（正規化パスのSHA-256先頭32桁）で
  /// 生成したIDを使う。旅行未設定・救済写真は空文字。
  final String id;

  /// 保存データが参照していた（存在しない）ファイルパス。
  final String path;

  /// 所属旅行のID。旅行未設定・無効タイトル旅行からの救済写真は空文字。
  final String tripId;

  /// 所属旅行のタイトル。旅行未設定・救済写真は空文字。
  final String tripTitle;
}

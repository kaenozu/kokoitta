import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/photo.dart';

void main() {
  test('createPhotoIdはパスに依存せず毎回異なるIDを生成する', () {
    final first = createPhotoId();
    final second = createPhotoId();
    expect(first, isNot(second));
    expect(first, startsWith('photo-'));
  });

  test('fromFileはパスを保持し新規IDを付与する', () {
    final file = File('/photos/example.jpg');
    final photo = Photo.fromFile(file);
    expect(photo.file.path, file.path);
    expect(photo.id, startsWith('photo-'));
    expect(photo.originalName, 'example.jpg');
  });

  test('fromFileは明示IDを尊重する', () {
    final file = File('/photos/example.jpg');
    final photo = Photo.fromFile(file, id: 'photo-keep-1');
    expect(photo.id, 'photo-keep-1');
  });

  test('idはファイルパスに依存しない', () {
    final file = File('/photos/example.jpg');
    final photo = Photo.fromFile(file);
    expect(photo.id, isNot(file.absolute.path));
  });

  test('metadata編集はsource fileを保持する', () {
    final file = File('/photos/example.jpg');
    final photo = Photo.fromFile(file).copyWith(location: '東京都');
    expect(photo.location, '東京都');
    expect(photo.file.path, file.path);
    expect(photo.id, isNotNull);
  });

  test('copyWithはmetadataをnullで明示的に消去できる', () {
    final photo = Photo.fromFile(File('/photos/example.jpg')).copyWith(
      capturedAt: DateTime(2026, 7, 1),
      location: '東京都',
      originalName: 'dsc.jpg',
      mimeType: 'image/jpeg',
    );
    final cleared = photo.copyWith(
      capturedAt: null,
      location: null,
      originalName: null,
      mimeType: null,
    );
    expect(cleared.capturedAt, isNull);
    expect(cleared.location, isNull);
    expect(cleared.originalName, isNull);
    expect(cleared.mimeType, isNull);
    expect(cleared.file.path, photo.file.path);
    expect(cleared.id, photo.id);
  });

  test('copyWithは省略したmetadataを保持する', () {
    final photo = Photo.fromFile(
      File('/photos/example.jpg'),
    ).copyWith(location: '東京都', originalName: 'dsc.jpg');
    final edited = photo.copyWith(location: '大阪府');
    expect(edited.location, '大阪府');
    expect(edited.originalName, 'dsc.jpg');
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/photo.dart';

void main() {
  test('File photos convert without losing path', () {
    final file = File('/photos/example.jpg');
    final photo = Photo.fromFile(file);
    expect(photo.file.path, file.path);
    expect(photo.id, file.absolute.path);
    expect(photo.originalName, 'example.jpg');
  });

  test('metadata edits preserve source file', () {
    final file = File('/photos/example.jpg');
    final photo = Photo.fromFile(file).copyWith(location: '東京都');
    expect(photo.location, '東京都');
    expect(photo.file.path, file.path);
  });
}

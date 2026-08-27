import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/photo_gps.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List jpegWithGps(double lat, double lon) {
  final tiff = Uint8List(128);
  final data = ByteData.sublistView(tiff);
  void u16(int p, int value) => data.setUint16(p, value);
  void u32(int p, int value) => data.setUint32(p, value);
  u16(0, 0x4d4d);
  u16(2, 42);
  u32(4, 8);
  u16(8, 1);
  u16(10, 0x8825);
  u16(12, 4);
  u32(14, 1);
  u32(18, 26);
  u16(26, 4);
  final tags = <int, int>{1: 1, 2: 2, 3: 3, 4: 4};
  var entry = 28;
  for (final tag in tags.keys) {
    u16(entry, tag);
    if (tag == 1 || tag == 3) {
      u16(entry + 2, 2);
      u32(entry + 4, 2);
      tiff[entry + 8] = tag == 1 ? 0x4e : 0x45;
    } else {
      u16(entry + 2, 5);
      u32(entry + 4, 3);
      u32(entry + 8, tag == 2 ? 80 : 104);
    }
    entry += 12;
  }
  u32(76, 0);
  void rational(int p, int value) {
    u32(p, value);
    u32(p + 4, 1);
  }

  final latDegrees = lat.floor();
  final lonDegrees = lon.floor();
  final latMinutes = ((lat - latDegrees) * 60).floor();
  final lonMinutes = ((lon - lonDegrees) * 60).floor();
  rational(80, latDegrees);
  rational(88, latMinutes);
  rational(96, 0);
  rational(104, lonDegrees);
  rational(112, lonMinutes);
  rational(120, 0);
  final exif = <int>[...'Exif\x00\x00'.codeUnits, ...tiff];
  final segmentLength = exif.length + 2;
  return Uint8List.fromList(<int>[
    0xff,
    0xd8,
    0xff,
    0xe1,
    segmentLength >> 8,
    segmentLength & 0xff,
    ...exif,
    0xff,
    0xd9,
  ]);
}

Uint8List jpegWithGpsAfterExifWithoutGps() {
  final noGpsExif = <int>[
    ...'Exif\x00\x00'.codeUnits,
    0x4d,
    0x4d,
    0x00,
    0x2a,
    0x00,
    0x00,
    0x00,
    0x08,
    0x00,
    0x00,
  ];
  final noGpsSegment = <int>[
    0xff,
    0xe1,
    (noGpsExif.length + 2) >> 8,
    (noGpsExif.length + 2) & 0xff,
    ...noGpsExif,
  ];
  final gps = jpegWithGps(35.68, 139.76);
  return Uint8List.fromList(<int>[
    0xff,
    0xd8,
    ...noGpsSegment,
    ...gps.sublist(2),
  ]);
}

void main() {
  test('GPSのない先行EXIFセグメントがあっても後続EXIFからGPSを読む', () {
    final gps = readJpegGpsBytes(jpegWithGpsAfterExifWithoutGps());
    expect(gps, isNotNull);
    expect(prefectureFromGps(gps!.latitude, gps.longitude), '東京');
  });

  test('JPEG EXIF GPSを読み取り、代表座標を都道府県へ変換する', () {
    final gps = readJpegGpsBytes(jpegWithGps(35.68, 139.76));
    expect(gps?.latitude, closeTo(35.6666, 0.02));
    expect(gps?.longitude, closeTo(139.75, 0.02));
    expect(prefectureFromGps(gps!.latitude, gps.longitude), '東京');
    expect(prefectureFromGps(34.69, 135.52), '大阪');
    expect(prefectureFromGps(43.06, 141.35), '北海道');
  });

  test('GPSなし・不正JPEG・座標範囲外は安全に無視する', () {
    expect(
      readJpegGpsBytes(Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9])),
      isNull,
    );
    expect(readJpegGpsBytes(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    expect(prefectureFromGps(91, 139), isNull);
    expect(prefectureFromGps(35, 181), isNull);
    expect(prefectureFromGps(0, 0), isNull);
  });

  test('GPSで反映した地図状態は保存と再読み込み後も保持される', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = await Directory.systemTemp.createTemp(
      'kokoitta-gps-persistence-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File(
      '${directory.path}/tokyo.jpg',
    ).writeAsBytes(jpegWithGps(35.68, 139.76));
    final photo = Photo.fromFile(file);
    final imported = await applyGpsPrefectureStates(
      AppData(
        trips: <Trip>[
          Trip(id: 'trip-1', title: '東京旅行', photos: <Photo>[photo]),
        ],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
      <Photo>[photo],
    );

    final firstStore = TripStore();
    await firstStore.save(imported);
    final restartedStore = TripStore();
    final restored = await restartedStore.load();

    expect(restored.trips.single.photos.single.id, photo.id);
    expect(restored.prefectureStates['東京'], 'visited');
  });

  test('既存の手動状態は上書きせず、GPS写真だけ未設定都道府県を追加する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kokoitta-gps-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File(
      '${directory.path}/tokyo.jpg',
    ).writeAsBytes(jpegWithGps(35.68, 139.76));
    final data = AppData(
      trips: const <Trip>[],
      unassignedPhotos: <Photo>[Photo.fromFile(file)],
      prefectureStates: const <String, String>{
        '東京': 'transit',
        '大阪': 'unvisited',
      },
    );
    final updated = await applyGpsPrefectureStates(data, data.unassignedPhotos);
    expect(updated.prefectureStates['東京'], 'transit');
    expect(updated.prefectureStates['大阪'], 'unvisited');
    expect(updated.prefectureStates, hasLength(2));

    final automatic = await applyGpsPrefectureStates(
      AppData(
        trips: const <Trip>[],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
      <Photo>[Photo.fromFile(file)],
    );
    expect(automatic.prefectureStates, <String, String>{'東京': 'visited'});
  });
}

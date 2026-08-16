import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'photo.dart';
import 'validators.dart';

/// Reads the GPS IFD from a JPEG EXIF APP1 segment.
///
/// This deliberately supports only the standard GPS fields needed here. Any
/// malformed, truncated, non-JPEG, or out-of-range input returns null.
Future<({double latitude, double longitude})?> readJpegGps(File file) async {
  try {
    final bytes = await file.readAsBytes();
    return readJpegGpsBytes(bytes);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

({double latitude, double longitude})? readJpegGpsBytes(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xff) return null;
    final marker = bytes[offset + 1];
    offset += 2;
    if (marker == 0xda || marker == 0xd9) break;
    if (offset + 2 > bytes.length) return null;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    if (marker == 0xe1 &&
        length >= 8 &&
        _ascii(bytes, offset + 2, 6) == 'Exif\x00\x00') {
      return _readTiffGps(bytes, offset + 8, offset + length);
    }
    offset += length;
  }
  return null;
}

String? prefectureFromGps(double latitude, double longitude) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    return null;
  }
  // Do not classify arbitrary world coordinates as a Japanese prefecture.
  if (latitude < 24 || latitude > 46 || longitude < 122 || longitude > 146) {
    return null;
  }
  // Stable representative points (JIS prefecture order). Nearest-point
  // partition is intentionally data-only and reproducible offline; it avoids
  // pretending that a coarse app asset is an authoritative legal boundary.
  var bestDistance = double.infinity;
  String? best;
  for (final point in _prefecturePoints) {
    final dLat = latitude - point.latitude;
    final dLon = (longitude - point.longitude) * 0.82;
    final distance = dLat * dLat + dLon * dLon;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = point.name;
    }
  }
  return best;
}

Future<AppData> applyGpsPrefectureStates(
  AppData data,
  Iterable<Photo> photos,
) async {
  final added = <String, String>{};
  for (final photo in photos) {
    final gps = await readJpegGps(photo.file);
    if (gps == null) continue;
    final prefecture = prefectureFromGps(gps.latitude, gps.longitude);
    // Presence means the user has made an explicit choice, including an
    // explicit unvisited state. Never overwrite manual state.
    if (prefecture != null &&
        !data.prefectureStates.containsKey(prefecture) &&
        !added.containsKey(prefecture)) {
      added[prefecture] = 'visited';
    }
  }
  if (added.isEmpty) return data;
  return data.copyWith(
    prefectureStates: normalizePrefectureStates(<String, String>{
      ...data.prefectureStates,
      ...added,
    }),
  );
}

String _ascii(Uint8List bytes, int start, int length) {
  if (start < 0 || start + length > bytes.length) return '';
  return String.fromCharCodes(bytes.sublist(start, start + length));
}

({double latitude, double longitude})? _readTiffGps(
  Uint8List bytes,
  int start,
  int end,
) {
  if (start + 8 > end) return null;
  final little = _ascii(bytes, start, 2) == 'II';
  if (!little && _ascii(bytes, start, 2) != 'MM') return null;
  int u16(int p) => _number(bytes, p, 2, little);
  int u32(int p) => _number(bytes, p, 4, little);
  final magic = u16(start + 2);
  final ifdOffset = u32(start + 4);
  if (magic != 42 || ifdOffset > end - start - 2) return null;
  final ifd = start + ifdOffset;
  if (ifd + 2 > end) return null;
  final count = u16(ifd);
  final gpsTag = 0x8825;
  int? gpsOffset;
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > end) return null;
    if (u16(entry) == gpsTag && u16(entry + 2) == 4) {
      final value = u32(entry + 8);
      if (value > end - start - 1) return null;
      gpsOffset = start + value;
      break;
    }
  }
  if (gpsOffset == null || gpsOffset + 2 > end) return null;
  final gpsCount = u16(gpsOffset);
  String? latRef;
  String? lonRef;
  List<double>? lat;
  List<double>? lon;
  for (var i = 0; i < gpsCount; i++) {
    final entry = gpsOffset + 2 + i * 12;
    if (entry + 12 > end) return null;
    final tag = u16(entry);
    final type = u16(entry + 2);
    final countValue = u32(entry + 4);
    if (tag == 1 || tag == 3) {
      if (type != 2 || countValue < 1 || entry + 8 >= end) continue;
      final ref = String.fromCharCode(bytes[entry + 8]);
      if (tag == 1) {
        latRef = ref;
      } else {
        lonRef = ref;
      }
    } else if (tag == 2 || tag == 4) {
      if (type != 5 || countValue != 3) continue;
      final valueOffset = u32(entry + 8);
      final values = <double>[];
      for (var n = 0; n < 3; n++) {
        final p = start + valueOffset + n * 8;
        if (p + 8 > end) return null;
        final numerator = u32(p);
        final denominator = u32(p + 4);
        if (denominator == 0) return null;
        values.add(numerator / denominator);
      }
      if (tag == 2) {
        lat = values;
      } else {
        lon = values;
      }
    }
  }
  if (latRef == null || lonRef == null || lat == null || lon == null) {
    return null;
  }
  if (latRef != 'N' && latRef != 'S' || lonRef != 'E' && lonRef != 'W') {
    return null;
  }
  final latitude = lat[0] + lat[1] / 60 + lat[2] / 3600;
  final longitude = lon[0] + lon[1] / 60 + lon[2] / 3600;
  final signedLat = latRef == 'S' ? -latitude : latitude;
  final signedLon = lonRef == 'W' ? -longitude : longitude;
  if (!signedLat.isFinite ||
      !signedLon.isFinite ||
      signedLat.abs() > 90 ||
      signedLon.abs() > 180 ||
      lat[0] < 0 ||
      lat[0] > 90 ||
      lon[0] < 0 ||
      lon[0] > 180 ||
      lat[1] < 0 ||
      lat[1] >= 60 ||
      lon[1] < 0 ||
      lon[1] >= 60 ||
      lat[2] < 0 ||
      lon[2] < 0) {
    return null;
  }
  return (latitude: signedLat, longitude: signedLon);
}

int _number(Uint8List bytes, int start, int length, bool little) {
  if (little) {
    var value = 0;
    for (var i = length - 1; i >= 0; i--) {
      value = value * 256 + bytes[start + i];
    }
    return value;
  }
  var value = 0;
  for (var i = 0; i < length; i++) {
    value = value * 256 + bytes[start + i];
  }
  return value;
}

class _PrefecturePoint {
  const _PrefecturePoint(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
}

const _prefecturePoints = <_PrefecturePoint>[
  _PrefecturePoint('北海道', 43.06, 141.35),
  _PrefecturePoint('青森', 40.82, 140.74),
  _PrefecturePoint('岩手', 39.70, 141.15),
  _PrefecturePoint('宮城', 38.27, 140.87),
  _PrefecturePoint('秋田', 39.72, 140.10),
  _PrefecturePoint('山形', 38.25, 140.34),
  _PrefecturePoint('福島', 37.76, 140.47),
  _PrefecturePoint('茨城', 36.34, 140.45),
  _PrefecturePoint('栃木', 36.57, 139.88),
  _PrefecturePoint('群馬', 36.39, 139.06),
  _PrefecturePoint('埼玉', 35.86, 139.65),
  _PrefecturePoint('千葉', 35.61, 140.12),
  _PrefecturePoint('東京', 35.68, 139.76),
  _PrefecturePoint('神奈川', 35.45, 139.64),
  _PrefecturePoint('新潟', 37.90, 139.02),
  _PrefecturePoint('富山', 36.70, 137.21),
  _PrefecturePoint('石川', 36.59, 136.63),
  _PrefecturePoint('福井', 36.07, 136.22),
  _PrefecturePoint('山梨', 35.66, 138.57),
  _PrefecturePoint('長野', 36.65, 138.18),
  _PrefecturePoint('岐阜', 35.39, 136.72),
  _PrefecturePoint('静岡', 34.98, 138.38),
  _PrefecturePoint('愛知', 35.18, 136.91),
  _PrefecturePoint('三重', 34.73, 136.51),
  _PrefecturePoint('滋賀', 35.00, 135.87),
  _PrefecturePoint('京都', 35.02, 135.76),
  _PrefecturePoint('大阪', 34.69, 135.52),
  _PrefecturePoint('兵庫', 34.69, 135.18),
  _PrefecturePoint('奈良', 34.69, 135.83),
  _PrefecturePoint('和歌山', 34.23, 135.17),
  _PrefecturePoint('鳥取', 35.50, 134.24),
  _PrefecturePoint('島根', 35.47, 133.05),
  _PrefecturePoint('岡山', 34.66, 133.93),
  _PrefecturePoint('広島', 34.40, 132.46),
  _PrefecturePoint('山口', 34.19, 131.47),
  _PrefecturePoint('徳島', 34.07, 134.56),
  _PrefecturePoint('香川', 34.34, 134.04),
  _PrefecturePoint('愛媛', 33.84, 132.77),
  _PrefecturePoint('高知', 33.56, 133.53),
  _PrefecturePoint('福岡', 33.59, 130.40),
  _PrefecturePoint('佐賀', 33.25, 130.30),
  _PrefecturePoint('長崎', 32.75, 129.88),
  _PrefecturePoint('熊本', 32.80, 130.71),
  _PrefecturePoint('大分', 33.24, 131.61),
  _PrefecturePoint('宮崎', 31.91, 131.42),
  _PrefecturePoint('鹿児島', 31.56, 130.56),
  _PrefecturePoint('沖縄', 26.21, 127.68),
];

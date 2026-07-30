const Set<String> validPrefectures = <String>{
  '北海道',
  '青森',
  '岩手',
  '宮城',
  '秋田',
  '山形',
  '福島',
  '茨城',
  '栃木',
  '群馬',
  '埼玉',
  '千葉',
  '東京',
  '神奈川',
  '新潟',
  '富山',
  '石川',
  '福井',
  '山梨',
  '長野',
  '岐阜',
  '静岡',
  '愛知',
  '三重',
  '滋賀',
  '京都',
  '大阪',
  '兵庫',
  '奈良',
  '和歌山',
  '鳥取',
  '島根',
  '岡山',
  '広島',
  '山口',
  '徳島',
  '香川',
  '愛媛',
  '高知',
  '福岡',
  '佐賀',
  '長崎',
  '熊本',
  '大分',
  '宮崎',
  '鹿児島',
  '沖縄',
};

const Set<String> validPrefectureStates = <String>{
  'unvisited',
  'visited',
  'transit',
};

const int maxTripTitleLength = 200;

String? normalizeTripTitle(String value) {
  final withSpaces = value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');
  final collapsed = withSpaces.split(RegExp(r'\s+')).join(' ');
  final trimmed = collapsed.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > maxTripTitleLength) {
    return trimmed.substring(0, maxTripTitleLength);
  }
  return trimmed;
}

String normalizePrefectureState(String value) {
  return validPrefectureStates.contains(value) ? value : 'unvisited';
}

bool isValidPrefecture(String name) {
  return validPrefectures.contains(name);
}

Map<String, String> normalizePrefectureStates(
  Map<String, String> states,
) {
  final result = <String, String>{};
  for (final entry in states.entries) {
    if (!validPrefectures.contains(entry.key)) continue;
    result[entry.key] = normalizePrefectureState(entry.value);
  }
  return result;
}
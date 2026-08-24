/// バックアップ/復元で生成するファイル名の拡張子を安全へ正規化する。
///
/// 元名に拡張子が無い・不審な場合はJPEGへフォールバックする。
String safeFileExtension(String path) {
  final fileName = path.split(RegExp(r'[/\\]')).last;
  final separator = fileName.lastIndexOf('.');
  if (separator < 0) return '.jpg';
  final extension = fileName.substring(separator).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension) ? extension : '.jpg';
}

import 'package:flutter/material.dart';

const int photoQuotaLimit = 300;

class PhotoQuotaStatus {
  const PhotoQuotaStatus({required this.count, this.limit = photoQuotaLimit});

  final int count;
  final int limit;

  int get normalizedCount => count < 0 ? 0 : count;
  int get remaining => (limit - normalizedCount).clamp(0, limit);
  bool get reached => normalizedCount >= limit;
  bool get exceeded => normalizedCount > limit;

  String get title => '写真 $normalizedCount / $limit枚';
  String get message => reached
      ? exceeded
            ? '上限を${normalizedCount - limit}枚超えています。既存の写真を整理してください'
            : '上限に達しています。既存の写真を整理してください'
      : '残り $remaining枚';
  String get semanticsLabel =>
      '写真使用数 $normalizedCount枚、上限 $limit枚、残り$remaining枚、${reached ? '写真追加不可' : '写真追加可能'}';
}

class PhotoQuotaCard extends StatelessWidget {
  const PhotoQuotaCard({super.key, required this.status});

  final PhotoQuotaStatus status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: status.semanticsLabel,
      child: Card(
        child: ListTile(
          leading: Icon(
            status.reached ? Icons.block : Icons.photo_library_outlined,
            semanticLabel: status.reached ? '写真追加不可' : '写真追加可能',
          ),
          title: Text(status.title),
          subtitle: Text(status.message),
        ),
      ),
    );
  }
}

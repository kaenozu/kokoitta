import 'package:flutter/material.dart';

class OfflineJapanMap extends StatelessWidget {
  const OfflineJapanMap({super.key, required this.states});

  final Map<String, String> states;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'オフライン日本地図。都道府県の訪問状態を色と記号で表示',
    child: AspectRatio(
      aspectRatio: 1.45,
      child: CustomPaint(
        painter: _JapanMapPainter(
          states: states,
          scheme: Theme.of(context).colorScheme,
        ),
      ),
    ),
  );
}

class _JapanMapPainter extends CustomPainter {
  const _JapanMapPainter({required this.states, required this.scheme});

  final Map<String, String> states;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.outlineVariant;
    const names = <String>[
      '北海道',
      '青森県',
      '岩手県',
      '宮城県',
      '秋田県',
      '山形県',
      '福島県',
      '茨城県',
      '栃木県',
      '群馬県',
      '埼玉県',
      '東京都',
      '千葉県',
      '神奈川県',
      '新潟県',
      '富山県',
      '石川県',
      '福井県',
      '山梨県',
      '長野県',
      '岐阜県',
      '静岡県',
      '愛知県',
      '三重県',
      '滋賀県',
      '京都府',
      '大阪府',
      '兵庫県',
      '奈良県',
      '和歌山県',
      '鳥取県',
      '島根県',
      '岡山県',
      '広島県',
      '山口県',
      '徳島県',
      '香川県',
      '愛媛県',
      '高知県',
      '福岡県',
      '佐賀県',
      '長崎県',
      '熊本県',
      '大分県',
      '宮崎県',
      '鹿児島県',
      '沖縄県',
    ];
    const columns = 7;
    final width = size.width / columns;
    final height = size.height / 7;
    for (var index = 0; index < names.length; index++) {
      final row = index ~/ columns;
      final column = index % columns;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          column * width + 2,
          row * height + 2,
          width - 4,
          height - 4,
        ),
        const Radius.circular(5),
      );
      final state = states[names[index]] ?? 'unvisited';
      fill.color = switch (state) {
        'visited' => scheme.primary,
        'transit' => scheme.secondary,
        _ => scheme.surfaceContainerHighest,
      };
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, border);
      final text = TextPainter(
        text: TextSpan(
          text: names[index].replaceFirst(RegExp(r'[県府都]$'), ''),
          style: TextStyle(
            color: state == 'unvisited'
                ? scheme.onSurfaceVariant
                : scheme.onPrimary,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 6);
      text.paint(
        canvas,
        Offset(
          rect.left + (rect.width - text.width) / 2,
          rect.top + (rect.height - text.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_JapanMapPainter oldDelegate) =>
      oldDelegate.states != states;
}

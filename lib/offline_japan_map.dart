import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef PrefectureStateTapHandler = Future<void> Function(
  String name,
  String currentState,
);

/// Supplies the persistence-aware prefecture action without coupling the map
/// widget to the application's storage implementation.
class PrefectureMapActions extends InheritedWidget {
  const PrefectureMapActions({
    super.key,
    required this.onTap,
    required super.child,
  });

  final PrefectureStateTapHandler onTap;

  static PrefectureMapActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrefectureMapActions>();

  @override
  bool updateShouldNotify(PrefectureMapActions oldWidget) =>
      onTap != oldWidget.onTap;
}

/// A geographically arranged prefecture cartogram.
///
/// The map is intentionally hand-authored instead of depending on a remote map
/// service or a third-party geographic asset. It keeps all 47 prefectures
/// available offline while the precise chip list below it remains the fallback.
class OfflineJapanMap extends StatelessWidget {
  const OfflineJapanMap({
    super.key,
    required this.states,
    this.onPrefectureTap,
  });

  final Map<String, String> states;
  final ValueChanged<String>? onPrefectureTap;

  static const int prefectureCount = 47;

  @override
  Widget build(BuildContext context) {
    final inheritedAction = PrefectureMapActions.maybeOf(context)?.onTap;

    return Semantics(
      container: true,
      label: 'オフライン日本地図。47都道府県の訪問状態を表示',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _MapLegend(),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (!width.isFinite || width <= 0) {
                return const Text(
                  '日本地図を表示できません。下の都道府県一覧を利用してください。',
                );
              }

              const columns = 10;
              const rows = 16;
              final cellWidth = width / columns;
              final cellHeight = cellWidth * 0.78;

              return SizedBox(
                height: cellHeight * rows,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: _prefectures.map((prefecture) {
                    final state = states[prefecture.name] ?? 'unvisited';
                    final VoidCallback? onTap;
                    if (onPrefectureTap != null) {
                      onTap = () => onPrefectureTap!(prefecture.name);
                    } else if (inheritedAction != null) {
                      onTap = () => inheritedAction(prefecture.name, state);
                    } else {
                      onTap = null;
                    }
                    return Positioned(
                      left: prefecture.column * cellWidth,
                      top: prefecture.row * cellHeight,
                      width: prefecture.columnSpan * cellWidth,
                      height: prefecture.rowSpan * cellHeight,
                      child: Padding(
                        padding: const EdgeInsets.all(1.5),
                        child: _PrefectureTile(
                          prefecture: prefecture,
                          state: state,
                          onTap: onTap,
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: const <Widget>[
        _LegendItem(state: 'visited'),
        _LegendItem(state: 'transit'),
        _LegendItem(state: 'unvisited'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final colors = _stateColors(Theme.of(context).colorScheme, state);
    return Semantics(
      label: _stateLabel(state),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 22,
            height: 18,
            decoration: ShapeDecoration(
              color: colors.background,
              shape: _HexagonBorder(
                side: BorderSide(color: colors.border),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              _stateIcon(state),
              size: 12,
              color: colors.foreground,
            ),
          ),
          const SizedBox(width: 4),
          ExcludeSemantics(child: Text(_stateLabel(state))),
        ],
      ),
    );
  }
}

class _PrefectureTile extends StatelessWidget {
  const _PrefectureTile({
    required this.prefecture,
    required this.state,
    required this.onTap,
  });

  final _PrefecturePosition prefecture;
  final String state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = _stateColors(scheme, state);
    final nextState = switch (state) {
      'visited' => '通過',
      'transit' => '未訪問',
      _ => '訪問済み',
    };
    final semanticsLabel = onTap == null
        ? '${prefecture.name}、${_stateLabel(state)}'
        : '${prefecture.name}、${_stateLabel(state)}。タップすると$nextStateに変更';

    return Semantics(
      key: ValueKey<String>(
        'prefecture-map-${prefecture.code.toString().padLeft(2, '0')}',
      ),
      button: onTap != null,
      enabled: onTap != null,
      label: semanticsLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: '${prefecture.name}：${_stateLabel(state)}',
          child: Material(
            color: colors.background,
            shape: _HexagonBorder(
              side: BorderSide(color: colors.border, width: 1.2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          prefecture.shortLabel,
                          maxLines: 1,
                          style: TextStyle(
                            color: colors.foreground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: Icon(
                        _stateIcon(state),
                        size: 9,
                        color: colors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StateColors {
  const _StateColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

_StateColors _stateColors(ColorScheme scheme, String state) {
  return switch (state) {
    'visited' => _StateColors(
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
      border: scheme.primary,
    ),
    'transit' => _StateColors(
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
      border: scheme.secondary,
    ),
    _ => _StateColors(
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
      border: scheme.outline,
    ),
  };
}

String _stateLabel(String state) => switch (state) {
  'visited' => '訪問済み',
  'transit' => '通過',
  _ => '未訪問',
};

IconData _stateIcon(String state) => switch (state) {
  'visited' => Icons.check,
  'transit' => Icons.directions_car,
  _ => Icons.circle_outlined,
};

class _HexagonBorder extends ShapeBorder {
  const _HexagonBorder({required this.side});

  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) => _HexagonBorder(side: side.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final inset = math.min(rect.width * 0.18, rect.height * 0.32);
    return Path()
      ..moveTo(rect.left + inset, rect.top)
      ..lineTo(rect.right - inset, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.right - inset, rect.bottom)
      ..lineTo(rect.left + inset, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      side.toPaint(),
    );
  }
}

class _PrefecturePosition {
  const _PrefecturePosition(
    this.code,
    this.name,
    this.shortLabel,
    this.column,
    this.row, {
    this.columnSpan = 1,
    this.rowSpan = 1,
  });

  final int code;
  final String name;
  final String shortLabel;
  final double column;
  final double row;
  final double columnSpan;
  final double rowSpan;
}

// A hand-authored geographic cartogram. Stable JIS prefecture codes are used as
// identifiers. Hokkaido and Okinawa are enlarged/inset so they stay visible on
// narrow Android screens.
const List<_PrefecturePosition> _prefectures = <_PrefecturePosition>[
  _PrefecturePosition(1, '北海道', '北海道', 8, 0, columnSpan: 2, rowSpan: 1.5),
  _PrefecturePosition(2, '青森県', '青森', 8, 2),
  _PrefecturePosition(3, '岩手県', '岩手', 8, 3),
  _PrefecturePosition(4, '宮城県', '宮城', 8, 4),
  _PrefecturePosition(5, '秋田県', '秋田', 7, 3),
  _PrefecturePosition(6, '山形県', '山形', 7, 4),
  _PrefecturePosition(7, '福島県', '福島', 7, 5),
  _PrefecturePosition(8, '茨城県', '茨城', 9, 5),
  _PrefecturePosition(9, '栃木県', '栃木', 8, 5),
  _PrefecturePosition(10, '群馬県', '群馬', 7, 6),
  _PrefecturePosition(11, '埼玉県', '埼玉', 8, 6),
  _PrefecturePosition(12, '千葉県', '千葉', 9, 7),
  _PrefecturePosition(13, '東京都', '東京', 8, 7),
  _PrefecturePosition(14, '神奈川県', '神奈', 8, 8),
  _PrefecturePosition(15, '新潟県', '新潟', 6, 5),
  _PrefecturePosition(16, '富山県', '富山', 5, 6),
  _PrefecturePosition(17, '石川県', '石川', 4, 6),
  _PrefecturePosition(18, '福井県', '福井', 4, 7),
  _PrefecturePosition(19, '山梨県', '山梨', 7, 7),
  _PrefecturePosition(20, '長野県', '長野', 6, 6),
  _PrefecturePosition(21, '岐阜県', '岐阜', 5, 7),
  _PrefecturePosition(22, '静岡県', '静岡', 7, 8),
  _PrefecturePosition(23, '愛知県', '愛知', 6, 8),
  _PrefecturePosition(24, '三重県', '三重', 6, 9),
  _PrefecturePosition(25, '滋賀県', '滋賀', 5, 8),
  _PrefecturePosition(26, '京都府', '京都', 4, 8),
  _PrefecturePosition(27, '大阪府', '大阪', 4, 9),
  _PrefecturePosition(28, '兵庫県', '兵庫', 3, 8),
  _PrefecturePosition(29, '奈良県', '奈良', 5, 9),
  _PrefecturePosition(30, '和歌山県', '和歌', 4, 10),
  _PrefecturePosition(31, '鳥取県', '鳥取', 2, 8),
  _PrefecturePosition(32, '島根県', '島根', 1, 8),
  _PrefecturePosition(33, '岡山県', '岡山', 2, 9),
  _PrefecturePosition(34, '広島県', '広島', 1, 9),
  _PrefecturePosition(35, '山口県', '山口', 0, 9),
  _PrefecturePosition(36, '徳島県', '徳島', 3, 10),
  _PrefecturePosition(37, '香川県', '香川', 3, 9),
  _PrefecturePosition(38, '愛媛県', '愛媛', 2, 10),
  _PrefecturePosition(39, '高知県', '高知', 2, 11),
  _PrefecturePosition(40, '福岡県', '福岡', 0, 11),
  _PrefecturePosition(41, '佐賀県', '佐賀', 0, 12),
  _PrefecturePosition(42, '長崎県', '長崎', 0, 13),
  _PrefecturePosition(43, '熊本県', '熊本', 1, 12),
  _PrefecturePosition(44, '大分県', '大分', 1, 11),
  _PrefecturePosition(45, '宮崎県', '宮崎', 2, 12),
  _PrefecturePosition(46, '鹿児島県', '鹿児', 1, 13),
  _PrefecturePosition(47, '沖縄県', '沖縄', 4, 14, columnSpan: 2),
];

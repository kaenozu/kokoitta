import 'package:flutter/material.dart';

import 'design/kokoitta_design_system.dart';

/// One actionable semantics node for a prefecture state transition.
class PrefectureStateListTile extends StatelessWidget {
  const PrefectureStateListTile({
    required this.name,
    required this.currentLabel,
    required this.nextLabel,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String name;
  final String currentLabel;
  final String nextLabel;
  final IconData icon;
  final VoidCallback? onTap;

  String get semanticLabel =>
      '$name、$currentLabel。タップすると$nextLabelに変更';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ListTile(
          minTileHeight: KokoittaSize.minimumTapTarget,
          leading: Icon(icon),
          title: Text(name),
          subtitle: Text(currentLabel),
          trailing: Text('$nextLabelへ'),
          onTap: onTap,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'design/kokoitta_design_system.dart';

export 'design/kokoitta_components.dart';
export 'design/kokoitta_design_system.dart';
export 'home_dashboard.dart';
export 'import_state_contract.dart';
export 'prefecture_state_list_tile.dart';
export 'settings_backup_view.dart';
export 'trip_detail_view.dart';
export 'trip_list_view.dart';

/// Backward-compatible entry point used by the application shell and tests.
ThemeData buildKokoittaTheme(Brightness brightness) =>
    buildKokoittaDesignTheme(brightness);

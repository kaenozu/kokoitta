import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'image_decode.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_data_operations.dart';
import 'backup_service.dart';
import 'models.dart';
import 'offline_japan_map.dart';
import 'operation_coordinator.dart';
import 'photo.dart';
import 'import_progress.dart';
import 'storage_cleanup.dart';
import 'trip_store.dart';
import 'validators.dart';

part 'home_data.dart';
part 'home_view.dart';
part 'home_backup.dart';

void main() => runApp(const KokoittaApp());

/// 起動時cleanupの実行関数。キュー直列化の対象となる写真ファイル削除処理。
typedef CleanupRunner = Future<void> Function(AppData data);

class KokoittaApp extends StatelessWidget {
  const KokoittaApp({super.key, this.cleanupRunner});

  /// 起動時cleanupの実行関数。テストで競合を制御するために注入可能。
  final CleanupRunner? cleanupRunner;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ここいった',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xff1b4332),
              brightness: Brightness.light,
            ).copyWith(
              primary: const Color(0xff1b4332),
              secondary: const Color(0xffff7051),
              surface: const Color(0xfffcf9f8),
            ),
        scaffoldBackgroundColor: const Color(0xfffcf9f8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfffcf9f8),
          foregroundColor: Color(0xff1b1c1c),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shadowColor: const Color(0x221b4332),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xfff0eded),
          indicatorColor: Color(0xffc1ecd4),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xff1b4332),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff8fd3aa),
          brightness: Brightness.dark,
        ).copyWith(primary: Color(0xffb5e8c8), secondary: Color(0xffffa58f)),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          margin: EdgeInsets.zero,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: HomePage(cleanupRunner: cleanupRunner),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.operationCoordinator, this.cleanupRunner});

  final OperationCoordinator? operationCoordinator;

  /// 起動時cleanupの実行関数。テストで競合を制御するために注入可能。
  final CleanupRunner? cleanupRunner;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const MethodChannel _shareChannel = MethodChannel(
    'com.kaenozu.kokoitta/share',
  );
  static const int _maxTrips = 10;
  static const int _maxPhotos = 300;

  final ImagePicker _picker = ImagePicker();
  final BackupService _backupService = BackupService();
  final TripStore _store = TripStore();
  final List<String> _prefectures = validPrefectures.toList(growable: false);

  late final OperationCoordinator _coordinator;
  late final CleanupRunner _cleanupRunner;
  late final Future<void> _initialization;
  AppData _data = AppData.empty();
  bool _isLoading = true;
  String? _loadError;
  int _tab = 0;
  final ImportRequestGate _importRequestGate = ImportRequestGate();
  final Set<String> _cancelledImportRequestIds = <String>{};
  final Set<String> _terminalImportRequestIds = <String>{};
  ImportEvent? _importEvent;
  bool _isCleanupRunning = false;
  StreamSubscription<OperationStatus>? _statusSub;

  /// 防御用に保持するrequestId集合の上限。Android側はrequestIdを毎回ユニークに
  /// 発行するため、ここに残るのは直近の終了・キャンセル履歴だけでよい。
  static const int _maxTrackedImportRequestIds = 64;

  @override
  void initState() {
    super.initState();
    _coordinator = widget.operationCoordinator ?? OperationCoordinator();
    _cleanupRunner =
        widget.cleanupRunner ?? (data) => StorageCleanup.run(appData: data);
    _initialization = _initialize();
    _shareChannel.setMethodCallHandler(_handleShareMethod);
    _statusSub = _coordinator.statusStream.listen((_) {
      if (mounted) _updateState(() {});
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _coordinator.dispose();
    _shareChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _updateState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  bool get _isImportBusy => _importEvent != null && !_importEvent!.isTerminal;

  /// 終了・キャンセル済みrequestIdを上限付きで記録する。
  ///
  /// 挿入順を保持するLinkedHashSetの先頭が最古エントリのため、上限超過時は
  /// 古いものから除去して無制限成長を防ぐ。requestIdはAndroid側で毎回ユニーク
  /// 化されるため、この防御履歴は直近の重複イベント対策としてのみ機能する。
  void _rememberImportRequestId(Set<String> tracked, String requestId) {
    tracked.add(requestId);
    while (tracked.length > _maxTrackedImportRequestIds) {
      tracked.remove(tracked.first);
    }
  }

  void _setImportEvent(ImportEvent event) {
    if (!_importRequestGate.accepts(event.requestId)) return;
    _updateState(() => _importEvent = event);
    if (event.isTerminal) {
      _rememberImportRequestId(_terminalImportRequestIds, event.requestId);
      _importRequestGate.finish(event.requestId);
    }
  }

  Future<void> _cancelImport() async {
    final event = _importEvent;
    if (event == null || event.isTerminal) return;
    _rememberImportRequestId(_cancelledImportRequestIds, event.requestId);
    try {
      await _shareChannel.invokeMethod<void>('cancelSharedImport');
    } on MissingPluginException {
      // The normal picker has no native session to cancel.
    } on PlatformException {
      // The local cancellation state still prevents a later commit.
    }
    _setImportEvent(
      event.copyWith(phase: ImportPhase.cancelled, isTerminal: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PrefectureMapActions(
      onTap: _isDisabled ? null : _updatePrefecture,
      child: _buildPage(context),
    );
  }
}

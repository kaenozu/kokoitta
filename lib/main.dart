import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_data_operations.dart';
import 'backup_service.dart';
import 'models.dart';
import 'storage_cleanup.dart';
import 'trip_store.dart';
import 'validators.dart';

part 'home_data.dart';
part 'home_view.dart';
part 'home_backup.dart';

void main() => runApp(const KokoittaApp());

class KokoittaApp extends StatelessWidget {
  const KokoittaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ここいった',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const MethodChannel _shareChannel =
      MethodChannel('com.kaenozu.kokoitta/share');
  static const int _maxTrips = 10;
  static const int _maxPhotos = 300;

  final ImagePicker _picker = ImagePicker();
  final BackupService _backupService = BackupService();
  final TripStore _store = TripStore();
  final List<String> _prefectures = validPrefectures.toList(growable: false);

  AppData _data = AppData.empty();
  Future<void> _mutationQueue = Future<void>.value();
  late final Future<void> _initialization;
  bool _isLoading = true;
  String? _loadError;
  int _tab = 0;
  bool _isCleanupRunning = false;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
    _shareChannel.setMethodCallHandler(_handleShareMethod);
  }

  @override
  void dispose() {
    _shareChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _updateState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'backup_service.dart';

void main() => runApp(const KokoittaApp());

class KokoittaApp extends StatelessWidget {
  const KokoittaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'ここいった',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1b4332), brightness: Brightness.light).copyWith(primary: const Color(0xff1b4332), secondary: const Color(0xffff7051), surface: const Color(0xfffcf9f8)),
          scaffoldBackgroundColor: const Color(0xfffcf9f8),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xfffcf9f8), foregroundColor: Color(0xff1b1c1c), elevation: 0, centerTitle: false),
          cardTheme: CardThemeData(color: Colors.white, elevation: 1, shadowColor: const Color(0x221b4332), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), margin: EdgeInsets.zero),
          navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xfff0eded), indicatorColor: Color(0xffc1ecd4)),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Color(0xff1b4332), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(28)))),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class Trip {
  Trip(this.title, this.photos);
  String title;
  final List<File> photos;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _shareChannel = MethodChannel('com.kaenozu.kokoitta/share');
  final _picker = ImagePicker();
  final _backupService = BackupService();
  final _trips = <Trip>[];
  final _prefectures = <String>['北海道', '青森', '岩手', '宮城', '秋田', '山形', '福島', '茨城', '栃木', '群馬', '埼玉', '千葉', '東京', '神奈川', '新潟', '富山', '石川', '福井', '山梨', '長野', '岐阜', '静岡', '愛知', '三重', '滋賀', '京都', '大阪', '兵庫', '奈良', '和歌山', '鳥取', '島根', '岡山', '広島', '山口', '徳島', '香川', '愛媛', '高知', '福岡', '佐賀', '長崎', '熊本', '大分', '宮崎', '鹿児島', '沖縄'];
  final _prefectureStates = <String, String>{};
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _loadPrefectureStates();
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedUris') await _importSharedUris(List<String>.from(call.arguments as List));
    });
    _shareChannel.invokeMethod<List<dynamic>>('getSharedUris').then((uris) {
      if (uris != null) _importSharedUris(uris.cast<String>());
    });
  }

  Future<void> _importSharedUris(List<String> uris) async {
    if (uris.isEmpty || !mounted) return;
    final existingPhotos = _trips.fold<int>(0, (sum, trip) => sum + trip.photos.length);
    if (_trips.length >= 10 || existingPhotos + uris.length > 300) return;
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos')..createSync(recursive: true);
    final copied = <File>[];
    for (final uri in uris) {
      final source = File(uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri);
      if (source.existsSync()) copied.add(await source.copy('${photosDirectory.path}/${DateTime.now().microsecondsSinceEpoch}_${source.uri.pathSegments.last}'));
    }
    if (!mounted || copied.isEmpty) return;
    setState(() => _trips.add(Trip('共有からのおでかけ ${_trips.length + 1}', copied)));
    await _saveTrips();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${copied.length}枚を共有から取り込みました')));
  }

  Future<void> _loadTrips() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList('trips') ?? <String>[];
    final loaded = <Trip>[];
    for (final record in stored) {
      final separator = record.indexOf('|');
      if (separator <= 0) continue;
      final title = record.substring(0, separator);
      final paths = record.substring(separator + 1).split(';;').where((path) => path.isNotEmpty).map(File.new).where((file) => file.existsSync()).toList();
      loaded.add(Trip(title, paths));
    }
    if (mounted) setState(() => _trips.addAll(loaded));
  }

  Future<void> _saveTrips() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('trips', _trips.map((trip) => '${trip.title}|${trip.photos.map((file) => file.path).join(';;')}').toList());
  }

  Future<void> _loadPrefectureStates() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList('prefectureStates') ?? <String>[];
    if (!mounted) return;
    setState(() {
      for (final value in stored) {
        final separator = value.indexOf('|');
        if (separator > 0) _prefectureStates[value.substring(0, separator)] = value.substring(separator + 1);
      }
    });
  }

  Future<void> _savePrefectureStates() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('prefectureStates', _prefectureStates.entries.map((entry) => '${entry.key}|${entry.value}').toList());
  }

  Future<void> _addPhotos() async {
    final selected = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 2048);
    if (selected.isEmpty || !mounted) return;
    final existingPhotos = _trips.fold<int>(0, (sum, trip) => sum + trip.photos.length);
    if (_trips.length >= 10 || existingPhotos + selected.length > 300) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('無料版の上限を超えます（旅行10件・写真300枚）。${_trips.length >= 10 ? '旅行を整理してください。' : '写真を300枚以内に選び直してください。'}')));
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos')..createSync(recursive: true);
    final copied = <File>[];
    for (final image in selected) {
      final safeName = image.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final destination = File('${photosDirectory.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName');
      copied.add(await File(image.path).copy(destination.path));
    }
    if (!mounted) return;
    setState(() => _trips.add(Trip('新しいおでかけ ${_trips.length + 1}', copied)));
    await _saveTrips();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${copied.length}枚を取り込みました')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('ここいった'),
          actions: [IconButton(onPressed: _addPhotos, icon: const Icon(Icons.add_photo_alternate_outlined), tooltip: '写真を追加'), IconButton(onPressed: _showBackupMenu, icon: const Icon(Icons.settings_outlined), tooltip: '設定')],
        ),
        body: _tab == 0 ? _mapView(context) : _tripView(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: '地図'),
            NavigationDestination(icon: Icon(Icons.photo_album_outlined), selectedIcon: Icon(Icons.photo_album), label: '旅行'),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: _addPhotos, icon: const Icon(Icons.add_a_photo), label: const Text('写真を追加')),
      );

  Widget _mapView(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('こんにちは', style: Theme.of(context).textTheme.bodyMedium), Text('旅の記録', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))]), IconButton(onPressed: _showBackupMenu, icon: const Icon(Icons.tune), tooltip: '設定')]),
          const SizedBox(height: 20),
          Card(color: const Color(0xff1b4332), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.explore_outlined, color: Color(0xffc1ecd4), size: 42), const SizedBox(height: 16), const Text('まだ知らない場所へ', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text('${_prefectureStates.values.where((state) => state == 'visited').length} / 47 都道府県を訪問', style: const TextStyle(color: Color(0xffc1ecd4))), const SizedBox(height: 20), FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xffff7051), foregroundColor: Colors.white), onPressed: _addPhotos, icon: const Icon(Icons.add_a_photo), label: const Text('写真を読み込む'))]))),
          const SizedBox(height: 28),
          Text('都道府県マップ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 6, runSpacing: 6, children: _prefectures.map((name) { final state = _prefectureStates[name] ?? 'unvisited'; return ActionChip(label: Text(name), avatar: Icon(state == 'visited' ? Icons.check : state == 'transit' ? Icons.directions_car : Icons.circle_outlined, size: 16), onPressed: () { setState(() { _prefectureStates[name] = state == 'unvisited' ? 'visited' : state == 'visited' ? 'transit' : 'unvisited'; }); _savePrefectureStates(); }); }).toList()))),
          const SizedBox(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('最近の旅行', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('すべて見る'))]),
          const SizedBox(height: 10),
          if (_trips.isEmpty) const Text('写真を追加すると、ここに旅の思い出が並びます。') else SizedBox(height: 150, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _trips.length.clamp(0, 5), separatorBuilder: (context, index) => const SizedBox(width: 12), itemBuilder: (_, index) { final trip = _trips[index]; return SizedBox(width: 180, child: Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => _showTrip(trip), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: trip.photos.isEmpty ? const Center(child: Icon(Icons.landscape)) : Image.file(trip.photos.first, width: double.infinity, fit: BoxFit.cover)), Padding(padding: const EdgeInsets.all(10), child: Text(trip.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)))])))); })),
        ],
      );

  Widget _tripView() => _trips.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.photo_album_outlined, size: 64), const SizedBox(height: 12), const Text('旅行がありません'), const SizedBox(height: 16), FilledButton.icon(onPressed: _addPhotos, icon: const Icon(Icons.add_a_photo), label: const Text('写真を追加'))]))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _trips.length,
          itemBuilder: (context, index) {
            final trip = _trips[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: () => _showTrip(trip), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(height: 150, width: double.infinity, child: trip.photos.isEmpty ? const Center(child: Icon(Icons.landscape, size: 48)) : Image.file(trip.photos.first, fit: BoxFit.cover)), Padding(padding: const EdgeInsets.fromLTRB(16, 14, 8, 14), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(trip.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text('${trip.photos.length}枚の思い出', style: Theme.of(context).textTheme.bodySmall)])), PopupMenuButton<String>(onSelected: (value) => _deleteTrip(trip, value == 'delete'), itemBuilder: (_) => const [PopupMenuItem(value: 'move', child: Text('旅行未設定へ移動')), PopupMenuItem(value: 'delete', child: Text('写真も削除'))])]))])),
            );
          },
        );

  void _showTrip(Trip trip) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SizedBox(height: 220, child: GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4), itemCount: trip.photos.length, itemBuilder: (_, index) => Image.file(trip.photos[index], fit: BoxFit.cover))),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => _shareTrip(trip), icon: const Icon(Icons.share), label: const Text('写真を共有')),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () { Navigator.pop(context); _addPhotos(); }, icon: const Icon(Icons.add), label: const Text('写真を追加')),
            ]),
          ),
        ),
      );

  Future<void> _deleteTrip(Trip trip, bool deletePhotos) async {
    if (deletePhotos) {
      for (final file in trip.photos) {
        if (file.existsSync()) await file.delete();
      }
    }
    setState(() => _trips.remove(trip));
    await _saveTrips();
  }

  Future<void> _showBackupMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [const Align(alignment: Alignment.centerLeft, child: Text('データ保護', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), const SizedBox(height: 12), ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('完全バックアップを作成'), subtitle: const Text('旅行と写真をZIPに保存して共有'), onTap: () { Navigator.pop(sheetContext); _createBackup(); }), ListTile(leading: const Icon(Icons.restore), title: const Text('完全復元'), subtitle: const Text('現在のデータをバックアップで置き換え'), onTap: () { Navigator.pop(sheetContext); _restoreBackup(); })]))));
  }

  Future<void> _createBackup() async {
    final file = await _backupService.createBackup(_trips.map((trip) => BackupTrip(trip.title, trip.photos)).toList());
    if (!mounted) return;
    await _backupService.shareBackup(file);
  }

  Future<void> _restoreBackup() async {
    try {
      final restored = await _backupService.restoreBackup();
      if (restored.isEmpty || !mounted) return;
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('完全復元'), content: Text('${restored.length}旅行を読み込みました。現在のデータを置き換えますか？'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('置き換える'))]));
      if (confirmed != true || !mounted) return;
      setState(() { _trips..clear()..addAll(restored.map((trip) => Trip(trip.title, trip.photos))); });
      await _saveTrips();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('復元が完了しました')));
    } on FormatException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('復元できません: $error')));
    }
  }

  Future<void> _shareTrip(Trip trip) async {
    final files = trip.photos.where((file) => file.existsSync()).map((file) => XFile(file.path)).toList();
    if (files.isNotEmpty) await SharePlus.instance.share(ShareParams(files: files, text: trip.title));
  }
}


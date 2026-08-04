part of 'main.dart';

extension _HomeView on _HomePageState {
  static const _photoQuota = 300;

  int get _photoCount =>
      _data.unassignedPhotos.length +
      _data.trips.fold<int>(0, (total, trip) => total + trip.photos.length);

  bool get _photoQuotaReached => _photoCount >= _photoQuota;

  bool get _isDisabled => _isLoading || _coordinator.isBusy || _isImportBusy;

  bool get _cannotAddPhotos =>
      _isDisabled || _loadError != null || _photoQuotaReached;

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ここいった'),
        actions: <Widget>[
          if (_coordinator.isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_importEvent != null && !_importEvent!.isTerminal)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '取り込み ${_importEvent!.processed} / ${_importEvent!.total}',
                ),
                TextButton(
                  onPressed: _cancelImport,
                  child: const Text('キャンセル'),
                ),
              ],
            ),
          IconButton(
            onPressed: _cannotAddPhotos ? null : _addPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '写真を追加',
          ),
          IconButton(
            onPressed: _isDisabled ? null : _showBackupMenu,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => _updateState(() => _tab = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '地図',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_album_outlined),
            selectedIcon: Icon(Icons.photo_album),
            label: '旅行',
          ),
        ],
      ),
      floatingActionButton: _isLoading || _loadError != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _cannotAddPhotos ? null : _addPhotos,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('写真を追加'),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              const Text(
                '保存データを読み込めませんでした',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _showBackupMenu,
                icon: const Icon(Icons.restore),
                label: const Text('バックアップから復元'),
              ),
            ],
          ),
        ),
      );
    }
    return _tab == 0 ? _mapView(context) : _tripView();
  }

  Widget _mapView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('こんにちは', style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  '旅の記録',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: _isDisabled ? null : _showBackupMenu,
              icon: const Icon(Icons.tune),
              tooltip: '設定',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.explore_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 42,
                ),
                const SizedBox(height: 16),
                Text(
                  'まだ知らない場所へ',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_data.prefectureStates.values.where((state) => state == 'visited').length} / 47 都道府県を訪問',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  ),
                  onPressed: _cannotAddPhotos ? null : _addPhotos,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('写真を読み込む'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          label:
              '写真使用数 $_photoCount枚、上限 $_photoQuota枚、残り${(_photoQuota - _photoCount).clamp(0, _photoQuota)}枚',
          child: Card(
            child: ListTile(
              leading: Icon(
                _photoQuotaReached ? Icons.block : Icons.photo_library_outlined,
              ),
              title: Text('写真 $_photoCount / $_photoQuota枚'),
              subtitle: Text(
                _photoQuotaReached
                    ? '上限に達しています。既存の写真を整理してください'
                    : '残り ${(_photoQuota - _photoCount).clamp(0, _photoQuota)}枚',
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: OfflineJapanMap(states: _data.prefectureStates),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '都道府県マップ',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _prefectures.map((name) {
                final state = _data.prefectureStates[name] ?? 'unvisited';
                return ActionChip(
                  label: Text(name),
                  avatar: Icon(
                    state == 'visited'
                        ? Icons.check
                        : state == 'transit'
                        ? Icons.directions_car
                        : Icons.circle_outlined,
                    size: 16,
                  ),
                  onPressed: _isDisabled
                      ? null
                      : () => _updatePrefecture(name, state),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              '最近の旅行',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => _updateState(() => _tab = 1),
              child: const Text('すべて見る'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_data.trips.isEmpty)
          const Text('写真を追加すると、ここに旅の思い出が並びます。')
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _data.trips.length > 5 ? 5 : _data.trips.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (_, index) {
                final trip = _data.trips[index];
                return SizedBox(
                  width: 180,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _showTrip(trip),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: _photoPreview(trip.photos)),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              trip.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _tripView() {
    if (_data.trips.isEmpty && _data.unassignedPhotos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.photo_album_outlined, size: 64),
            const SizedBox(height: 12),
            const Text('旅行がありません'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cannotAddPhotos ? null : _addPhotos,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('写真を追加'),
            ),
          ],
        ),
      );
    }

    final itemCount =
        _data.trips.length + (_data.unassignedPhotos.isEmpty ? 0 : 1);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0 && _data.unassignedPhotos.isNotEmpty) {
          return _unassignedCard();
        }
        final tripIndex = index - (_data.unassignedPhotos.isEmpty ? 0 : 1);
        return _tripCard(_data.trips[tripIndex]);
      },
    );
  }

  Widget _unassignedCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showUnassignedPhotos,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 150,
              width: double.infinity,
              child: _photoPreview(_data.unassignedPhotos),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '旅行未設定',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text('${_data.unassignedPhotos.length}枚'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tripCard(Trip trip) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showTrip(trip),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 150,
              width: double.infinity,
              child: _photoPreview(trip.photos),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          trip.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${trip.photos.length}枚の思い出',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: !_isDisabled,
                    onSelected: (value) => _handleTripMenu(trip, value),
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'move', child: Text('旅行未設定へ移動')),
                      PopupMenuItem(value: 'delete', child: Text('写真も削除')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPreview(List<Photo> photos) {
    if (photos.isEmpty) {
      return const Center(child: Icon(Icons.landscape, size: 48));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dimension = thumbnailDecodeDimension(
          logicalWidth: constraints.maxWidth,
          logicalHeight: constraints.maxHeight,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        return Image.file(
          photos.first.file,
          width: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: dimension,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
        );
      },
    );
  }

  void _showTrip(Trip trip) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                trip.title,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SizedBox(height: 260, child: _photoGrid(trip.photos)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _shareFiles(trip.photos, trip.title),
                icon: const Icon(Icons.share),
                label: const Text('写真を共有'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _cannotAddPhotos
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _addPhotos(tripId: trip.id);
                      },
                icon: const Icon(Icons.add),
                label: const Text('この旅行に写真を追加'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnassignedPhotos() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('旅行未設定', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              SizedBox(height: 260, child: _photoGrid(_data.unassignedPhotos)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _shareFiles(_data.unassignedPhotos, '旅行未設定'),
                icon: const Icon(Icons.share),
                label: const Text('写真を共有'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isDisabled ? null : _createTripFromUnassigned,
                icon: const Icon(Icons.photo_album_outlined),
                label: const Text('新しい旅行にまとめる'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoGrid(List<Photo> photos) {
    if (photos.isEmpty) return const Center(child: Text('写真がありません'));
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) => Semantics(
        button: true,
        label: '写真 ${index + 1} / ${photos.length} を拡大表示',
        child: GestureDetector(
          onTap: () => _showPhotoViewer(photos, index),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dimension = thumbnailDecodeDimension(
                logicalWidth: constraints.maxWidth,
                logicalHeight: constraints.maxHeight,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              );
              return Image.file(
                photos[index].file,
                fit: BoxFit.cover,
                cacheWidth: dimension,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xffeeeeee),
                  child: Icon(Icons.broken_image_outlined),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

extension _PhotoViewerActions on _HomePageState {
  void _showPhotoViewer(List<Photo> photos, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            _PhotoViewer(photos: photos, initialIndex: initialIndex),
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initialIndex});

  final List<Photo> photos;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('写真')),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        itemBuilder: (context, index) => LayoutBuilder(
          builder: (context, constraints) {
            final dimension = fullscreenDecodeDimension(
              logicalWidth: constraints.maxWidth,
              logicalHeight: constraints.maxHeight,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            );
            return InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.file(
                  widget.photos[index].file,
                  fit: BoxFit.contain,
                  cacheWidth: dimension,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 72),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

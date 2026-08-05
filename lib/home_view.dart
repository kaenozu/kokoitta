part of 'main.dart';

extension _HomeView on _HomePageState {
  int get _photoCount =>
      _data.unassignedPhotos.length +
      _data.trips.fold<int>(0, (total, trip) => total + trip.photos.length);

  PhotoQuotaStatus get _quotaStatus => PhotoQuotaStatus(count: _photoCount);

  bool get _photoQuotaReached => _quotaStatus.reached;

  bool get _isDisabled => _isLoading || _coordinator.isBusy || _isImportBusy;

  bool get _cannotAddPhotos =>
      _isDisabled || _loadError != null || _photoQuotaReached;

  HomePrefectureSummary get _homePrefectureSummary {
    final visited = _prefectures
        .where((name) => _data.prefectureStates[name] == 'visited')
        .length;
    final planned = _prefectures
        .where((name) => _data.prefectureStates[name] == 'transit')
        .length;
    return HomePrefectureSummary(
      visited: visited,
      planned: planned,
      unvisited: OfflineJapanMap.prefectureCount - visited - planned,
    );
  }

  HomeDashboardOperation? get _homeOperation {
    final event = _importEvent;
    if (event != null && !event.isTerminal) {
      final cancelling = event.phase == ImportPhase.cancelled;
      return HomeDashboardOperation(
        title: cancelling
            ? '写真の追加をキャンセルしています'
            : '取り込み ${event.processed} / ${event.total}',
        message: cancelling
            ? '保存前の処理を安全に取り消しています。完了するまでお待ちください。'
            : '写真を安全に処理しています。',
        processed: event.processed,
        total: event.total,
        onCancel: cancelling ? null : _cancelImport,
      );
    }
    if (_coordinator.isBusy || _isCleanupRunning) {
      return const HomeDashboardOperation(
        title: 'データを安全に処理しています',
        message: '処理が完了すると写真を追加できます。',
      );
    }
    return null;
  }

  String? get _addDisabledReason {
    if (_photoQuotaReached) {
      return '保存上限に達しています。旅行一覧で不要な写真を整理してください。';
    }
    if (_homeOperation != null) {
      return '処理が完了すると写真を追加できます。';
    }
    if (!_pendingDeletionAvailable && _pendingDeletion != null) {
      return '削除処理の回復を確認しているため、写真を追加できません。';
    }
    return null;
  }

  List<HomeRecentTripItem> get _homeRecentTrips => _data.trips
      .take(3)
      .map(
        (trip) => HomeRecentTripItem(
          title: trip.title,
          photoCount: trip.photos.length,
          image: _photoPreview(trip.photos),
          onTap: () => _showTrip(trip),
        ),
      )
      .toList(growable: false);

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ここいった'),
        actions: <Widget>[
          KokoittaSemanticIconButton(
            onPressed: _isDisabled ? null : _showBackupMenu,
            icon: Icons.settings_outlined,
            label: '設定を開く',
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
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(KokoittaSpacing.lg),
          child: KokoittaStatePanel(
            tone: KokoittaStateTone.progress,
            title: '旅の記録を読み込んでいます',
            message: '端末内の写真と地図の状態を確認しています。',
            busy: true,
            liveRegion: true,
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KokoittaSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: KokoittaStatePanel(
              tone: KokoittaStateTone.error,
              title: '保存データを読み込めませんでした',
              message: 'バックアップがある場合は、安全に内容を確認してから復元できます。',
              primaryAction: KokoittaActionButton(
                label: 'バックアップから復元',
                icon: Icons.restore_outlined,
                onPressed: _showBackupMenu,
              ),
            ),
          ),
        ),
      );
    }
    return _tab == 0 ? _mapView(context) : _tripView();
  }

  Widget _mapView(BuildContext context) {
    final operation = _homeOperation;
    return Column(
      children: <Widget>[
        if (operation != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KokoittaSpacing.md,
              KokoittaSpacing.sm,
              KokoittaSpacing.md,
              0,
            ),
            child: KokoittaStatePanel(
              tone: KokoittaStateTone.progress,
              title: operation.title,
              message: operation.message,
              progress: operation.progress,
              busy: true,
              liveRegion: true,
              secondaryAction: operation.onCancel == null
                  ? null
                  : KokoittaActionButton(
                      label: 'キャンセル',
                      emphasis: KokoittaActionEmphasis.secondary,
                      onPressed: operation.onCancel,
                    ),
            ),
          ),
        Expanded(
          child: HomeMapDashboard(
            prefectureStates: _data.prefectureStates,
            prefectureSummary: _homePrefectureSummary,
            quota: HomeDashboardQuota(
              count: _photoCount,
              limit: _quotaStatus.limit,
            ),
            photoCount: _photoCount,
            recentTrips: _homeRecentTrips,
            addDisabledReason: _addDisabledReason,
            onAddPhotos: _cannotAddPhotos ? null : _addPhotos,
            onShowAllTrips: () => _updateState(() => _tab = 1),
            onShowPrefectureList: _isDisabled ? null : _showPrefectureList,
            onRestoreBackup: _isDisabled ? null : _showBackupMenu,
            onOpenSettings: null,
          ),
        ),
      ],
    );
  }

  void _showPrefectureList() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KokoittaSpacing.lg,
                  KokoittaSpacing.xs,
                  KokoittaSpacing.lg,
                  KokoittaSpacing.md,
                ),
                child: KokoittaSectionHeader(
                  title: '都道府県の状態を設定',
                  supportingText: _homePrefectureSummary.semanticLabel,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _prefectures.length,
                  itemBuilder: (context, index) {
                    final name = _prefectures[index];
                    final state = _data.prefectureStates[name] ?? 'unvisited';
                    final currentLabel = _prefectureStateLabel(state);
                    final nextLabel = _prefectureNextStateLabel(state);
                    return Semantics(
                      button: true,
                      label: '$name、$currentLabel。タップすると$nextLabelに変更',
                      child: ExcludeSemantics(
                        child: ListTile(
                          minTileHeight: KokoittaSize.minimumTapTarget,
                          leading: Icon(_prefectureStateIcon(state)),
                          title: Text(name),
                          subtitle: Text(currentLabel),
                          trailing: Text('$nextLabelへ'),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            unawaited(_updatePrefecture(name, state));
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _prefectureStateLabel(String state) => switch (state) {
    'visited' => '訪問済み',
    'transit' => '計画中・通過',
    _ => '未訪問',
  };

  String _prefectureNextStateLabel(String state) => switch (state) {
    'visited' => '計画中・通過',
    'transit' => '未訪問',
    _ => '訪問済み',
  };

  IconData _prefectureStateIcon(String state) => switch (state) {
    'visited' => Icons.check_circle_outline,
    'transit' => Icons.route_outlined,
    _ => Icons.circle_outlined,
  };

  Widget _tripView() {
    return KokoittaTripListView(
      items: _data.trips.map(_tripListItem).toList(growable: false),
      unassigned: _data.unassignedPhotos.isEmpty
          ? null
          : _unassignedTripListItem(),
      onAddPhotos: _cannotAddPhotos ? null : _addPhotos,
      onRestoreBackup: _isDisabled ? null : _showBackupMenu,
      disabledReason: _cannotAddPhotos ? _addDisabledReason : null,
    );
  }

  TripListItem _tripListItem(Trip trip) {
    return TripListItem(
      title: trip.title,
      photoCount: trip.photos.length,
      capturedAtLabel: formatTripCapturedAt(trip.photos),
      locationLabel: formatTripLocations(trip.photos),
      image: _photoPreview(trip.photos),
      onTap: () => _showTrip(trip),
      overflow: PopupMenuButton<String>(
        enabled: !_isDisabled,
        tooltip: '${trip.title}の管理メニュー',
        onSelected: (value) => _handleTripMenu(trip, value),
        itemBuilder: (_) => const <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'move', child: Text('旅行未設定へ移動')),
          PopupMenuItem(value: 'delete', child: Text('写真も削除')),
        ],
      ),
    );
  }

  TripListItem _unassignedTripListItem() {
    return TripListItem(
      title: '旅行未設定',
      photoCount: _data.unassignedPhotos.length,
      capturedAtLabel: formatTripCapturedAt(_data.unassignedPhotos),
      locationLabel: formatTripLocations(_data.unassignedPhotos),
      image: _photoPreview(_data.unassignedPhotos),
      onTap: _showUnassignedPhotos,
      badge: const Chip(label: Text('整理できます')),
    );
  }

  Widget _photoPreview(List<Photo> photos) {
    if (photos.isEmpty) {
      return const KokoittaPhotoPlaceholder(
        state: KokoittaPhotoPlaceholderState.empty,
        aspect: KokoittaImageAspect.wide,
      );
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
          errorBuilder: (_, _, _) => const KokoittaPhotoPlaceholder(
            state: KokoittaPhotoPlaceholderState.missing,
            aspect: KokoittaImageAspect.wide,
          ),
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
        builder: (_) => PhotoViewer(photos: photos, initialIndex: initialIndex),
      ),
    );
  }
}

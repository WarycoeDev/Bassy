// lib/screens/library_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/favorites_store.dart';
import '../services/media_scanner.dart';
import '../services/playback_controller.dart';
import '../services/playlists_store.dart';
import '../widgets/action_menu.dart';
import '../widgets/input_menu.dart';
import '../widgets/nested_navigator_scope.dart';
import '../widgets/playback_menu.dart';
import '../widgets/song_tile.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.onExitRoot});

  static NavigatorState? currentNavigator;
  static bool Function()? handleBack;

  static List<Playlist> currentAlbums = const [];
  static List<Playlist> currentArtists = const [];
  static List<Playlist> currentPodcasts = const [];

  final VoidCallback? onExitRoot;

  static void pushInLibrary(BuildContext context, Route<void> route) {
    final nav = currentNavigator;
    if (nav != null && nav.mounted) {
      nav.push(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const int _fAll = 0;
  static const int _fSongs = 1;
  static const int _fFavorites = 2;
  static const int _fPlaylists = 3;
  static const int _fAlbums = 4;
  static const int _fArtists = 5;
  static const int _fPodcasts = 6;
  static const int _fDownloads = 7;

  static const List<String> _filters = [
    'Todo',
    'Canciones',
    'Favoritos',
    'Playlists',
    'Álbumes',
    'Artistas',
    'Podcasts',
    'Descargas',
  ];

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  int _selectedFilter = _fAll;
  bool _slideFromRight = true;

  bool _reorderMode = false;
  Playlist? _inlinePlaylist;

  final Set<String> _removingIds = {};

  final Map<int, ScrollController> _scrollControllers = {};

  ScrollController _controllerFor(int index) {
    return _scrollControllers.putIfAbsent(index, () => ScrollController());
  }

  List<Song> _songs = const [];
  List<Song> _podcasts = const [];
  List<String> _scanErrors = const [];
  bool _loadingLibrary = true;
  bool _scanning = false;
  int _processedFiles = 0;
  String? _scanStatus;

  List<Playlist> _albumPlaylists = const [];
  List<Playlist> _artistPlaylists = const [];
  List<Playlist> _podcastPlaylists = const [];

  StreamSubscription<ScanProgress>? _scanSub;

  static const double _songTileExtent = 78;

  @override
  void initState() {
    super.initState();
    LibraryScreen.handleBack = _handleBack;
    FavoritesStore.instance.load();
    PlaylistsStore.instance.load();
    _startWatching();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = _navKey.currentState;
      if (nav != null) LibraryScreen.currentNavigator = nav;
    });
  }

  @override
  void dispose() {
    if (LibraryScreen.handleBack == _handleBack) {
      LibraryScreen.handleBack = null;
    }
    if (LibraryScreen.currentNavigator == _navKey.currentState) {
      LibraryScreen.currentNavigator = null;
    }
    _scanSub?.cancel();
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }

  bool _handleBack() {
    if (_inlinePlaylist != null) {
      _closeInlinePlaylist();
      return true;
    }
    if (_reorderMode) {
      setState(() => _reorderMode = false);
      return true;
    }
    return false;
  }

  Playlist _favoritesPlaylist() =>
      FavoritesStore.instance.buildPlaylist(_songs);

  Future<void> _playAll(BuildContext context, Playlist playlist) async {
    if (playlist.songs.isEmpty) return;

    final controller = PlaybackController.instance;
    if (!controller.isReady) return;

    final queueNotEmpty = controller.songs.isNotEmpty;

    if (!queueNotEmpty) {
      await controller.setQueue(
        playlist.songs,
        startIndex: 0,
        autoPlay: true,
      );
      return;
    }

    await PlaybackMenu.show(
      context,
      title: playlist.title,
      subtitle: '${playlist.count} elementos',
      coverPath: _playlistCover(playlist),
      isPodcast: playlist.kind == PlaylistKind.podcast,
      actions: [
        PlaybackMenuAction(
          icon: Icons.play_arrow,
          label: 'Reproducir ahora',
          onTap: () async {
            await controller.setQueue(
              playlist.songs,
              startIndex: 0,
              autoPlay: true,
            );
          },
        ),
        PlaybackMenuAction(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          onTap: () async {
            for (final s in playlist.songs) {
              await controller.addToQueue(s);
            }
          },
        ),
      ],
    );
  }

  void _recomputeGroups() {
    _albumPlaylists = Playlist.fromAlbums(_songs);
    _artistPlaylists = Playlist.fromArtists(_songs);
    _podcastPlaylists = Playlist.fromPodcasts(_podcasts);

    LibraryScreen.currentAlbums = _albumPlaylists;
    LibraryScreen.currentArtists = _artistPlaylists;
    LibraryScreen.currentPodcasts = _podcastPlaylists;
  }

  String? _playlistCover(Playlist playlist) {
    for (final s in playlist.songs) {
      final p = s.coverPath;
      if (p != null && p.isNotEmpty) return p;
    }
    return null;
  }

  void _startWatching() {
    final last = MediaScanner.instance.lastResult;
    setState(() {
      _loadingLibrary = last == null;
      _scanning = MediaScanner.instance.isScanning;
      _processedFiles = last?.totalCount ?? 0;
      _scanErrors = last?.errors ?? const [];
      if (last != null) {
        _songs = last.songs;
        _podcasts = last.podcasts;
      }
      _recomputeGroups();
    });

    _scanSub?.cancel();
    _scanSub = MediaScanner.instance.watchStream().listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _songs = p.songs;
          _podcasts = p.podcasts;
          _scanErrors = p.errors;
          _processedFiles = p.processedFiles;
          _loadingLibrary = false;
          _scanning = p.scanning;
          _scanStatus = p.statusMessage;
          _recomputeGroups();
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _scanErrors = [..._scanErrors, 'Error: $e'];
          _loadingLibrary = false;
          _scanning = false;
          _scanStatus = null;
        });
      },
    );
  }

  Future<void> _manualRescan() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _scanStatus = 'Escaneando biblioteca…';
      _scanErrors = const [];
      _processedFiles = 0;
    });

    final result = await MediaScanner.instance.scan();
    if (!mounted) return;
    setState(() {
      _songs = result.songs;
      _podcasts = result.podcasts;
      _scanErrors = result.errors;
      _scanning = false;
      _scanStatus = null;
      _loadingLibrary = false;
      _recomputeGroups();
    });
  }

  void _changeFilter(int index) {
    if (index == _selectedFilter) return;
    _slideFromRight = index > _selectedFilter;
    setState(() {
      _selectedFilter = index;
      _inlinePlaylist = null;
      if (index != _fFavorites) _reorderMode = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _scrollControllers[index];
      if (c != null && c.hasClients) c.jumpTo(0);
    });
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    setState(() => _inlinePlaylist = playlist);
  }

  void _closeInlinePlaylist() {
    if (_inlinePlaylist == null) return;
    setState(() => _inlinePlaylist = null);
  }

  // ============================================================
  // PLAYLISTS DE USUARIO (.bassy)
  // ============================================================

  Future<void> _createPlaylist() async {
    final result = await InputMenu.show(
      context,
      title: 'Nueva playlist',
      subtitle: 'Se guardará como archivo .bassy',
      hintText: 'Nombre de la playlist…',
      confirmLabel: 'Crear',
      cancelLabel: 'Cancelar',
      maxLength: 60,
    );

    if (result == null || !result.confirmed) return;
    final name = result.text.trim();
    if (name.isEmpty) return;

    try {
      final created = await PlaylistsStore.instance.create(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist «${created.name}» creada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la playlist: $e')),
      );
    }
  }

  void _openUserPlaylist(BuildContext context, UserPlaylist pl) {
    final all = <Song>[..._songs, ..._podcasts];
    final map = {for (final s in all) s.path: s};
    final songs =
        pl.songPaths.map((p) => map[p]).whereType<Song>().toList();

    final playlist = Playlist(
      id: 'user:${pl.id}',
      title: pl.name,
      subtitle: '${songs.length} canciones',
      kind: PlaylistKind.custom,
      songs: songs,
    );
    _openPlaylist(context, playlist);
  }

  // ============================================================
  // MENÚ DE OPCIONES DE PLAYLIST (usando ActionMenu)
  // ============================================================

  Future<void> _playlistOptions(
    BuildContext context,
    UserPlaylist pl,
  ) async {
    await ActionMenu.show(
      context,
      title: pl.name,
      subtitle: '${pl.songPaths.length} canciones · .bassy',
      fallbackIcon: Icons.queue_music,
      actions: [
        ActionMenuItem(
          icon: Icons.edit_outlined,
          label: 'Renombrar',
          onTap: () => _renameUserPlaylist(context, pl),
        ),
        ActionMenuItem(
          icon: Icons.ios_share,
          label: 'Exportar',
          onTap: () => _exportUserPlaylist(context, pl),
        ),
        ActionMenuItem(
          icon: Icons.delete_outline,
          label: 'Eliminar',
          isDestructive: true,
          onTap: () => _deleteUserPlaylist(context, pl),
        ),
      ],
    );
  }

  Future<void> _renameUserPlaylist(
    BuildContext context,
    UserPlaylist pl,
  ) async {
    final result = await InputMenu.show(
      context,
      title: 'Renombrar playlist',
      initialValue: pl.name,
      confirmLabel: 'Guardar',
      cancelLabel: 'Cancelar',
      maxLength: 60,
    );
    if (result == null || !result.confirmed) return;
    final name = result.text.trim();
    if (name.isEmpty || name == pl.name) return;

    try {
      await PlaylistsStore.instance.save(pl.copyWith(name: name));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist renombrada a «$name»')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo renombrar: $e')),
      );
    }
  }

  Future<void> _exportUserPlaylist(
    BuildContext context,
    UserPlaylist pl,
  ) async {
    try {
      final path = await PlaylistsStore.instance.exportTo(pl.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exportado a:\n$path'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar: $e')),
      );
    }
  }

  Future<void> _deleteUserPlaylist(
    BuildContext context,
    UserPlaylist pl,
  ) async {
    final confirmed = await ActionMenu.confirm(
      context,
      title: pl.name,
      subtitle: '${pl.songPaths.length} canciones',
      fallbackIcon: Icons.queue_music,
      message:
          '¿Eliminar «${pl.name}»? El archivo .bassy se borrará del disco.',
      confirmLabel: 'Eliminar',
      cancelLabel: 'Cancelar',
      confirmIcon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;

    try {
      await PlaylistsStore.instance.delete(pl.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist «${pl.name}» eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return NestedNavigatorScope(
      navigatorKey: _navKey,
      onExitRoot: widget.onExitRoot,
      handleBackButton: false,
      child: _buildLibraryHome(context),
    );
  }

  Widget _buildLibraryHome(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  FavoritesStore.instance,
                  PlaylistsStore.instance,
                ]),
                builder: (context, _) => _buildHeader(context),
              ),
            ),
            const SizedBox(height: 12),
            _buildScanProgress(context),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildFilterChips(context),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final begin =
                        Offset(_slideFromRight ? 0.15 : -0.15, 0);
                    final offset = Tween<Offset>(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: offset,
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      '$_selectedFilter:${_inlinePlaylist?.id ?? ''}',
                    ),
                    child: _buildScrollableContent(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildScrollableContent(BuildContext context) {
    final inline = _inlinePlaylist;
    if (inline != null) {
      return PlaylistDetailScreen(
        playlist: inline,
        // Favoritos y playlists .bassy necesitan el catálogo para
        // resolver/reordenar canciones en vivo.
        catalog: (inline.canReorder ||
                inline.kind == PlaylistKind.custom)
            ? <Song>[..._songs, ..._podcasts]
            : null,
        inline: true,
        onBack: _closeInlinePlaylist,
      );
    }

    switch (_selectedFilter) {
      case _fAll:
        return _buildAllTab(context);
      case _fSongs:
        return _buildSongsList(context);
      case _fPlaylists:
        return _buildPlaylistsTab(context);
      case _fAlbums:
        return _wrapInList(_fAlbums, _buildAlbumsDetailed(context));
      case _fArtists:
        return _wrapInList(_fArtists, _buildArtistsDetailed(context));
      case _fPodcasts:
        return _buildPodcastsList(context);
      case _fFavorites:
        return _buildFavoritesList(context);
      case _fDownloads:
        return _buildDownloadsTab(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _wrapInList(int filterIndex, Widget child) {
    return ListView(
      controller: _controllerFor(filterIndex),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        child,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAllTab(BuildContext context) {
    return ListView(
      controller: _controllerFor(_fAll),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        _buildSectionTitle(
          context,
          'Canciones',
          onSeeAll: () => _changeFilter(_fSongs),
        ),
        const SizedBox(height: 12),
        _buildSongs(context, limit: 5),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Playlists',
          onSeeAll: () => _changeFilter(_fPlaylists),
        ),
        const SizedBox(height: 12),
        _buildPlaylists(context),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Álbumes',
          onSeeAll: () => _changeFilter(_fAlbums),
        ),
        const SizedBox(height: 12),
        _buildAlbums(context),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Artistas',
          onSeeAll: () => _changeFilter(_fArtists),
        ),
        const SizedBox(height: 12),
        _buildArtists(context),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Podcasts',
          onSeeAll: () => _changeFilter(_fPodcasts),
        ),
        const SizedBox(height: 12),
        _buildPodcasts(context, limit: 5),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildScanProgress(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasStatus = _scanStatus != null && _scanStatus!.isNotEmpty;

    if (!_scanning && _scanErrors.isEmpty && !hasStatus) {
      return const SizedBox.shrink();
    }

    final progressText = _scanStatus ??
        'Escaneando… ${_songs.length + _podcasts.length} encontradas · '
            '$_processedFiles archivos';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scanning || hasStatus) ...[
            Row(
              children: [
                if (_scanning)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                else
                  Icon(Icons.sync, size: 14, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progressText,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_scanning) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: scheme.surfaceContainerHigh,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
          if (_scanErrors.isNotEmpty) ...[
            if (_scanning || hasStatus) const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_scanErrors.length} advertencia(s) durante el escaneo',
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _songs.length + _podcasts.length;
    final favCount = FavoritesStore.instance.count;
    final plCount = PlaylistsStore.instance.playlists.length;

    final subtitle = _scanning
        ? (_scanStatus ?? 'Escaneando… $_processedFiles archivos')
        : (total == 0
            ? 'Música local en tu dispositivo'
            : '$total elementos · $favCount favoritos · $plCount playlists');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu biblioteca',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Row(
          children: [
            _buildIconButton(
              context,
              Icons.playlist_add,
              onTap: _createPlaylist,
            ),
            const SizedBox(width: 8),
            _buildIconButton(
              context,
              Icons.refresh,
              onTap: _scanning ? null : _manualRescan,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIconButton(
    BuildContext context,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: onTap == null
              ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
              : scheme.onSurface,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedFilter;
          return GestureDetector(
            onTap: () => _changeFilter(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? scheme.primary
                    : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  _filters[index],
                  style: TextStyle(
                    color: isSelected
                        ? scheme.onPrimary
                        : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title, {
    bool showSeeAll = true,
    VoidCallback? onSeeAll,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (showSeeAll)
          GestureDetector(
            onTap: onSeeAll,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),
              child: Text(
                'Ver todo',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSongs(BuildContext context, {int? limit}) {
    if (_loadingLibrary) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_songs.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.library_music_outlined,
        title: 'No hay canciones',
        subtitle: _scanErrors.isNotEmpty
            ? _scanErrors.first
            : 'Configura tus carpetas en Ajustes y vuelve a escanear.',
      );
    }

    final extent = _songTileExtent;

    if (limit != null) {
      final scheme = Theme.of(context).colorScheme;
      const visibleRows = 4.5;
      final boxHeight = extent * visibleRows + 8;

      return Container(
        height: boxHeight,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          primary: false,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 4,
          ),
          itemCount: _songs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            final song = _songs[index];
            return SizedBox(
              height: extent,
              child: RepaintBoundary(
                key: ValueKey<String>(song.path),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SongTile(song: song),
                ),
              ),
            );
          },
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _songs.length,
      itemExtent: extent,
      itemBuilder: (context, index) {
        final song = _songs[index];
        return RepaintBoundary(
          key: ValueKey<String>(song.path),
          child: SongTile(song: song),
        );
      },
    );
  }

  Widget _buildSongsList(BuildContext context) {
    final controller = _controllerFor(_fSongs);

    if (_loadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_songs.isEmpty) {
      return ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _buildEmptyState(
            context,
            icon: Icons.library_music_outlined,
            title: 'No hay canciones',
            subtitle: _scanErrors.isNotEmpty
                ? _scanErrors.first
                : 'Configura tus carpetas en Ajustes y vuelve a escanear.',
          ),
        ],
      );
    }

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _songs.length,
      itemExtent: _songTileExtent,
      itemBuilder: (context, index) {
        final song = _songs[index];
        return RepaintBoundary(
          key: ValueKey<String>(song.path),
          child: SongTile(song: song),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Favoritos
  // -------------------------------------------------------------------------

  Widget _buildFavoritesList(BuildContext context) {
    final controller = _controllerFor(_fFavorites);

    if (_loadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }

    return AnimatedBuilder(
      animation: FavoritesStore.instance,
      builder: (context, _) {
        final playlist = _favoritesPlaylist();
        final scheme = Theme.of(context).colorScheme;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  _buildFavoritesCover(context, playlist),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.title,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${playlist.count} elementos · '
                          '${playlist.totalDurationLabel}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: playlist.songs.isEmpty
                                  ? null
                                  : () => _playAll(context, playlist),
                              icon: const Icon(
                                Icons.play_arrow,
                                size: 20,
                              ),
                              label: const Text('Reproducir todo'),
                            ),
                            const SizedBox(width: 8),
                            if (playlist.songs.length > 1)
                              IconButton.filledTonal(
                                onPressed: () {
                                  setState(() {
                                    _reorderMode = !_reorderMode;
                                  });
                                },
                                tooltip: _reorderMode
                                    ? 'Listo'
                                    : 'Reordenar',
                                icon: Icon(
                                  _reorderMode
                                      ? Icons.check
                                      : Icons.swap_vert,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: playlist.songs.isEmpty
                  ? ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildEmptyState(
                          context,
                          icon: Icons.favorite_border,
                          title: 'Aún no tienes favoritos',
                          subtitle:
                              'Usa el menú de una canción para añadirla a favoritos.',
                          showRescan: false,
                        ),
                      ],
                    )
                  : ReorderableListView.builder(
                      scrollController: controller,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: playlist.songs.length,
                      onReorder: FavoritesStore.instance.reorder,
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, _) {
                            final elevation =
                                Tween<double>(begin: 0, end: 6)
                                    .evaluate(animation);
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: Material(
                                elevation: elevation,
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  SongTile.tileRadius,
                                ),
                                clipBehavior: Clip.antiAlias,
                                shadowColor: Colors.black.withValues(
                                  alpha: 0.5,
                                ),
                                child: child,
                              ),
                            );
                          },
                        );
                      },
                      itemBuilder: (context, index) {
                        final song = playlist.songs[index];
                        final bool isReorder = _reorderMode;
                        final bool isRemoving =
                            _removingIds.contains(song.path);

                        return Dismissible(
                          key: ValueKey<String>('fav:${song.path}'),
                          direction: isReorder || isRemoving
                              ? DismissDirection.none
                              : DismissDirection.startToEnd,
                          background: Container(
                            alignment: Alignment.centerLeft,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(
                                SongTile.tileRadius,
                              ),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: scheme.onErrorContainer,
                              size: 24,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            final confirmed = await ActionMenu.confirm(
                              context,
                              title: song.title,
                              subtitle: song.subtitle,
                              coverPath: song.coverPath,
                              fallbackIcon:
                                  song.kind == MediaKind.podcast
                                      ? Icons.mic
                                      : Icons.music_note,
                              message:
                                  '«${song.title}» se eliminará de Favoritos.',
                              confirmLabel: 'Quitar',
                            );

                            if (confirmed) {
                              setState(
                                () => _removingIds.add(song.path),
                              );
                              await Future.delayed(
                                const Duration(milliseconds: 300),
                              );
                              await FavoritesStore.instance.remove(song);
                              if (mounted) {
                                setState(
                                  () => _removingIds.remove(song.path),
                                );
                              }
                              return false;
                            }
                            return false;
                          },
                          onDismissed: (_) {},
                          child: SongTile(
                            song: song,
                            queueContext: playlist.songs,
                            queueIndex: index,
                            reorderMode: isReorder,
                            reorderIndex: index,
                            isRemoving: isRemoving,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFavoritesCover(BuildContext context, Playlist playlist) {
    final scheme = Theme.of(context).colorScheme;
    final coverPath = _playlistCover(playlist);

    Widget fallback() => Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surfaceContainerHigh,
                scheme.surfaceContainer,
              ],
            ),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Icon(
            Icons.favorite,
            size: 44,
            color: scheme.onSurfaceVariant,
          ),
        );

    if (coverPath == null) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.file(
        File(coverPath),
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    bool showRescan = true,
    VoidCallback? action,
    String? actionLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: action,
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel ?? 'Crear'),
            ),
          ] else if (showRescan) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _scanning ? null : _manualRescan,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Escanear de nuevo'),
            ),
          ],
        ],
      ),
    );
  }

    Widget _buildPlaylists(BuildContext context) {
    if (_loadingLibrary) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: PlaylistsStore.instance,
      builder: (context, _) {
        final playlists = PlaylistsStore.instance.playlists;
        if (playlists.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.queue_music_outlined,
            title: 'Aún no hay playlists',
            subtitle:
                'Crea tu primera playlist; se guardará como archivo .bassy.',
            showRescan: false,
            action: _createPlaylist,
            actionLabel: 'Crear playlist',
          );
        }
        final scheme = Theme.of(context).colorScheme;
        return Column(
          children: playlists.map((pl) {
            final coverPath = _userPlaylistCover(pl);
            return GestureDetector(
              onTap: () => _openUserPlaylist(context, pl),
              onLongPress: () => _playlistOptions(context, pl),
              child: _buildDetailCard(
                context: context,
                leading: _buildUserPlaylistCover(
                  context,
                  coverPath: coverPath,
                ),
                title: pl.name,
                meta: '${pl.songPaths.length} canciones · .bassy',
                trailing: Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Busca la primera carátula disponible entre las canciones de la
  /// playlist de usuario (resolviendo `songPaths` contra el catálogo
  /// actual de `_songs` + `_podcasts`).
  String? _userPlaylistCover(UserPlaylist pl) {
    if (pl.songPaths.isEmpty) return null;
    // Índice path → Song para no recorrer el catálogo por cada path.
    final map = <String, Song>{
      for (final s in _songs) s.path: s,
      for (final s in _podcasts) s.path: s,
    };
    for (final p in pl.songPaths) {
      final song = map[p];
      final cover = song?.coverPath;
      if (cover != null && cover.isNotEmpty) return cover;
    }
    return null;
  }

  /// Carátula cuadrada 64×64 con esquinas redondeadas; si no hay
  /// imagen, muestra el icono `queue_music` con el mismo estilo que
  /// las demás tarjetas del listado.
  Widget _buildUserPlaylistCover(
    BuildContext context, {
    required String? coverPath,
  }) {
    final scheme = Theme.of(context).colorScheme;

    Widget fallback() => Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Icon(
            Icons.queue_music,
            color: scheme.onSurfaceVariant,
            size: 30,
          ),
        );

    if (coverPath == null) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(coverPath),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        cacheWidth: 192,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }

  Widget _buildPlaylistsTab(BuildContext context) {
    return ListView(
      controller: _controllerFor(_fPlaylists),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Playlists',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _createPlaylist,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPlaylists(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDownloadsTab(BuildContext context) {
    return ListView(
      controller: _controllerFor(_fDownloads),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        _buildDownloads(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDownloads(BuildContext context) {
    return _buildEmptyState(
      context,
      icon: Icons.download_outlined,
      title: 'Sin descargas',
      subtitle: 'Aún no hay descargas registradas.',
      showRescan: false,
    );
  }

  Widget _buildAlbums(BuildContext context) {
    if (_loadingLibrary) return const SizedBox.shrink();
    final albums = _albumPlaylists;
    if (albums.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.album_outlined,
        title: 'No hay álbumes',
        subtitle:
            'Las canciones necesitan metadatos de álbum para agruparse.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final list = albums.take(10).toList();
    return SizedBox(
      height: 192,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        itemBuilder: (context, index) {
          final album = list[index];
          final coverPath = _playlistCover(album);
          return GestureDetector(
            onTap: () => _openPlaylist(context, album),
            child: Container(
              width: 150,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCoverImageOrIcon(
                          context,
                          coverPath: coverPath,
                          fallbackIcon: Icons.album,
                          iconSize: 52,
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow,
                              color: scheme.onPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlbumsDetailed(BuildContext context) {
    if (_loadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }
    final albums = _albumPlaylists;
    if (albums.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.album_outlined,
        title: 'No hay álbumes',
        subtitle: 'Las canciones necesitan metadatos de álbum.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: albums.map((album) {
        final coverPath = _playlistCover(album);
        return GestureDetector(
          onTap: () => _openPlaylist(context, album),
          child: _buildDetailCard(
            context: context,
            leading: _buildSquareCover(
              context,
              coverPath: coverPath,
              fallbackIcon: Icons.album,
              size: 64,
              rounded: 10,
            ),
            title: album.title,
            meta: '${album.count} pistas · ${album.totalDurationLabel}',
            trailing: Icon(
              Icons.chevron_right,
              color: scheme.onSurfaceVariant,
              size: 24,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildArtists(BuildContext context) {
    if (_loadingLibrary) return const SizedBox.shrink();
    final artists = _artistPlaylists;
    if (artists.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.person_outline,
        title: 'No hay artistas',
        subtitle:
            'Las canciones necesitan metadatos de artista para agruparse.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final list = artists.take(10).toList();
    return SizedBox(
      height: 136,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        itemBuilder: (context, index) {
          final artist = list[index];
          final coverPath = _playlistCover(artist);
          return GestureDetector(
            onTap: () => _openPlaylist(context, artist),
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: _buildCoverImageOrIcon(
                        context,
                        coverPath: coverPath,
                        fallbackIcon: Icons.person,
                        iconSize: 38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    artist.title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtistsDetailed(BuildContext context) {
    if (_loadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }
    final artists = _artistPlaylists;
    if (artists.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.person_outline,
        title: 'No hay artistas',
        subtitle: 'Las canciones necesitan metadatos de artista.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: artists.map((artist) {
        final coverPath = _playlistCover(artist);
        return GestureDetector(
          onTap: () => _openPlaylist(context, artist),
          child: _buildDetailCard(
            context: context,
            leading: ClipOval(
              child: SizedBox(
                width: 64,
                height: 64,
                child: _buildCoverImageOrIcon(
                  context,
                  coverPath: coverPath,
                  fallbackIcon: Icons.person,
                  iconSize: 32,
                ),
              ),
            ),
            title: artist.title,
            trailing: Icon(
              Icons.chevron_right,
              color: scheme.onSurfaceVariant,
              size: 24,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPodcasts(BuildContext context, {int? limit}) {
    if (_loadingLibrary) return const SizedBox.shrink();
    final podcasts = _podcastPlaylists;
    if (podcasts.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.podcasts_outlined,
        title: 'No hay podcasts',
        subtitle: 'Agrega carpetas de podcasts en Ajustes.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final list = limit == null ? podcasts : podcasts.take(limit).toList();
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        itemBuilder: (context, index) {
          final pod = list[index];
          final coverPath = _playlistCover(pod);
          return GestureDetector(
            onTap: () => _openPlaylist(context, pod),
            child: Container(
              width: 220,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: _buildCoverImageOrIcon(
                        context,
                        coverPath: coverPath,
                        fallbackIcon: Icons.mic,
                        iconSize: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          pod.title,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPodcastsList(BuildContext context) {
    final controller = _controllerFor(_fPodcasts);

    if (_loadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }
    final podcasts = _podcastPlaylists;
    if (podcasts.isEmpty) {
      return ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _buildEmptyState(
            context,
            icon: Icons.podcasts_outlined,
            title: 'No hay podcasts',
            subtitle: 'Agrega carpetas de podcasts en Ajustes.',
          ),
        ],
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: podcasts.length,
      itemExtent: 90,
      itemBuilder: (context, index) {
        final pod = podcasts[index];
        final coverPath = _playlistCover(pod);
        return RepaintBoundary(
          key: ValueKey<String>(pod.id),
          child: GestureDetector(
            onTap: () => _openPlaylist(context, pod),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: _buildCoverImageOrIcon(
                        context,
                        coverPath: coverPath,
                        fallbackIcon: Icons.mic,
                        iconSize: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          pod.title,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverImageOrIcon(
    BuildContext context, {
    required String? coverPath,
    required IconData fallbackIcon,
    required double iconSize,
  }) {
    if (coverPath != null) {
      return Image.file(
        File(coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            _buildIconFill(context, icon: fallbackIcon, iconSize: iconSize),
      );
    }
    return _buildIconFill(context, icon: fallbackIcon, iconSize: iconSize);
  }

  Widget _buildIconFill(
    BuildContext context, {
    required IconData icon,
    required double iconSize,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: scheme.onSurfaceVariant),
    );
  }

  Widget _buildSquareCover(
    BuildContext context, {
    required String? coverPath,
    required IconData fallbackIcon,
    required double size,
    required double rounded,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(rounded),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: _buildCoverImageOrIcon(
          context,
          coverPath: coverPath,
          fallbackIcon: fallbackIcon,
          iconSize: size * 0.45,
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required BuildContext context,
    required Widget leading,
    required String title,
    String? subtitle,
    String? meta,
    required Widget trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (meta != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        meta,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
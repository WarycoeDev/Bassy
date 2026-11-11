import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/media_scanner.dart';
import '../widgets/nested_navigator_scope.dart';
import '../widgets/song_tile.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.onExitRoot});

  /// Navigator anidado ACTUAL de Library.
  static NavigatorState? currentNavigator;

  static List<Playlist> currentAlbums = const [];
  static List<Playlist> currentArtists = const [];
  static List<Playlist> currentPodcasts = const [];

  /// Se invoca cuando el usuario pulsa atrás estando ya en la raíz de
  /// Library (no hay rutas internas que popear). El padre (AppShell) decide
  /// qué hacer: volver a Inicio, salir de la app, etc.
  /// Si es null, el gesto de atrás se ignora (comportamiento conservador).
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
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  int _selectedFilter = 0;
  bool _slideFromRight = true;

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

  final List<String> _filters = const [
    'Todo',
    'Canciones',
    'Playlists',
    'Álbumes',
    'Artistas',
    'Podcasts',
    'Descargas',
  ];

  static const double _songTileExtent = 78;

  @override
  void initState() {
    super.initState();
    _startWatching();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = _navKey.currentState;
      if (nav != null) LibraryScreen.currentNavigator = nav;
    });
  }

  @override
  void dispose() {
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

  // -------------------------------------------------------------------------
  // Agrupaciones / carátulas
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Ciclo de escaneo
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Navegación
  // -------------------------------------------------------------------------

  void _changeFilter(int index) {
    if (index == _selectedFilter) return;
    _slideFromRight = index > _selectedFilter;
    setState(() => _selectedFilter = index);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _scrollControllers[index];
      if (c != null && c.hasClients) c.jumpTo(0);
    });
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    final nav = _navKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlist: playlist),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // NestedNavigatorScope gestiona el back:
    //  - Si hay rutas internas → las popea.
    //  - Si estamos en la raíz → delega en onExitRoot.
    return NestedNavigatorScope(
      navigatorKey: _navKey,
      onExitRoot: widget.onExitRoot,
      child: _buildLibraryHome(context),
    );
  }

  // =========================================================================
  // A partir de aquí, TODO EL RESTO DEL ARCHIVO PERMANECE IGUAL.
  // =========================================================================

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
              child: _buildHeader(context),
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
                    final begin = Offset(_slideFromRight ? 0.15 : -0.15, 0);
                    final offset = Tween<Offset>(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_selectedFilter),
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
    if (_selectedFilter == 0) {
      return ListView(
        controller: _controllerFor(0),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 8),
          _buildSectionTitle(context, 'Canciones',
              onSeeAll: () => _changeFilter(1)),
          const SizedBox(height: 12),
          _buildSongs(context, limit: 5),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Playlists',
              onSeeAll: () => _changeFilter(2)),
          const SizedBox(height: 12),
          _buildPlaylists(context),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Álbumes',
              onSeeAll: () => _changeFilter(3)),
          const SizedBox(height: 12),
          _buildAlbums(context),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Artistas',
              onSeeAll: () => _changeFilter(4)),
          const SizedBox(height: 12),
          _buildArtists(context),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Podcasts',
              onSeeAll: () => _changeFilter(5)),
          const SizedBox(height: 12),
          _buildPodcasts(context, limit: 5),
          const SizedBox(height: 24),
        ],
      );
    }

    if (_selectedFilter == 1) return _buildSongsList(context);
    if (_selectedFilter == 5) return _buildPodcastsList(context);

    return ListView(
      controller: _controllerFor(_selectedFilter),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        ..._buildFilteredContent(context),
        const SizedBox(height: 24),
      ],
    );
  }

  List<Widget> _buildFilteredContent(BuildContext context) {
    switch (_selectedFilter) {
      case 2:
        return [_buildPlaylistsDetailed(context)];
      case 3:
        return [_buildAlbumsDetailed(context)];
      case 4:
        return [_buildArtistsDetailed(context)];
      case 6:
        return [_buildDownloads(context)];
      default:
        return [];
    }
  }

  Widget _buildScanProgress(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_scanning && _scanErrors.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scanning) ...[
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _scanStatus ??
                        'Escaneando… ${_songs.length + _podcasts.length} encontradas · $_processedFiles archivos',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
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
          if (_scanErrors.isNotEmpty) ...[
            if (_scanning) const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: scheme.onErrorContainer),
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
                _scanning
                    ? (_scanStatus ?? 'Escaneando… $_processedFiles archivos')
                    : (total == 0
                        ? 'Música local en tu dispositivo'
                        : '$total elementos'),
                style:
                    TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Row(
          children: [
            _buildIconButton(context, Icons.search),
            const SizedBox(width: 12),
            _buildIconButton(context, Icons.sort),
            const SizedBox(width: 12),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isSelected ? scheme.primary : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  _filters[index],
                  style: TextStyle(
                    color:
                        isSelected ? scheme.onPrimary : scheme.onSurface,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
    final controller = _controllerFor(1);

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

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
            style:
                TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _scanning ? null : _manualRescan,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Escanear de nuevo'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylists(BuildContext context) {
    return _buildEmptyState(
      context,
      icon: Icons.queue_music,
      title: 'Sin playlists',
      subtitle: 'Las playlists personalizadas llegarán pronto.',
    );
  }

  Widget _buildPlaylistsDetailed(BuildContext context) =>
      _buildPlaylists(context);

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
                  const SizedBox(height: 2),
                  Text(
                    '${album.subtitle} · ${album.count}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
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
            subtitle: album.subtitle,
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
                  Text(
                    '${artist.count} canciones',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
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
            subtitle: artist.subtitle,
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
                        const SizedBox(height: 4),
                        Text(
                          '${pod.count} episodios · ${pod.totalDurationLabel}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
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
    final controller = _controllerFor(5);

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
                        const SizedBox(height: 4),
                        Text(
                          '${pod.count} episodios · ${pod.totalDurationLabel}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloads(BuildContext context) {
    return _buildEmptyState(
      context,
      icon: Icons.download_outlined,
      title: 'Sin descargas',
      subtitle: 'Aún no hay descargas registradas.',
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
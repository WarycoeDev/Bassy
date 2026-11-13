// lib/screens/playlist_detail_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/favorites_store.dart';
import '../services/playback_controller.dart';
import '../services/playlists_store.dart';
import '../widgets/action_menu.dart';
import '../widgets/playback_menu.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  /// Catálogo completo de canciones. Necesario para reconstruir en vivo
  /// Favoritos y playlists `.bassy` (resolver `songPaths` y reordenar).
  final List<Song>? catalog;

  final bool inline;
  final VoidCallback? onBack;
  final bool showBackButton;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.catalog,
    this.inline = false,
    this.onBack,
    this.showBackButton = true,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  bool _reorderMode = false;
  final Set<String> _removingIds = {};

  /// Snapshot local mientras se reordena. Evita que el `AnimatedBuilder`
  /// externo reconstruya la lista en cada `notifyListeners` del store,
  /// que era lo que causaba el "parpadeo" entre posición vieja y nueva.
  List<Song>? _localSongs;

  bool get _isFavorites => widget.playlist.kind == PlaylistKind.favorites;

  bool get _isUserPlaylist => widget.playlist.kind == PlaylistKind.custom;

  String? get _userId {
    final id = widget.playlist.id;
    if (!_isUserPlaylist) return null;
    return id.startsWith('user:') ? id.substring('user:'.length) : id;
  }

  bool get _canReorder => _isFavorites || _isUserPlaylist;

  // ============================================================
  // Playlist "viva"
  // ============================================================

  Playlist _livePlaylist() {
    // En reorderMode usamos el snapshot local (evita parpadeos).
    if (_reorderMode && _localSongs != null) {
      final songs = _localSongs!;
      return Playlist(
        id: widget.playlist.id,
        title: widget.playlist.title,
        subtitle: '${songs.length} canciones',
        kind: widget.playlist.kind,
        songs: List<Song>.unmodifiable(songs),
      );
    }

    if (_isFavorites) {
      final cat = widget.catalog;
      if (cat == null) return widget.playlist;
      return FavoritesStore.instance.buildPlaylist(cat);
    }

    if (_isUserPlaylist) {
      final uid = _userId;
      if (uid == null) return widget.playlist;
      final pl = PlaylistsStore.instance.byId(uid);
      if (pl == null) return widget.playlist;
      final cat = widget.catalog ?? const <Song>[];
      final map = {for (final s in cat) s.path: s};
      final songs =
          pl.songPaths.map((p) => map[p]).whereType<Song>().toList();
      return Playlist(
        id: widget.playlist.id,
        title: pl.name,
        subtitle: '${songs.length} canciones',
        kind: PlaylistKind.custom,
        songs: songs,
      );
    }

    return widget.playlist;
  }

  // ============================================================
  // Reorder / remove
  // ============================================================

  void _enterReorderMode(Playlist live) {
    setState(() {
      _reorderMode = true;
      _localSongs = List<Song>.of(live.songs);
    });
  }

  Future<void> _exitReorderMode() async {
    final snapshot = _localSongs;
    if (snapshot == null) {
      setState(() => _reorderMode = false);
      return;
    }

    // Volcamos el orden final al store de una sola vez.
    if (_isFavorites) {
      await FavoritesStore.instance.reorderToPaths(
        snapshot.map((s) => s.path).toList(),
      );
    } else {
      final uid = _userId;
      if (uid != null) {
        await PlaylistsStore.instance.reorderToPaths(
          uid,
          snapshot.map((s) => s.path).toList(),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _reorderMode = false;
      _localSongs = null;
    });
  }

  void _onLocalReorder(int oldIndex, int newIndex) {
    final list = _localSongs;
    if (list == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    setState(() {
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
    });
  }

  Future<void> _removeAt(Song song, int index) async {
    if (_isFavorites) {
      setState(() => _removingIds.add(song.path));
      await Future.delayed(const Duration(milliseconds: 300));
      await FavoritesStore.instance.remove(song);
      if (mounted) setState(() => _removingIds.remove(song.path));
      return;
    }
    final uid = _userId;
    if (uid == null) return;
    setState(() => _removingIds.add(song.path));
    await Future.delayed(const Duration(milliseconds: 300));
    await PlaylistsStore.instance.removeAt(uid, index);
    if (mounted) setState(() => _removingIds.remove(song.path));
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Durante reorderMode NO escuchamos al store: el snapshot local
    // manda. Así evitamos parpadeos por rebuilds intermedios.
    final Listenable? listenable = _reorderMode
        ? null
        : (_isFavorites
            ? FavoritesStore.instance
            : (_isUserPlaylist ? PlaylistsStore.instance : null));

    Widget bodyFor(Playlist live) {
      if (widget.inline) {
        return SafeArea(
          top: false,
          child: _buildInlineBody(context, scheme, live),
        );
      }
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) nav.pop();
        },
        child: Scaffold(
          backgroundColor: scheme.surface,
          appBar: widget.showBackButton
              ? AppBar(
                  backgroundColor: scheme.surface,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Atrás',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  title: Text(
                    widget.playlist.title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : null,
          body: SafeArea(
            child: _buildBody(context, scheme, live),
          ),
        ),
      );
    }

    if (listenable == null) {
      return bodyFor(_livePlaylist());
    }
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) => bodyFor(_livePlaylist()),
    );
  }

  // ============================================================
  // Reproducir todo
  // ============================================================

  Future<void> _playAll(BuildContext context, Playlist live) async {
    if (live.songs.isEmpty) return;

    final controller = PlaybackController.instance;
    if (!controller.isReady) {
      debugPrint('PlaylistDetailScreen: PlaybackController no inicializado');
      return;
    }

    final queueKind = live.kind == PlaylistKind.podcast
        ? MediaKind.podcast
        : MediaKind.music;

    final targetQueueSongs = controller.songsOf(queueKind);
    final queueHasContent = targetQueueSongs.isNotEmpty;

    if (!queueHasContent) {
      await controller.switchToQueue(queueKind);
      await controller.setQueueOf(
        queueKind,
        live.songs,
        startIndex: 0,
        autoPlay: true,
      );
      return;
    }

    await PlaybackMenu.show(
      context,
      title: live.title,
      subtitle: '${live.count} elementos',
      coverPath: _firstCover(live),
      isPodcast: live.kind == PlaylistKind.podcast,
      actions: [
        PlaybackMenuAction(
          icon: Icons.play_arrow,
          label: 'Sobreescribir cola y reproducir',
          onTap: () async {
            await controller.switchToQueue(queueKind);
            await controller.setQueueOf(
              queueKind,
              live.songs,
              startIndex: 0,
              autoPlay: true,
            );
          },
        ),
        PlaybackMenuAction(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          onTap: () async {
            for (final s in live.songs) {
              await controller.addToQueueOf(queueKind, s);
            }
          },
        ),
      ],
    );
  }

  // ============================================================
  // Cuerpo pantalla completa
  // ============================================================

  Widget _buildBody(
    BuildContext context,
    ColorScheme scheme,
    Playlist live,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              _buildCover(context, live),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      live.title,
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
                      '${live.count} elementos · ${live.totalDurationLabel}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildHeaderActions(context, live),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: live.songs.isEmpty
              ? Center(
                  child: Text(
                    'Sin elementos',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : _buildSongList(context, scheme, live),
        ),
      ],
    );
  }

  // ============================================================
  // Cuerpo inline
  // ============================================================

  Widget _buildInlineBody(
    BuildContext context,
    ColorScheme scheme,
    Playlist live,
  ) {
    final header = Row(
      children: [
        _buildCover(context, live),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                live.title,
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
                '${live.count} elementos · ${live.totalDurationLabel}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              _buildHeaderActions(context, live),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: header,
            ),
            if (widget.onBack != null)
              Positioned(
                top: 10,
                left: 6,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: Colors.black54,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onBack,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: live.songs.isEmpty
              ? Center(
                  child: Text(
                    'Sin elementos',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : _buildSongList(context, scheme, live),
        ),
      ],
    );
  }

  Widget _buildHeaderActions(BuildContext context, Playlist live) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: live.songs.isEmpty
              ? null
              : () => _playAll(context, live),
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text('Reproducir todo'),
        ),
        if (_canReorder && live.songs.length > 1) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () {
              if (_reorderMode) {
                _exitReorderMode();
              } else {
                _enterReorderMode(live);
              }
            },
            tooltip: _reorderMode ? 'Listo' : 'Reordenar',
            icon: Icon(
              _reorderMode ? Icons.check : Icons.swap_vert,
              size: 20,
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // Lista de canciones
  // ============================================================

  Widget _buildSongList(
    BuildContext context,
    ColorScheme scheme,
    Playlist live,
  ) {
    // Modo reordenar: usa el snapshot local, sin escuchar al store.
    if (_canReorder && _reorderMode) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: live.songs.length,
        onReorder: _onLocalReorder,
        buildDefaultDragHandles: false,
        // Sin AnimatedBuilder: elevación fija para evitar repaints
        // por frame durante el arrastre.
        proxyDecorator: (child, index, animation) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              elevation: 6,
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(SongTile.tileRadius),
              clipBehavior: Clip.antiAlias,
              shadowColor: Colors.black.withValues(alpha: 0.5),
              child: child,
            ),
          );
        },
        itemBuilder: (context, index) {
          final song = live.songs[index];
          return RepaintBoundary(
            key: ValueKey<String>(song.path),
            child: SongTile(
              song: song,
              queueContext: live.songs,
              queueIndex: index,
              reorderMode: true,
              reorderIndex: index,
            ),
          );
        },
      );
    }

    // Modo normal con swipe-to-delete para Favoritos y .bassy.
    if (_canReorder) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: live.songs.length,
        itemBuilder: (context, index) {
          final song = live.songs[index];
          final isRemoving = _removingIds.contains(song.path);

          return Dismissible(
            key: ValueKey<String>('swipe:${song.path}'),
            direction: isRemoving
                ? DismissDirection.none
                : DismissDirection.startToEnd,
            background: Container(
              alignment: Alignment.centerLeft,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius:
                    BorderRadius.circular(SongTile.tileRadius),
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
                fallbackIcon: song.kind == MediaKind.podcast
                    ? Icons.mic
                    : Icons.music_note,
                message:
                    '«${song.title}» se eliminará de «${live.title}».',
                confirmLabel: 'Quitar',
              );
              if (confirmed) {
                await _removeAt(song, index);
              }
              return false;
            },
            onDismissed: (_) {},
            child: SongTile(
              song: song,
              queueContext: live.songs,
              queueIndex: index,
              isRemoving: isRemoving,
            ),
          );
        },
      );
    }

    // Lista plana (álbum/artista/podcast).
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: live.songs.length,
      itemExtent: 78,
      itemBuilder: (context, index) {
        final song = live.songs[index];
        return RepaintBoundary(
          key: ValueKey<String>(song.path),
          child: SongTile(
            song: song,
            queueContext: live.songs,
            queueIndex: index,
          ),
        );
      },
    );
  }

  // ============================================================
  // Carátula
  // ============================================================

  Widget _buildCover(BuildContext context, Playlist live) {
    final coverPath = _firstCover(live);

    if (coverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(coverPath),
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackCover(context, live),
        ),
      );
    }

    return _buildFallbackCover(context, live);
  }

  String? _firstCover(Playlist live) {
    for (final s in live.songs) {
      final p = s.coverPath;
      if (p != null && p.isNotEmpty) return p;
    }
    return null;
  }

  Widget _buildFallbackCover(BuildContext context, Playlist live) {
    final scheme = Theme.of(context).colorScheme;
    final IconData icon;
    switch (live.kind) {
      case PlaylistKind.album:
        icon = Icons.album;
        break;
      case PlaylistKind.artist:
        icon = Icons.person;
        break;
      case PlaylistKind.podcast:
        icon = Icons.podcasts;
        break;
      case PlaylistKind.favorites:
        icon = Icons.favorite;
        break;
      case PlaylistKind.custom:
        icon = Icons.queue_music;
        break;
    }
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surfaceContainerHigh, scheme.surfaceContainer],
        ),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(icon, size: 44, color: scheme.onSurfaceVariant),
    );
  }
}
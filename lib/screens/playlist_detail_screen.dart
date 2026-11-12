// lib/screens/playlist_detail_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/favorites_store.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  /// Catálogo completo de canciones. Solo se usa cuando
  /// `playlist.canReorder` es true (favoritos), para reconstruir la
  /// playlist desde `FavoritesStore` en cada rebuild y reflejar el
  /// orden guardado en vivo. Para álbumes/artistas/podcasts es null.
  final List<Song>? catalog;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.catalog,
  });

  /// Primera carátula disponible entre las canciones de la playlist.
  String? get _coverPath {
    for (final s in playlist.songs) {
      final p = s.coverPath;
      if (p != null && p.isNotEmpty) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Atrás',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            playlist.title,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          // En modo reordenable escuchamos al store para que el header
          // (contador, duración) también se actualice al reordenar.
          child: playlist.canReorder
              ? AnimatedBuilder(
                  animation: FavoritesStore.instance,
                  builder: (context, _) =>
                      _buildBody(context, scheme, _livePlaylist()),
                )
              : _buildBody(context, scheme, playlist),
        ),
      ),
    );
  }

  /// Para favoritos, reconstruye la playlist desde el store usando
  /// el catálogo. Para el resto devuelve la playlist original.
  Playlist _livePlaylist() {
    final cat = catalog;
    if (!playlist.canReorder || cat == null) return playlist;
    return FavoritesStore.instance.buildPlaylist(cat);
  }

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
                      live.subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
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
                    FilledButton.icon(
                      onPressed: live.songs.isEmpty ? null : () {},
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: const Text('Reproducir todo'),
                    ),
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

  Widget _buildSongList(
    BuildContext context,
    ColorScheme scheme,
    Playlist live,
  ) {
    if (live.canReorder) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: live.songs.length,
        onReorder: FavoritesStore.instance.reorder,
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 6,
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final song = live.songs[index];
          return RepaintBoundary(
            key: ValueKey<String>(song.path),
            child: SongTile(song: song),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: live.songs.length,
      itemExtent: 78,
      itemBuilder: (context, index) {
        final song = live.songs[index];
        return RepaintBoundary(
          key: ValueKey<String>(song.path),
          child: SongTile(song: song),
        );
      },
    );
  }

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
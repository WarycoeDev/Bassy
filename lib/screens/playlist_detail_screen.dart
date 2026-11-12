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

  /// Si es true, se renderiza solo el cuerpo (cabecera + lista) sin
  /// Scaffold/AppBar/PopScope, para poder embeberlo en otra pantalla
  /// (p. ej. dentro de una pestaña de LibraryScreen).
  final bool inline;

  /// Callback opcional para el botón "atrás" en modo inline.
  final VoidCallback? onBack;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.catalog,
    this.inline = false,
    this.onBack,
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

    // ----- Modo embebido (inline) -----
    if (inline) {
      return SafeArea(
        top: false,
        child: playlist.canReorder
            ? AnimatedBuilder(
                animation: FavoritesStore.instance,
                builder: (context, _) =>
                    _buildInlineBody(context, scheme, _livePlaylist()),
              )
            : _buildInlineBody(context, scheme, playlist),
      );
    }

    // ----- Modo pantalla completa (original) -----
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

  // ============================================================
  // CUERPO — MODO PANTALLA COMPLETA
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

  // ============================================================
  // CUERPO — MODO INLINE (embebido en una pestaña)
  // ============================================================

  Widget _buildInlineBody(
    BuildContext context,
    ColorScheme scheme,
    Playlist live,
  ) {
    // Cabecera: carátula pegada a la izquierda + textos.
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
              FilledButton.icon(
                onPressed: live.songs.isEmpty ? null : () {},
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Reproducir todo'),
              ),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stack: la cabecera ocupa el layout normal; el botón atrás
        // flota ENCIMA de la esquina superior izquierda de la carátula
        // con fondo circular semitransparente + sombra para que se vea.
        // Se coloca pegado al borde izquierdo de la carátula (left: 6)
        // pero sin salirse de ella.
        Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: header,
            ),
            if (onBack != null)
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
                    onTap: onBack,
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

  // ============================================================
  // LISTA DE CANCIONES (compartida por ambos modos)
  // ============================================================

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

  // ============================================================
  // CARÁTULA
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
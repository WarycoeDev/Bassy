import 'dart:io';

import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

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

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  _buildCover(context),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.subtitle,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${playlist.count} elementos · ${playlist.totalDurationLabel}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: playlist.songs.isEmpty ? null : () {},
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
              child: playlist.songs.isEmpty
                  ? Center(
                      child: Text(
                        'Sin elementos',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: playlist.songs.length,
                      itemExtent: 78,
                      itemBuilder: (context, index) {
                        final song = playlist.songs[index];
                        return RepaintBoundary(
                          key: ValueKey<String>(song.path),
                          child: SongTile(song: song),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverPath = _coverPath;

    if (coverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(coverPath),
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackCover(context),
        ),
      );
    }

    return _buildFallbackCover(context);
  }

  Widget _buildFallbackCover(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final IconData icon;
    switch (playlist.kind) {
      case PlaylistKind.album:
        icon = Icons.album;
        break;
      case PlaylistKind.artist:
        icon = Icons.person;
        break;
      case PlaylistKind.podcast:
        icon = Icons.podcasts;
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
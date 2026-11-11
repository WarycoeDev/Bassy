// lib/widgets/song_tile.dart
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';
import 'song_context_menu.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  final bool showPlayingIndicator;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.onMore,
    this.showPlayingIndicator = true,
  });

  static final Map<String, _CoverCacheEntry> _coverCache = {};

  static bool _hasCover(String? cover) {
    if (cover == null || cover.isEmpty) return false;
    try {
      final file = File(cover);
      if (!file.existsSync()) return false;

      final mtime = file.lastModifiedSync().millisecondsSinceEpoch;
      final cached = _coverCache[cover];
      if (cached != null && cached.mtime == mtime) return cached.exists;

      _coverCache[cover] = _CoverCacheEntry(exists: true, mtime: mtime);
      return true;
    } catch (_) {
      _coverCache.remove(cover);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPodcast = song.kind == MediaKind.podcast;
    final cover = song.coverPath;
    final hasCover = _hasCover(cover);

    final tile = InkWell(
      onTap: onTap ?? () => _defaultOnTap(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildCover(scheme, cover, hasCover, isPodcast),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Solo artista (o "Artista desconocido").
                  Text(
                    song.artistOrUnknown,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.durationLabel,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${song.extension.toUpperCase()} · ${song.sizeLabel}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onMore ??
                      () => SongContextMenu.showSheet(context, song),
                  icon: Icon(
                    Icons.more_vert,
                    color: scheme.onSurfaceVariant,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  tooltip: 'Más opciones',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) {
        SongContextMenu.showSheet(context, song);
      },
      onSecondaryTapDown: (_) {
        SongContextMenu.showSheet(context, song);
      },
      child: tile,
    );

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          label: '${song.title}. ${song.artistOrUnknown}. ${song.durationLabel}',
          button: true,
          onLongPress: () => SongContextMenu.showSheet(context, song),
          child: interactive,
        ),
      ),
    );
  }

  Widget _buildCover(
    ColorScheme scheme,
    String? cover,
    bool hasCover,
    bool isPodcast,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: scheme.surfaceContainerHigh,
              child: hasCover
                  ? Image.file(
                      File(cover!),
                      fit: BoxFit.cover,
                      cacheWidth: 156,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) =>
                          _fallbackIcon(scheme, isPodcast),
                    )
                  : _fallbackIcon(scheme, isPodcast),
            ),
            if (showPlayingIndicator)
              Positioned(
                right: 2,
                bottom: 2,
                child: _PlayingBadge(song: song, onCover: true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon(ColorScheme scheme, bool isPodcast) {
    return Icon(
      isPodcast ? Icons.mic : Icons.music_note,
      color: scheme.onSurfaceVariant,
    );
  }

  Future<void> _defaultOnTap(BuildContext context) async {
    final c = PlaybackController.instance;

    if (!c.isReady) {
      debugPrint('SongTile: PlaybackController no listo');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El reproductor aún no está listo…'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final handler = c.handler;

    if (handler.songs.isEmpty) {
      try {
        await handler.setQueue([song], startIndex: 0, autoPlay: true);
      } catch (e, st) {
        debugPrint('SongTile: fallo al reproducir -> $e\n$st');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo reproducir: $e')),
          );
        }
      }
      return;
    }

    if (context.mounted) {
      await SongContextMenu.showQueueSheet(context, song);
    }
  }
}

class _PlayingBadge extends StatelessWidget {
  final Song song;
  final bool onCover;
  const _PlayingBadge({required this.song, this.onCover = false});

  @override
  Widget build(BuildContext context) {
    final c = PlaybackController.instance;
    if (!c.isReady) return const SizedBox.shrink();

    return StreamBuilder<MediaItem?>(
      stream: c.currentItem,
      builder: (context, snap) {
        final isCurrent = snap.data?.id == song.path;
        if (!isCurrent) return const SizedBox.shrink();

        final icon = Icon(
          Icons.graphic_eq,
          size: 14,
          color: onCover
              ? Colors.white
              : Theme.of(context).colorScheme.primary,
        );

        if (!onCover) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: icon,
          );
        }

        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: icon,
        );
      },
    );
  }
}

class _CoverCacheEntry {
  final bool exists;
  final int mtime;
  const _CoverCacheEntry({required this.exists, required this.mtime});
}
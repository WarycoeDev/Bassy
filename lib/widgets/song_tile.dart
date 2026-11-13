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
  final List<Song>? queueContext;
  final int? queueIndex;

  final bool reorderMode;
  final int? reorderIndex;

  /// Si es true, el tile se encoge a altura 0 suavemente (para animar
  /// su eliminación de la lista sin que los demás salten de golpe).
  final bool isRemoving;

  static const double tileRadius = 12;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.onMore,
    this.showPlayingIndicator = true,
    this.queueContext,
    this.queueIndex,
    this.reorderMode = false,
    this.reorderIndex,
    this.isRemoving = false,
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

    final bool isInteractive = !reorderMode && !isRemoving;

    final tile = InkWell(
      onTap: isInteractive ? (onTap ?? () => _defaultOnTap(context)) : null,
      borderRadius: BorderRadius.circular(tileRadius),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(tileRadius),
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
            if (reorderMode && reorderIndex != null)
              _buildDragHandle(scheme, reorderIndex!)
            else
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
                        () => SongContextMenu.showSheet(
                              context,
                              song,
                              queueContext: queueContext,
                              queueIndex: queueIndex,
                            ),
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
      onLongPressStart: isInteractive
          ? (_) {
              SongContextMenu.showSheet(
                context,
                song,
                queueContext: queueContext,
                queueIndex: queueIndex,
              );
            }
          : null,
      onSecondaryTapDown: isInteractive
          ? (_) {
              SongContextMenu.showSheet(
                context,
                song,
                queueContext: queueContext,
                queueIndex: queueIndex,
              );
            }
          : null,
      child: tile,
    );

    // Envolvemos todo en AnimatedSize y ClipRect para que,
    // cuando isRemoving cambie a true, la altura colapse a 0 suavemente.
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: SizedBox(
          height: isRemoving ? 0 : null,
          child: Padding(
            padding: EdgeInsets.only(bottom: isRemoving ? 0 : 10),
            child: Semantics(
              label:
                  '${song.title}. ${song.artistOrUnknown}. ${song.durationLabel}',
              button: isInteractive,
              onLongPress: isInteractive
                  ? () => SongContextMenu.showSheet(
                        context,
                        song,
                        queueContext: queueContext,
                        queueIndex: queueIndex,
                      )
                  : null,
              child: interactive,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle(ColorScheme scheme, int index) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ReorderableDragStartListener(
        key: ValueKey<String>('drag:${song.path}'),
        index: index,
        child: Container(
          width: 48,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(tileRadius),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.drag_handle,
            size: 28,
            color: scheme.onSurfaceVariant,
          ),
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

  int _resolvedIndex(List<Song> ctx) {
    final provided = queueIndex;
    if (provided != null &&
        provided >= 0 &&
        provided < ctx.length &&
        ctx[provided].path == song.path) {
      return provided;
    }
    final found = ctx.indexWhere((s) => s.path == song.path);
    return found >= 0 ? found : 0;
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
    final ctx = queueContext;
    final queueSongs = handler.songsOf(song.kind);

    if (ctx == null || ctx.isEmpty) {
      if (queueSongs.isNotEmpty && context.mounted) {
        if (song.kind == MediaKind.podcast) {
          await SongContextMenu.showSheet(context, song);
        } else {
          await SongContextMenu.showQueueSheet(context, song);
        }
        return;
      }

      try {
        await c.switchToQueue(song.kind);
        await handler.setQueueOf(
          song.kind,
          [song],
          startIndex: 0,
          autoPlay: true,
        );
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

    final startIndex = _resolvedIndex(ctx);

    if (queueSongs.isNotEmpty && context.mounted) {
      if (song.kind == MediaKind.podcast) {
        await SongContextMenu.showSheet(
          context,
          song,
          queueContext: ctx,
          queueIndex: startIndex,
        );
        return;
      }

      await SongContextMenu.showQueueSheetForContext(
        context,
        song,
        contextSongs: ctx,
        startIndex: startIndex,
      );
      return;
    }

    try {
      await c.switchToQueue(song.kind);
      await handler.setQueueOf(
        song.kind,
        ctx,
        startIndex: startIndex,
        autoPlay: true,
      );
    } catch (e, st) {
      debugPrint('SongTile: fallo al reproducir contexto -> $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reproducir: $e')),
        );
      }
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
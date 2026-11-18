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

  /// Widget opcional que se dibuja SOBRE la carátula, en la esquina
  /// superior izquierda. Sirve para badges de estado (completado,
  /// en progreso, etc.) sin ocupar espacio en la fila.
  final Widget? coverOverlay;

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
    this.coverOverlay,
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

    final tile = Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(tileRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isInteractive ? (onTap ?? () => _defaultOnTap(context)) : null,
        borderRadius: BorderRadius.circular(tileRadius),
        child: Padding(
          padding: const EdgeInsets.all(8),
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
          ? (details) {
              SongContextMenu.showAt(
                context,
                song,
                globalPosition: details.globalPosition,
                queueContext: queueContext,
                queueIndex: queueIndex,
              );
            }
          : null,
      child: tile,
    );

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
            if (coverOverlay != null)
              Positioned(
                top: -1,
                left: -1,
                child: coverOverlay!,
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
    final resolved = found >= 0 ? found : 0;
    if (kDebugMode && found < 0) {
      debugPrint(
        'SongTile._resolvedIndex: "${song.title}" no está en ctx '
        '(len=${ctx.length}); usando índice 0',
      );
    }
    return resolved;
  }

  /// Tap simple en el tile.
  ///
  /// Reglas:
  /// 1. PODCAST: siempre abre el menú de podcast (`showSheet`), sin
  ///    importar si la cola tiene contenido o no. Así el usuario decide
  ///    entre "Reproducir desde el principio", "Reanudar", añadir a la
  ///    cola, etc., y el contexto de la lista se reenvía para que la
  ///    cola se cargue con todos los capítulos.
  /// 2. MÚSICA:
  ///    - Si CUALQUIERA de las dos colas (música o podcast) ya tiene
  ///      elementos, se abre el menú de queue correspondiente para
  ///      decidir qué hacer (Reproducir ahora, Añadir a la cola, etc.).
  ///    - Si ambas colas están vacías, se reproduce directamente la
  ///      lista de contexto (`queueContext`) empezando por esta canción,
  ///      o solo esta canción si no hay contexto. Esto equivale al
  ///      botón "Reproducir ahora" del PlaybackMenu.
  ///
  /// Nota: cuando se reproduce directamente (ambas colas vacías) NO se
  /// llama a `switchToQueue` antes de `setQueueOf`, porque `setQueueOf`
  /// ya cambia la cola activa (ver `_setQueueImpl`). Llamar primero a
  /// `switchToQueue` reproduciría momentáneamente la canción previa de
  /// la cola de música antes de ser reemplazada.
  Future<void> _defaultOnTap(BuildContext context) async {
    final c = PlaybackController.instance;

    if (!c.isReady) {
      debugPrint('SongTile: PlaybackController no listo');
      return;
    }

    final handler = c.handler;
    final ctx = queueContext;

    // --- PODCAST: siempre menú de podcast -------------------------
    if (song.kind == MediaKind.podcast) {
      if (!context.mounted) return;
      final startIndex = (ctx != null && ctx.isNotEmpty)
          ? _resolvedIndex(ctx)
          : null;
      await SongContextMenu.showSheet(
        context,
        song,
        queueContext: ctx,
        queueIndex: startIndex ?? queueIndex,
      );
      return;
    }

    // --- MÚSICA ------------------------------------------------
    // Si alguna de las dos colas ya tiene contenido, mostramos el menú
    // de queue para que el usuario decida qué hacer.
    final musicQueue = handler.songsOf(MediaKind.music);
    final podcastQueue = handler.songsOf(MediaKind.podcast);
    final hasAnyQueue = musicQueue.isNotEmpty || podcastQueue.isNotEmpty;

    if (hasAnyQueue && context.mounted) {
      if (ctx != null && ctx.isNotEmpty) {
        final startIndex = _resolvedIndex(ctx);
        await SongContextMenu.showQueueSheetForContext(
          context,
          song,
          contextSongs: ctx,
          startIndex: startIndex,
        );
      } else {
        await SongContextMenu.showQueueSheet(context, song);
      }
      return;
    }

    // Ambas colas vacías: reproducir directamente (equivale a
    // "Reproducir ahora" del PlaybackMenu).
    try {
      if (ctx != null && ctx.isNotEmpty) {
        // Reproduce TODA la lista de contexto, empezando por esta canción.
        await handler.setQueueOf(
          song.kind,
          ctx,
          startIndex: _resolvedIndex(ctx),
          autoPlay: true,
        );
      } else {
        // Sin contexto: reproduce únicamente este tile.
        await handler.setQueueOf(
          song.kind,
          [song],
          startIndex: 0,
          autoPlay: true,
        );
      }
    } catch (e, st) {
      debugPrint('SongTile: fallo al reproducir -> $e\n$st');
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
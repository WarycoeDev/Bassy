// lib/widgets/queue_viewer.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';

/// Visor de la cola de reproducción actual.
///
/// Se abre SIEMPRE como dialog flotante centrado. Permite ver la cola,
/// saltar a una canción y eliminarla.
class QueueViewer {
  QueueViewer._();

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: const _QueueBody(),
        ),
      ),
    );
  }
}

class _QueueBody extends StatefulWidget {
  const _QueueBody();

  @override
  State<_QueueBody> createState() => _QueueBodyState();
}

class _QueueBodyState extends State<_QueueBody> {
  final controller = PlaybackController.instance;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();

    void refresh(dynamic _) {
      if (mounted) setState(() {});
    }

    // Cambia la lista (agregar / quitar / reordenar).
    _subs.add(controller.handler.queue.listen(refresh));

    // Cambia la canción actual (saltar, siguiente, anterior, fin de pista).
    _subs.add(controller.handler.mediaItem.listen(refresh));

    // Cambia el índice de la cola en el estado de reproducción. Cubre el caso
    // en que `currentIndex` se actualiza un instante después de `mediaItem`.
    _subs.add(
      controller.handler.playbackState
          .map((s) => s.queueIndex)
          .distinct()
          .listen(refresh),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final songs = controller.songs;
    final currentIndex = controller.currentIndex;

    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cabecera
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  color: scheme.onSurface,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cola de reproducción',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Flexible(
            child: songs.isEmpty
                ? _EmptyState(scheme: scheme)
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: songs.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 76,
                      endIndent: 16,
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return _QueueTile(
                        song: song,
                        index: index,
                        isCurrent: index == currentIndex,
                        scheme: scheme,
                        onTap: () => controller.playFromQueue(index),
                        onRemove: () =>
                            controller.handler.removeFromQueue(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final Song song;
  final int index;
  final bool isCurrent;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.scheme,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent
          ? scheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              _QueueCover(song: song, scheme: scheme, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? scheme.primary : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.volume_up_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                )
              else if (song.duration > Duration.zero)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    song.durationLabel,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 22,
                ),
                tooltip: 'Quitar de la cola',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueCover extends StatelessWidget {
  final Song song;
  final ColorScheme scheme;
  final double size;

  const _QueueCover({
    required this.song,
    required this.scheme,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cover = song.coverPath;
    final hasCover = cover != null && cover.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasCover
          ? Image.file(
              File(cover),
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Icon(
        Icons.music_note_rounded,
        color: scheme.onSurfaceVariant,
        size: size * 0.5,
      );
}

class _EmptyState extends StatelessWidget {
  final ColorScheme scheme;
  const _EmptyState({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'La cola está vacía',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
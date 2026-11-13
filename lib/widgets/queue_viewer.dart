// lib/widgets/queue_viewer.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 380,
            maxWidth: 480,
            maxHeight: 640,
          ),
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

    _subs.add(controller.handler.queue.listen(refresh));
    _subs.add(controller.handler.mediaItem.listen(refresh));
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
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
                : _QueueContainer(
                    scheme: scheme,
                    songs: songs,
                    currentIndex: currentIndex,
                    onPlay: controller.playFromQueue,
                    onRemove: controller.handler.removeFromQueue,
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueContainer extends StatelessWidget {
  final ColorScheme scheme;
  final List<Song> songs;
  final int currentIndex;
  final void Function(int) onPlay;
  final void Function(int) onRemove;

  const _QueueContainer({
    required this.scheme,
    required this.songs,
    required this.currentIndex,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            itemCount: songs.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 64,
              endIndent: 8,
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            itemBuilder: (context, index) {
              final song = songs[index];
              return _QueueTile(
                song: song,
                index: index,
                isCurrent: index == currentIndex,
                scheme: scheme,
                onTap: () => onPlay(index),
                onRemove: () => onRemove(index),
              );
            },
          ),
        ),
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
    final radius = BorderRadius.circular(14);

    return Material(
      color: isCurrent
          ? scheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              _QueueCover(song: song, scheme: scheme, size: 52),
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
                    const SizedBox(height: 3),
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
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
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
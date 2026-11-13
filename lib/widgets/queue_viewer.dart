// lib/widgets/queue_viewer.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';
import 'action_menu.dart';

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
          child: const QueuePanel(embedded: false),
        ),
      ),
    );
  }
}

/// Panel de la cola de reproducción.
///
/// Si [embedded] es `true` no muestra botón de cerrar (se usa dentro de
/// la tarjeta flotante del layout de escritorio). Si es `false` muestra
/// la cabecera con botón de cierre para usarlo dentro de un Dialog.
///
/// Muestra un selector Música / Capítulos para visualizar/editar
/// **ambas** colas independientemente de cuál esté activa.
class QueuePanel extends StatefulWidget {
  final bool embedded;

  const QueuePanel({super.key, this.embedded = false});

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  /// Altura mínima compartida entre el estado vacío y la lista con pocos
  /// elementos, para que el panel no cambie de tamaño al vaciarse o al
  /// tener solo 1-2 ítems. Ajusta este valor a tu gusto.
  static const double _minPanelHeight = 360;

  final controller = PlaybackController.instance;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Cola que el panel está mostrando (no necesariamente la activa).
  MediaKind _viewKind = MediaKind.music;

  @override
  void initState() {
    super.initState();
    if (controller.isReady) {
      _viewKind = controller.activeQueueKind;
    }

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
    _subs.add(controller.handler.activeQueueStream.listen((kind) {
      if (!mounted) return;
      // Si el usuario no ha cambiado manualmente, seguimos a la activa.
      setState(() => _viewKind = kind);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    await controller.reorderQueueOf(_viewKind, oldIndex, newIndex);
    if (mounted) setState(() {});
  }

  Future<void> _handleRemove(int index) async {
    if (_viewKind == controller.activeQueueKind &&
        index == controller.currentIndex) {
      return;
    }
    await controller.removeFromQueueOf(_viewKind, index);
    if (mounted) setState(() {});
  }

  Future<void> _handlePlay(int index) async {
    // Si la cola mostrada no es la activa, primero la activamos.
    if (_viewKind != controller.activeQueueKind) {
      await controller.switchToQueue(_viewKind);
    }
    await controller.playFromQueue(index);
    if (mounted) setState(() {});
  }

  String get _title =>
      _viewKind == MediaKind.podcast ? 'Capítulos' : 'Cola de reproducción';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final songs = controller.songsOf(_viewKind);
    final isActiveKind = _viewKind == controller.activeQueueKind;
    final currentIndex =
        isActiveKind ? controller.currentIndex : -1;

    final minHeight = widget.embedded ? 0.0 : _minPanelHeight;

    return Material(
      color: widget.embedded
          ? Colors.transparent
          : scheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              widget.embedded ? 20 : 8,
              12,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _viewKind == MediaKind.podcast
                        ? Icons.mic
                        : Icons.queue_music_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (!widget.embedded)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<MediaKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<MediaKind>(
                  value: MediaKind.music,
                  label: Text('Música'),
                  icon: Icon(Icons.music_note, size: 18),
                ),
                ButtonSegment<MediaKind>(
                  value: MediaKind.podcast,
                  label: Text('Capítulos'),
                  icon: Icon(Icons.mic, size: 18),
                ),
              ],
              selected: {_viewKind},
              onSelectionChanged: (sel) {
                if (sel.isEmpty) return;
                setState(() => _viewKind = sel.first);
              },
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Flexible(
            child: songs.isEmpty
                ? SizedBox(
                    height: minHeight > 0 ? minHeight : null,
                    child: _EmptyState(scheme: scheme, kind: _viewKind),
                  )
                : _QueueContainer(
                    scheme: scheme,
                    songs: songs,
                    currentIndex: currentIndex,
                    onPlay: _handlePlay,
                    onRemove: _handleRemove,
                    onReorder: _handleReorder,
                    minHeight: minHeight,
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
  final double minHeight;
  final Future<void> Function(int) onPlay;
  final Future<void> Function(int) onRemove;
  final Future<void> Function(int, int) onReorder;

  const _QueueContainer({
    required this.scheme,
    required this.songs,
    required this.currentIndex,
    required this.minHeight,
    required this.onPlay,
    required this.onRemove,
    required this.onReorder,
  });

  String _entryKey(int index) {
    final base = songs[index].path ?? songs[index].title;
    var occurrence = 0;
    for (var i = 0; i < index; i++) {
      if ((songs[i].path ?? songs[i].title) == base) occurrence++;
    }
    return '$base#$occurrence';
  }

  Future<bool> _confirmRemove(BuildContext context, Song song) {
    return ActionMenu.confirm(
      context,
      title: song.title,
      subtitle: song.subtitle,
      coverPath: song.coverPath,
      fallbackIcon: song.kind == MediaKind.podcast
          ? Icons.mic
          : Icons.music_note,
      message: '«${song.title}» se eliminará de la cola.',
      confirmLabel: 'Quitar',
    );
  }

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
          // Compensa el padding vertical (10+10) para que la altura total
          // del contenedor coincida con la del estado vacío.
          constraints: BoxConstraints(
            minHeight: minHeight > 0
                ? (minHeight - 20).clamp(0, double.infinity)
                : 0,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            buildDefaultDragHandles: false,
            itemCount: songs.length,
            onReorder: (o, n) => onReorder(o, n),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isLast = index == songs.length - 1;
              final isCurrent = index == currentIndex;
              final entryKey = _entryKey(index);

              return Column(
                key: ValueKey('queue-item-$entryKey'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Dismissible(
                    key: ValueKey('dismiss-$entryKey'),
                    direction: isCurrent
                        ? DismissDirection.none
                        : DismissDirection.horizontal,
                    background: _DismissBg(
                      scheme: scheme,
                      alignment: Alignment.centerLeft,
                      icon: Icons.delete_outline_rounded,
                      enabled: !isCurrent,
                    ),
                    secondaryBackground: _DismissBg(
                      scheme: scheme,
                      alignment: Alignment.centerRight,
                      icon: Icons.delete_outline_rounded,
                      enabled: !isCurrent,
                    ),
                    confirmDismiss: (_) => isCurrent
                        ? Future.value(false)
                        : _confirmRemove(context, song),
                    onDismissed: (_) => onRemove(index),
                    child: _QueueTile(
                      song: song,
                      index: index,
                      isCurrent: isCurrent,
                      scheme: scheme,
                      onTap: () => onPlay(index),
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 64,
                      endIndent: 8,
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                ],
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

  const _QueueTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.scheme,
    required this.onTap,
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
                        color: isCurrent
                            ? scheme.primary
                            : scheme.onSurface,
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
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: scheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
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

class _DismissBg extends StatelessWidget {
  final ColorScheme scheme;
  final Alignment alignment;
  final IconData icon;
  final bool enabled;

  const _DismissBg({
    required this.scheme,
    required this.alignment,
    required this.icon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = enabled
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        color: enabled
            ? scheme.onErrorContainer
            : scheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme scheme;
  final MediaKind kind;

  const _EmptyState({required this.scheme, required this.kind});

  @override
  Widget build(BuildContext context) {
    final isPodcast = kind == MediaKind.podcast;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPodcast ? Icons.mic_none_rounded : Icons.queue_music_rounded,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              isPodcast ? 'No hay capítulos en cola' : 'La cola está vacía',
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
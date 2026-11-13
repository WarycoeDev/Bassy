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

class QueuePanel extends StatefulWidget {
  final bool embedded;

  const QueuePanel({super.key, this.embedded = false});

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  static const double _minPanelHeight = 360;
  static const double _itemHeightEstimate = 69;
  static const double _listTopPadding = 10;

  final controller = PlaybackController.instance;
  final List<StreamSubscription<dynamic>> _subs = [];
  final ScrollController _scroll = ScrollController();

  MediaKind _viewKind = MediaKind.music;

  /// Canciones en proceso de animación de salida.
  final Set<String> _removingIds = {};

  int _lastIndex = -2;
  MediaKind? _lastKind;
  bool _firstScroll = true;

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
      setState(() => _viewKind = kind);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _maybeAutoScroll(int currentIndex, int itemCount) {
    if (itemCount == 0 || _removingIds.isNotEmpty) {
      if (itemCount == 0) {
        _lastIndex = -2;
        _lastKind = _viewKind;
      }
      return;
    }

    if (currentIndex < 0) {
      if (_lastKind != _viewKind) {
        _lastKind = _viewKind;
        _lastIndex = currentIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          _scroll.jumpTo(_scroll.position.minScrollExtent);
        });
      }
      return;
    }

    if (_lastIndex == currentIndex && _lastKind == _viewKind) return;

    final animate = !_firstScroll && _lastKind == _viewKind;
    final kindAtSchedule = _viewKind;
    _lastIndex = currentIndex;
    _lastKind = _viewKind;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) {
        _lastIndex = -2;
        return;
      }
      if (kindAtSchedule != _viewKind) return;

      _firstScroll = false;
      final pos = _scroll.position;
      final target = (_listTopPadding +
              currentIndex * _itemHeightEstimate +
              _itemHeightEstimate / 2 -
              pos.viewportDimension / 2)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent)
          .toDouble();

      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  void _syncLastIndex() {
    if (_viewKind == controller.activeQueueKind) {
      _lastIndex = controller.currentIndex;
      _lastKind = _viewKind;
    }
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    await controller.reorderQueueOf(_viewKind, oldIndex, newIndex);
    _syncLastIndex();
    if (mounted) setState(() {});
  }

  /// Este método SÓLO se llama cuando la animación de colapso ya terminó.
  Future<void> _actuallyRemoveFromQueue(int index, Song song) async {
    await controller.removeFromQueueOf(_viewKind, index);
    _syncLastIndex();

    if (mounted) {
      setState(() => _removingIds.remove(song.path));
    }
  }

  Future<void> _handlePlay(int index) async {
    _lastIndex = index;
    _lastKind = _viewKind;
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
    final currentIndex = isActiveKind ? controller.currentIndex : -1;

    _maybeAutoScroll(currentIndex, songs.length);

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
                    onRemoveConfirmed: (index, song) async {
                      // 1. Disparamos la animación de colapso
                      setState(() => _removingIds.add(song.path));

                      // 2. Esperamos a que termine la animación
                      await Future.delayed(
                        _CollapseOnRemove.duration +
                            const Duration(milliseconds: 20),
                      );

                      // 3. Eliminamos del Store (esto actualiza la lista real)
                      await _actuallyRemoveFromQueue(index, song);
                    },
                    onReorder: _handleReorder,
                    minHeight: minHeight,
                    scrollController: _scroll,
                    listPadding: _listTopPadding,
                    removingIds: _removingIds,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Colapsa (altura → 0 + fade) el item completo cuando [removing] es true,
/// de modo que los items de abajo suban suavemente en vez de saltar.
class _CollapseOnRemove extends StatelessWidget {
  final bool removing;
  final Widget child;

  const _CollapseOnRemove({
    super.key,
    required this.removing,
    required this.child,
  });

  static const Duration duration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: removing ? 0.0 : 1.0,
        child: AnimatedOpacity(
          opacity: removing ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}

class _QueueContainer extends StatelessWidget {
  final ColorScheme scheme;
  final List<Song> songs;
  final int currentIndex;
  final double minHeight;
  final ScrollController scrollController;
  final double listPadding;
  final Set<String> removingIds;
  final Future<void> Function(int) onPlay;
  final Future<void> Function(int index, Song song) onRemoveConfirmed;
  final Future<void> Function(int, int) onReorder;

  const _QueueContainer({
    required this.scheme,
    required this.songs,
    required this.currentIndex,
    required this.minHeight,
    required this.scrollController,
    required this.listPadding,
    required this.removingIds,
    required this.onPlay,
    required this.onRemoveConfirmed,
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
            scrollController: scrollController,
            // Sin prototypeItem: cada item mide su altura real, lo que
            // permite que el colapso animado funcione.
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: listPadding,
            ),
            buildDefaultDragHandles: false,
            itemCount: songs.length,
            onReorder: (o, n) => onReorder(o, n),
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final elevation = Tween<double>(begin: 0, end: 6)
                      .evaluate(animation);
                  return Padding(
                    padding: EdgeInsets.zero,
                    child: Material(
                      elevation: elevation,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      shadowColor: Colors.black.withValues(alpha: 0.5),
                      child: child,
                    ),
                  );
                },
              );
            },
            itemBuilder: (context, index) {
              final song = songs[index];
              final isLast = index == songs.length - 1;
              final isCurrent = index == currentIndex;
              final entryKey = _entryKey(index);
              final isRemoving = removingIds.contains(song.path);

              return _CollapseOnRemove(
                key: ValueKey('queue-item-$entryKey'),
                removing: isRemoving,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Dismissible(
                      key: ValueKey('dismiss-$entryKey'),
                      direction: (isCurrent || isRemoving)
                          ? DismissDirection.none
                          : DismissDirection.horizontal,
                      background: _DismissBg(
                        scheme: scheme,
                        alignment: Alignment.centerLeft,
                        icon: Icons.delete_outline_rounded,
                        enabled: !isCurrent && !isRemoving,
                      ),
                      secondaryBackground: _DismissBg(
                        scheme: scheme,
                        alignment: Alignment.centerRight,
                        icon: Icons.delete_outline_rounded,
                        enabled: !isCurrent && !isRemoving,
                      ),
                      confirmDismiss: (_) async {
                        if (isCurrent) return false;

                        final confirmed = await _confirmRemove(context, song);
                        if (confirmed) {
                          // Le pasamos el índice original y la canción para
                          // que _QueuePanel haga la animación y luego elimine.
                          onRemoveConfirmed(index, song);
                        }

                        // Siempre retornamos false para que Dismissible NO
                        // haga su animación (la maneja _CollapseOnRemove).
                        return false;
                      },
                      onDismissed: (_) {},
                      child: _QueueTile(
                        song: song,
                        index: index,
                        isCurrent: isCurrent,
                        scheme: scheme,
                        isRemoving: isRemoving,
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
                ),
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
  final bool isRemoving;
  final VoidCallback onTap;

  const _QueueTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.scheme,
    required this.isRemoving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final isInteractive = !isRemoving;

    return Material(
      color: isCurrent
          ? scheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isInteractive ? onTap : null,
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
                        color:
                            isCurrent ? scheme.primary : scheme.onSurface,
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
                enabled: isInteractive,
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
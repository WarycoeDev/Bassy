// lib/screens/music_player_screen.dart
import 'dart:io';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/favorites_store.dart';
import '../services/playback_audio_handler.dart' show PlayerRepeatMode;
import '../services/playback_controller.dart';
import '../widgets/queue_viewer.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Breakpoint a partir del cual se usa el layout de escritorio
/// (panel lateral con la cola siempre visible).
const double _kDesktopBreakpoint = 900.0;

class MusicPlayerScreen extends StatefulWidget {
  final String? heroTagPrefix;

  const MusicPlayerScreen({super.key, this.heroTagPrefix});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final _controller = PlaybackController.instance;

  double? _seekValue;
  bool get _isSeeking => _seekValue != null;

  double? _volumeValue;
  bool get _isAdjustingVolume => _volumeValue != null;

  double _lastNonZeroVolume = 1.0;

  @override
  void initState() {
    super.initState();
    // Idempotente: load() retorna de inmediato si ya se cargó.
    FavoritesStore.instance.load();
  }

  Future<void> _onSeekEnd(double valueMs) async {
    final target = Duration(milliseconds: valueMs.round());
    await _controller.seek(target);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    setState(() => _seekValue = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Reproduciendo'),
        centerTitle: true,
      ),
      body: StreamBuilder<MediaItem?>(
        stream: _controller.currentItem,
        builder: (context, mediaSnap) {
          final song = _controller.currentSong;
          if (song == null || mediaSnap.data == null) {
            return const Center(child: Text('Sin reproducción'));
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;

              if (isDesktop) {
                return _DesktopLayout(
                  song: song,
                  mediaItem: mediaSnap.data!,
                  heroTagPrefix: widget.heroTagPrefix,
                  isSeeking: _isSeeking,
                  seekValue: _seekValue,
                  isAdjustingVolume: _isAdjustingVolume,
                  volumeValue: _volumeValue,
                  lastNonZeroVolume: _lastNonZeroVolume,
                  onSeekStart: (v) => setState(() => _seekValue = v),
                  onSeekChanged: (v) => setState(() => _seekValue = v),
                  onSeekEnd: _onSeekEnd,
                  onVolumeStart: (v) =>
                      setState(() => _volumeValue = v),
                  onVolumeChanged: (v) {
                    setState(() => _volumeValue = v);
                    if (v > 0.001) {
                      _lastNonZeroVolume = v;
                    }
                    _controller.setVolume(v);
                  },
                  onVolumeEnd: (_) =>
                      setState(() => _volumeValue = null),
                  onVolumeUpdateLast: (v) =>
                      _lastNonZeroVolume = v,
                );
              }

              return _MobileLayout(
                song: song,
                mediaItem: mediaSnap.data!,
                heroTagPrefix: widget.heroTagPrefix,
                isSeeking: _isSeeking,
                seekValue: _seekValue,
                isAdjustingVolume: _isAdjustingVolume,
                volumeValue: _volumeValue,
                lastNonZeroVolume: _lastNonZeroVolume,
                onSeekStart: (v) => setState(() => _seekValue = v),
                onSeekChanged: (v) => setState(() => _seekValue = v),
                onSeekEnd: _onSeekEnd,
                onVolumeStart: (v) =>
                    setState(() => _volumeValue = v),
                onVolumeChanged: (v) {
                  setState(() => _volumeValue = v);
                  if (v > 0.001) {
                    _lastNonZeroVolume = v;
                  }
                  _controller.setVolume(v);
                },
                onVolumeEnd: (_) => setState(() => _volumeValue = null),
                onVolumeUpdateLast: (v) => _lastNonZeroVolume = v,
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// LAYOUT MÓVIL (vertical, con botón "Ver Cola")
// ============================================================
class _MobileLayout extends StatelessWidget {
  final Song song;
  final MediaItem mediaItem;
  final String? heroTagPrefix;
  final bool isSeeking;
  final double? seekValue;
  final bool isAdjustingVolume;
  final double? volumeValue;
  final double lastNonZeroVolume;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double> onVolumeStart;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onVolumeEnd;
  final ValueChanged<double> onVolumeUpdateLast;

  const _MobileLayout({
    required this.song,
    required this.mediaItem,
    required this.heroTagPrefix,
    required this.isSeeking,
    required this.seekValue,
    required this.isAdjustingVolume,
    required this.volumeValue,
    required this.lastNonZeroVolume,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onVolumeStart,
    required this.onVolumeChanged,
    required this.onVolumeEnd,
    required this.onVolumeUpdateLast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = PlaybackController.instance;

    return StreamBuilder<Duration>(
      stream: controller.position,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        final duration = song.duration > Duration.zero
            ? song.duration
            : (mediaItem.duration ?? Duration.zero);
        final maxMs = duration.inMilliseconds
            .toDouble()
            .clamp(1.0, double.infinity);

        final streamMs =
            position.inMilliseconds.toDouble().clamp(0.0, maxMs);
        final valueMs = isSeeking ? seekValue! : streamMs;

        final shownPosition = isSeeking
            ? Duration(milliseconds: valueMs.round())
            : position;

        return StreamBuilder<bool>(
          stream: controller.isPlaying,
          initialData: controller.handler.isPlaying,
          builder: (context, playingSnap) {
            final isPlaying = playingSnap.data ?? false;

            return LayoutBuilder(
              builder: (context, constraints) {
                final coverSize =
                    (constraints.maxWidth * 0.72).clamp(180.0, 360.0);

                final cover = _AnimatedCover(
                  song: song,
                  size: coverSize,
                );
                final heroPrefix = heroTagPrefix;
                final heroCover = heroPrefix == null
                    ? cover
                    : Hero(
                        tag: '$heroPrefix${song.path}',
                        child: cover,
                      );

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      heroCover,
                      const SizedBox(height: 32),
                      _AnimatedSongInfo(song: song, scheme: scheme),
                      const SizedBox(height: 28),
                      _SeekBar(
                        duration: duration,
                        valueMs: valueMs,
                        shownPosition: shownPosition,
                        onStart: onSeekStart,
                        onChanged: onSeekChanged,
                        onEnd: onSeekEnd,
                      ),
                      const SizedBox(height: 16),
                      _ControlsRow(scheme: scheme, isPlaying: isPlaying),
                      const SizedBox(height: 8),
                      _VolumeRow(
                        scheme: scheme,
                        isAdjustingVolume: isAdjustingVolume,
                        volumeValue: volumeValue,
                        lastNonZeroVolume: lastNonZeroVolume,
                        onStart: onVolumeStart,
                        onChanged: onVolumeChanged,
                        onEnd: onVolumeEnd,
                        onUpdateLast: onVolumeUpdateLast,
                      ),
                      const SizedBox(height: 16),
                      _BottomButtonsRow(
                        song: song,
                        scheme: scheme,
                        onShowQueue: () => QueueViewer.show(context),
                        // Móvil: favoritos sigue en la fila inferior.
                        showFavorites: true,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ============================================================
// LAYOUT ESCRITORIO
//  - Columna izquierda: carátula + info + controles + barra + volumen
//  - Columna derecha: panel con la cola SIEMPRE visible (sin botón)
// ============================================================
class _DesktopLayout extends StatelessWidget {
  final Song song;
  final MediaItem mediaItem;
  final String? heroTagPrefix;
  final bool isSeeking;
  final double? seekValue;
  final bool isAdjustingVolume;
  final double? volumeValue;
  final double lastNonZeroVolume;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double> onVolumeStart;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onVolumeEnd;
  final ValueChanged<double> onVolumeUpdateLast;

  const _DesktopLayout({
    required this.song,
    required this.mediaItem,
    required this.heroTagPrefix,
    required this.isSeeking,
    required this.seekValue,
    required this.isAdjustingVolume,
    required this.volumeValue,
    required this.lastNonZeroVolume,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onVolumeStart,
    required this.onVolumeChanged,
    required this.onVolumeEnd,
    required this.onVolumeUpdateLast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = PlaybackController.instance;

    return StreamBuilder<Duration>(
      stream: controller.position,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        final duration = song.duration > Duration.zero
            ? song.duration
            : (mediaItem.duration ?? Duration.zero);
        final maxMs = duration.inMilliseconds
            .toDouble()
            .clamp(1.0, double.infinity);

        final streamMs =
            position.inMilliseconds.toDouble().clamp(0.0, maxMs);
        final valueMs = isSeeking ? seekValue! : streamMs;

        final shownPosition = isSeeking
            ? Duration(milliseconds: valueMs.round())
            : position;

        return StreamBuilder<bool>(
          stream: controller.isPlaying,
          initialData: controller.handler.isPlaying,
          builder: (context, playingSnap) {
            final isPlaying = playingSnap.data ?? false;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // -------- Columna izquierda (player) --------
                Expanded(
                  flex: 5,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(48, 8, 48, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            _buildHeroCover(),
                            const SizedBox(height: 32),
                            _AnimatedSongInfo(song: song, scheme: scheme),
                            const SizedBox(height: 28),
                            _SeekBar(
                              duration: duration,
                              valueMs: valueMs,
                              shownPosition: shownPosition,
                              onStart: onSeekStart,
                              onChanged: onSeekChanged,
                              onEnd: onSeekEnd,
                            ),
                            const SizedBox(height: 16),
                            _ControlsRow(
                              scheme: scheme,
                              isPlaying: isPlaying,
                            ),
                            const SizedBox(height: 8),
                            _VolumeRow(
                              scheme: scheme,
                              isAdjustingVolume: isAdjustingVolume,
                              volumeValue: volumeValue,
                              lastNonZeroVolume: lastNonZeroVolume,
                              onStart: onVolumeStart,
                              onChanged: onVolumeChanged,
                              onEnd: onVolumeEnd,
                              onUpdateLast: onVolumeUpdateLast,
                            ),
                            // En escritorio ya no hay fila inferior:
                            //  - Favoritos → sobre la carátula
                            //  - Ver Cola → panel lateral siempre visible
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // -------- Separador vertical --------
                Container(
                  width: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
                // -------- Columna derecha (cola siempre visible) --------
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 24, 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: const QueuePanel(embedded: true),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHeroCover() {
    const coverSize = 320.0;
    final cover = _AnimatedCover(song: song, size: coverSize);
    final heroPrefix = heroTagPrefix;
    final heroCover = heroPrefix == null
        ? cover
        : Hero(
            tag: '$heroPrefix${song.path}',
            child: cover,
          );

    // Stack: cover + botón de favoritos en la esquina superior derecha.
    return SizedBox(
      width: coverSize,
      height: coverSize,
      child: Stack(
        children: [
          heroCover,
          Positioned(
            top: 10,
            right: 10,
            child: _CoverFavoriteButton(song: song),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BARRA DE PROGRESO (seek)
// ============================================================
class _SeekBar extends StatelessWidget {
  final Duration duration;
  final double valueMs;
  final Duration shownPosition;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onEnd;

  const _SeekBar({
    required this.duration,
    required this.valueMs,
    required this.shownPosition,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMs = duration.inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity);
    final canSeek = duration.inMilliseconds > 0;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 7,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 16,
            ),
          ),
          child: Slider(
            min: 0,
            max: maxMs,
            value: valueMs,
            onChangeStart: canSeek ? onStart : null,
            onChanged: canSeek ? onChanged : null,
            onChangeEnd: canSeek ? onEnd : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmt(shownPosition),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontFeatures: const [
                    FontFeature.tabularFigures()
                  ],
                ),
              ),
              Text(
                _fmt(duration),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontFeatures: const [
                    FontFeature.tabularFigures()
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// FILA DE CONTROLES (shuffle, prev, play/pause, next, repeat)
// ============================================================
class _ControlsRow extends StatelessWidget {
  final ColorScheme scheme;
  final bool isPlaying;

  const _ControlsRow({required this.scheme, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // ---------- ALEATORIO (animado) ----------
        StreamBuilder<bool>(
          stream: controller.shuffle,
          initialData: controller.shuffleEnabled,
          builder: (context, snap) {
            final on = snap.data ?? false;
            return _AnimatedIconButton(
              icon: Icons.shuffle_rounded,
              tooltip: 'Aleatorio',
              scheme: scheme,
              size: 24,
              color: on ? scheme.primary : scheme.onSurfaceVariant,
              stateKey: on,
              onPressed: () => controller.setShuffle(!on),
            );
          },
        ),
        IconButton(
          icon: Icon(
            Icons.skip_previous_rounded,
            size: 40,
            color: scheme.onSurface,
          ),
          tooltip: 'Anterior',
          onPressed: controller.previous,
        ),
        _BigPlayButton(
          isPlaying: isPlaying,
          onPressed: isPlaying ? controller.pause : controller.play,
          scheme: scheme,
        ),
        IconButton(
          icon: Icon(
            Icons.skip_next_rounded,
            size: 40,
            color: controller.hasNext
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.3),
          ),
          tooltip: 'Siguiente',
          onPressed: controller.hasNext ? controller.next : null,
        ),
        // ---------- REPETIR (animado) ----------
        StreamBuilder<PlayerRepeatMode>(
          stream: controller.repeat,
          initialData: controller.repeatModeNow,
          builder: (context, snap) {
            final mode = snap.data ?? PlayerRepeatMode.off;
            final icon = switch (mode) {
              PlayerRepeatMode.one => Icons.repeat_one_rounded,
              _ => Icons.repeat_rounded,
            };
            final active = mode != PlayerRepeatMode.off;
            return _AnimatedIconButton(
              icon: icon,
              tooltip: 'Repetir',
              scheme: scheme,
              size: 24,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
              stateKey: mode,
              onPressed: () {
                final next = switch (mode) {
                  PlayerRepeatMode.off => PlayerRepeatMode.all,
                  PlayerRepeatMode.all => PlayerRepeatMode.one,
                  PlayerRepeatMode.one => PlayerRepeatMode.off,
                };
                controller.setRepeatMode(next);
              },
            );
          },
        ),
      ],
    );
  }
}

// ============================================================
// FILA DE VOLUMEN
// ============================================================
class _VolumeRow extends StatelessWidget {
  final ColorScheme scheme;
  final bool isAdjustingVolume;
  final double? volumeValue;
  final double lastNonZeroVolume;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onEnd;
  final ValueChanged<double> onUpdateLast;

  const _VolumeRow({
    required this.scheme,
    required this.isAdjustingVolume,
    required this.volumeValue,
    required this.lastNonZeroVolume,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    required this.onUpdateLast,
  });

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return ValueListenableBuilder<double>(
      valueListenable: controller.volume,
      builder: (context, streamVolume, _) {
        final safeStream = streamVolume.clamp(0.0, 1.0);
        final volume =
            isAdjustingVolume ? volumeValue! : safeStream;
        final muted = volume <= 0.001;
        final icon = muted
            ? Icons.volume_off_rounded
            : volume < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded;

        return Row(
          children: [
            IconButton(
              icon: Icon(
                icon,
                color: scheme.onSurfaceVariant,
              ),
              tooltip: muted ? 'Activar sonido' : 'Silenciar',
              onPressed: () {
                if (muted) {
                  controller.setVolume(lastNonZeroVolume);
                } else {
                  onUpdateLast(volume);
                  controller.setVolume(0);
                }
              },
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  onChangeStart: onStart,
                  onChanged: onChanged,
                  onChangeEnd: onEnd,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// FILA DE BOTONES INFERIORES (favoritos + ver cola opcional)
// ============================================================
class _BottomButtonsRow extends StatelessWidget {
  final Song song;
  final ColorScheme scheme;
  final VoidCallback? onShowQueue;
  final bool showFavorites;

  const _BottomButtonsRow({
    required this.song,
    required this.scheme,
    required this.onShowQueue,
    this.showFavorites = true,
  });

  @override
  Widget build(BuildContext context) {
    // Si no hay nada que mostrar, no pintamos la fila vacía.
    if (!showFavorites && onShowQueue == null) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Favoritos (animado, conectado a FavoritesStore)
        if (showFavorites)
          ListenableBuilder(
            listenable: FavoritesStore.instance,
            builder: (context, _) {
              final isFav = FavoritesStore.instance.contains(song);
              return _AnimatedRoundIconButton(
                icon: isFav
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                tooltip: isFav
                    ? 'Quitar de favoritos'
                    : 'Añadir a favoritos',
                scheme: scheme,
                color: isFav ? scheme.error : null,
                onPressed: () async {
                  await FavoritesStore.instance.toggle(song);
                },
              );
            },
          ),
        if (showFavorites && onShowQueue != null)
          const SizedBox(width: 12),
        if (onShowQueue != null)
          _LabeledButton(
            icon: Icons.playlist_play_rounded,
            label: 'Ver Cola',
            scheme: scheme,
            onPressed: onShowQueue!,
          ),
      ],
    );
  }
}

// ============================================================
// BOTÓN DE FAVORITOS SOBREPUESTO EN LA CARÁTULA
// (se usa en el layout de escritorio)
// ============================================================
class _CoverFavoriteButton extends StatelessWidget {
  final Song song;
  const _CoverFavoriteButton({required this.song});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: FavoritesStore.instance,
      builder: (context, _) {
        final isFav = FavoritesStore.instance.contains(song);
        return Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => FavoritesStore.instance.toggle(song),
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: isFav
                  ? 'Quitar de favoritos'
                  : 'Añadir a favoritos',
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.28),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(
                      scale: animation,
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    ),
                    child: Icon(
                      isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(isFav),
                      color: isFav ? scheme.error : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
// ============================================================
// CARÁTULA ANIMADA (cross-fade + scale al cambiar de canción)
// ============================================================
class _AnimatedCover extends StatelessWidget {
  final Song song;
  final double size;

  const _AnimatedCover({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            ),
          );
        },
        child: _CoverContent(
          key: ValueKey(song.path),
          song: song,
          size: size,
          scheme: scheme,
        ),
      ),
    );
  }
}

class _CoverContent extends StatelessWidget {
  final Song song;
  final double size;
  final ColorScheme scheme;

  const _CoverContent({
    super.key,
    required this.song,
    required this.size,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final cover = song.coverPath;
    if (cover != null && cover.isNotEmpty) {
      return Image.file(
        File(cover),
        fit: BoxFit.cover,
        width: size,
        height: size,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        child: Icon(
          Icons.music_note_rounded,
          color: scheme.onPrimaryContainer,
          size: size * 0.4,
        ),
      );
}

// ============================================================
// TÍTULO + ARTISTA ANIMADOS (cross-fade al cambiar de canción)
// ============================================================
class _AnimatedSongInfo extends StatelessWidget {
  final Song song;
  final ColorScheme scheme;

  const _AnimatedSongInfo({required this.song, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey('info_${song.path}'),
        children: [
          _MarqueeTitle(title: song.title, scheme: scheme),
          const SizedBox(height: 6),
          Text(
            song.subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TÍTULO CON MARQUESINA CÍCLICA
// ============================================================
class _MarqueeTitle extends StatefulWidget {
  final String title;
  final ColorScheme scheme;

  const _MarqueeTitle({
    required this.title,
    required this.scheme,
  });

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle>
    with SingleTickerProviderStateMixin {
  static const _gap = 64.0;
  static const _pause = Duration(seconds: 2);
  static const _speed = 40.0;

  late final AnimationController _ctrl;
  late Animation<double> _anim;

  double _lastTextWidth = -1;
  double _lastAvailable = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _anim = const AlwaysStoppedAnimation<double>(0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  TextStyle get _style => TextStyle(
        color: widget.scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      );

  double _measureText(BuildContext context, TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    final tp = TextPainter(
      text: TextSpan(text: widget.title, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textWidthBasis: TextWidthBasis.longestLine,
      textScaler: scaler,
    )..layout(maxWidth: double.infinity);
    return tp.width;
  }

  void _configureAnimation(double textWidth, double available) {
    final cycleDistance = textWidth + _gap;
    final moveMs = (cycleDistance / _speed * 1000).round();
    final totalMs = moveMs + _pause.inMilliseconds;
    final moveFraction = moveMs / totalMs;

    _anim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: cycleDistance),
        weight: moveFraction,
      ),
      TweenSequenceItem(
        tween: ConstantTween(cycleDistance),
        weight: 1.0 - moveFraction,
      ),
    ]).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.linear),
    );

    _ctrl.duration = Duration(milliseconds: totalMs);
    _ctrl.value = 0;
    _ctrl.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final textWidth = _measureText(context, style);
        final needsScroll = textWidth > available;

        if (!needsScroll) {
          if (_ctrl.isAnimating) {
            _ctrl.stop();
          }
          return Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        final sizeChanged = (textWidth - _lastTextWidth).abs() > 0.5 ||
            (available - _lastAvailable).abs() > 0.5;
        if (sizeChanged) {
          _lastTextWidth = textWidth;
          _lastAvailable = available;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _configureAnimation(textWidth, available);
          });
        }

        final lineHeight = scaler.scale(style.fontSize ?? 22) * 1.4;

        return ClipRect(
          child: SizedBox(
            width: available,
            height: lineHeight,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              minWidth: 0,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, _) {
                  final dx = _anim.value;
                  return Transform.translate(
                    offset: Offset(-dx, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          softWrap: false,
                          style: style,
                        ),
                        const SizedBox(width: _gap),
                        Text(
                          widget.title,
                          maxLines: 1,
                          softWrap: false,
                          style: style,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BigPlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final ColorScheme scheme;

  const _BigPlayButton({
    required this.isPlaying,
    required this.onPressed,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.3)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(isPlaying),
              color: scheme.onPrimary,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTÓN DE ICONO ANIMADO
// ============================================================
class _AnimatedIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final ColorScheme scheme;
  final double size;
  final Color? color;
  final Object? stateKey;
  final VoidCallback? onPressed;

  const _AnimatedIconButton({
    required this.icon,
    required this.tooltip,
    required this.scheme,
    required this.size,
    this.color,
    this.stateKey,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? scheme.onSurfaceVariant;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          icon,
          key: ValueKey('${icon.codePoint}_$stateKey'),
          size: size,
          color: iconColor,
        ),
      ),
    );
  }
}

// ============================================================
// BOTÓN REDONDO ANIMADO (solo icono) — Favoritos
// ============================================================
class _AnimatedRoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final ColorScheme scheme;
  final Color? color;
  final VoidCallback onPressed;

  const _AnimatedRoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.scheme,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? scheme.onSurface;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHigh,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Tooltip(
            message: tooltip,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  icon,
                  key: ValueKey(icon),
                  color: iconColor,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTÓN REDONDEADO (icono + texto)
// ============================================================
class _LabeledButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;
  final VoidCallback onPressed;

  const _LabeledButton({
    required this.icon,
    required this.label,
    required this.scheme,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerHigh,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: scheme.onSurface,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
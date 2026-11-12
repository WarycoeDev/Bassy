// lib/screens/music_player_screen.dart
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_audio_handler.dart' show PlayerRepeatMode;
import '../services/playback_controller.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Player de MÚSICA: carátula grande, título/artista, barra de progreso
/// con seek, y controles (shuffle / prev / play-pause / next / repeat).
class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final _controller = PlaybackController.instance;

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

          return StreamBuilder<Duration>(
            stream: _controller.position,
            builder: (context, posSnap) {
              final position = posSnap.data ?? Duration.zero;
              final duration = song.duration > Duration.zero
                  ? song.duration
                  : (mediaSnap.data?.duration ?? Duration.zero);
              final maxMs = duration.inMilliseconds
                  .toDouble()
                  .clamp(1.0, double.infinity);
              final valueMs =
                  position.inMilliseconds.toDouble().clamp(0.0, maxMs);

              return StreamBuilder<bool>(
                stream: _controller.isPlaying,
                initialData: _controller.handler.isPlaying,
                builder: (context, playingSnap) {
                  final isPlaying = playingSnap.data ?? false;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final coverSize = (constraints.maxWidth * 0.72)
                          .clamp(180.0, 360.0);

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            _Cover(song: song, size: coverSize),
                            const SizedBox(height: 32),
                            Text(
                              song.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
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
                            const SizedBox(height: 28),
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
                                onChanged: duration.inMilliseconds > 0
                                    ? (v) => _controller.seek(
                                          Duration(milliseconds: v.round()),
                                        )
                                    : null,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _fmt(position),
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
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // SHUFFLE (reactivo al handler)
                                StreamBuilder<bool>(
                                  stream: _controller.shuffle,
                                  initialData: _controller.shuffleEnabled,
                                  builder: (context, snap) {
                                    final on = snap.data ?? false;
                                    return IconButton(
                                      icon: Icon(
                                        Icons.shuffle_rounded,
                                        color: on
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                      tooltip: 'Aleatorio',
                                      onPressed: () =>
                                          _controller.setShuffle(!on),
                                    );
                                  },
                                ),
                                // PREVIOUS
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_previous_rounded,
                                    size: 40,
                                    color: scheme.onSurface,
                                  ),
                                  tooltip: 'Anterior',
                                  onPressed: _controller.previous,
                                ),
                                // PLAY / PAUSE
                                _BigPlayButton(
                                  isPlaying: isPlaying,
                                  onPressed: isPlaying
                                      ? _controller.pause
                                      : _controller.play,
                                  scheme: scheme,
                                ),
                                // NEXT
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    size: 40,
                                    color: _controller.hasNext
                                        ? scheme.onSurface
                                        : scheme.onSurface
                                            .withValues(alpha: 0.3),
                                  ),
                                  tooltip: 'Siguiente',
                                  onPressed: _controller.hasNext
                                      ? _controller.next
                                      : null,
                                ),
                                // REPEAT (reactivo al handler)
                                StreamBuilder<PlayerRepeatMode>(
                                  stream: _controller.repeat,
                                  initialData: _controller.repeatModeNow,
                                  builder: (context, snap) {
                                    final mode =
                                        snap.data ?? PlayerRepeatMode.off;
                                    final icon = switch (mode) {
                                      PlayerRepeatMode.one =>
                                        Icons.repeat_one_rounded,
                                      _ => Icons.repeat_rounded,
                                    };
                                    final active =
                                        mode != PlayerRepeatMode.off;
                                    return IconButton(
                                      icon: Icon(
                                        icon,
                                        color: active
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                      tooltip: 'Repetir',
                                      onPressed: () {
                                        final next = switch (mode) {
                                          PlayerRepeatMode.off =>
                                            PlayerRepeatMode.all,
                                          PlayerRepeatMode.all =>
                                            PlayerRepeatMode.one,
                                          PlayerRepeatMode.one =>
                                            PlayerRepeatMode.off,
                                        };
                                        _controller.setRepeatMode(next);
                                      },
                                    );
                                  },
                                ),
                              ],
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
        },
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final Song song;
  final double size;
  const _Cover({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = song.coverPath;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: cover != null && cover.isNotEmpty
          ? Image.file(
              File(cover),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(scheme),
            )
          : _fallback(scheme),
    );
  }

  Widget _fallback(ColorScheme scheme) => DecoratedBox(
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
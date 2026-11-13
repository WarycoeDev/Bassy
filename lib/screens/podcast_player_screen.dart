// lib/screens/podcast_player_screen.dart
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Player de PODCAST: metadatos, velocidad, skip ±15s/30s y progreso.
class PodcastPlayerScreen extends StatefulWidget {
  /// Prefijo del `Hero` que viene del miniplayer que abrió esta pantalla.
  final String? heroTagPrefix;

  const PodcastPlayerScreen({super.key, this.heroTagPrefix});

  @override
  State<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends State<PodcastPlayerScreen> {
  final _controller = PlaybackController.instance;

  double _speed = 1.0;

  /// Valor del dedo mientras se arrastra el slider. `null` = no arrastrando.
  double? _seekValue;
  bool get _isSeeking => _seekValue != null;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    final current = _controller.speedNow;
    if (current > 0) _speed = current;
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
        title: const Text('Podcast'),
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

              final streamMs =
                  position.inMilliseconds.toDouble().clamp(0.0, maxMs);
              final valueMs = _isSeeking ? _seekValue! : streamMs;

              final shownPosition = _isSeeking
                  ? Duration(milliseconds: valueMs.round())
                  : position;
              final remaining = duration - shownPosition;

              return StreamBuilder<bool>(
                stream: _controller.isPlaying,
                initialData: _controller.handler.isPlaying,
                builder: (context, playingSnap) {
                  final isPlaying = playingSnap.data ?? false;

                  final cover =
                      _PodcastCover(song: song, scheme: scheme);
                  final heroPrefix = widget.heroTagPrefix;
                  final heroCover = heroPrefix == null
                      ? cover
                      : Hero(
                          tag: '$heroPrefix${song.path}',
                          child: cover,
                        );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cabecera horizontal: cover + meta
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heroCover,
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    song.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Faltan ${_fmt(remaining)}',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Barra de progreso con seek
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: maxMs,
                            value: valueMs,
                            onChangeStart: duration.inMilliseconds > 0
                                ? (v) => setState(() => _seekValue = v)
                                : null,
                            onChanged: duration.inMilliseconds > 0
                                ? (v) => setState(() => _seekValue = v)
                                : null,
                            onChangeEnd: duration.inMilliseconds > 0
                                ? _onSeekEnd
                                : null,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmt(shownPosition),
                                style: _timeStyle(scheme),
                              ),
                              Text(
                                _fmt(duration),
                                style: _timeStyle(scheme),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Fila de skip + play
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _SkipButton(
                              icon: Icons.replay_10_rounded,
                              label: '15',
                              onPressed: () {
                                final t =
                                    position - const Duration(seconds: 15);
                                _controller.seek(
                                  t < Duration.zero ? Duration.zero : t,
                                );
                              },
                              scheme: scheme,
                            ),
                            const SizedBox(width: 24),
                            _PodcastPlayButton(
                              isPlaying: isPlaying,
                              onPressed: isPlaying
                                  ? _controller.pause
                                  : _controller.play,
                              scheme: scheme,
                            ),
                            const SizedBox(width: 24),
                            _SkipButton(
                              icon: Icons.forward_10_rounded,
                              label: '30',
                              onPressed: () {
                                final t =
                                    position + const Duration(seconds: 30);
                                _controller.seek(
                                  t > duration ? duration : t,
                                );
                              },
                              scheme: scheme,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Selector de velocidad
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: scheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.speed_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Velocidad',
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              DropdownButton<double>(
                                value: _speed,
                                underline: const SizedBox.shrink(),
                                dropdownColor: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                                items: [
                                  for (final s in _speeds)
                                    DropdownMenuItem(
                                      value: s,
                                      child: Text('${s}x'),
                                    ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _speed = v);
                                  _controller.setSpeed(v);
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Metadatos disponibles en Song
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _metaRow(
                                'Álbum',
                                song.albumOrUnknown,
                                scheme,
                              ),
                              const SizedBox(height: 8),
                              _metaRow(
                                'Artista',
                                song.artistOrUnknown,
                                scheme,
                              ),
                              const SizedBox(height: 8),
                              _metaRow(
                                'Archivo',
                                song.fileName,
                                scheme,
                              ),
                              const SizedBox(height: 8),
                              _metaRow(
                                'Formato',
                                '${song.extension.toUpperCase()} · ${song.sizeLabel}',
                                scheme,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  TextStyle _timeStyle(ColorScheme scheme) => TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _metaRow(String label, String value, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurface, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _PodcastCover extends StatelessWidget {
  final Song song;
  final ColorScheme scheme;
  const _PodcastCover({required this.song, required this.scheme});

  @override
  Widget build(BuildContext context) {
    const size = 96.0;
    final cover = song.coverPath;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        // Radius fijo (24) para que el vuelo del Hero no salte al aterrizar.
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: cover != null && cover.isNotEmpty
          ? Image.file(
              File(cover),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
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
          Icons.podcasts_rounded,
          color: scheme.onPrimaryContainer,
          size: 40,
        ),
      );
}

class _SkipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final ColorScheme scheme;
  const _SkipButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(icon, size: 38, color: scheme.onSurface),
          onPressed: onPressed,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _PodcastPlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final ColorScheme scheme;
  const _PodcastPlayButton({
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
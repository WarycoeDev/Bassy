// lib/screens/podcast_player_screen.dart
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Player de PODCAST: metadatos, velocidad, skip ±segundos y progreso.
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

  /// Valor del dedo mientras se arrastra el slider de seek. `null` = no arrastrando.
  double? _seekValue;
  bool get _isSeeking => _seekValue != null;

  /// Valor del dedo mientras se arrastra el slider de volumen.
  double? _volumeValue;
  bool get _isAdjustingVolume => _volumeValue != null;

  /// Último volumen > 0 para restaurar al desmutear.
  double _lastNonZeroVolume = 1.0;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  int get _speedIndex {
    final i = _speeds.indexOf(_speed);
    return i < 0 ? 1 : i; // fallback a 1.0x
  }

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

  void _onSpeedSelected(double v) {
    if (v == _speed) return;
    setState(() => _speed = v);
    _controller.setSpeed(v);
  }

  // ---------- Callbacks del slider de volumen ----------
  void _onVolumeStart(double v) => setState(() => _volumeValue = v);

  void _onVolumeChanged(double v) {
    setState(() => _volumeValue = v);
    if (v > 0.001) {
      _lastNonZeroVolume = v;
    }
    _controller.setVolume(v);
  }

  void _onVolumeEnd(double _) => setState(() => _volumeValue = null);

  void _onVolumeUpdateLast(double v) => _lastNonZeroVolume = v;

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

                  final cover = _PodcastCover(song: song, scheme: scheme);
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

                        // Fila de skip + play (play/pausa copiado de music player)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _SkipButton(
                              forward: false,
                              seconds: 10,
                              onPressed: () {
                                final t =
                                    position - const Duration(seconds: 10);
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
                              forward: true,
                              seconds: 30,
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

                        const SizedBox(height: 16),

                        // ═══════════════════════════════════════════════
                        // SLIDER DE VOLUMEN (copiado de music_player_screen)
                        // ═══════════════════════════════════════════════
                        _VolumeRow(
                          scheme: scheme,
                          isAdjustingVolume: _isAdjustingVolume,
                          volumeValue: _volumeValue,
                          lastNonZeroVolume: _lastNonZeroVolume,
                          onStart: _onVolumeStart,
                          onChanged: _onVolumeChanged,
                          onEnd: _onVolumeEnd,
                          onUpdateLast: _onVolumeUpdateLast,
                        ),

                        const SizedBox(height: 24),

                        // ═══════════════════════════════════════════════
                        // VARIANTE 1: Selector de velocidad [- / +]
                        // ═══════════════════════════════════════════════
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
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
                              _StepBtn(
                                icon: Icons.remove_rounded,
                                scheme: scheme,
                                enabled: _speedIndex > 0,
                                onPressed: () => _onSpeedSelected(
                                  _speeds[_speedIndex - 1],
                                ),
                              ),
                              SizedBox(
                                width: 56,
                                child: Center(
                                  child: Text(
                                    '${_speed}x',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _StepBtn(
                                icon: Icons.add_rounded,
                                scheme: scheme,
                                enabled: _speedIndex < _speeds.length - 1,
                                onPressed: () => _onSpeedSelected(
                                  _speeds[_speedIndex + 1],
                                ),
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
                              _metaRow('Álbum', song.albumOrUnknown, scheme),
                              const SizedBox(height: 8),
                              _metaRow('Artista', song.artistOrUnknown, scheme),
                              const SizedBox(height: 8),
                              _metaRow('Archivo', song.fileName, scheme),
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

// ============================================================
// FILA DE VOLUMEN (copiada de music_player_screen.dart)
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
        final volume = isAdjustingVolume ? volumeValue! : safeStream;
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

/// Botón de salto (±segundos) con iconos nativos simétricos de Material.
class _SkipButton extends StatelessWidget {
  final bool forward;

  /// Segundos del salto. Soportados nativamente: 5, 10 y 30.
  final int seconds;
  final VoidCallback onPressed;
  final ColorScheme scheme;

  const _SkipButton({
    required this.forward,
    required this.seconds,
    required this.onPressed,
    required this.scheme,
  });

  IconData get _icon {
    if (forward) {
      switch (seconds) {
        case 5:
          return Icons.forward_5_rounded;
        case 30:
          return Icons.forward_30_rounded;
        case 10:
        default:
          return Icons.forward_10_rounded;
      }
    } else {
      switch (seconds) {
        case 5:
          return Icons.replay_5_rounded;
        case 30:
          return Icons.replay_30_rounded;
        case 10:
        default:
          return Icons.replay_10_rounded;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_icon, size: 38, color: scheme.onSurface),
      onPressed: onPressed,
    );
  }
}

/// VARIANTE 1: botón circular [-] / [+] para el selector de velocidad.
class _StepBtn extends StatelessWidget {
  final IconData icon;
  final ColorScheme scheme;
  final bool enabled;
  final VoidCallback onPressed;

  const _StepBtn({
    required this.icon,
    required this.scheme,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTÓN PLAY/PAUSA (copiado de _BigPlayButton en music_player_screen)
// ============================================================
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
            // Scale + fade, idéntico a _BigPlayButton del music player.
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
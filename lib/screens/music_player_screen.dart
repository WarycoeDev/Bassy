// lib/screens/music_player_screen.dart
import 'dart:io';
import 'dart:ui' show FontFeature;

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

              return StreamBuilder<bool>(
                stream: _controller.isPlaying,
                initialData: _controller.handler.isPlaying,
                builder: (context, playingSnap) {
                  final isPlaying = playingSnap.data ?? false;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final coverSize = (constraints.maxWidth * 0.72)
                          .clamp(180.0, 360.0);

                      // Animación de la carátula al cambiar de canción.
                      // El Hero se mantiene FUERA del AnimatedSwitcher para
                      // no interferir con el vuelo del Hero entre pantallas.
                      final cover = _AnimatedCover(
                        song: song,
                        size: coverSize,
                      );
                      final heroPrefix = widget.heroTagPrefix;
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
                            // Título + artista animados (cross-fade + scale)
                            _AnimatedSongInfo(
                              song: song,
                              scheme: scheme,
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // ---------- ALEATORIO (animado) ----------
                                StreamBuilder<bool>(
                                  stream: _controller.shuffle,
                                  initialData: _controller.shuffleEnabled,
                                  builder: (context, snap) {
                                    final on = snap.data ?? false;
                                    return _AnimatedIconButton(
                                      icon: Icons.shuffle_rounded,
                                      tooltip: 'Aleatorio',
                                      scheme: scheme,
                                      size: 24,
                                      color: on
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                      stateKey: on,
                                      onPressed: () =>
                                          _controller.setShuffle(!on),
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
                                  onPressed: _controller.previous,
                                ),
                                _BigPlayButton(
                                  isPlaying: isPlaying,
                                  onPressed: isPlaying
                                      ? _controller.pause
                                      : _controller.play,
                                  scheme: scheme,
                                ),
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
                                // ---------- REPETIR (animado) ----------
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
                                    return _AnimatedIconButton(
                                      icon: icon,
                                      tooltip: 'Repetir',
                                      scheme: scheme,
                                      size: 24,
                                      color: active
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                      stateKey: mode,
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
                            const SizedBox(height: 8),
                            // ---------- VOLUMEN ----------
                            ValueListenableBuilder<double>(
                              valueListenable: _controller.volume,
                              builder: (context, streamVolume, _) {
                                final safeStream =
                                    streamVolume.clamp(0.0, 1.0);
                                final volume = _isAdjustingVolume
                                    ? _volumeValue!
                                    : safeStream;
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
                                      tooltip: muted
                                          ? 'Activar sonido'
                                          : 'Silenciar',
                                      onPressed: () {
                                        if (muted) {
                                          _controller.setVolume(
                                              _lastNonZeroVolume);
                                        } else {
                                          _lastNonZeroVolume = volume;
                                          _controller.setVolume(0);
                                        }
                                      },
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data:
                                            SliderTheme.of(context).copyWith(
                                          trackHeight: 2,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                            enabledThumbRadius: 6,
                                          ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                            overlayRadius: 12,
                                          ),
                                        ),
                                        child: Slider(
                                          min: 0,
                                          max: 1,
                                          value: volume,
                                          onChangeStart: (v) {
                                            setState(
                                                () => _volumeValue = v);
                                          },
                                          onChanged: (v) {
                                            setState(
                                                () => _volumeValue = v);
                                            if (v > 0.001) {
                                              _lastNonZeroVolume = v;
                                            }
                                            _controller.setVolume(v);
                                          },
                                          onChangeEnd: (v) {
                                            setState(
                                                () => _volumeValue = null);
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            // ---------- BOTONES CENTRALES ----------
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Favoritos (animado, conectado a FavoritesStore)
                                ListenableBuilder(
                                  listenable: FavoritesStore.instance,
                                  builder: (context, _) {
                                    final isFav =
                                        FavoritesStore.instance.contains(song);
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
                                        await FavoritesStore.instance
                                            .toggle(song);
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context);
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                // Ver cola (funcional)
                                _LabeledButton(
                                  icon: Icons.playlist_play_rounded,
                                  label: 'Ver Cola',
                                  scheme: scheme,
                                  onPressed: () {
                                    QueueViewer.show(context);
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

// ============================================================
// CARÁTULA ANIMADA (cross-fade + scale al cambiar de canción)
// El contenedor externo (tamaño, sombra, radio) se mantiene fijo
// para que el layout no "salte"; solo anima el contenido interno.
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
          _MarqueeTitle(
            title: song.title,
            scheme: scheme,
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
        ],
      ),
    );
  }
}

// ============================================================
// TÍTULO CON MARQUESINA CÍCLICA
// - Si el texto cabe: se muestra normal, centrado.
// - Si no cabe: scroll continuo izq→der con 2 copias + pausa
//   de 2 s al final de cada vuelta (bucle infinito).
//
// Claves para que NO se corte y el bucle sea perfecto:
//  * Se mide con TextPainter respetando MediaQuery.textScalerOf.
//  * El Row interno mide su ancho real (2*textWidth + gap) y vive
//    dentro de un OverflowBox; el ClipRect exterior recorta la vista
//    pero no el layout, así no se pierde ningún píxel del texto.
//  * Transform.translate se aplica al Row completo, no a cada Text.
//  * dx recorre exactamente textWidth + gap por ciclo: al reiniciar,
//    la copia 2 queda donde estaba la copia 1 → bucle invisible.
//  * Un TweenSequence añade un tramo ConstantTween de 2 s al final.
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
  static const _gap = 64.0; // separación visual entre las 2 copias
  static const _pause = Duration(seconds: 2);
  static const _speed = 40.0; // px/s (más lento = más legible)

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

  /// Reconfigura el controller para un ciclo: mover + pausa.
  /// Solo se llama desde un post-frame callback, nunca durante build.
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
// BOTÓN DE ICONO ANIMADO (misma animación que play/pausa)
// Usado para Aleatorio y Repetir.
// `stateKey` fuerza el cambio visual aunque el icono sea el mismo
// (ej. shuffle cambia solo de color; repeat off↔all comparte icono).
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
// BOTÓN REDONDO ANIMADO (solo icono) — usado para Favoritos
// ============================================================
class _AnimatedRoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final ColorScheme scheme;

  /// Color opcional del icono. Si es `null`, usa `scheme.onSurface`.
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
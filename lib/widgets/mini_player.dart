// lib/widgets/mini_player.dart
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';

// ============================================================
// HELPERS COMPARTIDOS
// ============================================================
String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ============================================================
// MINIPLAYER TIPO TARJETA (panel lateral tablet/PC)
// ============================================================
class MiniPlayerCard extends StatelessWidget {
  const MiniPlayerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;
    if (!controller.isReady) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<MediaItem?>(
      stream: controller.currentItem,
      builder: (context, mediaSnap) {
        final song = controller.currentSong;
        if (song == null || mediaSnap.data == null) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<bool>(
          stream: controller.isPlaying,
          initialData: controller.handler.isPlaying,
          builder: (context, playingSnap) {
            final isPlaying = playingSnap.data ?? false;

            return StreamBuilder<Duration>(
              stream: controller.position,
              builder: (context, posSnap) {
                final position = posSnap.data ?? Duration.zero;
                final duration = song.duration ?? Duration.zero;
                final progress = duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;

                return Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.surfaceContainerHigh,
                        scheme.surfaceContainer,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Cabecera: cover + info ---
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Row(
                          children: [
                            _MiniCover(song: song, scheme: scheme, size: 56),
                            const SizedBox(width: 14),
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
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      letterSpacing: -0.2,
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
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // --- Progreso + tiempos ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: progress),
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                                builder: (_, value, __) =>
                                    LinearProgressIndicator(
                                  value: value,
                                  minHeight: 4,
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation(
                                    scheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _fmt(position),
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 10.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                Text(
                                  _fmt(duration),
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 10.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // --- Controles ---
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded),
                              iconSize: 30,
                              color: scheme.onSurface,
                              onPressed: controller.previous,
                              tooltip: 'Anterior',
                            ),
                            _PlayButton(
                              isPlaying: isPlaying,
                              onPressed: isPlaying
                                  ? controller.pause
                                  : controller.play,
                              scheme: scheme,
                              size: 56,
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded),
                              iconSize: 30,
                              color: scheme.onSurface,
                              onPressed: controller.next,
                              tooltip: 'Siguiente',
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
    );
  }
}

// ============================================================
// MINIPLAYER TIPO BARRA (móvil, parte inferior)
// ============================================================
// ============================================================
// MINIPLAYER TIPO BARRA FLOTANTE (móvil, sobre el contenido)
// ============================================================
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;
    if (!controller.isReady) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<MediaItem?>(
      stream: controller.currentItem,
      builder: (context, mediaSnap) {
        final song = controller.currentSong;
        if (song == null || mediaSnap.data == null) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<bool>(
          stream: controller.isPlaying,
          initialData: controller.handler.isPlaying,
          builder: (context, playingSnap) {
            final isPlaying = playingSnap.data ?? false;

            return StreamBuilder<Duration>(
              stream: controller.position,
              builder: (context, posSnap) {
                final position = posSnap.data ?? Duration.zero;
                final duration = song.duration ?? Duration.zero;
                final progress = duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;

                // --- Contenedor flotante ---
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.surfaceContainerHigh,
                            scheme.surfaceContainer,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.22),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // --- Barra de progreso fina (pegada al borde superior) ---
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: progress),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            builder: (_, value, __) => LinearProgressIndicator(
                              value: value,
                              minHeight: 2.5,
                              backgroundColor:
                                  scheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation(
                                scheme.primary,
                              ),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(10, 10, 6, 10),
                            child: Row(
                              children: [
                                _MiniCover(
                                  song: song,
                                  scheme: scheme,
                                  size: 46,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
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
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _PlayButton(
                                  isPlaying: isPlaying,
                                  onPressed: isPlaying
                                      ? controller.pause
                                      : controller.play,
                                  scheme: scheme,
                                  size: 42,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next_rounded),
                                  iconSize: 26,
                                  color: scheme.onSurface,
                                  onPressed: controller.next,
                                  tooltip: 'Siguiente',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
// BOTÓN PLAY/PAUSE ANIMADO
// ============================================================
class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final ColorScheme scheme;
  final double size;

  const _PlayButton({
    required this.isPlaying,
    required this.onPressed,
    required this.scheme,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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
            color: scheme.primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
              size: size * 0.55,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CARÁTULA COMPARTIDA (mejorada)
// ============================================================
class _MiniCover extends StatelessWidget {
  final Song song;
  final ColorScheme scheme;
  final double size;

  const _MiniCover({
    required this.song,
    required this.scheme,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cover = song.coverPath;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * 0.23),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
            colors: [
              scheme.primaryContainer,
              scheme.tertiaryContainer,
            ],
          ),
        ),
        child: Icon(
          Icons.music_note_rounded,
          color: scheme.onPrimaryContainer,
          size: size * 0.5,
        ),
      );
}
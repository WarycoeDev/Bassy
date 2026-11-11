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

/// Umbral para decidir si "previous" reinicia la canción o salta a la anterior.
const Duration _kRestartThreshold = Duration(seconds: 3);

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

                // --- Estado de los botones ---
                final canGoPrevious =
                    controller.hasPrevious || position > _kRestartThreshold;
                final canGoNext = controller.hasNext;
                final canPlayPause = true; // siempre hay canción aquí

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
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
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
                            _ControlIconButton(
                              icon: Icons.skip_previous_rounded,
                              iconSize: 30,
                              enabled: canGoPrevious,
                              scheme: scheme,
                              onPressed: controller.previous,
                              tooltip: 'Anterior',
                            ),
                            _PlayButton(
                              isPlaying: isPlaying,
                              onPressed: canPlayPause
                                  ? (isPlaying
                                      ? controller.pause
                                      : controller.play)
                                  : null,
                              scheme: scheme,
                              size: 56,
                            ),
                            _ControlIconButton(
                              icon: Icons.skip_next_rounded,
                              iconSize: 30,
                              enabled: canGoNext,
                              scheme: scheme,
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
// MINIPLAYER TIPO BARRA FLOTANTE (móvil, sobre el contenido)
// ============================================================
class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

enum _MiniPlayerVisibility { visible, hiddenBySwipe }

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  _MiniPlayerVisibility _visibility = _MiniPlayerVisibility.visible;

  AnimationController? _settleController;
  Animation<Offset>? _offsetAnim;
  Animation<double>? _opacityAnim;

  Offset _dragOffset = Offset.zero;
  double _dragOpacity = 1.0;

  Offset _settleOffset = Offset.zero;
  double _settleOpacity = 1.0;

  bool _animatingOut = false;

  bool _pendingEntrance = false;

  String? _lastItemId;

  static const double _dragThreshold = 160;
  static const double _velocityThreshold = 350;
  static const Offset _closeTarget = Offset(400, 0);
  static const Offset _hideTarget = Offset(0, 200);

  @override
  void initState() {
    super.initState();
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    c.addListener(_onSettleTick);
    _settleController = c;
    _pendingEntrance = true;
  }

  void _onSettleTick() {
    final o = _offsetAnim;
    final op = _opacityAnim;
    if (o == null || op == null) return;
    if (!mounted) return;
    setState(() {
      _settleOffset = o.value;
      _settleOpacity = op.value;
    });
  }

  @override
  void dispose() {
    final c = _settleController;
    _settleController = null;
    _offsetAnim = null;
    _opacityAnim = null;
    if (c != null) {
      c.removeListener(_onSettleTick);
      c.dispose();
    }
    super.dispose();
  }

  void _resetVisualState({bool triggerEntrance = true}) {
    _settleController?.reset();
    _offsetAnim = null;
    _opacityAnim = null;
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _settleOffset = Offset.zero;
    _settleOpacity = 1.0;
    _animatingOut = false;
    _visibility = _MiniPlayerVisibility.visible;
    _pendingEntrance = triggerEntrance;
  }

  Offset get _effectiveOffset => _dragOffset + _settleOffset;
  double get _effectiveOpacity =>
      (_dragOpacity * _settleOpacity).clamp(0.0, 1.0);

  // ---------- Settle helper ----------

  Future<void> _settle({
    required Offset target,
    required double targetOpacity,
    Curve curve = Curves.easeOutCubic,
    VoidCallback? onDone,
  }) async {
    final controller = _settleController;
    if (!mounted || controller == null) {
      onDone?.call();
      return;
    }

    final startOffset = _effectiveOffset;
    final startOpacity = _effectiveOpacity;

    _offsetAnim = Tween<Offset>(begin: startOffset, end: target)
        .chain(CurveTween(curve: curve))
        .animate(controller);
    _opacityAnim = Tween<double>(begin: startOpacity, end: targetOpacity)
        .chain(CurveTween(curve: curve))
        .animate(controller);

    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;

    controller.reset();
    try {
      await controller.forward().orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    onDone?.call();
  }

  // ---------- Cierre (swipe derecha) ----------

  Future<void> _closeAndClear() async {
    if (_animatingOut) return;
    setState(() => _animatingOut = true);

    await _settle(target: _closeTarget, targetOpacity: 0.0);
    if (!mounted) return;

    await PlaybackController.instance.clearQueue();
    if (!mounted) return;

    setState(() {
      _animatingOut = false;
      _settleOffset = Offset.zero;
      _settleOpacity = 1.0;
      _dragOffset = Offset.zero;
      _dragOpacity = 1.0;
    });
    _settleController?.reset();
  }

  // ---------- Ocultar (swipe abajo) ----------

  Future<void> _hide() async {
    if (_animatingOut) return;
    setState(() => _animatingOut = true);

    await _settle(target: _hideTarget, targetOpacity: 0.0);
    if (!mounted) return;

    setState(() {
      _visibility = _MiniPlayerVisibility.hiddenBySwipe;
      _animatingOut = false;
      _settleOffset = Offset.zero;
      _settleOpacity = 1.0;
      _dragOffset = Offset.zero;
      _dragOpacity = 1.0;
    });
    _settleController?.reset();
  }

  // ---------- Mostrar (tap en FAB) ----------

  void _show() {
    if (_visibility == _MiniPlayerVisibility.visible) return;
    setState(() {
      _visibility = _MiniPlayerVisibility.visible;
      _dragOffset = _hideTarget;
      _dragOpacity = 0.0;
      _settleOffset = Offset.zero;
      _settleOpacity = 1.0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _settle(target: Offset.zero, targetOpacity: 1.0);
    });
  }

  // ---------- Snap-back ----------

  void _snapBack() {
    _settle(target: Offset.zero, targetOpacity: 1.0);
  }

  // ---------- Gestos ----------

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (_animatingOut) return;
    final next = (_dragOffset.dx + d.delta.dx).clamp(0.0, 400.0);
    setState(() {
      _dragOffset = Offset(next, 0);
      _dragOpacity = (1.0 - next / 400.0).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_animatingOut) return;
    final next = (_dragOffset.dy + d.delta.dy).clamp(0.0, 200.0);
    setState(() {
      _dragOffset = Offset(0, next);
      _dragOpacity = (1.0 - next / 200.0).clamp(0.0, 1.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    if (_animatingOut) return;
    final v = d.primaryVelocity ?? 0;
    final passed = v > _velocityThreshold || _dragOffset.dx > _dragThreshold;
    if (passed) {
      _closeAndClear();
    } else {
      _snapBack();
    }
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_animatingOut) return;
    final v = d.primaryVelocity ?? 0;
    final passed = v > _velocityThreshold || _dragOffset.dy > _dragThreshold;
    if (passed) {
      _hide();
    } else {
      _snapBack();
    }
  }

  void _onDragCancel() {
    if (_animatingOut) return;
    _snapBack();
  }

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;
    if (!controller.isReady) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<MediaItem?>(
      stream: controller.currentItem,
      builder: (context, mediaSnap) {
        final song = controller.currentSong;
        final itemId = mediaSnap.data?.id;

        // --- Sin canción actual ---
        if (song == null || mediaSnap.data == null) {
          if (_lastItemId != null ||
              _dragOffset != Offset.zero ||
              _settleOffset != Offset.zero ||
              _visibility != _MiniPlayerVisibility.visible ||
              _animatingOut ||
              !_pendingEntrance) {
            _lastItemId = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_lastItemId != null) return;
              setState(() => _resetVisualState(triggerEntrance: true));
            });
          }
          return const SizedBox.shrink();
        }

        // --- Hay canción ---
        if (_lastItemId != itemId) {
          _lastItemId = itemId;
          if (!_pendingEntrance) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_lastItemId != itemId) return;
              setState(() {
                _settleController?.reset();
                _offsetAnim = null;
                _opacityAnim = null;
                _dragOffset = Offset.zero;
                _dragOpacity = 1.0;
                _settleOffset = Offset.zero;
                _settleOpacity = 1.0;
              });
            });
          }
        }

        // --- Animación de entrada ---
        if (_pendingEntrance) {
          _pendingEntrance = false;
          _settleController?.reset();
          _offsetAnim = null;
          _opacityAnim = null;
          _dragOffset = _hideTarget;
          _dragOpacity = 0.0;
          _settleOffset = Offset.zero;
          _settleOpacity = 1.0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _settle(target: Offset.zero, targetOpacity: 1.0);
          });
        }

        // --- Estado oculto: FAB para restaurar ---
        if (_visibility == _MiniPlayerVisibility.hiddenBySwipe) {
          return Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 16),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 24),
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: Ink(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primary,
                          Color.lerp(
                            scheme.primary,
                            scheme.tertiary,
                            0.3,
                          )!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _show,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: scheme.onPrimary,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // --- Estado visible: miniplayer + gestos ---
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

                // --- Estado de los botones ---
                final canGoPrevious =
                    controller.hasPrevious || position > _kRestartThreshold;
                final canGoNext = controller.hasNext;

                final bar = Padding(
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
                          color: scheme.outlineVariant
                              .withValues(alpha: 0.4),
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
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: progress),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            builder: (_, value, __) =>
                                LinearProgressIndicator(
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
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                          fontWeight:
                                              FontWeight.w600,
                                          fontSize: 14,
                                          letterSpacing: -0.1,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.subtitle,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: scheme
                                              .onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),

                                // Previous (desactivable)
                                _ControlIconButton(
                                  icon: Icons.skip_previous_rounded,
                                  iconSize: 24,
                                  enabled: canGoPrevious,
                                  scheme: scheme,
                                  onPressed: controller.previous,
                                  tooltip: 'Anterior',
                                  compact: true,
                                ),

                                _PlayButton(
                                  isPlaying: isPlaying,
                                  onPressed: isPlaying
                                      ? controller.pause
                                      : controller.play,
                                  scheme: scheme,
                                  size: 40,
                                ),

                                // Next (desactivable)
                                _ControlIconButton(
                                  icon: Icons.skip_next_rounded,
                                  iconSize: 24,
                                  enabled: canGoNext,
                                  scheme: scheme,
                                  onPressed: controller.next,
                                  tooltip: 'Siguiente',
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  onHorizontalDragCancel: _onDragCancel,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  onVerticalDragCancel: _onDragCancel,
                  child: Opacity(
                    opacity: _effectiveOpacity,
                    child: Transform.translate(
                      offset: _effectiveOffset,
                      child: bar,
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
// BOTÓN DE CONTROL REUTILIZABLE (previous/next con estado enabled)
// ============================================================
class _ControlIconButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final bool enabled;
  final ColorScheme scheme;
  final VoidCallback onPressed;
  final String tooltip;
  final bool compact;

  const _ControlIconButton({
    required this.icon,
    required this.iconSize,
    required this.enabled,
    required this.scheme,
    required this.onPressed,
    required this.tooltip,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = scheme.onSurface;
    final color = enabled ? baseColor : baseColor.withValues(alpha: 0.3);

    return IconButton(
      icon: Icon(icon),
      iconSize: iconSize,
      color: color,
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints(minWidth: 34, minHeight: 34)
          : null,
    );
  }
}

// ============================================================
// BOTÓN PLAY/PAUSE ANIMADO
// ============================================================
class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback? onPressed;
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
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Container(
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
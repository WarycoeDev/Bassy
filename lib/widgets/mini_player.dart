// lib/widgets/mini_player.dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/song.dart';
import '../screens/player_router.dart';
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

/// Prefijos de Hero. Se usan para que `MiniPlayerCard` y `MiniPlayerBar`
/// no compartan tag si conviven en el mismo árbol (tablet/PC).
const String _kCardHeroPrefix = 'card-';
const String _kBarHeroPrefix = 'bar-';

/// `true` si el framework está en medio de un frame (build/layout/paint).
bool _isInFrame() {
  final phase = SchedulerBinding.instance.schedulerPhase;
  return phase == SchedulerPhase.persistentCallbacks ||
      phase == SchedulerPhase.midFrameMicrotasks ||
      phase == SchedulerPhase.transientCallbacks;
}

// ============================================================
// MINIPLAYER TIPO TARJETA (panel lateral tablet/PC)
// ============================================================
class MiniPlayerCard extends StatefulWidget {
  const MiniPlayerCard({super.key});

  @override
  State<MiniPlayerCard> createState() => _MiniPlayerCardState();
}

class _MiniPlayerCardState extends State<MiniPlayerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<Offset>? _offsetAnim;
  Animation<double>? _opacityAnim;

  Offset _dragOffset = Offset.zero;
  double _dragOpacity = 1.0;

  bool _animatingOut = false;
  bool _pendingEntrance = false;
  bool _resetScheduled = false;
  bool _entranceScheduled = false;

  String? _lastItemId;

  static const double _dragThreshold = 120;
  static const double _velocityThreshold = 350;
  static const double _offscreenY = 400;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _pendingEntrance = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetVisualState({bool triggerEntrance = true}) {
    _controller.reset();
    _offsetAnim = null;
    _opacityAnim = null;
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _animatingOut = false;
    _pendingEntrance = triggerEntrance;
  }

  Offset get _effectiveOffset =>
      _dragOffset + (_offsetAnim?.value ?? Offset.zero);
  double get _effectiveOpacity =>
      (_dragOpacity * (_opacityAnim?.value ?? 1.0)).clamp(0.0, 1.0);

  // ------------------------------------------------------------
  // Programadores seguros (macrotask: corren FUERA del frame)
  // ------------------------------------------------------------
  void _scheduleReset() {
    if (_resetScheduled) return;
    _resetScheduled = true;
    Timer.run(() {
      _resetScheduled = false;
      if (!mounted) return;
      if (_lastItemId != null) return;
      if (_isInFrame()) {
        _scheduleReset();
        return;
      }
      setState(() => _resetVisualState(triggerEntrance: true));
    });
  }

  void _scheduleEntrance() {
    if (_entranceScheduled) return;
    _entranceScheduled = true;
    Timer.run(() {
      _entranceScheduled = false;
      if (!mounted) return;
      if (_isInFrame()) {
        _scheduleEntrance();
        return;
      }
      _playEntrance();
    });
  }

  Future<void> _settle({
    required Offset targetOffset,
    required double targetOpacity,
    required int durationMs,
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (!mounted) return;

    final startOffset = _effectiveOffset;
    final startOpacity = _effectiveOpacity;

    _offsetAnim = Tween<Offset>(begin: startOffset, end: targetOffset)
        .chain(CurveTween(curve: curve))
        .animate(_controller);
    _opacityAnim = Tween<double>(begin: startOpacity, end: targetOpacity)
        .chain(CurveTween(curve: curve))
        .animate(_controller);

    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;

    _controller.duration = Duration(milliseconds: durationMs);
    _controller.reset();
    try {
      await _controller.forward().orCancel;
    } on TickerCanceled {
      return;
    }
  }

  // ---------- Entrada: aparece desde abajo ----------
  Future<void> _playEntrance() async {
    if (!mounted) return;
    await _settle(
      targetOffset: Offset.zero,
      targetOpacity: 1.0,
      durationMs: 320,
      curve: Curves.easeOutCubic,
    );
  }

  // ---------- Cierre por gesto ----------
  Future<void> _finishCloseWithInertia() async {
    if (_animatingOut) return;
    setState(() => _animatingOut = true);

    final remaining =
        (_offscreenY - _effectiveOffset.dy).clamp(0.0, _offscreenY);
    final fraction = remaining / _offscreenY;
    final durationMs = (260 * fraction).round().clamp(80, 260);

    await _settle(
      targetOffset: const Offset(0, _offscreenY),
      targetOpacity: 0.0,
      durationMs: durationMs,
      curve: Curves.linear,
    );
    if (!mounted) return;

    await PlaybackController.instance.clearQueue();
    if (!mounted) return;

    setState(() => _resetVisualState(triggerEntrance: true));
  }

  // ---------- Cierre por botón X ----------
  Future<void> _closeViaButton() async {
    if (_animatingOut) return;
    setState(() => _animatingOut = true);

    await _settle(
      targetOffset: const Offset(0, _offscreenY),
      targetOpacity: 0.0,
      durationMs: 260,
      curve: Curves.easeInCubic,
    );
    if (!mounted) return;

    await PlaybackController.instance.clearQueue();
    if (!mounted) return;

    setState(() => _resetVisualState(triggerEntrance: true));
  }

  Future<void> _snapBack() async {
    if (!mounted) return;
    await _settle(
      targetOffset: Offset.zero,
      targetOpacity: 1.0,
      durationMs: 220,
      curve: Curves.easeOutCubic,
    );
  }

  // ---------- Gestos ----------
  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_animatingOut) return;
    final next = (_dragOffset.dy + d.delta.dy).clamp(0.0, _offscreenY);
    setState(() {
      _dragOffset = Offset(0, next);
      _dragOpacity = (1.0 - next / _offscreenY).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_animatingOut) return;
    final v = d.primaryVelocity ?? 0;
    final passed = v > _velocityThreshold || _dragOffset.dy > _dragThreshold;
    if (passed) {
      _finishCloseWithInertia();
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
          if (_lastItemId != null) {
            _lastItemId = null;
            _scheduleReset();
          }
          return const SizedBox.shrink();
        }

        // --- Hay canción: preparar estado "fuera de pantalla" SOLO la 1ª vez ---
        if (_lastItemId != itemId) {
          final hadPrevious = _lastItemId != null;
          _lastItemId = itemId;

          if (!hadPrevious) {
            // Primera aparición: preparar entrada desde abajo.
            _controller.reset();
            _offsetAnim = null;
            _opacityAnim = null;
            _dragOffset = const Offset(0, _offscreenY);
            _dragOpacity = 0.0;
            _pendingEntrance = true;
          }
          // Si ya había canción: no tocar animación ni posición.
          // El miniplayer permanece visible y solo cambian textos/carátula.
        }

        if (_pendingEntrance) {
          _pendingEntrance = false;
          _scheduleEntrance();
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

                final canGoPrevious =
                    controller.hasPrevious || position > _kRestartThreshold;
                final canGoNext = controller.hasNext;

                final card = Container(
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
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final s = controller.currentSong;
                        if (s != null) {
                          openPlayerFor(
                            context,
                            s,
                            heroTagPrefix: _kCardHeroPrefix,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Cabecera
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 16, 44, 12),
                                child: Row(
                                  children: [
                                    Hero(
                                      tag: '$_kCardHeroPrefix${song.path}',
                                      child: _MiniCover(
                                        song: song,
                                        scheme: scheme,
                                        size: 56,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
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
                              // Progreso
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0, end: progress),
                                        duration:
                                            const Duration(milliseconds: 300),
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
                              // Controles
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 8, 8, 12),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
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
                                      onPressed: isPlaying
                                          ? controller.pause
                                          : controller.play,
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
                          // Botón X
                          Positioned(
                            top: 4,
                            right: 4,
                            child: IconButton(
                              icon: const Icon(Icons.close_rounded),
                              iconSize: 18,
                              color: scheme.onSurfaceVariant,
                              tooltip: 'Cerrar',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed:
                                  _animatingOut ? null : _closeViaButton,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  onVerticalDragCancel: _onDragCancel,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final settleOffset =
                          _offsetAnim?.value ?? Offset.zero;
                      final settleOpacity =
                          _opacityAnim?.value ?? 1.0;
                      final offset = _dragOffset + settleOffset;
                      final opacity =
                          (_dragOpacity * settleOpacity).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: opacity,
                        child: Transform.translate(
                          offset: offset,
                          child: child,
                        ),
                      );
                    },
                    child: card,
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
// MINIPLAYER TIPO BARRA FLOTANTE (móvil)
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

  bool _animatingOut = false;
  bool _pendingEntrance = false;
  bool _resetScheduled = false;
  bool _entranceScheduled = false;

  String? _lastItemId;

  static const double _dragThreshold = 160;
  static const double _velocityThreshold = 350;
  static const Offset _closeTarget = Offset(400, 0);
  static const Offset _hideTarget = Offset(0, 200);

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _pendingEntrance = true;
  }

  @override
  void dispose() {
    final c = _settleController;
    _settleController = null;
    _offsetAnim = null;
    _opacityAnim = null;
    c?.dispose();
    super.dispose();
  }

  void _resetVisualState({bool triggerEntrance = true}) {
    _settleController?.reset();
    _offsetAnim = null;
    _opacityAnim = null;
    _dragOffset = Offset.zero;
    _dragOpacity = 1.0;
    _animatingOut = false;
    _visibility = _MiniPlayerVisibility.visible;
    _pendingEntrance = triggerEntrance;
  }

  Offset get _effectiveOffset =>
      _dragOffset + (_offsetAnim?.value ?? Offset.zero);
  double get _effectiveOpacity =>
      (_dragOpacity * (_opacityAnim?.value ?? 1.0)).clamp(0.0, 1.0);

  // ------------------------------------------------------------
  // Programadores seguros (macrotask: corren FUERA del frame)
  // ------------------------------------------------------------
  void _scheduleReset() {
    if (_resetScheduled) return;
    _resetScheduled = true;
    Timer.run(() {
      _resetScheduled = false;
      if (!mounted) return;
      if (_lastItemId != null) return;
      if (_isInFrame()) {
        _scheduleReset();
        return;
      }
      setState(() => _resetVisualState(triggerEntrance: true));
    });
  }

  void _scheduleEntrance() {
    if (_entranceScheduled) return;
    _entranceScheduled = true;
    Timer.run(() {
      _entranceScheduled = false;
      if (!mounted) return;
      if (_isInFrame()) {
        _scheduleEntrance();
        return;
      }
      _settle(target: Offset.zero, targetOpacity: 1.0);
    });
  }

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

  Future<void> _closeAndClear() async {
    if (_animatingOut) return;
    setState(() => _animatingOut = true);
    await _settle(target: _closeTarget, targetOpacity: 0.0);
    if (!mounted) return;
    await PlaybackController.instance.clearQueue();
    if (!mounted) return;
    setState(() {
      _animatingOut = false;
      _dragOffset = Offset.zero;
      _dragOpacity = 1.0;
    });
    _settleController?.reset();
  }

  Future<void> _hide() async {
    if (_animatingOut) return;
    setState(() => _animatingOut = true);
    await _settle(target: _hideTarget, targetOpacity: 0.0);
    if (!mounted) return;
    setState(() {
      _visibility = _MiniPlayerVisibility.hiddenBySwipe;
      _animatingOut = false;
      _dragOffset = Offset.zero;
      _dragOpacity = 1.0;
    });
    _settleController?.reset();
  }

  void _show() {
    if (_visibility == _MiniPlayerVisibility.visible) return;
    setState(() {
      _visibility = _MiniPlayerVisibility.visible;
      _dragOffset = _hideTarget;
      _dragOpacity = 0.0;
    });
    _scheduleEntrance();
  }

  void _snapBack() => _settle(target: Offset.zero, targetOpacity: 1.0);

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

        if (song == null || mediaSnap.data == null) {
          if (_lastItemId != null ||
              _dragOffset != Offset.zero ||
              _offsetAnim != null ||
              _visibility != _MiniPlayerVisibility.visible ||
              _animatingOut ||
              !_pendingEntrance) {
            _lastItemId = null;
            _scheduleReset();
          }
          return const SizedBox.shrink();
        }

        // --- Hay canción: preparar estado "fuera de pantalla" SOLO la 1ª vez ---
        if (_lastItemId != itemId) {
          final hadPrevious = _lastItemId != null;
          _lastItemId = itemId;

          if (!hadPrevious) {
            // Primera aparición: preparar entrada desde abajo.
            _settleController?.reset();
            _offsetAnim = null;
            _opacityAnim = null;
            _dragOffset = _hideTarget;
            _dragOpacity = 0.0;
            _pendingEntrance = true;
          }
          // Si ya había canción: no tocar animación ni posición.
          // El miniplayer permanece visible y solo cambian textos/carátula.
        }

        if (_pendingEntrance) {
          _pendingEntrance = false;
          _scheduleEntrance();
        }

        if (_visibility == _MiniPlayerVisibility.hiddenBySwipe) {
          return Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 12),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 16),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.92),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.28),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _show,
                      child: const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: Colors.black,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
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
                          color:
                              scheme.outlineVariant.withValues(alpha: 0.4),
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
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            final s = controller.currentSong;
                            if (s != null) {
                              openPlayerFor(
                                context,
                                s,
                                heroTagPrefix: _kBarHeroPrefix,
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
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
                                padding: const EdgeInsets.fromLTRB(
                                    10, 10, 6, 10),
                                child: Row(
                                  children: [
                                    Hero(
                                      tag: '$_kBarHeroPrefix${song.path}',
                                      child: _MiniCover(
                                        song: song,
                                        scheme: scheme,
                                        size: 46,
                                      ),
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
                    ),
                  ),
                );

                final settleController = _settleController;

                final animatedBar = settleController == null
                    ? Opacity(
                        opacity: _effectiveOpacity,
                        child: Transform.translate(
                          offset: _effectiveOffset,
                          child: bar,
                        ),
                      )
                    : AnimatedBuilder(
                        animation: settleController,
                        builder: (context, child) {
                          final settleOffset =
                              _offsetAnim?.value ?? Offset.zero;
                          final settleOpacity =
                              _opacityAnim?.value ?? 1.0;
                          final offset = _dragOffset + settleOffset;
                          final opacity = (_dragOpacity * settleOpacity)
                              .clamp(0.0, 1.0);
                          return Opacity(
                            opacity: opacity,
                            child: Transform.translate(
                              offset: offset,
                              child: child,
                            ),
                          );
                        },
                        child: bar,
                      );

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  onHorizontalDragCancel: _onDragCancel,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  onVerticalDragCancel: _onDragCancel,
                  child: animatedBar,
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
// BOTÓN DE CONTROL REUTILIZABLE
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
// CARÁTULA COMPARTIDA
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
        // Radius fijo para que el vuelo del Hero no "salte" al aterrizar.
        borderRadius: BorderRadius.circular(24),
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
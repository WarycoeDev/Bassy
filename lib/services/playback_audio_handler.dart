// lib/services/playback_audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'playback_queue.dart';
import 'replay_gain_service.dart';

enum PlayerRepeatMode { off, all, one }

/// Fases de la máquina de estados del crossfade real (dos players).
enum _XfPhase {
  idle, // nada en curso
  preparing, // cargando la siguiente pista en el player secundario
  ready, // secundario cargado, esperando entrar en la ventana
  fading, // principal baja, secundario sube
  handoffSeek, // principal saltando a la siguiente pista (silenciado)
  handoffRamp, // mini-ramp principal↑ / secundario↓
}

class PlaybackAudioHandler extends BaseAudioHandler with SeekHandler {
  late final AudioPlayer _player;
  AndroidLoudnessEnhancer? _loudness;

  // ----- Dos colas independientes -----
  final PlaybackQueue _musicQueue = PlaybackQueue(kind: MediaKind.music);
  final PlaybackQueue _chaptersQueue = PlaybackQueue(kind: MediaKind.podcast);

  PlaybackQueue _activeQueue = PlaybackQueue(kind: MediaKind.music);

  PlaybackQueue _queueFor(MediaKind kind) =>
      kind == MediaKind.podcast ? _chaptersQueue : _musicQueue;

  MediaKind get activeQueueKind => _activeQueue.kind;

  ConcatenatingAudioSource? _queueSource;

  Future<void> _loadChain = Future<void>.value();
  int _loadGeneration = 0;

  bool _loading = false;
  bool _resumeAfterLoad = false;
  bool _handlingCompleted = false;
  bool _reordering = false;

  bool _isSeeking = false;
  int _seekGeneration = 0;
  List<MediaControl>? _lastControls;
  List<int>? _lastCompactActionIndices;
  String? _lastMediaItemKey;
  String? _lastQueueKey;

  DateTime _lastPositionPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _positionPublishEvery = Duration(milliseconds: 250);
  static const _rewindThreshold = Duration(seconds: 3);

  // Volumen + ReplayGain + Boost
  double _userVolume = 1.0;
  double _volume = 1.0;
  final ValueNotifier<double> _volumeNotifier = ValueNotifier<double>(1.0);
  final ReplayGainService _rg = ReplayGainService.instance;
  double _replayGainDb = 0.0;
  double _volumeBoostDb = 0.0;

  // just_audio multiplica por 1000 el valor, pero Android espera milibelios
  // (1 dB = 100 mB), así que hay que pasar dB / 10.
  static const double _kLoudnessGainScale = 10.0;

  // ============================================================
  // TRANSICIONES (Fade In/Out / Crossfade)
  // ============================================================

  bool _transitionsEnabled = false;
  int _transitionMode = 0; // 0 = Crossfade, 1 = Fade In/Out
  double _crossfadeSeconds = 4.0;
  double _fadeSeconds = 3.0;

  /// Factor de volumen del player PRINCIPAL (0..1).
  double _fadeFactor = 1.0;

  /// Factor de volumen del player SECUNDARIO (0..1), solo crossfade.
  double _xfFactor = 0.0;

  /// Mientras es true (modo Fade) el volumen se fuerza a 0: se usa al
  /// cambiar de pista manualmente para que NUNCA suene nada antes del
  /// fade-in.
  bool _fadeSuspended = false;

  /// Ticker de alta frecuencia que calcula los fades. Usa
  /// `_player.position` (que just_audio extrapola entre eventos) en lugar
  /// de `positionStream` (~200 ms), así la rampa es suave y llega a 0.
  Timer? _fadeTimer;
  static const Duration _fadeTick = Duration(milliseconds: 30);

  /// Cuando quedan <= estos ms de pista, el volumen es exactamente 0.
  static const int _zeroGuardMs = 40;

  // ---- Crossfade real (segundo player) ----
  AudioPlayer? _xfPlayer;
  AndroidLoudnessEnhancer? _xfLoudness;
  _XfPhase _xfPhase = _XfPhase.idle;
  int _xfGen = 0;
  int _xfNextIndex = -1; // índice (en el source) de la pista siguiente
  int _xfFromIndex = -1; // índice del principal al empezar el crossfade
  int _xfBlockedFrom = -1; // índice donde falló la precarga (no reintentar)
  final Stopwatch _xfRamp = Stopwatch();
  static const int _xfRampMs = 120;
  double _xfSeekLatencyMs = 120.0; // se autoajusta

  // Últimos volúmenes enviados (evita llamadas redundantes al canal nativo).
  double _lastSetPrimary = 1.0;
  double _lastSetSecondary = 0.0;

  bool get _xfAudible =>
      _xfPhase == _XfPhase.fading ||
      _xfPhase == _XfPhase.handoffSeek ||
      _xfPhase == _XfPhase.handoffRamp;

  final _shuffleCtrl = StreamController<bool>.broadcast();
  final _repeatCtrl = StreamController<PlayerRepeatMode>.broadcast();
  final _canGoPreviousCtrl = StreamController<bool>.broadcast();
  final _canGoNextCtrl = StreamController<bool>.broadcast();
  final _activeQueueCtrl = StreamController<MediaKind>.broadcast();

  bool _canGoPrevious = false;
  bool _canGoNext = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  PlaybackAudioHandler() {
    _activeQueue = _musicQueue;

    // Crear el player con el pipeline de audio si estamos en Android.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _loudness = AndroidLoudnessEnhancer();
        _player = AudioPlayer(
          audioPipeline: AudioPipeline(androidAudioEffects: [_loudness!]),
        );
        _applyLoudness();
      } catch (e, st) {
        debugPrint(
          'PlaybackAudioHandler: AudioPipeline no disponible -> $e\n$st',
        );
        _loudness = null;
        _player = AudioPlayer();
      }
    } else {
      _player = AudioPlayer();
    }

    _subs.add(_player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: playback error -> $e\n$st');
        _publish();
      },
    ));

    _subs.add(_player.playingStream.listen((playing) {
      _publish();
      // Mantener sincronizado el secundario con pausas/reanudaciones
      // (incluye pérdida de foco de audio).
      if (_xfAudible) _xfSetPlaying(playing);
    }));

    _subs.add(_player.processingStateStream.listen((state) {
      _publish();
      if (state == ProcessingState.completed) {
        unawaited(_onCompleted());
      }
    }));

    _subs.add(_player.currentIndexStream.listen((sourceIndex) {
      if (_loading || _reordering) return;
      if (sourceIndex == null) return;

      // Cambio de pista que NO es nuestro traspaso: lo precargado ya no vale.
      if (_xfPhase == _XfPhase.idle ||
          _xfPhase == _XfPhase.preparing ||
          _xfPhase == _XfPhase.ready) {
        _xfBlockedFrom = -1;
        _cancelCrossfade();
      }

      final order = _activeQueue.sourceOrder;
      if (sourceIndex < 0 || sourceIndex >= order.length) return;
      final songIndex = order[sourceIndex];
      if (songIndex < 0 || songIndex >= _activeQueue.songs.length) return;
      _activeQueue.currentIndex = songIndex;
      _updateFactors(force: true);
      _emitControlsState();
    }));

    _subs.add(_player.durationStream.listen((d) {
      if (_transitionsEnabled) _updateFactors(force: true);
      _publish();
    }));
    _subs.add(_player.positionDiscontinuityStream.listen((_) {
      if (_transitionsEnabled) _updateFactors(force: true);
      _publish();
    }));
    _subs.add(_player.positionStream.listen(_onPosition));
    _subs.add(_player.speedStream.listen((_) => _publish()));

    _rg.activeGainDb.addListener(_onReplayGainChanged);
    _onReplayGainChanged();

    _publish();
  }

  // ============================================================
  // STREAMS PÚBLICOS
  // ============================================================

  Stream<bool> get canGoPreviousStream => _canGoPreviousCtrl.stream;
  Stream<bool> get canGoNextStream => _canGoNextCtrl.stream;
  Stream<bool> get shuffleStream => _shuffleCtrl.stream;
  Stream<PlayerRepeatMode> get repeatStream => _repeatCtrl.stream;
  Stream<MediaKind> get activeQueueStream => _activeQueueCtrl.stream;

  // ============================================================
  // GETTERS
  // ============================================================

  List<Song> get songs => List.unmodifiable(_activeQueue.songs);
  Song? get currentSong => _activeQueue.currentSong;
  int get currentIndex => _activeQueue.currentIndex;

  bool get hasNext =>
      _queueSource != null &&
      (_activeQueue.shuffleEnabled ? _player.hasNext : _activeQueue.hasNext);

  bool get hasPrevious =>
      _queueSource != null &&
      (_activeQueue.shuffleEnabled
          ? _player.hasPrevious
          : _activeQueue.hasPrevious);

  Duration get position => _player.position;

  bool get canGoPrevious =>
      hasPrevious ||
      (_queueSource != null && _player.position > _rewindThreshold);

  bool get canGoNext => hasNext;
  bool get isPlaying => _player.playing;
  double get playerSpeed => _player.speed;

  /// Volumen del usuario (0..1). NO incluye RG ni boost.
  double get volume => _userVolume;
  ValueListenable<double> get volumeListenable => _volumeNotifier;

  /// Volumen físico real del player (incluye RG + boost + fade). Solo debug.
  double get effectiveVolume => _player.volume;

  /// Amplificación de volumen actual en dB (−12..+12).
  double get volumeBoost => _volumeBoostDb;

  /// Factor de fade actual del player principal (0..1). Útil para debug/UI.
  double get fadeFactor => _fadeFactor;

  bool get shuffleEnabled => _activeQueue.shuffleEnabled;
  PlayerRepeatMode get repeatMode => _activeQueue.repeatMode;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  List<Song> songsOf(MediaKind kind) =>
      List.unmodifiable(_queueFor(kind).songs);

  Song? currentSongOf(MediaKind kind) => _queueFor(kind).currentSong;

  bool get isActiveQueueEmpty => _activeQueue.isEmpty;

  // ============================================================
  // TRANSICIONES: API PÚBLICA
  // ============================================================

  /// Actualiza la configuración de transiciones y re-aplica el volumen.
  /// Llamar cada vez que el usuario cambie algo en SettingsScreen.
  void setTransitionConfig({
    required bool enabled,
    required int mode,
    required double crossfadeSeconds,
    required double fadeSeconds,
  }) {
    _cancelCrossfade();

    _transitionsEnabled = enabled;
    _transitionMode = mode == 1 ? 1 : 0;
    _crossfadeSeconds = crossfadeSeconds.clamp(0.0, 12.0).toDouble();
    _fadeSeconds = fadeSeconds.clamp(0.0, 12.0).toDouble();

    _fadeSuspended = false;
    _xfBlockedFrom = -1;

    if (!_transitionsEnabled) {
      _fadeFactor = 1.0;
      _xfFactor = 0.0;
    }
    _syncFadeTimer();
    _updateFactors(force: true);
  }

  void _syncFadeTimer() {
    if (_transitionsEnabled) {
      _fadeTimer ??= Timer.periodic(_fadeTick, (_) => _tick());
    } else {
      _fadeTimer?.cancel();
      _fadeTimer = null;
    }
  }

  // ------------------------------------------------------------
  // Curvas
  // ------------------------------------------------------------

  /// Curva seno: 0 → 0 exacto, 1 → 1 exacto. Para crossfade,
  /// ease(t) y ease(1-t) dan potencia constante.
  static double _ease(double t) =>
      math.sin(t.clamp(0.0, 1.0).toDouble() * math.pi / 2);

  /// Factor del modo Fade In/Out (función pura de posición/duración).
  ///   - posición 0            → 0 absoluto
  ///   - últimos _zeroGuardMs  → 0 absoluto
  double _computeFadeFactor(Duration position, Duration? duration) {
    if (!_transitionsEnabled || _transitionMode != 1) return 1.0;

    var fadeMs = (_fadeSeconds * 1000).round();
    if (fadeMs <= 0) return 1.0;

    final hasDur = duration != null && duration > Duration.zero;
    if (hasDur) {
      // Si la pista es corta, el fade ocupa como máximo la mitad.
      fadeMs = math.min(fadeMs, duration.inMilliseconds ~/ 2);
    }
    if (fadeMs <= 0) return 1.0;

    final posMs = position.inMilliseconds;

    // Fade in. Si aún no se conoce la duración, igualmente se aplica el
    // fade-in por posición (evita un golpe de volumen al empezar).
    var f = posMs <= 0 ? 0.0 : (posMs / fadeMs);

    // Fade out.
    if (hasDur) {
      final rem = duration.inMilliseconds - posMs;
      final out = rem <= _zeroGuardMs ? 0.0 : (rem / fadeMs);
      f = math.min(f, out);
    }
    return _ease(f);
  }

  // ------------------------------------------------------------
  // Ticker
  // ------------------------------------------------------------

  void _tick() {
    if (!_transitionsEnabled) return;
    if (_loading || _reordering || _queueSource == null) return;

    if (_transitionMode == 1) {
      _updateFactors();
    } else {
      _crossfadeTick();
    }
  }

  /// Calcula los factores de ambos players según modo/fase y los aplica.
  void _updateFactors({bool force = false}) {
    var p = 1.0;
    var s = 0.0;

    if (_transitionsEnabled) {
      if (_transitionMode == 1) {
        p = _fadeSuspended
            ? 0.0
            : _computeFadeFactor(_player.position, _player.duration);
      } else {
        switch (_xfPhase) {
          case _XfPhase.fading:
            if (_player.currentIndex != _xfFromIndex) {
              // El principal ya avanzó solo: silenciarlo hasta el traspaso.
              p = 0.0;
              s = 1.0;
            } else {
              final t = _xfProgress();
              p = _ease(1 - t);
              s = _ease(t);
            }
          case _XfPhase.handoffSeek:
            p = 0.0;
            s = 1.0;
          case _XfPhase.handoffRamp:
            final r = (_xfRamp.elapsedMilliseconds / _xfRampMs)
                .clamp(0.0, 1.0)
                .toDouble();
            p = _ease(r);
            s = _ease(1 - r);
          default:
            break;
        }
      }
    }

    if (!force && p == _fadeFactor && s == _xfFactor) return;
    _fadeFactor = p;
    _xfFactor = s;
    _applyEffectiveVolume();
  }

  // ------------------------------------------------------------
  // Cambio de pista manual (modo Fade): silencio ANTES de cambiar
  // ------------------------------------------------------------

  Future<void> _beginTrackChange() async {
    if (!_transitionsEnabled || _transitionMode != 1) return;
    _fadeSuspended = true;
    _fadeFactor = 0.0;
    await _applyVolumeImpl();
  }

  void _endTrackChange() {
    if (!_fadeSuspended) return;
    _fadeSuspended = false;
    _updateFactors(force: true);
  }

  // ============================================================
  // CROSSFADE REAL
  // ============================================================

  int _xfWindowMs(Duration dur) => math.min(
        (_crossfadeSeconds * 1000).round(),
        dur.inMilliseconds ~/ 2,
      );

  /// Progreso del crossfade (0..1) a partir de lo que le queda al principal.
  double _xfProgress() {
    final dur = _player.duration;
    if (dur == null || dur <= Duration.zero) return 0.0;
    final x = _xfWindowMs(dur);
    if (x <= 0) return 1.0;
    final rem = (dur - _player.position).inMilliseconds;
    return (1 - rem / x).clamp(0.0, 1.0).toDouble();
  }

  /// Siguiente pista (índice en el source + canción), o null si no aplica.
  ({int index, Song song})? _xfResolveNext() {
    if (_activeQueue.repeatMode == PlayerRepeatMode.one) return null;
    final ni = _player.nextIndex;
    if (ni == null) return null;
    if (ni == _player.currentIndex) return null;
    final order = _activeQueue.sourceOrder;
    if (ni < 0 || ni >= order.length) return null;
    final si = order[ni];
    if (si < 0 || si >= _activeQueue.songs.length) return null;
    final song = _activeQueue.songs[si];
    final path = song.path;
    if (path == null || path.isEmpty) return null;
    return (index: ni, song: song);
  }

  AudioPlayer _ensureXfPlayer() {
    final existing = _xfPlayer;
    if (existing != null) return existing;

    AudioPlayer p;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _xfLoudness = AndroidLoudnessEnhancer();
        p = AudioPlayer(
          audioPipeline: AudioPipeline(androidAudioEffects: [_xfLoudness!]),
        );
        _applyLoudness();
      } catch (e, st) {
        debugPrint('PlaybackAudioHandler: pipeline xf no disponible -> $e\n$st');
        _xfLoudness = null;
        p = AudioPlayer();
      }
    } else {
      p = AudioPlayer();
    }
    _xfPlayer = p;
    _lastSetSecondary = 1.0; // valor inicial real de un AudioPlayer nuevo
    return p;
  }

  void _xfSetPlaying(bool playing) {
    final xp = _xfPlayer;
    if (xp == null) return;
    if (playing) {
      unawaited(xp.play().catchError((Object _) {}));
    } else {
      unawaited(xp.pause().catchError((Object _) {}));
    }
  }

  void _crossfadeTick() {
    final dur = _player.duration;
    final pos = _player.position;

    if (_xfPhase == _XfPhase.idle) {
      if (_player.playing &&
          dur != null &&
          _player.currentIndex != _xfBlockedFrom) {
        final x = _xfWindowMs(dur);
        final rem = (dur - pos).inMilliseconds;
        if (x >= 500 && rem > 1000 && rem <= x + 5000) {
          final next = _xfResolveNext();
          if (next != null) unawaited(_xfPrepare(next.index, next.song));
        }
      }
    } else if (_xfPhase == _XfPhase.ready) {
      if (dur != null && _player.playing) {
        final next = _xfResolveNext();
        if (next == null || next.index != _xfNextIndex) {
          _cancelCrossfade();
        } else {
          final x = _xfWindowMs(dur);
          final rem = (dur - pos).inMilliseconds;
          if (rem <= x) _xfStart();
        }
      }
    } else if (_xfPhase == _XfPhase.fading) {
      final advanced = _player.currentIndex != _xfFromIndex;
      if (advanced) {
        unawaited(_xfHandoff());
      } else if (dur != null) {
        final rem = (dur - pos).inMilliseconds;
        if (rem <= _zeroGuardMs) unawaited(_xfHandoff());
      }
    } else if (_xfPhase == _XfPhase.handoffRamp) {
      if (_xfRamp.elapsedMilliseconds >= _xfRampMs) _xfFinish();
    }

    _updateFactors();
  }

  Future<void> _xfPrepare(int nextIndex, Song song) async {
    final gen = ++_xfGen;
    _xfPhase = _XfPhase.preparing;
    _xfNextIndex = nextIndex;
    final from = _player.currentIndex ?? -1;
    try {
      final xp = _ensureXfPlayer();
      await xp.setVolume(0.0);
      _lastSetSecondary = 0.0;
      await xp.setAudioSource(
        AudioSource.file(song.path!),
        initialPosition: Duration.zero,
      );
      await xp.setSpeed(_player.speed);
      if (gen != _xfGen) return;
      _xfPhase = _XfPhase.ready;
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: precarga crossfade falló -> $e\n$st');
      if (gen == _xfGen) {
        _xfBlockedFrom = from;
        _xfPhase = _XfPhase.idle;
      }
    }
  }

  void _xfStart() {
    final xp = _xfPlayer;
    if (xp == null) {
      _cancelCrossfade();
      return;
    }
    _xfFromIndex = _player.currentIndex ?? -1;
    _xfPhase = _XfPhase.fading;
    _updateFactors(force: true); // secundario a ~0 antes de play()
    unawaited(xp.play().catchError((Object e) {
      debugPrint('PlaybackAudioHandler: play xf falló -> $e');
    }));
  }

  /// El principal llegó al final (volumen 0): lo movemos a la siguiente
  /// pista en la misma posición que lleva el secundario y hacemos un
  /// mini-ramp para que el principal tome el relevo.
  Future<void> _xfHandoff() async {
    if (_xfPhase != _XfPhase.fading) return;
    final xp = _xfPlayer;
    if (xp == null) {
      _cancelCrossfade();
      return;
    }
    final gen = _xfGen;
    _xfPhase = _XfPhase.handoffSeek;
    _updateFactors(force: true); // principal 0, secundario 1

    try {
      final sw = Stopwatch()..start();
      final target =
          xp.position + Duration(milliseconds: _xfSeekLatencyMs.round());
      await _player.seek(target, index: _xfNextIndex);
      sw.stop();
      if (gen != _xfGen) return;

      // Autoajuste de la latencia estimada del seek.
      _xfSeekLatencyMs =
          (_xfSeekLatencyMs * 0.5 + sw.elapsedMilliseconds * 0.5)
              .clamp(30.0, 600.0)
              .toDouble();

      _xfRamp
        ..reset()
        ..start();
      _xfPhase = _XfPhase.handoffRamp;
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: handoff crossfade falló -> $e\n$st');
      if (gen == _xfGen) _cancelCrossfade();
    }
  }

  void _xfFinish() {
    _xfGen++;
    _xfPhase = _XfPhase.idle;
    _xfBlockedFrom = -1;
    _xfRamp.stop();
    unawaited(_xfPlayer?.stop().catchError((Object _) {}) ?? Future.value());
    _fadeFactor = 1.0;
    _xfFactor = 0.0;
    _updateFactors(force: true);
  }

  /// Cancela cualquier crossfade en curso y restaura el principal.
  void _cancelCrossfade() {
    _xfGen++;
    if (_xfPhase == _XfPhase.idle) return;
    _xfPhase = _XfPhase.idle;
    _xfRamp.stop();
    unawaited(_xfPlayer?.stop().catchError((Object _) {}) ?? Future.value());
    _fadeFactor = 1.0;
    _xfFactor = 0.0;
    _updateFactors(force: true);
  }

  // ============================================================
  // DEDUPE
  // ============================================================

  String _songKey(Song s) =>
      (s.path != null && s.path!.isNotEmpty) ? s.path! : s.title;

  ({List<Song> unique, Map<int, int> indexMap}) _dedupeSongs(
    List<Song> input,
  ) {
    final seen = <String>{};
    final unique = <Song>[];
    final map = <int, int>{};
    for (var i = 0; i < input.length; i++) {
      final key = _songKey(input[i]);
      if (seen.add(key)) {
        map[i] = unique.length;
        unique.add(input[i]);
      }
    }
    return (unique: unique, indexMap: map);
  }

  // ============================================================
  // ORDEN FÍSICO
  // ============================================================

  void _ensureOrder(PlaybackQueue q) {
    if (q.sourceOrder.length != q.songs.length) q.resetOrder();
  }

  int _sourceIndexOf(PlaybackQueue q, int songIndex) {
    _ensureOrder(q);
    final i = q.sourceOrder.indexOf(songIndex);
    return i < 0 ? 0 : i;
  }

  ConcatenatingAudioSource _buildSource(PlaybackQueue q) {
    _ensureOrder(q);
    return ConcatenatingAudioSource(
      children: [
        for (final i in q.sourceOrder) AudioSource.file(q.songs[i].path!),
      ],
    );
  }

  List<int> _buildOrder(PlaybackQueue q, int firstSong) {
    final n = q.songs.length;
    if (!q.shuffleEnabled) return List<int>.generate(n, (i) => i);
    final rest = <int>[
      for (var i = 0; i < n; i++)
        if (i != firstSong) i,
    ]..shuffle();
    return [firstSong, ...rest];
  }

  int _remapAfterMove(int v, int from, int to) {
    if (v == from) return to;
    if (from < to && v > from && v <= to) return v - 1;
    if (from > to && v >= to && v < from) return v + 1;
    return v;
  }

  Future<void> _applyOrder(List<int> newOrder, {required int keepSong}) async {
    final q = _activeQueue;
    final source = _queueSource;
    if (source == null) {
      q.sourceOrder = newOrder;
      return;
    }

    _cancelCrossfade();

    final cur = q.sourceOrder.indexOf(keepSong);
    final p = newOrder.indexOf(keepSong);
    if (cur < 0 || p < 0) return;

    _reordering = true;
    try {
      if (cur < source.length - 1) {
        await source.removeRange(cur + 1, source.length);
      }
      if (cur > 0) {
        await source.removeRange(0, cur);
      }
      q.sourceOrder = newOrder;

      final before = [
        for (final i in newOrder.sublist(0, p))
          AudioSource.file(q.songs[i].path!),
      ];
      final after = [
        for (final i in newOrder.sublist(p + 1))
          AudioSource.file(q.songs[i].path!),
      ];
      if (before.isNotEmpty) await source.insertAll(0, before);
      if (after.isNotEmpty) await source.addAll(after);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: _applyOrder falló -> $e\n$st');
    } finally {
      _reordering = false;
    }
    q.currentIndex = keepSong;
    _emitControlsState();
  }

  // ============================================================
  // PUBLICACIÓN
  // ============================================================

  bool get _effectivePlaying {
    if (_activeQueue.songs.isEmpty) return false;
    if (_loading) return _resumeAfterLoad;
    if (_player.processingState == ProcessingState.completed) return false;
    return _player.playing;
  }

  AudioProcessingState get _effectiveProcessingState {
    if (_activeQueue.songs.isEmpty) return AudioProcessingState.idle;
    if (_loading) return AudioProcessingState.loading;
    if (_handlingCompleted) return AudioProcessingState.ready;

    return switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.ready,
    };
  }

  AudioServiceRepeatMode get _systemRepeatMode =>
      switch (_activeQueue.repeatMode) {
        PlayerRepeatMode.off => AudioServiceRepeatMode.none,
        PlayerRepeatMode.all => AudioServiceRepeatMode.all,
        PlayerRepeatMode.one => AudioServiceRepeatMode.one,
      };

  AudioServiceShuffleMode get _systemShuffleMode =>
      _activeQueue.shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none;

  void _publish({bool updateControls = true, bool updateQueue = true}) {
    if (_isSeeking) {
      updateControls = false;
      updateQueue = false;
    }

    final song = currentSong;
    final playing = _effectivePlaying;

    if (updateQueue) {
      if (song == null) {
        if (_lastMediaItemKey != null) {
          mediaItem.add(null);
          _lastMediaItemKey = null;
        }
      } else {
        final d = _loading ? null : _player.duration;
        final liveDuration = (d != null && d > Duration.zero) ? d : null;
        final key =
            '${_activeQueue.kind.name}|${song.path ?? song.title}|${liveDuration?.inMilliseconds}';

        if (key != _lastMediaItemKey) {
          mediaItem.add(_toMediaItem(song, liveDuration));
          _lastMediaItemKey = key;
        }
      }

      final queueKey =
          '${_activeQueue.kind.name}#${_activeQueue.songs.map((s) => s.path ?? s.title).join('|')}';
      if (queueKey != _lastQueueKey) {
        queue.add(
          _activeQueue.songs
              .map((s) => _toMediaItem(s))
              .toList(growable: false),
        );
        _lastQueueKey = queueKey;
      }

      _rg.notifyCurrentSong(song?.path);
    }

    if (updateControls) {
      final controls = <MediaControl>[];
      final compact = <int>[];

      if (canGoPrevious) {
        compact.add(controls.length);
        controls.add(MediaControl.skipToPrevious);
      }

      compact.add(controls.length);
      controls.add(playing ? MediaControl.pause : MediaControl.play);

      if (canGoNext) {
        compact.add(controls.length);
        controls.add(MediaControl.skipToNext);
      }

      _lastControls = controls;
      _lastCompactActionIndices = compact;
    }

    playbackState.add(
      PlaybackState(
        controls: _lastControls ?? const <MediaControl>[],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToQueueItem,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        },
        androidCompactActionIndices:
            _lastCompactActionIndices ?? const <int>[],
        processingState: _effectiveProcessingState,
        playing: playing,
        updatePosition: _loading ? Duration.zero : _player.position,
        bufferedPosition: _loading ? Duration.zero : _player.bufferedPosition,
        speed: _player.speed,
        queueIndex:
            _activeQueue.currentIndex >= 0 ? _activeQueue.currentIndex : null,
        repeatMode: _systemRepeatMode,
        shuffleMode: _systemShuffleMode,
      ),
    );
  }

  MediaItem _toMediaItem(Song song, [Duration? duration]) {
    final cover = song.coverPath;
    final d = song.duration;
    return MediaItem(
      id: song.path ?? song.title,
      title: song.title,
      artist: song.subtitle,
      duration: duration ?? ((d != null && d > Duration.zero) ? d : null),
      artUri: cover != null && cover.isNotEmpty && File(cover).existsSync()
          ? Uri.file(cover)
          : null,
      extras: {
        'path': song.path,
        'queueKind': _activeQueue.kind.name,
      },
      playable: song.path != null && song.path!.isNotEmpty,
    );
  }

  // ============================================================
  // POSICIÓN / COMPLETED
  // ============================================================

  void _onPosition(Duration position) {
    // Los fades ya NO se calculan aquí (lo hace el ticker de 30 ms).
    _emitCanGoPrevious();
    if (!_player.playing) return;
    final now = DateTime.now();
    if (now.difference(_lastPositionPublish) < _positionPublishEvery) return;
    _lastPositionPublish = now;
    _publish();
  }

  Future<void> _onCompleted() async {
    if (_handlingCompleted || _loading || _activeQueue.songs.isEmpty) return;
    _handlingCompleted = true;
    _cancelCrossfade();
    try {
      if (_activeQueue.repeatMode == PlayerRepeatMode.one) return;
      await _player.pause();
      await _player.seek(Duration.zero, index: 0);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: normalizar completed falló -> $e\n$st');
    } finally {
      _handlingCompleted = false;
      _activeQueue.currentIndex = _activeQueue.songs.isEmpty
          ? -1
          : (_activeQueue.sourceOrder.isEmpty
              ? 0
              : _activeQueue.sourceOrder.first);
      _emitControlsState();
    }
  }

  // ============================================================
  // EMISIÓN DE CONTROLES
  // ============================================================

  void _emitCanGoPrevious() {
    final next = canGoPrevious;
    if (next == _canGoPrevious) return;
    _canGoPrevious = next;
    if (!_canGoPreviousCtrl.isClosed) _canGoPreviousCtrl.add(next);
  }

  void _emitCanGoNext() {
    final next = canGoNext;
    if (next == _canGoNext) return;
    _canGoNext = next;
    if (!_canGoNextCtrl.isClosed) _canGoNextCtrl.add(next);
  }

  void _emitControlsState() {
    _emitCanGoPrevious();
    _emitCanGoNext();
    _publish();
  }

  // ============================================================
  // SHUFFLE / REPEAT
  // ============================================================

  Future<void> setShuffle(bool enabled) async {
    final q = _activeQueue;
    if (q.shuffleEnabled == enabled) return;
    q.shuffleEnabled = enabled;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(enabled);

    if (q.songs.isNotEmpty) {
      _ensureOrder(q);
      final keep = q.currentIndex >= 0 ? q.currentIndex : 0;
      await _applyOrder(_buildOrder(q, keep), keepSong: keep);
    }
    _emitControlsState();
  }

  Future<void> setRepeatModeForUI(PlayerRepeatMode mode) async {
    if (_activeQueue.repeatMode == mode) return;
    _activeQueue.repeatMode = mode;
    _cancelCrossfade();
    await _applyLoopMode();
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(mode);
    _emitControlsState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final next = switch (repeatMode) {
      AudioServiceRepeatMode.none => PlayerRepeatMode.off,
      AudioServiceRepeatMode.all => PlayerRepeatMode.all,
      AudioServiceRepeatMode.one => PlayerRepeatMode.one,
      AudioServiceRepeatMode.group => PlayerRepeatMode.off,
    };
    await setRepeatModeForUI(next);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = switch (shuffleMode) {
      AudioServiceShuffleMode.all => true,
      AudioServiceShuffleMode.none => false,
      AudioServiceShuffleMode.group => false,
    };
    await setShuffle(enable);
  }

  Future<void> _applyLoopMode() async {
    switch (_activeQueue.repeatMode) {
      case PlayerRepeatMode.off:
        await _player.setLoopMode(LoopMode.off);
      case PlayerRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
      case PlayerRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
    }
  }

  bool _isPlayable(Song s) {
    final p = s.path;
    if (p == null || p.isEmpty) return false;
    if (!File(p).existsSync()) {
      debugPrint('PlaybackAudioHandler: path no existe -> $p');
      return false;
    }
    return true;
  }

  // ============================================================
  // SET QUEUE
  // ============================================================

  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    final kind = songs.isEmpty
        ? _activeQueue.kind
        : (songs[startIndex.clamp(0, songs.length - 1)].kind ==
                MediaKind.podcast
            ? MediaKind.podcast
            : MediaKind.music);
    return setQueueOf(kind, songs,
        startIndex: startIndex, autoPlay: autoPlay);
  }

  Future<void> setQueueOf(
    MediaKind kind,
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    final generation = ++_loadGeneration;
    final run = _loadChain.catchError((_) {}).then<void>((_) async {
      if (generation != _loadGeneration) return;
      await _setQueueImpl(kind, songs,
          startIndex: startIndex, autoPlay: autoPlay);
    });
    _loadChain = run;
    return run;
  }

  Future<void> playOnly(Song song) =>
      setQueueOf(song.kind, [song], startIndex: 0, autoPlay: true);

  Future<void> _setQueueImpl(
    MediaKind kind,
    List<Song> songs, {
    required int startIndex,
    required bool autoPlay,
  }) async {
    _cancelCrossfade();

    if (songs.isEmpty) {
      await _clearQueueOf(kind);
      return;
    }
    if (startIndex < 0 || startIndex >= songs.length) startIndex = 0;

    final target = songs[startIndex];

    final dedup = _dedupeSongs(songs);
    songs = dedup.unique;

    final playable = songs.where(_isPlayable).toList();
    if (playable.isEmpty) {
      debugPrint('PlaybackAudioHandler: no hay fuentes válidas en la cola');
      await _clearQueueOf(kind);
      return;
    }
    final targetKey = _songKey(target);
    var newStart = playable.indexWhere((s) => _songKey(s) == targetKey);
    if (newStart < 0) newStart = 0;

    final targetQueue = _queueFor(kind);

    if (kind != _activeQueue.kind) {
      targetQueue.songs = playable;
      targetQueue.resetOrder();
      targetQueue.currentIndex = newStart;
      targetQueue.shuffleEnabled = false;
      targetQueue.savedPosition = Duration.zero;
      targetQueue.savedPlaying = autoPlay;
      _emitControlsState();
      return;
    }

    _activeQueue.shuffleEnabled = false;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);

    _loading = true;
    _resumeAfterLoad = autoPlay;

    try {
      await _player.pause();
      // Modo Fade: silencio absoluto antes de cargar la nueva pista.
      await _beginTrackChange();

      _activeQueue.songs = playable;
      _activeQueue.resetOrder();
      _activeQueue.currentIndex = newStart;
      _publish();

      final concat = _buildSource(_activeQueue);
      _queueSource = concat;

      try {
        await _player.setAudioSource(
          concat,
          initialIndex: newStart,
          initialPosition: Duration.zero,
        );
      } catch (e, st) {
        debugPrint('PlaybackAudioHandler: setAudioSource falló -> $e\n$st');
        _queueSource = null;
        _activeQueue.reset();
        _resumeAfterLoad = false;
        _loading = false;
        await _player.stop();
        _emitControlsState();
        rethrow;
      }
    } finally {
      _loading = false;
      _endTrackChange();
    }

    _activeQueue.currentIndex = newStart;
    _rg.notifyCurrentSong(_activeQueue.currentSong?.path);

    await _applyLoopMode();
    _updateFactors(force: true);

    if (autoPlay) {
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
      }));
    }

    _emitControlsState();
  }

  // ============================================================
  // CAMBIO DE COLA ACTIVA
  // ============================================================

  Future<void> switchToQueue(
    MediaKind kind, {
    int? startIndex,
    bool? autoPlay,
  }) async {
    if (kind == _activeQueue.kind && _queueSource != null) {
      if (startIndex != null) await skipToQueueItem(startIndex);
      return;
    }

    _cancelCrossfade();

    final oldKind = _activeQueue.kind;

    _activeQueue.saveLiveState(
      position: _player.position,
      playing: _player.playing,
    );

    try {
      await _player.pause();
    } catch (_) {}

    final target = _queueFor(kind);
    if (startIndex != null &&
        startIndex >= 0 &&
        startIndex < target.songs.length) {
      target.currentIndex = startIndex;
      target.savedPosition = Duration.zero;
      target.savedPlaying = autoPlay ?? true;
    } else if (autoPlay != null) {
      target.savedPlaying = autoPlay;
    }

    _activeQueue = target;
    _lastMediaItemKey = null;
    _lastQueueKey = null;

    if (!_activeQueueCtrl.isClosed) _activeQueueCtrl.add(kind);

    _rg.notifyCurrentSong(_activeQueue.currentSong?.path);

    if (_activeQueue.songs.isEmpty) {
      try {
        await _player.stop();
      } catch (_) {}
      _queueSource = null;
      if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(_activeQueue.shuffleEnabled);
      if (!_repeatCtrl.isClosed) _repeatCtrl.add(_activeQueue.repeatMode);
      _emitControlsState();
      return;
    }

    _loading = true;
    _resumeAfterLoad = _activeQueue.savedPlaying;
    final restorePos = _activeQueue.savedPosition;

    try {
      await _beginTrackChange();

      final concat = _buildSource(_activeQueue);
      _queueSource = concat;

      await _player.setAudioSource(
        concat,
        initialIndex: _sourceIndexOf(
          _activeQueue,
          _activeQueue.currentIndex >= 0 ? _activeQueue.currentIndex : 0,
        ),
        initialPosition: restorePos,
      );
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: switchToQueue falló -> $e\n$st');
    } finally {
      _loading = false;
      _endTrackChange();
    }

    await _applyLoopMode();
    _updateFactors(force: true);

    if (_resumeAfterLoad) {
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
      }));
    }

    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(_activeQueue.shuffleEnabled);
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(_activeQueue.repeatMode);

    debugPrint(
      'PlaybackAudioHandler: switchToQueue $oldKind -> $kind '
      '(songs=${_activeQueue.songs.length}, idx=${_activeQueue.currentIndex})',
    );

    _emitControlsState();
  }

  // ============================================================
  // CLEAR QUEUE
  // ============================================================

  Future<void> _clearQueueOf(MediaKind kind) async {
    final q = _queueFor(kind);
    q.reset();

    if (kind == _activeQueue.kind) {
      _cancelCrossfade();
      _queueSource = null;
      _resumeAfterLoad = false;
      await _player.stop();
      if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);
    }
    _rg.notifyCurrentSong(null);
    _emitControlsState();
  }

  Future<void> clearQueue() async {
    _loadGeneration++;
    await _clearQueueOf(_activeQueue.kind);
  }

  Future<void> clearQueueOf(MediaKind kind) async {
    _loadGeneration++;
    await _clearQueueOf(kind);
  }

  Future<void> clearAllQueues() async {
    _loadGeneration++;
    _cancelCrossfade();

    _activeQueue.saveLiveState(
      position: _player.position,
      playing: false,
    );

    _musicQueue.reset();
    _chaptersQueue.reset();

    _queueSource = null;
    _resumeAfterLoad = false;
    try {
      await _player.stop();
    } catch (e, st) {
      debugPrint(
        'PlaybackAudioHandler: stop en clearAllQueues falló -> $e\n$st',
      );
    }

    _activeQueue = _musicQueue;

    if (!_activeQueueCtrl.isClosed) {
      _activeQueueCtrl.add(MediaKind.music);
    }
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(PlayerRepeatMode.off);

    _lastMediaItemKey = null;
    _lastQueueKey = null;

    _rg.notifyCurrentSong(null);
    _emitControlsState();
  }

  // ============================================================
  // ADD / REMOVE / REORDER
  // ============================================================

  Future<void> addToQueue(Song song) => addToQueueOf(song.kind, song);

  Future<void> addToQueueOf(MediaKind kind, Song song) async {
    if (!_isPlayable(song)) return;

    final q = _queueFor(kind);

    final key = _songKey(song);
    if (q.songs.any((s) => _songKey(s) == key)) {
      debugPrint('PlaybackAudioHandler: canción ya en la cola ($key)');
      return;
    }

    if (kind != _activeQueue.kind) {
      _ensureOrder(q);
      q.songs = [...q.songs, song];
      q.sourceOrder = [...q.sourceOrder, q.songs.length - 1];
      if (q.currentIndex < 0) q.currentIndex = 0;
      _emitControlsState();
      return;
    }

    final source = _queueSource;
    if (source == null) {
      final newSongs = [...q.songs, song];
      await setQueueOf(
        kind,
        newSongs,
        startIndex: q.currentIndex < 0 ? newSongs.length - 1 : q.currentIndex,
        autoPlay: false,
      );
      return;
    }

    _cancelCrossfade();
    _ensureOrder(q);
    q.songs = [...q.songs, song];
    q.sourceOrder = [...q.sourceOrder, q.songs.length - 1];
    await source.add(AudioSource.file(song.path!));
    _emitControlsState();
  }

  Future<void> removeFromQueue(int index) =>
      removeFromQueueOf(_activeQueue.kind, index);

  Future<void> removeFromQueueOf(MediaKind kind, int index) async {
    final q = _queueFor(kind);
    if (index < 0 || index >= q.songs.length) return;

    if (kind == _activeQueue.kind) _cancelCrossfade();

    _ensureOrder(q);
    final sourcePos = q.sourceOrder.indexOf(index);

    final wasCurrent = index == q.currentIndex;
    final newSongs = List<Song>.from(q.songs)..removeAt(index);

    if (newSongs.isEmpty) {
      await _clearQueueOf(kind);
      return;
    }

    int newIndex = q.currentIndex;
    if (index < q.currentIndex) {
      newIndex = q.currentIndex - 1;
    } else if (wasCurrent) {
      newIndex = index.clamp(0, newSongs.length - 1);
    }

    q.songs = newSongs;
    q.sourceOrder = [
      for (final v in q.sourceOrder)
        if (v != index) (v > index ? v - 1 : v),
    ];
    q.currentIndex = newIndex;

    if (kind == _activeQueue.kind) {
      final source = _queueSource;
      if (source != null && sourcePos >= 0) {
        try {
          await source.removeAt(sourcePos);
        } catch (e, st) {
          debugPrint('PlaybackAudioHandler: removeAt falló -> $e\n$st');
        }
      }
    }

    _emitControlsState();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      reorderQueueOf(_activeQueue.kind, oldIndex, newIndex);

  Future<void> reorderQueueOf(
    MediaKind kind,
    int oldIndex,
    int newIndex,
  ) async {
    final q = _queueFor(kind);
    if (oldIndex < 0 || oldIndex >= q.songs.length) return;
    if (newIndex < 0 || newIndex > q.songs.length) return;
    if (oldIndex == newIndex) return;

    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (oldIndex == targetIndex) return;

    if (kind == _activeQueue.kind) _cancelCrossfade();

    final updated = List<Song>.from(q.songs);
    final moved = updated.removeAt(oldIndex);
    updated.insert(targetIndex, moved);
    q.songs = updated;

    if (q.currentIndex == oldIndex) {
      q.currentIndex = targetIndex;
    } else if (oldIndex < q.currentIndex && targetIndex >= q.currentIndex) {
      q.currentIndex--;
    } else if (oldIndex > q.currentIndex && targetIndex <= q.currentIndex) {
      q.currentIndex++;
    }

    _ensureOrder(q);
    final shuffled = q.shuffleEnabled;
    if (shuffled) {
      q.sourceOrder = [
        for (final v in q.sourceOrder)
          _remapAfterMove(v, oldIndex, targetIndex),
      ];
    }

    _emitControlsState();

    if (kind == _activeQueue.kind && !shuffled) {
      final source = _queueSource;
      if (source != null) {
        try {
          await source.move(oldIndex, targetIndex);
        } catch (e, st) {
          debugPrint('PlaybackAudioHandler: move falló -> $e\n$st');
        }
      }
    }
  }

  // ============================================================
  // REPRODUCCIÓN
  // ============================================================

  Future<void> playFromQueueOf(MediaKind kind, int index) async {
    if (kind == _activeQueue.kind && _queueSource != null) {
      await skipToQueueItem(index);
    } else {
      await switchToQueue(kind, startIndex: index, autoPlay: true);
    }
  }

  Future<void> playSong(Song song) async {
    final q = _queueFor(song.kind);
    final idx = q.songs.indexWhere((s) => s.path == song.path);
    if (idx >= 0) {
      if (_activeQueue.kind != song.kind || _queueSource == null) {
        await switchToQueue(song.kind, startIndex: idx, autoPlay: true);
      } else {
        await skipToQueueItem(idx);
      }
    } else {
      await playOnly(song);
    }
  }

  Future<void> playFromQueue(int index) => skipToQueueItem(index);

  Future<void> setSpeed(double speed) async {
    if (speed <= 0) return;
    await _player.setSpeed(speed);
    final xp = _xfPlayer;
    if (xp != null && _xfPhase != _XfPhase.idle) {
      unawaited(xp.setSpeed(speed).catchError((Object _) {}));
    }
    _publish();
  }

  // ============================================================
  // VOLUMEN + REPLAYGAIN + VOLUME BOOST + TRANSICIONES
  // ============================================================

  @override
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0).toDouble();
    _userVolume = v;
    _volume = v;
    _volumeNotifier.value = v;
    _applyEffectiveVolume();
  }

  void setVolumeBoost(double db) {
    final v = db.clamp(-12.0, 12.0).toDouble();
    if ((v - _volumeBoostDb).abs() < 0.01) return;
    _volumeBoostDb = v;
    _applyLoudness();
    _applyEffectiveVolume();
  }

  /// Solo amplifica (dB > 0) con el LoudnessEnhancer de Android.
  /// Las atenuaciones (dB < 0) se hacen con el volumen lineal.
  /// Se configura tanto el enhancer del player principal como el del
  /// secundario (crossfade) para que el boost sea consistente.
  void _applyLoudness() {
    final positiveDb = _volumeBoostDb > 0 ? _volumeBoostDb : 0.0;
    _configureEnhancer(_loudness, positiveDb);
    _configureEnhancer(_xfLoudness, positiveDb);
  }

  void _configureEnhancer(AndroidLoudnessEnhancer? l, double positiveDb) {
    if (l == null) return;
    unawaited(() async {
      try {
        await l.setEnabled(positiveDb > 0);
        await l.setTargetGain(positiveDb / _kLoudnessGainScale);
        debugPrint(
          'Boost: enhancer enabled=${positiveDb > 0} '
          'gain=${positiveDb / _kLoudnessGainScale} ($positiveDb dB)',
        );
      } catch (e, st) {
        debugPrint('PlaybackAudioHandler: loudness falló -> $e\n$st');
      }
    }());
  }

  void _onReplayGainChanged() {
    _replayGainDb = _rg.enabled.value ? _rg.activeGainDb.value : 0.0;
    _applyEffectiveVolume();
  }

  /// userVolume × linear(RG) × linear(boost) — SIN fade.
  /// Android: el boost positivo va por LoudnessEnhancer, solo el negativo
  /// se aplica aquí. Otras plataformas: multiplicador clásico.
  double _baseLinear() {
    final rgLinear = _replayGainDb == 0
        ? 1.0
        : math.pow(10, _replayGainDb / 20).toDouble();

    final boostLinear = _volumeBoostDb == 0
        ? 1.0
        : (_loudness != null
            ? (_volumeBoostDb < 0
                ? math.pow(10, _volumeBoostDb / 20).toDouble()
                : 1.0)
            : math.pow(10, _volumeBoostDb / 20).toDouble());

    return _userVolume * rgLinear * boostLinear;
  }

  /// Evita llamadas redundantes al canal nativo, pero SIEMPRE deja pasar
  /// el paso hacia/desde 0 exacto.
  bool _needsSet(double next, double last) {
    if (next == last) return false;
    if (next == 0.0 || last == 0.0) return true;
    return (next - last).abs() >= 0.002;
  }

  void _applyEffectiveVolume() => unawaited(_applyVolumeImpl());

  Future<void> _applyVolumeImpl() async {
    final base = _baseLinear();
    final fp = _transitionsEnabled ? _fadeFactor : 1.0;
    final fs = _transitionsEnabled ? _xfFactor : 0.0;

    final p = (base * fp).clamp(0.0, 1.0).toDouble();
    final s = (base * fs).clamp(0.0, 1.0).toDouble();

    final futures = <Future<void>>[];

    if (_needsSet(p, _lastSetPrimary)) {
      _lastSetPrimary = p;
      futures.add(_player.setVolume(p));
    }

    final xp = _xfPlayer;
    if (xp != null && _needsSet(s, _lastSetSecondary)) {
      _lastSetSecondary = s;
      futures.add(xp.setVolume(s));
    }

    if (futures.isNotEmpty) {
      try {
        await Future.wait(futures);
      } catch (e) {
        debugPrint('PlaybackAudioHandler: setVolume falló -> $e');
      }
    }
  }

  // ============================================================
  // PLAY / PAUSE / STOP / SEEK
  // ============================================================

  @override
  Future<void> play() async {
    if (_queueSource == null) {
      debugPrint('PlaybackAudioHandler: play() sin fuente cargada');
      return;
    }
    unawaited(_player.play().catchError((Object e, StackTrace st) {
      debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
    }));
    if (_xfAudible) _xfSetPlaying(true);
    _publish();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    if (_xfAudible) _xfSetPlaying(false);
    _publish();
  }

  @override
  Future<void> stop() async {
    _loadGeneration++;
    _cancelCrossfade();
    _activeQueue.saveLiveState(
      position: _player.position,
      playing: false,
    );
    await _clearQueueOf(_activeQueue.kind);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    final generation = ++_seekGeneration;
    _isSeeking = true;
    _publish(updateControls: false, updateQueue: false);

    _cancelCrossfade();

    // Modo Fade: si se salta al inicio de la pista, silencio antes del seek.
    final guardFade = _transitionsEnabled &&
        _transitionMode == 1 &&
        position.inMilliseconds < (_fadeSeconds * 1000).round();
    if (guardFade) await _beginTrackChange();

    try {
      await _player.seek(position);
    } finally {
      if (guardFade) _endTrackChange();
      if (generation == _seekGeneration) {
        _isSeeking = false;
        _updateFactors(force: true);
        _emitCanGoPrevious();
        _publish();
      }
    }
  }

  @override
  Future<void> skipToNext() async {
    if (!hasNext || _queueSource == null) return;
    _cancelCrossfade();
    await _beginTrackChange();
    try {
      await _player.seekToNext();
    } finally {
      _endTrackChange();
    }
    _emitControlsState();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queueSource == null) return;

    if (_player.position > _rewindThreshold) {
      await seek(Duration.zero);
      return;
    }

    if (hasPrevious) {
      _cancelCrossfade();
      await _beginTrackChange();
      try {
        await _player.seekToPrevious();
      } finally {
        _endTrackChange();
      }
      _emitControlsState();
      return;
    }

    debugPrint('PlaybackAudioHandler: previous no aplica');
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final q = _activeQueue;
    if (index < 0 || index >= q.songs.length) return;

    if (_queueSource == null) {
      await setQueueOf(
        q.kind,
        q.songs,
        startIndex: index,
        autoPlay: true,
      );
      return;
    }

    _cancelCrossfade();
    await _beginTrackChange();

    q.currentIndex = index;
    try {
      await _player.seek(Duration.zero, index: _sourceIndexOf(q, index));
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: seek falló -> $e\n$st');
      _endTrackChange();
      return;
    }

    if (q.shuffleEnabled) {
      await _applyOrder(_buildOrder(q, index), keepSong: index);
    }

    _endTrackChange();

    unawaited(_player.play().catchError((Object e, StackTrace st) {
      debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
    }));
    _emitControlsState();
  }

  @override
  Future<void> onTaskRemoved() async {}

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _rg.activeGainDb.removeListener(_onReplayGainChanged);
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _canGoPreviousCtrl.close();
    await _canGoNextCtrl.close();
    await _shuffleCtrl.close();
    await _repeatCtrl.close();
    await _activeQueueCtrl.close();
    _volumeNotifier.dispose();
    try {
      await _xfPlayer?.dispose();
    } catch (_) {}
    _xfPlayer = null;
    await _player.dispose();
  }
}
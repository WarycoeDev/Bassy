// lib/services/playback_audio_handler.dart
//
// Handler de reproducción sobre flutter_soloud (SoLoud + miniaudio).
// Misma API pública que la versión con just_audio, para que
// PlaybackController y las pantallas no cambien.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as sl;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'playback_queue.dart';
import 'replay_gain_service.dart';
import 'reverb_service.dart';

enum PlayerRepeatMode { off, all, one }

class PlaybackAudioHandler extends BaseAudioHandler with SeekHandler {
  sl.SoLoud get _soloud => sl.SoLoud.instance;
  Future<void>? _engineInit;

  // ----- Voz principal -----
  sl.AudioSource? _source;
  sl.SoundHandle? _handle;

  // ----- Dos colas independientes -----
  final PlaybackQueue _musicQueue = PlaybackQueue(kind: MediaKind.music);
  final PlaybackQueue _chaptersQueue = PlaybackQueue(kind: MediaKind.podcast);

  PlaybackQueue _activeQueue = PlaybackQueue(kind: MediaKind.music);

  PlaybackQueue _queueFor(MediaKind kind) =>
      kind == MediaKind.podcast ? _chaptersQueue : _musicQueue;

  MediaKind get activeQueueKind => _activeQueue.kind;

  /// true si la cola activa es de música. Los efectos de audio
  /// (ReplayGain, Slowed y Reverb) solo se aplican en este caso.
  bool get _isMusicQueue => _activeQueue.kind == MediaKind.music;

  Future<void> _loadChain = Future<void>.value();
  int _loadGeneration = 0; // para setQueueOf encadenado
  int _loadToken = 0; // para _loadAndPlay (descarta cargas obsoletas)

  bool _loading = false;
  bool _resumeAfterLoad = false;
  bool _handlingCompleted = false;
  bool _playing = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  // ----- Slowed (ralentiza + baja el tono, como un disco frenado) -----
  /// Factor de velocidad del efecto: 1.0 = apagado, 0.6 = más lento y grave.
  double _slowed = 1.0;
  final ValueNotifier<double> _slowedNotifier = ValueNotifier<double>(1.0);

  static const double kMinSlowed = 0.6;
  static const String _kSlowedPrefKey = 'effects_slowed_factor';

  /// Velocidad real aplicada a las voces (velocidad normal × slowed).
  /// El efecto Slowed solo aplica a música; en podcast se usa solo `_speed`.
  double get _effectiveSpeed => _speed * (_isMusicQueue ? _slowed : 1.0);

  // ----- Reverb: se silencia mientras suena un podcast -----
  /// Nivel de reverb del usuario guardado mientras la cola activa es de
  /// podcast (null = no hay nada que restaurar).
  double? _reverbBeforePodcast;

  List<MediaControl>? _lastControls;
  List<int>? _lastCompactActionIndices;
  String? _lastMediaItemKey;
  String? _lastQueueKey;

  static const Duration _tickEvery = Duration(milliseconds: 40);
  static const Duration _positionEmitEvery = Duration(milliseconds: 100);
  static const Duration _publishEvery = Duration(milliseconds: 250);
  static const Duration _rewindThreshold = Duration(seconds: 3);
  static const int _diskLoadThresholdBytes = 64 * 1024 * 1024;

  Timer? _ticker;
  DateTime _lastPositionEmit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);

  // Volumen + ReplayGain
  double _userVolume = 1.0;
  final ValueNotifier<double> _volumeNotifier = ValueNotifier<double>(1.0);
  final ReplayGainService _rg = ReplayGainService.instance;
  double _replayGainDb = 0.0;
  double _lastVol = -1;

  // ============================================================
  // TRANSICIONES (Fade In/Out / Crossfade)
  // ============================================================

  bool _transitionsEnabled = false;
  int _transitionMode = 0; // 0 = Crossfade, 1 = Fade In/Out
  double _crossfadeSeconds = 4.0;
  double _fadeSeconds = 3.0;

  /// Factor de fade actual del player principal (0..1).
  double _fadeFactor = 1.0;

  static const int _zeroGuardMs = 40;

  // ---- Crossfade (segunda voz) ----
  sl.AudioSource? _nextSource;
  sl.SoundHandle? _nextHandle;
  int _nextIdx = -1; // índice de canción (en q.songs) de la entrante
  bool _crossfading = false;
  bool _xfPreparing = false;
  bool _xfBlocked = false;
  int _xfToken = 0;
  int _xfStartMs = 0;
  int _xfSpanMs = 1;
  static const Duration _xfPreloadLead = Duration(seconds: 10);

  final _shuffleCtrl = StreamController<bool>.broadcast();
  final _repeatCtrl = StreamController<PlayerRepeatMode>.broadcast();
  final _canGoPreviousCtrl = StreamController<bool>.broadcast();
  final _canGoNextCtrl = StreamController<bool>.broadcast();
  final _activeQueueCtrl = StreamController<MediaKind>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration?>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  // ===== STATS =====
  final _trackCompletedCtrl = StreamController<String>.broadcast();

  bool _canGoPrevious = false;
  bool _canGoNext = false;

  PlaybackAudioHandler() {
    _activeQueue = _musicQueue;
    _rg.activeGainDb.addListener(_onReplayGainChanged);
    _onReplayGainChanged();
    _publish();
    unawaited(_loadSlowed());
  }

  // ============================================================
  // MOTOR
  // ============================================================

  Future<void> _ensureEngine() async {
    if (_soloud.isInitialized) return;
    await (_engineInit ??= _soloud.init().whenComplete(() {
      _engineInit = null;
    }));
    ReverbService.instance.applyToEngine();
    _syncReverbForQueue();
  }

  Future<void> _disposeSource(sl.AudioSource? source) async {
    if (source == null) return;
    try {
      // Al liberar la fuente también se detienen sus voces.
      await _soloud.disposeSource(source);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: error liberando fuente -> $e');
    }
  }

  bool _isValid(sl.SoundHandle? h) {
    if (h == null) return false;
    try {
      return _soloud.getIsValidVoiceHandle(h);
    } catch (_) {
      return false;
    }
  }

  Duration _livePosition() {
    final h = _handle;
    if (h == null) return _position;
    try {
      return _soloud.getPosition(h);
    } catch (_) {
      return _position;
    }
  }

  /// Detiene y libera la voz principal (y cualquier crossfade).
  Future<void> _releaseVoice() async {
    _cancelCrossfade();
    final s = _source;
    _source = null;
    _handle = null;
    _lastVol = -1;
    _syncTicker();
    await _disposeSource(s);
  }

  void _setPlaying(bool v) {
    if (_playing != v) {
      _playing = v;
      if (!_playingCtrl.isClosed) _playingCtrl.add(v);
    }
    _syncTicker();
  }

  bool get _hasSource => _source != null || _loading;

  // ============================================================
  // EFECTOS SOLO PARA MÚSICA
  // ============================================================

  /// Reverb: mientras la cola activa es de podcast se pone a 0 (sin
  /// persistir) y al volver a música se restaura el nivel del usuario.
  void _syncReverbForQueue() {
    final reverb = ReverbService.instance;
    try {
      if (!reverb.isSupported) return;
      if (_isMusicQueue) {
        final saved = _reverbBeforePodcast;
        if (saved != null) {
          _reverbBeforePodcast = null;
          reverb.setLevel(saved);
        }
      } else {
        if (_reverbBeforePodcast == null) {
          final current = reverb.level.value;
          _reverbBeforePodcast = current;
          if (current > 0.0) reverb.setLevel(0.0);
        }
      }
    } catch (e) {
      debugPrint('PlaybackAudioHandler: sync reverb falló -> $e');
    }
  }

  // ============================================================
  // STREAMS PÚBLICOS
  // ============================================================

  Stream<bool> get canGoPreviousStream => _canGoPreviousCtrl.stream;
  Stream<bool> get canGoNextStream => _canGoNextCtrl.stream;
  Stream<bool> get shuffleStream => _shuffleCtrl.stream;
  Stream<PlayerRepeatMode> get repeatStream => _repeatCtrl.stream;
  Stream<MediaKind> get activeQueueStream => _activeQueueCtrl.stream;

  Stream<Duration> get positionStream => _positionCtrl.stream;
  Stream<Duration?> get durationStream => _durationCtrl.stream;
  Stream<bool> get playingStream => _playingCtrl.stream;

  /// Emite el `songKey` (path o title) de la pista que terminó de forma
  /// natural. Sirve para contar reproducciones en StatsService.
  // ===== STATS =====
  Stream<String> get trackCompletedStream => _trackCompletedCtrl.stream;

  // ============================================================
  // GETTERS
  // ============================================================

  List<Song> get songs => List.unmodifiable(_activeQueue.songs);
  Song? get currentSong => _activeQueue.currentSong;
  int get currentIndex => _activeQueue.currentIndex;

  bool get hasNext => _hasSource && _nextIndexOf(_activeQueue) != null;
  bool get hasPrevious => _hasSource && _previousIndexOf(_activeQueue) != null;

  Duration get position => _position;

  bool get canGoPrevious =>
      hasPrevious || (_hasSource && _position > _rewindThreshold);

  bool get canGoNext => hasNext;
  bool get isPlaying => _playing;
  double get playerSpeed => _speed;

  /// Factor de Slowed actual (1.0 = apagado). Solo afecta a música.
  double get slowed => _slowed;
  ValueListenable<double> get slowedListenable => _slowedNotifier;

  /// Volumen del usuario (0..1). NO incluye RG.
  double get volume => _userVolume;
  ValueListenable<double> get volumeListenable => _volumeNotifier;

  /// Volumen físico real de la voz (incluye RG + fade). Solo debug.
  double get effectiveVolume => _lastVol < 0 ? _userVolume : _lastVol;

  double get fadeFactor => _fadeFactor;

  bool get shuffleEnabled => _activeQueue.shuffleEnabled;
  PlayerRepeatMode get repeatMode => _activeQueue.repeatMode;

  List<Song> songsOf(MediaKind kind) =>
      List.unmodifiable(_queueFor(kind).songs);

  Song? currentSongOf(MediaKind kind) => _queueFor(kind).currentSong;

  bool get isActiveQueueEmpty => _activeQueue.isEmpty;

  // ============================================================
  // ORDEN / SIGUIENTE / ANTERIOR
  // ============================================================

  void _ensureOrder(PlaybackQueue q) {
    if (q.sourceOrder.length != q.songs.length) q.resetOrder();
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

  /// Índice de canción de la siguiente pista, o null si no hay.
  int? _nextIndexOf(PlaybackQueue q) {
    _ensureOrder(q);
    final order = q.sourceOrder;
    if (order.isEmpty) return null;
    final pos = order.indexOf(q.currentIndex);
    if (pos < 0) return null;
    if (pos < order.length - 1) return order[pos + 1];
    if (q.repeatMode == PlayerRepeatMode.all && order.length > 1) {
      return order.first;
    }
    return null;
  }

  int? _previousIndexOf(PlaybackQueue q) {
    _ensureOrder(q);
    final order = q.sourceOrder;
    if (order.isEmpty) return null;
    final pos = order.indexOf(q.currentIndex);
    if (pos < 0) return null;
    if (pos > 0) return order[pos - 1];
    if (q.repeatMode == PlayerRepeatMode.all && order.length > 1) {
      return order.last;
    }
    return null;
  }

  // ============================================================
  // STATS: helpers
  // ============================================================

  // ===== STATS =====
  String _songKeyOf(Song s) =>
      (s.path != null && s.path!.isNotEmpty) ? s.path! : s.title;

  /// Notifica que la pista en [songIndex] de la cola activa terminó de
  /// forma natural. Llamar ANTES de cambiar de pista.
  // ===== STATS =====
  void _emitTrackCompleted(int songIndex) {
    final q = _activeQueue;
    if (songIndex < 0 || songIndex >= q.songs.length) return;
    final song = q.songs[songIndex];
    if (_trackCompletedCtrl.isClosed) return;
    _trackCompletedCtrl.add(_songKeyOf(song));
  }

  // ============================================================
  // TRANSICIONES: API PÚBLICA
  // ============================================================

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

    if (!_transitionsEnabled) _fadeFactor = 1.0;
    _applyVolume(force: true);
  }

  static double _ease(double t) =>
      math.sin(t.clamp(0.0, 1.0).toDouble() * math.pi / 2);

  /// Factor del modo Fade In/Out (función pura de posición/duración).
  double _computeFadeFactor(Duration position, Duration? duration) {
    if (!_transitionsEnabled || _transitionMode != 1) return 1.0;

    var fadeMs = (_fadeSeconds * 1000 * _effectiveSpeed).round();
    if (fadeMs <= 0) return 1.0;

    final hasDur = duration != null && duration > Duration.zero;
    if (hasDur) {
      fadeMs = math.min(fadeMs, duration.inMilliseconds ~/ 2);
    }
    if (fadeMs <= 0) return 1.0;

    final posMs = position.inMilliseconds;
    var f = posMs <= 0 ? 0.0 : (posMs / fadeMs);

    if (hasDur) {
      final rem = duration.inMilliseconds - posMs;
      final out = rem <= _zeroGuardMs ? 0.0 : (rem / fadeMs);
      f = math.min(f, out);
    }
    return _ease(f);
  }

  // ============================================================
  // TICKER
  // ============================================================

  void _syncTicker() {
    final needed = _handle != null && _playing;
    if (needed) {
      _ticker ??= Timer.periodic(_tickEvery, (_) => _onTick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _onTick() {
    final h = _handle;
    if (h == null || !_playing || _loading || _handlingCompleted) return;

    if (!_isValid(h)) {
      _onVoiceEnded();
      return;
    }

    final pos = _livePosition();
    _position = pos;

    if (_transitionsEnabled && _transitionMode == 0) {
      _driveCrossfade(pos);
    }

    if (!_crossfading) _applyVolume();

    final now = DateTime.now();
    if (now.difference(_lastPositionEmit) >= _positionEmitEvery) {
      _lastPositionEmit = now;
      if (!_positionCtrl.isClosed) _positionCtrl.add(pos);
      _emitCanGoPrevious();
    }
    if (now.difference(_lastPublish) >= _publishEvery) {
      _lastPublish = now;
      _publish();
    }
  }

  /// La voz principal dejó de existir: fin de pista o invalidación externa.
  void _onVoiceEnded() {
    final nearEnd = _duration > Duration.zero &&
        _position >= _duration - const Duration(seconds: 2);

    if (!nearEnd) {
      debugPrint('PlaybackAudioHandler: voz invalidada; se marca pausa.');
      _handle = null;
      _cancelCrossfade();
      _setPlaying(false);
      _publish();
      return;
    }

    // Había una siguiente pista precargada: se promueve sin hueco.
    if (_nextSource != null && (_crossfading || _startNextVoice())) {
      _finishCrossfade();
      return;
    }

    unawaited(_onCompleted());
  }

  // ============================================================
  // VOLUMEN
  // ============================================================

  double _baseLinear() {
    // ReplayGain solo aplica a música.
    final rg = (_isMusicQueue && _replayGainDb != 0)
        ? math.pow(10, _replayGainDb / 20).toDouble()
        : 1.0;
    return _userVolume * rg;
  }

  void _applyVolume({bool force = false}) {
    final h = _handle;
    if (h == null) return;

    final f = _transitionsEnabled && _transitionMode == 1
        ? _computeFadeFactor(_position, _duration)
        : 1.0;
    final v = (_baseLinear() * f).clamp(0.0, 4.0).toDouble();

    if (!force) {
      if (v == _lastVol) return;
      final touchesZero = v == 0.0 || _lastVol == 0.0;
      if (!touchesZero && (v - _lastVol).abs() < 0.002) return;
    }

    _lastVol = v;
    _fadeFactor = f;
    try {
      _soloud.setVolume(h, v);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: setVolume falló -> $e');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0).toDouble();
    _userVolume = v;
    _volumeNotifier.value = v;
    if (_crossfading) {
      _mixCrossfade(_position);
    } else {
      _applyVolume(force: true);
    }
  }

  void _onReplayGainChanged() {
    _replayGainDb = _rg.enabled.value ? _rg.activeGainDb.value : 0.0;
    // El ReplayGain solo afecta a música; en podcast no hace falta tocar voces.
    if (!_isMusicQueue) return;
    if (_crossfading) {
      _mixCrossfade(_position);
    } else {
      _applyVolume(force: true);
    }
  }

  /// Aplica la velocidad efectiva (velocidad × slowed) a las voces activas.
  void _applySpeedToVoices() {
    final s = _effectiveSpeed;
    try {
      final h = _handle;
      if (h != null && _isValid(h)) _soloud.setRelativePlaySpeed(h, s);
      final nh = _nextHandle;
      if (nh != null && _isValid(nh)) _soloud.setRelativePlaySpeed(nh, s);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: setRelativePlaySpeed falló -> $e');
    }
  }

  Future<void> setSpeed(double speed) async {
    if (speed <= 0) return;
    _speed = speed;
    _applySpeedToVoices();
    _publish();
  }

  /// Efecto Slowed: [factor] 1.0 = apagado, [kMinSlowed]..1.0 = más lento
  /// y más grave (velocidad y tono van juntos). Solo afecta a música.
  Future<void> setSlowed(double factor) async {
    final v = factor.clamp(kMinSlowed, 1.0).toDouble();
    if ((v - _slowed).abs() < 0.0005) return;
    _slowed = v;
    _slowedNotifier.value = v;
    // En podcast el slowed no aplica: no tocar voces ni cancelar crossfade.
    if (!_isMusicQueue) return;
    // La ventana de crossfade depende de la velocidad: se recalcula.
    _cancelCrossfade();
    _applySpeedToVoices();
    _publish();
  }

  /// Guarda el nivel de Slowed actual (llamar al soltar el slider).
  Future<void> persistSlowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kSlowedPrefKey, _slowed);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: no se pudo guardar slowed -> $e');
    }
  }

  /// Restaura el nivel de Slowed guardado al iniciar.
  Future<void> _loadSlowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_kSlowedPrefKey);
      if (saved == null) return;
      await setSlowed(saved);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: no se pudo leer slowed -> $e');
    }
  }

  // ============================================================
  // CROSSFADE REAL (dos voces)
  // ============================================================

  int _xfWindowMs() => math.min(
        (_crossfadeSeconds * 1000 * _effectiveSpeed).round(),
        _duration.inMilliseconds ~/ 2,
      );

  void _driveCrossfade(Duration position) {
    if (_handlingCompleted) return;

    if (!_crossfading) {
      if (_xfBlocked) return;
      if (_activeQueue.repeatMode == PlayerRepeatMode.one) return;

      final x = _xfWindowMs();
      if (x < 500) return;

      // Fase 1: precargar con antelación.
      if (_nextSource == null) {
        final preloadAt =
            _duration - Duration(milliseconds: x) - _xfPreloadLead;
        if (!_xfPreparing && position >= preloadAt) {
          final next = _nextIndexOf(_activeQueue);
          if (next == null) return;
          unawaited(_prepareCrossfade(next));
        }
        return;
      }

      // Fase 2: arrancar al entrar en la ventana.
      if (position.inMilliseconds < _xfStartMs) return;

      if (!_startNextVoice(lateMs: position.inMilliseconds - _xfStartMs)) {
        _cancelCrossfade();
        _xfBlocked = true;
        return;
      }
    }

    // Fase 3: mezclar. Fase 4: terminar.
    final t = _mixCrossfade(position);
    if (t >= 1.0) _finishCrossfade();
  }

  Future<void> _prepareCrossfade(int nextIdx) async {
    final token = _xfToken;
    _xfPreparing = true;
    sl.AudioSource? source;

    try {
      final songs = _activeQueue.songs;
      if (nextIdx < 0 || nextIdx >= songs.length) {
        _xfBlocked = true;
        return;
      }
      final path = songs[nextIdx].path;
      if (path == null || path.isEmpty || !await File(path).exists()) {
        if (token == _xfToken) _xfBlocked = true;
        return;
      }
      if (token != _xfToken) return;

      await _ensureEngine();
      final size = await File(path).length();
      source = await _soloud.loadFile(
        path,
        mode: size > _diskLoadThresholdBytes
            ? sl.LoadMode.disk
            : sl.LoadMode.memory,
      );

      if (token != _xfToken) {
        await _disposeSource(source);
        return;
      }

      final len = _soloud.getLength(source);
      final span = math.min(_xfWindowMs(), len.inMilliseconds ~/ 2);
      if (span < 300) {
        await _disposeSource(source);
        _xfBlocked = true;
        return;
      }

      _nextSource = source;
      _nextIdx = nextIdx;
      _xfSpanMs = span;
      _xfStartMs = _duration.inMilliseconds - span;
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: precarga crossfade falló -> $e\n$st');
      unawaited(_disposeSource(source));
      if (token == _xfToken) _xfBlocked = true;
    } finally {
      if (token == _xfToken) _xfPreparing = false;
    }
  }

  bool _startNextVoice({int lateMs = 0}) {
    final source = _nextSource;
    if (source == null) return false;
    if (_crossfading) return true;

    try {
      final h = _soloud.play(source, volume: 0.0, paused: true);
      if ((_effectiveSpeed - 1.0).abs() > 0.0005) {
        _soloud.setRelativePlaySpeed(h, _effectiveSpeed);
      }
      final offsetMs = math.min(lateMs, _xfSpanMs);
      if (offsetMs > 150) {
        try {
          _soloud.seek(h, Duration(milliseconds: offsetMs));
        } catch (_) {}
      }
      _soloud.setPause(h, false);
      _nextHandle = h;
      _crossfading = true;
      return true;
    } catch (e) {
      debugPrint('PlaybackAudioHandler: no se pudo iniciar voz entrante -> $e');
      return false;
    }
  }

  /// Aplica volúmenes de ambas voces según el progreso de la mezcla.
  double _mixCrossfade(Duration position) {
    final span = math.max(1, _xfSpanMs);
    final t = ((position.inMilliseconds - _xfStartMs) / span)
        .clamp(0.0, 1.0)
        .toDouble();
    final angle = t * math.pi / 2;
    final base = _baseLinear();

    final outV = (base * math.cos(angle)).clamp(0.0, 4.0).toDouble();
    final inV = (base * math.sin(angle)).clamp(0.0, 4.0).toDouble();

    try {
      final h = _handle;
      final nh = _nextHandle;
      if (h != null) _soloud.setVolume(h, outV);
      if (nh != null) _soloud.setVolume(nh, inV);
    } catch (_) {}

    _lastVol = outV;
    _fadeFactor = math.cos(angle);
    return t;
  }

  /// La voz entrante pasa a ser la principal (nunca se hace play() de
  /// nuevo sobre la misma fuente).
  void _finishCrossfade() {
    final ns = _nextSource;
    final nh = _nextHandle;
    final ni = _nextIdx;
    if (ns == null || nh == null || ni < 0) {
      _cancelCrossfade();
      return;
    }

    // ===== STATS =====
    // La pista saliente terminó de forma natural (crossfade completo).
    _emitTrackCompleted(_activeQueue.currentIndex);

    final oldSource = _source;

    _source = ns;
    _handle = nh;
    _nextSource = null;
    _nextHandle = null;
    _nextIdx = -1;
    _crossfading = false;
    _xfPreparing = false;
    _xfBlocked = false;
    _xfToken++;

    _activeQueue.currentIndex = ni;
    _duration = _soloud.getLength(ns);
    _position = _livePosition();
    _lastVol = -1;

    unawaited(_disposeSource(oldSource));
    _applyVolume(force: true);

    if (!_durationCtrl.isClosed) _durationCtrl.add(_duration);
    _rg.notifyCurrentSong(_activeQueue.currentSong?.path);
    _emitControlsState();
  }

  /// Cancela cualquier crossfade (en curso o precargado).
  void _cancelCrossfade() {
    _xfToken++;
    _xfPreparing = false;
    _xfBlocked = false;

    final ns = _nextSource;
    final wasCrossfading = _crossfading;
    _nextSource = null;
    _nextHandle = null;
    _nextIdx = -1;
    _crossfading = false;

    if (ns != null) unawaited(_disposeSource(ns));
    if (wasCrossfading) _applyVolume(force: true);
  }

  // ============================================================
  // CARGA Y REPRODUCCIÓN DE UNA PISTA
  // ============================================================

  Future<void> _loadAndPlay(
    int songIndex, {
    required bool autoPlay,
    Duration start = Duration.zero,
  }) async {
    final q = _activeQueue;
    if (songIndex < 0 || songIndex >= q.songs.length) return;

    final song = q.songs[songIndex];
    final path = song.path;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      debugPrint('PlaybackAudioHandler: archivo no disponible -> $path');
      return;
    }

    final token = ++_loadToken;
    _loading = true;
    _resumeAfterLoad = autoPlay;
    _cancelCrossfade();

    // Silencia la pista anterior mientras se carga la nueva.
    final oldHandle = _handle;
    if (oldHandle != null && _isValid(oldHandle)) {
      try {
        _soloud.setPause(oldHandle, true);
      } catch (_) {}
    }

    q.currentIndex = songIndex;
    _publish();

    try {
      await _ensureEngine();

      final size = await File(path).length();
      final source = await _soloud.loadFile(
        path,
        mode: size > _diskLoadThresholdBytes
            ? sl.LoadMode.disk
            : sl.LoadMode.memory,
      );

      if (token != _loadToken) {
        await _disposeSource(source);
        return;
      }

      await _releaseVoice();

      _source = source;
      _duration = _soloud.getLength(source);
      if (!_durationCtrl.isClosed) _durationCtrl.add(_duration);

      // La voz nace en pausa y a volumen 0: seek, velocidad y volumen se
      // dejan listos ANTES de que suene el primer sample.
      final handle = _soloud.play(
        source,
        volume: 0.0,
        paused: true,
        looping: q.repeatMode == PlayerRepeatMode.one,
      );
      _handle = handle;
      _lastVol = -1;

      var startAt = start;
      if (_duration > Duration.zero &&
          startAt >= _duration - const Duration(seconds: 2)) {
        startAt = Duration.zero;
      }
      _position = Duration.zero;
      if (startAt > Duration.zero) {
        try {
          _soloud.seek(handle, startAt);
          _position = startAt;
        } catch (e) {
          debugPrint('PlaybackAudioHandler: seek inicial falló -> $e');
        }
      }

      if ((_effectiveSpeed - 1.0).abs() > 0.0005) {
        _soloud.setRelativePlaySpeed(handle, _effectiveSpeed);
      }

      _applyVolume(force: true);

      if (autoPlay) {
        _soloud.setPause(handle, false);
        _setPlaying(true);
      } else {
        _setPlaying(false);
      }

      _lastPositionEmit = DateTime.fromMillisecondsSinceEpoch(0);
      if (!_positionCtrl.isClosed) _positionCtrl.add(_position);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: carga falló -> $e\n$st');
      _setPlaying(false);
    } finally {
      if (token == _loadToken) _loading = false;
    }

    _rg.notifyCurrentSong(_activeQueue.currentSong?.path);
    _emitControlsState();
  }

  Future<void> _onCompleted() async {
    if (_handlingCompleted || _loading || _activeQueue.songs.isEmpty) return;
    _handlingCompleted = true;
    try {
      final q = _activeQueue;

      // ===== STATS =====
      // Fin natural de la pista actual: notificar antes de cambiar.
      _emitTrackCompleted(q.currentIndex);

      if (q.repeatMode == PlayerRepeatMode.one) {
        await _loadAndPlay(q.currentIndex, autoPlay: true);
        return;
      }

      final next = _nextIndexOf(q);
      if (next != null) {
        await _loadAndPlay(next, autoPlay: true);
      } else {
        // Fin de la cola: se deja lista la primera pista, en pausa.
        _ensureOrder(q);
        final first = q.sourceOrder.isEmpty ? 0 : q.sourceOrder.first;
        await _loadAndPlay(first, autoPlay: false);
      }
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: completed falló -> $e\n$st');
    } finally {
      _handlingCompleted = false;
      _emitControlsState();
    }
  }

  // ============================================================
  // DEDUPE
  // ============================================================

  String _songKey(Song s) =>
      (s.path != null && s.path!.isNotEmpty) ? s.path! : s.title;

  List<Song> _dedupeSongs(List<Song> input) {
    final seen = <String>{};
    final unique = <Song>[];
    for (final s in input) {
      if (seen.add(_songKey(s))) unique.add(s);
    }
    return unique;
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
  // PUBLICACIÓN
  // ============================================================

  bool get _effectivePlaying {
    if (_activeQueue.songs.isEmpty) return false;
    if (_loading) return _resumeAfterLoad;
    return _playing;
  }

  AudioProcessingState get _effectiveProcessingState {
    if (_activeQueue.songs.isEmpty) return AudioProcessingState.idle;
    if (_loading) return AudioProcessingState.loading;
    return AudioProcessingState.ready;
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
    final song = currentSong;
    final playing = _effectivePlaying;

    if (updateQueue) {
      if (song == null) {
        if (_lastMediaItemKey != null) {
          mediaItem.add(null);
          _lastMediaItemKey = null;
        }
      } else {
        final liveDuration = (!_loading && _duration > Duration.zero)
            ? _duration
            : null;
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
        updatePosition: _loading ? Duration.zero : _position,
        bufferedPosition: _loading ? Duration.zero : _duration,
        speed: _effectiveSpeed,
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
      q.sourceOrder = _buildOrder(q, keep);
    }
    _cancelCrossfade();
    _emitControlsState();
  }

  Future<void> setRepeatModeForUI(PlayerRepeatMode mode) async {
    if (_activeQueue.repeatMode == mode) return;
    _activeQueue.repeatMode = mode;
    _cancelCrossfade();
    _applyLooping();
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(mode);
    _emitControlsState();
  }

  void _applyLooping() {
    final h = _handle;
    if (h == null || !_isValid(h)) return;
    try {
      _soloud.setLooping(h, _activeQueue.repeatMode == PlayerRepeatMode.one);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: setLooping falló -> $e');
    }
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
    return setQueueOf(kind, songs, startIndex: startIndex, autoPlay: autoPlay);
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
    final unique = _dedupeSongs(songs);
    final playable = unique.where(_isPlayable).toList();
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

    _activeQueue.songs = playable;
    _activeQueue.resetOrder();
    _activeQueue.currentIndex = newStart;

    await _loadAndPlay(newStart, autoPlay: autoPlay);
  }

  // ============================================================
  // CAMBIO DE COLA ACTIVA
  // ============================================================

  Future<void> switchToQueue(
    MediaKind kind, {
    int? startIndex,
    bool? autoPlay,
  }) async {
    if (kind == _activeQueue.kind && _source != null) {
      if (startIndex != null) await skipToQueueItem(startIndex);
      return;
    }

    _cancelCrossfade();

    _activeQueue.saveLiveState(position: _position, playing: _playing);

    final h = _handle;
    if (h != null && _isValid(h)) {
      try {
        _soloud.setPause(h, true);
      } catch (_) {}
    }
    _setPlaying(false);

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

    // Efectos (reverb) solo en música: se silencian/restauran al cambiar.
    _syncReverbForQueue();

    if (!_activeQueueCtrl.isClosed) _activeQueueCtrl.add(kind);
    _rg.notifyCurrentSong(_activeQueue.currentSong?.path);

    if (_activeQueue.songs.isEmpty) {
      await _releaseVoice();
      _position = Duration.zero;
      _duration = Duration.zero;
      if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(_activeQueue.shuffleEnabled);
      if (!_repeatCtrl.isClosed) _repeatCtrl.add(_activeQueue.repeatMode);
      _emitControlsState();
      return;
    }

    _ensureOrder(_activeQueue);
    final idx = _activeQueue.currentIndex >= 0 ? _activeQueue.currentIndex : 0;

    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(_activeQueue.shuffleEnabled);
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(_activeQueue.repeatMode);

    await _loadAndPlay(
      idx,
      autoPlay: _activeQueue.savedPlaying,
      start: _activeQueue.savedPosition,
    );
  }

  // ============================================================
  // CLEAR QUEUE
  // ============================================================

  Future<void> _clearQueueOf(MediaKind kind) async {
    final q = _queueFor(kind);
    q.reset();

    if (kind == _activeQueue.kind) {
      _loadToken++;
      _loading = false;
      _resumeAfterLoad = false;
      await _releaseVoice();
      _setPlaying(false);
      _position = Duration.zero;
      _duration = Duration.zero;
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
    _loadToken++;
    _loading = false;

    _activeQueue.saveLiveState(position: _position, playing: false);

    _musicQueue.reset();
    _chaptersQueue.reset();

    _resumeAfterLoad = false;
    await _releaseVoice();
    _setPlaying(false);
    _position = Duration.zero;
    _duration = Duration.zero;

    _activeQueue = _musicQueue;
    _syncReverbForQueue();

    if (!_activeQueueCtrl.isClosed) _activeQueueCtrl.add(MediaKind.music);
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

    if (_source == null && !_loading) {
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
    _emitControlsState();
  }

  Future<void> removeFromQueue(int index) =>
      removeFromQueueOf(_activeQueue.kind, index);

  Future<void> removeFromQueueOf(MediaKind kind, int index) async {
    final q = _queueFor(kind);
    if (index < 0 || index >= q.songs.length) return;

    final isActive = kind == _activeQueue.kind;
    if (isActive) _cancelCrossfade();

    _ensureOrder(q);

    final wasCurrent = index == q.currentIndex;
    final wasPlaying = _playing;
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

    if (isActive && wasCurrent) {
      // Se quitó la pista que sonaba: se carga la que ocupa su lugar.
      await _loadAndPlay(newIndex, autoPlay: wasPlaying);
      return;
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
    if (q.shuffleEnabled) {
      q.sourceOrder = [
        for (final v in q.sourceOrder) _remapAfterMove(v, oldIndex, targetIndex),
      ];
    } else {
      q.resetOrder();
    }

    _emitControlsState();
  }

  // ============================================================
  // REPRODUCCIÓN
  // ============================================================

  Future<void> playFromQueueOf(MediaKind kind, int index) async {
    if (kind == _activeQueue.kind && _source != null) {
      await skipToQueueItem(index);
    } else {
      await switchToQueue(kind, startIndex: index, autoPlay: true);
    }
  }

  Future<void> playSong(Song song) async {
    final q = _queueFor(song.kind);
    final idx = q.songs.indexWhere((s) => s.path == song.path);
    if (idx >= 0) {
      if (_activeQueue.kind != song.kind || _source == null) {
        await switchToQueue(song.kind, startIndex: idx, autoPlay: true);
      } else {
        await skipToQueueItem(idx);
      }
    } else {
      await playOnly(song);
    }
  }

  Future<void> playFromQueue(int index) => skipToQueueItem(index);

  // ============================================================
  // PLAY / PAUSE / STOP / SEEK
  // ============================================================

  @override
  Future<void> play() async {
    final q = _activeQueue;
    if (q.songs.isEmpty || q.currentIndex < 0) {
      debugPrint('PlaybackAudioHandler: play() sin cola cargada');
      return;
    }

    final h = _handle;
    if (h != null && _isValid(h)) {
      try {
        _soloud.setPause(h, false);
        final nh = _nextHandle;
        if (nh != null && _isValid(nh)) _soloud.setPause(nh, false);
      } catch (e) {
        debugPrint('PlaybackAudioHandler: play falló -> $e');
      }
      _setPlaying(true);
    } else {
      // Voz invalidada (p. ej. por el sistema): se recarga donde iba.
      await _loadAndPlay(q.currentIndex, autoPlay: true, start: _position);
    }
    _publish();
  }

  @override
  Future<void> pause() async {
    final h = _handle;
    try {
      if (h != null && _isValid(h)) _soloud.setPause(h, true);
      final nh = _nextHandle;
      if (nh != null && _isValid(nh)) _soloud.setPause(nh, true);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: pause falló -> $e');
    }
    _setPlaying(false);
    _publish();
  }

  @override
  Future<void> stop() async {
    _loadGeneration++;
    _cancelCrossfade();
    _activeQueue.saveLiveState(position: _position, playing: false);
    await _clearQueueOf(_activeQueue.kind);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    final h = _handle;
    if (h == null || !_isValid(h)) return;

    var target = position;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;

    _cancelCrossfade();

    try {
      _soloud.seek(h, target);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: seek falló -> $e');
      return;
    }

    _position = target;
    _applyVolume(force: true);
    if (!_positionCtrl.isClosed) _positionCtrl.add(target);
    _emitCanGoPrevious();
    _publish();
  }

  @override
  Future<void> skipToNext() async {
    if (!_hasSource) return;
    final next = _nextIndexOf(_activeQueue);
    if (next == null) return;
    await _loadAndPlay(next, autoPlay: _playing || _resumeAfterLoad);
  }

  @override
  Future<void> skipToPrevious() async {
    if (!_hasSource) return;

    if (_position > _rewindThreshold) {
      await seek(Duration.zero);
      return;
    }

    final prev = _previousIndexOf(_activeQueue);
    if (prev != null) {
      await _loadAndPlay(prev, autoPlay: _playing || _resumeAfterLoad);
      return;
    }

    debugPrint('PlaybackAudioHandler: previous no aplica');
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final q = _activeQueue;
    if (index < 0 || index >= q.songs.length) return;

    if (_source == null && !_loading) {
      await setQueueOf(q.kind, q.songs, startIndex: index, autoPlay: true);
      return;
    }

    if (q.shuffleEnabled) {
      _ensureOrder(q);
      q.sourceOrder = _buildOrder(q, index);
    }

    await _loadAndPlay(index, autoPlay: true);
  }

  @override
  Future<void> onTaskRemoved() async {}

  Future<void> dispose() async {
    _ticker?.cancel();
    _ticker = null;
    _rg.activeGainDb.removeListener(_onReplayGainChanged);
    await _canGoPreviousCtrl.close();
    await _canGoNextCtrl.close();
    await _shuffleCtrl.close();
    await _repeatCtrl.close();
    await _activeQueueCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _playingCtrl.close();
    // ===== STATS =====
    await _trackCompletedCtrl.close();
    _volumeNotifier.dispose();
    _slowedNotifier.dispose();
    await _releaseVoice();
    try {
      _soloud.deinit();
    } catch (_) {}
  }
}
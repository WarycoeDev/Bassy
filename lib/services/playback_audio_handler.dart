// lib/services/playback_audio_handler.dart
//
// Handler de reproducción sobre flutter_soloud (SoLoud + miniaudio).
// Misma API pública que la versión con just_audio, para que
// PlaybackController y las pantallas no cambien.
//
// Comportamiento de colas: hay dos colas independientes (música y
// podcast). Cuando una cola empieza a SONAR, la contraria se vacía.
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

  /// El tipo contrario a [k].
  MediaKind _otherKind(MediaKind k) =>
      k == MediaKind.podcast ? MediaKind.music : MediaKind.podcast;

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

  // ⚡ Solo archivos muy pequeños se decodifican a RAM. El resto se
  // streamea desde disco (LoadMode.disk): arranque casi instantáneo en
  // vez de decodificar todo el PCM antes de sonar.
  // Si notas duraciones/seeks imprecisos en MP3 VBR, sube este valor.
  static const int _diskLoadThresholdBytes = 2 * 1024 * 1024; // 2 MB

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

    // Pre-inicializa el motor, diferido para no competir con el arranque.
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      unawaited(_ensureEngine().catchError((Object e) {
        debugPrint('PlaybackAudioHandler: pre-init del motor falló -> $e');
      }));
    });
  }

  // ============================================================
  // MOTOR
  // ============================================================

  Future<void> _ensureEngine() async {
    if (_soloud.isInitialized) return;
    await (_engineInit ??= () async {
      if (_soloud.isInitialized) return;
      try {
        if (Platform.isLinux) {
          await _soloud.setLinuxAudioBackend(sl.LinuxAudioBackend.pulseAudio);
        }
      } catch (e) {
        debugPrint('PlaybackAudioHandler: backend de audio no aplicado -> $e');
      }
      if (_soloud.isInitialized) return;
      try {
        await _soloud.init();
      } catch (e) {
        // Si otro punto lo inicializó entretanto, no es un error real.
        if (!_soloud.isInitialized) rethrow;
      }
    }()
        .whenComplete(() {
      _engineInit = null;
    }));
    ReverbService.instance.applyToEngine();
    _syncReverbForQueue();
  }

  Future<void> _disposeSource(sl.AudioSource? source) async {
    if (source == null) return;
    try {
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

  /// Duración REAL de la pista cargada (Duration.zero mientras carga).
  /// Las estadísticas la usan porque `Song.duration` suele venir vacía
  /// en podcasts.
  Duration get durationNow => _duration;

  bool get canGoPrevious =>
      hasPrevious || (_hasSource && _position > _rewindThreshold);

  bool get canGoNext => hasNext;
  bool get isPlaying => _playing;
  double get playerSpeed => _speed;

  double get slowed => _slowed;
  ValueListenable<double> get slowedListenable => _slowedNotifier;

  double get volume => _userVolume;
  ValueListenable<double> get volumeListenable => _volumeNotifier;

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
    if (!_isMusicQueue) return;
    if (_crossfading) {
      _mixCrossfade(_position);
    } else {
      _applyVolume(force: true);
    }
  }

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

  Future<void> setSlowed(double factor) async {
    final v = factor.clamp(kMinSlowed, 1.0).toDouble();
    if ((v - _slowed).abs() < 0.0005) return;
    _slowed = v;
    _slowedNotifier.value = v;
    if (!_isMusicQueue) return;
    _cancelCrossfade();
    _applySpeedToVoices();
    _publish();
  }

  Future<void> persistSlowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kSlowedPrefKey, _slowed);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: no se pudo guardar slowed -> $e');
    }
  }

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

      if (position.inMilliseconds < _xfStartMs) return;

      if (!_startNextVoice(lateMs: position.inMilliseconds - _xfStartMs)) {
        _cancelCrossfade();
        _xfBlocked = true;
        return;
      }
    }

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

  void _finishCrossfade() {
    final ns = _nextSource;
    final nh = _nextHandle;
    final ni = _nextIdx;
    if (ns == null || nh == null || ni < 0) {
      _cancelCrossfade();
      return;
    }

    // ===== STATS =====
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
    int skipDepth = 0,
  }) async {
    final q = _activeQueue;
    if (songIndex < 0 || songIndex >= q.songs.length) return;

    final song = q.songs[songIndex];
    final path = song.path;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      debugPrint('PlaybackAudioHandler: archivo no disponible -> $path');
      // ⚡ Ya no validamos toda la cola al crearla; los archivos
      // inexistentes se saltan aquí, al llegar a ellos.
      if (autoPlay && skipDepth < 20) {
        final prevIdx = q.currentIndex;
        q.currentIndex = songIndex;
        final next = _nextIndexOf(q);
        if (next != null && next != songIndex) {
          return _loadAndPlay(
            next,
            autoPlay: true,
            skipDepth: skipDepth + 1,
          );
        }
        q.currentIndex = prevIdx;
      }
      return;
    }

    final token = ++_loadToken;
    _loading = true;
    _resumeAfterLoad = autoPlay;
    _cancelCrossfade();

    // Pausamos la voz vieja YA, pero NO la liberamos todavía. La
    // liberación se hace en background después de que la nueva voz
    // empiece a sonar.
    final oldSource = _source;
    final oldHandle = _handle;
    if (oldHandle != null && _isValid(oldHandle)) {
      try {
        _soloud.setPause(oldHandle, true);
      } catch (_) {}
    }
    _source = null;
    _handle = null;
    _lastVol = -1;

    q.currentIndex = songIndex;

    // ===== STATS / REANUDAR =====
    // Reiniciamos posición y duración ANTES de publicar: así nadie
    // (estadísticas, UI) ve la posición/duración de la pista anterior
    // asociada a la nueva. Si hay posición inicial, ya la reflejamos.
    _position = start;
    _duration = Duration.zero;
    _publish();
    if (!_positionCtrl.isClosed) _positionCtrl.add(start);

    try {
      await _ensureEngine();

      int size = 0;
      try {
        size = File(path).lengthSync();
      } catch (_) {
        size = 0;
      }
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

      _source = source;
      _duration = _soloud.getLength(source);
      if (!_durationCtrl.isClosed) _durationCtrl.add(_duration);

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
        if (startAt > const Duration(seconds: 1)) {
          unawaited(_verifySeek(handle, startAt, token));
        }
      } else {
        _setPlaying(false);
      }

      _lastPositionEmit = DateTime.fromMillisecondsSinceEpoch(0);
      if (!_positionCtrl.isClosed) _positionCtrl.add(_position);

      // Liberar la voz anterior en background.
      if (oldSource != null) {
        unawaited(_disposeSource(oldSource));
      }
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: carga falló -> $e\n$st');
      // Si falló la nueva, al menos liberamos la vieja.
      if (oldSource != null) unawaited(_disposeSource(oldSource));
      _setPlaying(false);
    } finally {
      if (token == _loadToken) _loading = false;
    }

    _rg.notifyCurrentSong(_activeQueue.currentSong?.path);
    _emitControlsState();
  }

  /// En archivos grandes (LoadMode.disk) un seek hecho con la voz en
  /// pausa puede no aplicarse. Comprobamos poco después de arrancar y
  /// repetimos el seek si la posición real quedó lejos del objetivo.
  Future<void> _verifySeek(
    sl.SoundHandle handle,
    Duration target,
    int token,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (token != _loadToken || !_isValid(handle)) return;
    try {
      final pos = _soloud.getPosition(handle);
      if ((pos - target).abs() > const Duration(seconds: 2)) {
        _soloud.seek(handle, target);
        _position = target;
        if (!_positionCtrl.isClosed) _positionCtrl.add(target);
      }
    } catch (e) {
      debugPrint('PlaybackAudioHandler: verificación de seek falló -> $e');
    }
  }

  Future<void> _onCompleted() async {
    if (_handlingCompleted || _loading || _activeQueue.songs.isEmpty) return;
    _handlingCompleted = true;
    try {
      final q = _activeQueue;

      // ===== STATS =====
      _emitTrackCompleted(q.currentIndex);

      if (q.repeatMode == PlayerRepeatMode.one) {
        await _loadAndPlay(q.currentIndex, autoPlay: true);
        return;
      }

      final next = _nextIndexOf(q);
      if (next != null) {
        await _loadAndPlay(next, autoPlay: true);
      } else {
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

  /// Comprobación COMPLETA (toca el disco). Úsala solo para una canción
  /// suelta, nunca en bucle sobre toda la cola.
  bool _isPlayable(Song s) {
    final p = s.path;
    if (p == null || p.isEmpty) return false;
    if (!File(p).existsSync()) {
      debugPrint('PlaybackAudioHandler: path no existe -> $p');
      return false;
    }
    return true;
  }

  /// Comprobación BARATA (sin disco) para filtrar colas grandes.
  bool _hasPath(Song s) {
    final p = s.path;
    return p != null && p.isNotEmpty;
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
        if (mediaItem.value != null) mediaItem.add(null);
        _lastMediaItemKey = null;
      } else {
        final liveDuration = (!_loading && _duration > Duration.zero)
            ? _duration
            : null;
        final key =
            '${_activeQueue.kind.name}|${song.path ?? song.title}|${liveDuration?.inMilliseconds}';
        if (key != _lastMediaItemKey) {
          mediaItem.add(_toMediaItem(song, liveDuration, true));
          _lastMediaItemKey = key;
        }
      }

      // ⚡ Clave O(1): toda mutación de la cola asigna una lista nueva,
      // así que identityHashCode + length detecta los cambios sin
      // recorrer ni unir todos los paths (esto se llama cada 250 ms).
      final queueKey =
          '${_activeQueue.kind.name}#${identityHashCode(_activeQueue.songs)}#${_activeQueue.songs.length}';
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

  Future<void> _publishStopped() async {
    _lastMediaItemKey = null;
    _lastQueueKey = null;
    _lastControls = const <MediaControl>[];
    _lastCompactActionIndices = const <int>[];

    mediaItem.add(null);
    queue.add(const <MediaItem>[]);

    playbackState.add(
      PlaybackState(
        controls: const <MediaControl>[],
        systemActions: const <MediaAction>{},
        androidCompactActionIndices: const <int>[],
        processingState:
            AudioProcessingState.idle, // Obliga a Android a descartar la sesión
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        queueIndex: null,
      ),
    );

    await super.stop();
  }

  /// [checkArt] = true comprueba en disco que exista la carátula (solo
  /// para el item actual). Para los items de la cola NO se comprueba:
  /// hacerlo por cada canción bloqueaba el hilo de UI.
  MediaItem _toMediaItem(
    Song song, [
    Duration? duration,
    bool checkArt = false,
  ]) {
    final cover = song.coverPath;
    final d = song.duration;
    final hasCover = cover != null &&
        cover.isNotEmpty &&
        (!checkArt || File(cover).existsSync());
    return MediaItem(
      id: song.path ?? song.title,
      title: song.title,
      artist: song.subtitle,
      duration: duration ?? ((d != null && d > Duration.zero) ? d : null),
      artUri: hasCover ? Uri.file(cover) : null,
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
    Duration? startPosition,
  }) {
    final kind = songs.isEmpty
        ? _activeQueue.kind
        : (songs[startIndex.clamp(0, songs.length - 1)].kind ==
                MediaKind.podcast
            ? MediaKind.podcast
            : MediaKind.music);
    return setQueueOf(
      kind,
      songs,
      startIndex: startIndex,
      autoPlay: autoPlay,
      startPosition: startPosition,
    );
  }

  Future<void> setQueueOf(
    MediaKind kind,
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
    Duration? startPosition,
  }) {
    final generation = ++_loadGeneration;
    final run = _loadChain.catchError((_) {}).then<void>((_) async {
      if (generation != _loadGeneration) return;
      await _setQueueImpl(
        kind,
        songs,
        startIndex: startIndex,
        autoPlay: autoPlay,
        startPosition: startPosition ?? Duration.zero,
      );
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
    Duration startPosition = Duration.zero,
  }) async {
    _cancelCrossfade();

    if (songs.isEmpty) {
      await _clearQueueOf(kind);
      return;
    }
    if (startIndex < 0 || startIndex >= songs.length) startIndex = 0;

    final target = songs[startIndex];
    final unique = _dedupeSongs(songs);

    // ⚡ Filtro barato (sin tocar el disco). Antes se hacía
    // File.existsSync() por cada canción de la cola en el hilo de UI,
    // lo que causaba el retraso al abrir. Los archivos que ya no
    // existan se saltan en _loadAndPlay.
    final playable = unique.where(_hasPath).toList();
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
      targetQueue.savedPosition = startPosition;
      targetQueue.savedPlaying = autoPlay;

      if (!autoPlay) {
        _emitControlsState();
        return;
      }

      final old = _activeQueue;
      final h = _handle;
      if (h != null && _isValid(h)) {
        try {
          _soloud.setPause(h, true);
        } catch (_) {}
      }
      old.reset();

      _activeQueue = targetQueue;
      _lastMediaItemKey = null;
      _lastQueueKey = null;
      _syncReverbForQueue();

      if (!_activeQueueCtrl.isClosed) _activeQueueCtrl.add(kind);
      if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);
      if (!_repeatCtrl.isClosed) _repeatCtrl.add(targetQueue.repeatMode);

      await _loadAndPlay(newStart, autoPlay: true, start: startPosition);
      return;
    }

    _activeQueue.shuffleEnabled = false;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);

    _activeQueue.songs = playable;
    _activeQueue.resetOrder();
    _activeQueue.currentIndex = newStart;

    if (autoPlay) _queueFor(_otherKind(kind)).reset();

    await _loadAndPlay(newStart, autoPlay: autoPlay, start: startPosition);
  }

  // ============================================================
  // CAMBIO DE COLA ACTIVA
  // ============================================================

  Future<void> switchToQueue(
    MediaKind kind, {
    int? startIndex,
    bool? autoPlay,
    Duration? startPosition,
  }) async {
    if (kind == _activeQueue.kind && _source != null) {
      if (startIndex != null) {
        await _skipToIndex(startIndex, start: startPosition);
      }
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
      target.savedPosition = startPosition ?? Duration.zero;
      target.savedPlaying = autoPlay ?? true;
    } else if (autoPlay != null) {
      target.savedPlaying = autoPlay;
    }

    if (target.songs.isNotEmpty && target.savedPlaying) {
      _queueFor(_otherKind(kind)).reset();
    }

    _activeQueue = target;
    _lastMediaItemKey = null;
    _lastQueueKey = null;

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
    _resumeAfterLoad = false;
    _handlingCompleted = false;

    _cancelCrossfade();
    _musicQueue.reset();
    _chaptersQueue.reset();

    await _releaseVoice();
    _setPlaying(false);

    _position = Duration.zero;
    _duration = Duration.zero;
    _fadeFactor = 1.0;
    _lastVol = -1;

    _activeQueue = _musicQueue;
    _syncReverbForQueue();

    if (!_activeQueueCtrl.isClosed) _activeQueueCtrl.add(MediaKind.music);
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(PlayerRepeatMode.off);
    if (!_positionCtrl.isClosed) _positionCtrl.add(Duration.zero);
    if (!_durationCtrl.isClosed) _durationCtrl.add(null);

    _rg.notifyCurrentSong(null);
    _emitCanGoPrevious();
    _emitCanGoNext();

    await _publishStopped();
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

  Future<void> playFromQueueOf(
    MediaKind kind,
    int index, {
    Duration? startPosition,
  }) async {
    if (kind == _activeQueue.kind && _source != null) {
      await _skipToIndex(index, start: startPosition);
    } else {
      await switchToQueue(
        kind,
        startIndex: index,
        autoPlay: true,
        startPosition: startPosition,
      );
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
      await _loadAndPlay(q.currentIndex, autoPlay: true, start: _position);
    }
    _publish();
  }

  @override
  Future<void> pause() async {
    final h = _handle;
    try {
      if (h != null && _isValid(h)) {
        // Posición exacta justo al pausar (para estadísticas/reanudar).
        _position = _livePosition();
        _soloud.setPause(h, true);
      }
      final nh = _nextHandle;
      if (nh != null && _isValid(nh)) _soloud.setPause(nh, true);
    } catch (e) {
      debugPrint('PlaybackAudioHandler: pause falló -> $e');
    }
    _setPlaying(false);
    if (!_positionCtrl.isClosed) _positionCtrl.add(_position);
    _publish();
  }

  @override
  Future<void> stop() async {
    await clearAllQueues();
    await super.stop(); // Destruye la MediaSession nativa y limpia el fantasma de Android
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
  Future<void> skipToQueueItem(int index) => _skipToIndex(index);

  Future<void> _skipToIndex(int index, {Duration? start}) async {
    final q = _activeQueue;
    if (index < 0 || index >= q.songs.length) return;

    if (_source == null && !_loading) {
      await setQueueOf(
        q.kind,
        q.songs,
        startIndex: index,
        autoPlay: true,
        startPosition: start,
      );
      return;
    }

    if (q.shuffleEnabled) {
      _ensureOrder(q);
      q.sourceOrder = _buildOrder(q, index);
    }

    await _loadAndPlay(
      index,
      autoPlay: true,
      start: start ?? Duration.zero,
    );
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
// lib/services/playback_audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

/// Modo de repetición expuesto a la UI. Se llama `PlayerRepeatMode` para
/// no colisionar con el `RepeatMode` que exporta `package:flutter/material.dart`.
enum PlayerRepeatMode { off, all, one }

/// Handler que expone la cola y delega la reproducción a just_audio.
///
/// Patrón (igual que DecibeXAudioHandler): TODO lo que ve el sistema
/// (mediaItem, queue, playbackState) sale de un único método, [_publish],
/// que recalcula el estado completo desde el player. Nada más llama a
/// mediaItem.add / queue.add / playbackState.add.
class PlaybackAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// Cola actual. Invariante: solo contiene canciones reproducibles
  /// (path no vacío y archivo existente), por lo que el índice de la cola
  /// coincide siempre con el índice de la fuente concatenada.
  List<Song> _songs = const [];
  int _currentIndex = -1;

  ConcatenatingAudioSource? _queueSource;

  /// Serializa las cargas; la última llamada gana.
  Future<void> _loadChain = Future<void>.value();
  int _loadGeneration = 0;

  /// `true` mientras se reemplaza la fuente (ignora eventos de índice viejos).
  bool _loading = false;

  /// Intención de reproducir mientras dura la carga. Evita publicar
  /// `playing:false` (el pause() interno) cuando en realidad se está
  /// cambiando de canción.
  bool _resumeAfterLoad = false;

  /// Evita reentrar en la normalización de "completed".
  bool _handlingCompleted = false;

  // ---- Estado de publicación (dedupe) ----

  bool _isSeeking = false;
  int _seekGeneration = 0;
  List<MediaControl>? _lastControls;
  List<int>? _lastCompactActionIndices;
  String? _lastMediaItemKey;
  String? _lastQueueKey;

  DateTime _lastPositionPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _positionPublishEvery = Duration(milliseconds: 250);

  static const _rewindThreshold = Duration(seconds: 3);

  // ---- Shuffle / Repeat ----

  bool _shuffleEnabled = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;

  /// Orden original de la cola (sin barajar). Se conserva para poder
  /// deshacer el shuffle sin perder canciones ni reordenar de más.
  List<Song> _originalOrder = const [];

  // ---- Estado reactivo (para la UI) ----

  final _shuffleCtrl = StreamController<bool>.broadcast();
  final _repeatCtrl = StreamController<PlayerRepeatMode>.broadcast();
  final _canGoPreviousCtrl = StreamController<bool>.broadcast();
  final _canGoNextCtrl = StreamController<bool>.broadcast();

  bool _canGoPrevious = false;
  bool _canGoNext = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  PlaybackAudioHandler() {
    // Solo log de errores; el estado se publica desde los streams de abajo.
    _subs.add(_player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: playback error -> $e\n$st');
        _publish();
      },
    ));

    _subs.add(_player.playingStream.listen((_) => _publish()));

    _subs.add(_player.processingStateStream.listen((state) {
      _publish();
      if (state == ProcessingState.completed) {
        unawaited(_onCompleted());
      }
    }));

    // just_audio avanza solo de canción.
    _subs.add(_player.currentIndexStream.listen((sourceIndex) {
      if (_loading) return; // durante la carga los índices no son fiables
      if (sourceIndex == null) return;
      if (sourceIndex < 0 || sourceIndex >= _songs.length) return;
      _currentIndex = sourceIndex;
      _emitControlsState();
    }));

    // La duración real del archivo llega después de cargar.
    _subs.add(_player.durationStream.listen((_) => _publish()));

    // Saltos de posición (seek, cambio de pista).
    _subs.add(_player.positionDiscontinuityStream.listen((_) => _publish()));

    // Posición: republica mientras suena (throttled).
    _subs.add(_player.positionStream.listen(_onPosition));

    // La velocidad puede cambiar desde el sistema (notificación, BT, etc.).
    _subs.add(_player.speedStream.listen((_) => _publish()));

    _publish();
  }

  void _onPosition(Duration _) {
    _emitCanGoPrevious();

    if (!_player.playing) return;

    final now = DateTime.now();
    if (now.difference(_lastPositionPublish) < _positionPublishEvery) return;
    _lastPositionPublish = now;

    _publish();
  }

  /// just_audio deja `playing == true` al terminar la cola; lo normalizamos
  /// (pausa y vuelve al inicio) para que la notificación sea coherente.
  Future<void> _onCompleted() async {
    if (_handlingCompleted || _loading || _songs.isEmpty) return;
    _handlingCompleted = true;
    try {
      // Con LoopMode.one, just_audio ya reinicia solo; no intervenimos.
      if (_repeatMode == PlayerRepeatMode.one) return;
      await _player.pause();
      await _player.seek(Duration.zero, index: 0);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: normalizar completed falló -> $e\n$st');
    } finally {
      _handlingCompleted = false;
      _currentIndex = _songs.isEmpty ? -1 : 0;
      _emitControlsState();
    }
  }

  // ---------- Publicación única hacia audio_service ----------

  /// Estado "playing" que ve el sistema.
  bool get _effectivePlaying {
    if (_songs.isEmpty) return false;
    if (_loading) return _resumeAfterLoad;
    if (_player.processingState == ProcessingState.completed) return false;
    return _player.playing;
  }

  AudioProcessingState get _effectiveProcessingState {
    if (_songs.isEmpty) return AudioProcessingState.idle;
    if (_loading) return AudioProcessingState.loading;
    if (_handlingCompleted) return AudioProcessingState.ready;

    return switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      // Se normaliza enseguida en _onCompleted; mientras tanto, "ready".
      ProcessingState.completed => AudioProcessingState.ready,
    };
  }

  AudioServiceRepeatMode get _systemRepeatMode => switch (_repeatMode) {
        PlayerRepeatMode.off => AudioServiceRepeatMode.none,
        PlayerRepeatMode.all => AudioServiceRepeatMode.all,
        PlayerRepeatMode.one => AudioServiceRepeatMode.one,
      };

  AudioServiceShuffleMode get _systemShuffleMode => _shuffleEnabled
      ? AudioServiceShuffleMode.all
      : AudioServiceShuffleMode.none;

  void _publish({bool updateControls = true, bool updateQueue = true}) {
    // Android reconstruye la notificación al recibir cambios de
    // controles/cola. Durante un seek solo se actualiza la posición.
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
        // Durante la carga _player.duration es de la pista anterior.
        final d = _loading ? null : _player.duration;
        final liveDuration = (d != null && d > Duration.zero) ? d : null;
        final key = '${song.path ?? song.title}|${liveDuration?.inMilliseconds}';

        if (key != _lastMediaItemKey) {
          mediaItem.add(_toMediaItem(song, liveDuration));
          _lastMediaItemKey = key;
        }
      }

      final queueKey = _songs.map((s) => s.path ?? s.title).join('|');
      if (queueKey != _lastQueueKey) {
        queue.add(_songs.map((s) => _toMediaItem(s)).toList(growable: false));
        _lastQueueKey = queueKey;
      }
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
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
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
      extras: {'path': song.path},
      playable: song.path != null && song.path!.isNotEmpty,
    );
  }

  // ---------- Getters de estado (sincrónicos) ----------

  bool get hasNext {
    if (_queueSource == null) return false;
    return _currentIndex >= 0 && _currentIndex < _songs.length - 1;
  }

  bool get hasPrevious {
    if (_queueSource == null) return false;
    return _currentIndex > 0 && _currentIndex < _songs.length;
  }

  Duration get position => _player.position;

  bool get canGoPrevious =>
      hasPrevious ||
      (_queueSource != null && _player.position > _rewindThreshold);

  bool get canGoNext => hasNext;

  /// Velocidad actual (1.0 = normal).
  double get playerSpeed => _player.speed;

  bool get shuffleEnabled => _shuffleEnabled;
  PlayerRepeatMode get repeatMode => _repeatMode;

  // ---------- Emisión reactiva ----------

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

  /// Emite los estados de los botones y republica todo.
  void _emitControlsState() {
    _emitCanGoPrevious();
    _emitCanGoNext();
    _publish();
  }

  Stream<bool> get canGoPreviousStream => _canGoPreviousCtrl.stream;
  Stream<bool> get canGoNextStream => _canGoNextCtrl.stream;
  Stream<bool> get shuffleStream => _shuffleCtrl.stream;
  Stream<PlayerRepeatMode> get repeatStream => _repeatCtrl.stream;

  // ---------- API pública para la UI ----------

  List<Song> get songs => List.unmodifiable(_songs);

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _songs.length
          ? _songs[_currentIndex]
          : null;

  int get currentIndex => _currentIndex;

  bool get isPlaying => _player.playing;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  // ---------- Shuffle / Repeat: setters ----------

  Future<void> setShuffle(bool enabled) async {
    if (_shuffleEnabled == enabled) return;
    _shuffleEnabled = enabled;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(enabled);

    if (_songs.isEmpty || _queueSource == null) {
      _publish();
      return;
    }

    final currentPath = currentSong?.path;
    final currentPos = _player.position;

    List<Song> newOrder;
    if (enabled) {
      // Guardar el orden original solo la primera vez que se activa.
      if (_originalOrder.isEmpty) {
        _originalOrder = List<Song>.from(_songs);
      }
      final current = currentPath == null
          ? null
          : _songs.firstWhere(
              (s) => s.path == currentPath,
              orElse: () => _songs.first,
            );
      final rest = _songs.where((s) => s.path != currentPath).toList()
        ..shuffle(Random());
      newOrder = [
        if (current != null) current,
        ...rest,
      ];
    } else {
      newOrder = _originalOrder.isNotEmpty
          ? List<Song>.from(_originalOrder)
          : List<Song>.from(_songs);
    }

    final newIndex = currentPath == null
        ? 0
        : newOrder.indexWhere((s) => s.path == currentPath);
    final targetIndex = newIndex < 0 ? 0 : newIndex;

    await _reloadQueueWith(
      newOrder,
      targetIndex,
      currentPos,
      keepPlaying: true,
    );
  }

  /// Setter para la UI (nuestro enum propio).
  Future<void> setRepeatModeForUI(PlayerRepeatMode mode) async {
    if (_repeatMode == mode) return;
    _repeatMode = mode;
    await _applyLoopMode();
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(mode);
    _publish();
  }

  /// Override del contrato de audio_service (notificación, Bluetooth, coche).
  /// Traduce `AudioServiceRepeatMode` a nuestro `PlayerRepeatMode`.
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final next = switch (repeatMode) {
      AudioServiceRepeatMode.none => PlayerRepeatMode.off,
      AudioServiceRepeatMode.all => PlayerRepeatMode.all,
      AudioServiceRepeatMode.one => PlayerRepeatMode.one,
      // "group" no lo soportamos; lo tratamos como off.
      AudioServiceRepeatMode.group => PlayerRepeatMode.off,
    };
    await setRepeatModeForUI(next);
  }

  /// Override del contrato de audio_service (shuffle desde notificación/BT).
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = switch (shuffleMode) {
      AudioServiceShuffleMode.all => true,
      AudioServiceShuffleMode.none => false,
      // "group" no lo soportamos; lo tratamos como off.
      AudioServiceShuffleMode.group => false,
    };
    await setShuffle(enable);
  }

  Future<void> _applyLoopMode() async {
    switch (_repeatMode) {
      case PlayerRepeatMode.off:
        await _player.setLoopMode(LoopMode.off);
      case PlayerRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
      case PlayerRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
    }
  }

  /// Reemplaza la fuente sin cortar audio si es posible: preserva posición
  /// y estado de reproducción.
  Future<void> _reloadQueueWith(
    List<Song> order,
    int startIndex,
    Duration startPosition, {
    bool keepPlaying = true,
  }) async {
    final wasPlaying = _player.playing;
    _loading = true;
    _resumeAfterLoad = keepPlaying && wasPlaying;

    try {
      await _player.pause();

      _songs = order;
      _currentIndex = startIndex;
      _publish();

      final concat = ConcatenatingAudioSource(
        children: [for (final s in _songs) AudioSource.file(s.path!)],
      );
      _queueSource = concat;

      await _player.setAudioSource(
        concat,
        initialIndex: startIndex,
        initialPosition: startPosition,
      );
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: _reloadQueueWith falló -> $e\n$st');
    } finally {
      _loading = false;
    }

    if (_resumeAfterLoad) {
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
      }));
    }

    await _applyLoopMode();
    _emitControlsState();
  }

  // ---------- Control de cola ----------

  bool _isPlayable(Song s) {
    final p = s.path;
    if (p == null || p.isEmpty) return false;
    if (!File(p).existsSync()) {
      debugPrint('PlaybackAudioHandler: path no existe -> $p');
      return false;
    }
    return true;
  }

  /// Reemplaza toda la cola. Si llegan varias llamadas seguidas, se ejecutan
  /// en orden y las intermedias se descartan (gana la última).
  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    final generation = ++_loadGeneration;
    final run = _loadChain.catchError((_) {}).then<void>((_) async {
      if (generation != _loadGeneration) return;
      await _setQueueImpl(songs, startIndex: startIndex, autoPlay: autoPlay);
    });
    _loadChain = run;
    return run;
  }

  Future<void> playOnly(Song song) =>
      setQueue([song], startIndex: 0, autoPlay: true);

  Future<void> _setQueueImpl(
    List<Song> songs, {
    required int startIndex,
    required bool autoPlay,
  }) async {
    if (songs.isEmpty) {
      await _clearQueue();
      return;
    }
    if (startIndex < 0 || startIndex >= songs.length) startIndex = 0;

    final target = songs[startIndex];
    final playable = songs.where(_isPlayable).toList();
    if (playable.isEmpty) {
      debugPrint('PlaybackAudioHandler: no hay fuentes válidas en la cola');
      await _clearQueue();
      return;
    }
    var newStart = playable.indexWhere((s) => identical(s, target));
    if (newStart < 0) newStart = 0;

    // Cualquier carga nueva reinicia shuffle al orden original.
    _originalOrder = List<Song>.from(playable);
    _shuffleEnabled = false;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);

    // Desde aquí el sistema ve "cargando" y la intención de reproducir,
    // sin pasar nunca por playing:false.
    _loading = true;
    _resumeAfterLoad = autoPlay;

    try {
      // Corta ya el audio anterior (no espera a que termine la canción).
      await _player.pause();

      _songs = playable;
      _currentIndex = newStart;
      _publish();

      final concat = ConcatenatingAudioSource(
        children: [for (final s in _songs) AudioSource.file(s.path!)],
      );
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
        _songs = const [];
        _currentIndex = -1;
        _resumeAfterLoad = false;
        _loading = false;
        await _player.stop();
        _emitControlsState();
        rethrow;
      }
    } finally {
      _loading = false;
    }

    _currentIndex = newStart;

    await _applyLoopMode();

    if (autoPlay) {
      // No await: el Future de play() dura toda la canción.
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
      }));
    }

    // Publica DESPUÉS de lanzar el play (player.playing ya es true).
    _emitControlsState();
  }

  Future<void> _clearQueue() async {
    _songs = const [];
    _currentIndex = -1;
    _queueSource = null;
    _resumeAfterLoad = false;
    _originalOrder = const [];
    _shuffleEnabled = false;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);
    await _player.stop();
    _emitControlsState();
  }

  Future<void> clearQueue() {
    // Invalida cargas pendientes para que no "resuciten" la cola.
    _loadGeneration++;
    return _clearQueue();
  }

  Future<void> addToQueue(Song song) async {
    if (!_isPlayable(song)) return;

    final source = _queueSource;
    if (source == null) {
      final newSongs = [..._songs, song];
      await setQueue(
        newSongs,
        startIndex: _currentIndex < 0 ? newSongs.length - 1 : _currentIndex,
        autoPlay: false,
      );
      return;
    }

    _songs = [..._songs, song];
    if (_originalOrder.isNotEmpty) {
      _originalOrder = [..._originalOrder, song];
    }
    await source.add(AudioSource.file(song.path!));
    _emitControlsState();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final removed = _songs[index];
    final wasCurrent = index == _currentIndex;
    final newSongs = List<Song>.from(_songs)..removeAt(index);

    if (newSongs.isEmpty) {
      await _clearQueue();
      return;
    }

    int newIndex = _currentIndex;
    if (index < _currentIndex) {
      newIndex = _currentIndex - 1;
    } else if (wasCurrent) {
      newIndex = index.clamp(0, newSongs.length - 1);
    }

    _songs = newSongs;
    _currentIndex = newIndex;
    _originalOrder =
        _originalOrder.where((s) => s.path != removed.path).toList();

    final source = _queueSource;
    if (source != null) {
      try {
        await source.removeAt(index);
      } catch (e, st) {
        debugPrint('PlaybackAudioHandler: removeAt falló -> $e\n$st');
      }
    }

    _emitControlsState();
  }

  Future<void> playSong(Song song) async {
    final idx = _songs.indexWhere((s) => s.path == song.path);
    if (idx >= 0 && _queueSource != null) {
      await skipToQueueItem(idx);
    } else {
      await setQueue([song], startIndex: 0, autoPlay: true);
    }
  }

  Future<void> playFromQueue(int index) => skipToQueueItem(index);

  // ---------- Velocidad ----------

  Future<void> setSpeed(double speed) async {
    if (speed <= 0) return;
    await _player.setSpeed(speed);
    _publish();
  }

  // ---------- Overrides de BaseAudioHandler ----------

  @override
  Future<void> play() async {
    if (_queueSource == null) {
      debugPrint('PlaybackAudioHandler: play() sin fuente cargada');
      return;
    }
    // No await: el Future de play() dura mientras suena.
    unawaited(_player.play().catchError((Object e, StackTrace st) {
      debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
    }));
    _publish(); // _player.playing ya es true (just_audio lo fija síncrono)
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _publish();
  }

  @override
  Future<void> stop() async {
    _loadGeneration++;
    await _clearQueue();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    final generation = ++_seekGeneration;
    _isSeeking = true;
    _publish(updateControls: false, updateQueue: false);

    try {
      await _player.seek(position);
    } finally {
      if (generation == _seekGeneration) {
        _isSeeking = false;
        _emitCanGoPrevious();
        _publish();
      }
    }
  }

  @override
  Future<void> skipToNext() async {
    if (!hasNext || _queueSource == null) return;
    await _player.seekToNext();
    // El listener de currentIndexStream actualiza el índice y publica.
    _emitControlsState();
  }

  /// "Previous" estilo Spotify/YouTube.
  @override
  Future<void> skipToPrevious() async {
    if (_queueSource == null) return;

    if (_player.position > _rewindThreshold) {
      await seek(Duration.zero);
      return;
    }

    if (hasPrevious) {
      await _player.seekToPrevious();
      _emitControlsState();
      return;
    }

    debugPrint('PlaybackAudioHandler: previous no aplica');
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;

    if (_queueSource == null) {
      await setQueue(_songs, startIndex: index, autoPlay: true);
      return;
    }

    _currentIndex = index;
    try {
      await _player.seek(Duration.zero, index: index);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: seek falló -> $e\n$st');
      return;
    }
    unawaited(_player.play().catchError((Object e, StackTrace st) {
      debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
    }));
    _emitControlsState();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Mantener la reproducción mientras el usuario cierra la UI desde
    // recientes; Android seguirá gestionando la sesión multimedia.
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _canGoPreviousCtrl.close();
    await _canGoNextCtrl.close();
    await _shuffleCtrl.close();
    await _repeatCtrl.close();
    await _player.dispose();
  }
}
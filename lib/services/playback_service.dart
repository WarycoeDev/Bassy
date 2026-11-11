// lib/services/playback_audio_handler.dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

/// Handler que expone la cola y delega la reproducción a just_audio.
/// Es el que se registra en AudioService.init().
class PlaybackAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// Cola actual. Invariante: solo contiene canciones reproducibles
  /// (path no vacío y archivo existente), por lo que el índice de la cola
  /// coincide siempre con el índice de la fuente concatenada.
  List<Song> _songs = const [];
  int _currentIndex = -1;

  /// Fuente concatenada actual. La guardamos para poder hacer
  /// operaciones incrementales (add/remove) sin recargar la pista actual.
  ConcatenatingAudioSource? _queueSource;

  /// Serializa las cargas; la última llamada gana.
  Future<void> _loadChain = Future<void>.value();
  int _loadGeneration = 0;

  /// `true` mientras se reemplaza la fuente (ignora eventos de índice viejos).
  bool _loading = false;

  /// Umbral a partir del cual "previous" reinicia la canción actual
  /// en lugar de ir a la anterior.
  static const _rewindThreshold = Duration(seconds: 3);

  // ---- Estado reactivo de los botones ----

  final _canGoPreviousCtrl = StreamController<bool>.broadcast();
  final _canGoNextCtrl = StreamController<bool>.broadcast();

  bool _canGoPrevious = false;
  bool _canGoNext = false;

  PlaybackAudioHandler() {
    // Publica el estado del player como PlaybackState.
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Refresca el MediaItem actual cuando just_audio avanza solo.
    _player.currentIndexStream.listen((sourceIndex) {
      if (_loading) return; // durante la carga los índices no son fiables
      if (sourceIndex == null) return;
      if (sourceIndex < 0 || sourceIndex >= _songs.length) return;
      _currentIndex = sourceIndex;
      mediaItem.add(_toMediaItem(_songs[sourceIndex]));
      _emitControlsState();
    });

    // Re-evalúa los botones cuando cambia la posición
    // (para reflejar el cruce del umbral de rewind).
    _player.positionStream.listen((_) => _emitCanGoPrevious());

    // Loguea errores del player para no fallar en silencio.
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: playback error -> $e\n$st');
      },
    );
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex >= 0 ? _currentIndex : null,
    );
  }

  MediaItem _toMediaItem(Song song) {
    final cover = song.coverPath;
    return MediaItem(
      id: song.path ?? song.title,
      title: song.title,
      artist: song.subtitle,
      duration: song.duration,
      artUri: cover != null && cover.isNotEmpty && File(cover).existsSync()
          ? Uri.file(cover)
          : null,
      extras: {'path': song.path},
    );
  }

  // ---------- Getters de estado (sincrónicos) ----------

  /// `true` si hay canción siguiente en la cola.
  bool get hasNext {
    if (_queueSource == null) return false;
    return _currentIndex >= 0 && _currentIndex < _songs.length - 1;
  }

  /// `true` si hay canción anterior en la cola.
  bool get hasPrevious {
    if (_queueSource == null) return false;
    return _currentIndex > 0 && _currentIndex < _songs.length;
  }

  /// Posición actual sincrónica (para decidir previous sin esperar al stream).
  Duration get position => _player.position;

  /// `true` si el botón "previous" debe estar habilitado:
  /// hay canción anterior **o** ya se superó el umbral de rewind.
  bool get canGoPrevious =>
      hasPrevious || _player.position > _rewindThreshold;

  /// `true` si el botón "next" debe estar habilitado.
  bool get canGoNext => hasNext;

  // ---------- Emisión reactiva de los botones ----------

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

  /// Emite ambos estados a la vez. Úsalo tras cualquier cambio de cola.
  void _emitControlsState() {
    _emitCanGoPrevious();
    _emitCanGoNext();
  }

  Stream<bool> get canGoPreviousStream => _canGoPreviousCtrl.stream;
  Stream<bool> get canGoNextStream => _canGoNextCtrl.stream;

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

  /// Reemplaza toda la cola. Por defecto **reproduce** desde [startIndex].
  /// Si llegan varias llamadas seguidas, se ejecutan en orden y las
  /// intermedias se descartan (gana la última).
  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    final generation = ++_loadGeneration;
    final run = _loadChain.catchError((_) {}).then<void>((_) async {
      if (generation != _loadGeneration) return; // superada por otra llamada
      await _setQueueImpl(songs, startIndex: startIndex, autoPlay: autoPlay);
    });
    _loadChain = run;
    return run;
  }

  /// Vacía la cola, deja solo [song] y la reproduce, cortando lo anterior.
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

    // Solo canciones reproducibles: así índice de cola == índice de fuente.
    final target = songs[startIndex];
    final playable = songs.where(_isPlayable).toList();
    if (playable.isEmpty) {
      debugPrint('PlaybackAudioHandler: no hay fuentes válidas en la cola');
      await _clearQueue();
      return;
    }
    var newStart = playable.indexWhere((s) => identical(s, target));
    if (newStart < 0) newStart = 0;

    _loading = true;
    try {
      // Corta ya el audio anterior (no espera a que termine la canción).
      await _player.pause();

      _songs = playable;
      _currentIndex = newStart;
      super.queue.add(_songs.map(_toMediaItem).toList(growable: false));
      mediaItem.add(_toMediaItem(_songs[newStart]));

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
        super.queue.add(const []);
        mediaItem.add(null);
        await _player.stop();
        _emitControlsState();
        rethrow;
      }
    } finally {
      _loading = false;
    }

    _currentIndex = newStart;
    _emitControlsState();

    if (autoPlay) {
      // IMPORTANTE: no await, el Future de play() dura toda la canción.
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
      }));
    }
  }

  Future<void> _clearQueue() async {
    _songs = const [];
    _currentIndex = -1;
    _queueSource = null;
    super.queue.add(const []);
    mediaItem.add(null);
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
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));
    await source.add(AudioSource.file(song.path!));
    _emitControlsState();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _songs.length) return;

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
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));

    final source = _queueSource;
    if (source != null) {
      try {
        // índice de cola == índice de fuente
        await source.removeAt(index);
      } catch (e, st) {
        debugPrint('PlaybackAudioHandler: removeAt falló -> $e\n$st');
      }
    }

    if (_currentIndex >= 0 && _currentIndex < _songs.length) {
      mediaItem.add(_toMediaItem(_songs[_currentIndex]));
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

  // ---------- Overrides de BaseAudioHandler ----------

  @override
  Future<void> play() async {
    if (_queueSource == null) {
      debugPrint('PlaybackAudioHandler: play() sin fuente cargada');
      return;
    }
    // No await: el Future de play() dura mientras suena.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _emitCanGoPrevious();
  }

  @override
  Future<void> skipToNext() async {
    if (!hasNext || _queueSource == null) return;
    await _player.seekToNext();
    // El listener de currentIndexStream actualizará el índice y emitirá.
    _emitControlsState();
  }

  /// Comportamiento "previous" estilo Spotify/YouTube:
  ///  - Si ya se reprodujo más del umbral → reinicia la canción actual.
  ///  - Si no pasó el umbral y hay anterior → va a la canción anterior.
  ///  - Si no pasó el umbral y no hay anterior → no hace nada.
  @override
  Future<void> skipToPrevious() async {
    if (_queueSource == null) return;

    if (_player.position > _rewindThreshold) {
      await _player.seek(Duration.zero);
      _emitCanGoPrevious();
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
      // índice de cola == índice de fuente
      await _player.seek(Duration.zero, index: index);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: seek falló -> $e\n$st');
      return;
    }
    unawaited(_player.play());
    _emitControlsState();
  }

  Future<void> dispose() async {
    await _canGoPreviousCtrl.close();
    await _canGoNextCtrl.close();
    await _player.dispose();
  }
}
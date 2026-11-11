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

  List<Song> _songs = const [];
  int _currentIndex = -1;

  /// Fuente concatenada actual. La guardamos para poder hacer
  /// operaciones incrementales (add/remove) sin recargar la pista actual.
  ConcatenatingAudioSource? _queueSource;

  /// Evita que dos llamadas concurrentes a `setQueue` se pisen.
  Future<void>? _pendingLoad;

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
      if (sourceIndex == null) return;
      final queueIndex = _queueIndexForSource(sourceIndex);
      if (queueIndex == null) return;
      _currentIndex = queueIndex;
      mediaItem.add(_toMediaItem(_songs[queueIndex]));
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

  // ---------- Mapeo cola ↔ fuente ----------
  // La fuente concatenada solo contiene canciones con `path` no vacío.
  // Si todas tienen path (caso normal), ambos índices coinciden.

  int? _sourceIndexForQueue(int queueIndex) {
    if (queueIndex < 0 || queueIndex >= _songs.length) return null;
    final p = _songs[queueIndex].path;
    if (p == null || p.isEmpty) return null;
    var sourceIndex = 0;
    for (var i = 0; i < queueIndex; i++) {
      final q = _songs[i].path;
      if (q != null && q.isNotEmpty) sourceIndex++;
    }
    return sourceIndex;
  }

  int? _queueIndexForSource(int sourceIndex) {
    var s = 0;
    for (var i = 0; i < _songs.length; i++) {
      final p = _songs[i].path;
      if (p == null || p.isEmpty) continue;
      if (s == sourceIndex) return i;
      s++;
    }
    return null;
  }

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

  /// Reemplaza toda la cola. Por defecto **reproduce** desde [startIndex].
  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (songs.isEmpty) {
      await _clearQueue();
      return;
    }
    if (startIndex < 0 || startIndex >= songs.length) startIndex = 0;

    final previous = _pendingLoad;
    final completer = Completer<void>();
    _pendingLoad = completer.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }

    try {
      _songs = List<Song>.from(songs);
      _currentIndex = startIndex;

      super.queue.add(_songs.map(_toMediaItem).toList(growable: false));
      mediaItem.add(_toMediaItem(_songs[startIndex]));

      final sources = <AudioSource>[];
      for (final s in _songs) {
        final p = s.path;
        if (p == null || p.isEmpty) continue;
        if (!File(p).existsSync()) {
          debugPrint('PlaybackAudioHandler: path no existe -> $p');
          continue;
        }
        sources.add(AudioSource.file(p));
      }

      if (sources.isEmpty) {
        debugPrint('PlaybackAudioHandler: no hay fuentes válidas en la cola');
        _queueSource = null;
        await _player.stop();
        mediaItem.add(null);
        _currentIndex = -1;
        _emitControlsState();
        return;
      }

      final concat = ConcatenatingAudioSource(children: sources);
      _queueSource = concat;

      final initialSourceIndex =
          (_sourceIndexForQueue(startIndex) ?? 0)
              .clamp(0, sources.length - 1);

      try {
        await _player.setAudioSource(
          concat,
          initialIndex: initialSourceIndex,
          initialPosition: Duration.zero,
        );
      } catch (e, st) {
        debugPrint('PlaybackAudioHandler: setAudioSource falló -> $e\n$st');
        _queueSource = null;
        _currentIndex = -1;
        mediaItem.add(null);
        await _player.stop();
        _emitControlsState();
        rethrow;
      }

      if (autoPlay) {
        await _player.play();
      }

      _emitControlsState();
    } finally {
      completer.complete();
      if (identical(_pendingLoad, completer.future)) {
        _pendingLoad = null;
      }
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

  Future<void> clearQueue() => _clearQueue();

  Future<void> addToQueue(Song song) async {
    final path = song.path;
    if (path == null || path.isEmpty) return;
    if (!File(path).existsSync()) {
      debugPrint('PlaybackAudioHandler: addToQueue path no existe -> $path');
      return;
    }

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
    await source.add(AudioSource.file(path));
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

    final sourceIndex = _sourceIndexForQueue(index);

    _songs = newSongs;
    _currentIndex = newIndex;
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));

    final source = _queueSource;
    if (source == null || sourceIndex == null) {
      if (_currentIndex >= 0 && _currentIndex < _songs.length) {
        mediaItem.add(_toMediaItem(_songs[_currentIndex]));
      }
      _emitControlsState();
      return;
    }

    try {
      await source.removeAt(sourceIndex);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: removeAt falló -> $e\n$st');
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
    await _player.play();
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
    // Por si acaso, forzamos re-evaluación (umbral ya no aplica al
    // cambiar de canción, y next puede haberse desactivado).
    _emitControlsState();
  }

  /// Comportamiento "previous" estilo Spotify/YouTube:
  ///  - Si ya se reprodujo más del umbral → reinicia la canción actual.
  ///  - Si no pasó el umbral y hay anterior → va a la canción anterior.
  ///  - Si no pasó el umbral y no hay anterior → no hace nada
  ///    (la UI debe tener el botón deshabilitado).
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
      // El listener de currentIndexStream actualizará índice y emitirá.
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

    final sourceIndex = _sourceIndexForQueue(index);
    if (sourceIndex == null) {
      debugPrint(
        'PlaybackAudioHandler: skipToQueueItem sin sourceIndex '
        '(canción sin path?)',
      );
      return;
    }

    _currentIndex = index;
    try {
      await _player.seek(Duration.zero, index: sourceIndex);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: seek falló -> $e\n$st');
      return;
    }
    await _player.play();
    _emitControlsState();
  }

  Future<void> dispose() async {
    await _canGoPreviousCtrl.close();
    await _canGoNextCtrl.close();
    await _player.dispose();
  }
}
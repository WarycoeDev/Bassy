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
    });

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
  ///
  /// FIX: antes no llamaba a play() y el player quedaba en `ready` pero
  /// pausado → la UI lo percibía como "se pausa". Ahora el contrato es
  /// explícito: `autoPlay = true`.
  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (songs.isEmpty) {
      // Cola vacía → limpiar estado en lugar de retornar en silencio.
      await _clearQueue();
      return;
    }
    if (startIndex < 0 || startIndex >= songs.length) startIndex = 0;

    // Serializa cargas concurrentes (evita condiciones de carrera
    // cuando se pulsa rápido varias canciones).
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

      // Valida que el path exista antes de crear AudioSource.
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
        debugPrint(
          'PlaybackAudioHandler: no hay fuentes válidas en la cola',
        );
        _queueSource = null;
        await _player.stop();
        mediaItem.add(null);
        _currentIndex = -1;
        return;
      }

      final concat = ConcatenatingAudioSource(children: sources);
      _queueSource = concat;

      // Recalcula el índice inicial por si se descartaron canciones sin path.
      final initialSourceIndex =
          (_sourceIndexForQueue(startIndex) ?? 0)
              .clamp(0, sources.length - 1);

      // try/catch para no dejar mediaItem apuntando a algo que no suena.
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
        rethrow;
      }

      // Arranca la reproducción.
      if (autoPlay) {
        await _player.play();
      }
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
  }

  /// Añade una canción al final de la cola SIN cortar la reproducción.
  Future<void> addToQueue(Song song) async {
    final path = song.path;
    if (path == null || path.isEmpty) return;
    if (!File(path).existsSync()) {
      debugPrint('PlaybackAudioHandler: addToQueue path no existe -> $path');
      return;
    }

    // Si no hay fuente activa todavía, delegamos a setQueue con
    // autoPlay=false (encolar no debe arrancar sola la reproducción).
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

    // Añadido incremental: no toca la pista actual.
    _songs = [..._songs, song];
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));
    await source.add(AudioSource.file(path));
  }

  /// Elimina la canción en [index] SIN recargar el resto de la cola.
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
    // Si no hay fuente cargada, no tiene sentido reproducir.
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
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_currentIndex + 1 >= _songs.length) return;
    if (_queueSource == null) return;
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex - 1 < 0) return;
    if (_queueSource == null) return;
    await _player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;

    // Si no hay fuente cargada, reconstruimos la cola.
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
  }
}
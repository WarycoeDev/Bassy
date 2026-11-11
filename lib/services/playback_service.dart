// lib/services/playback_audio_handler.dart
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
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
  // Estas funciones permiten convivir con canciones sin path.

  /// Devuelve el índice en la fuente concatenada para la canción en
  /// [queueIndex], o `null` si esa canción no tiene path.
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

  /// Devuelve el índice de cola para el [sourceIndex] de la fuente, o
  /// `null` si no se encuentra.
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
  // OJO: `queue` ya lo provee QueueHandler como BehaviorSubject<List<MediaItem>>.
  // Por eso exponemos `songs` para la cola tipada de Song.

  List<Song> get songs => List.unmodifiable(_songs);

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _songs.length
          ? _songs[_currentIndex]
          : null;

  int get currentIndex => _currentIndex;

  bool get isPlaying => _player.playing;

  // Streams públicos para que la UI no toque `_player`.
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  // ---------- Control de cola ----------

  /// Reemplaza toda la cola y empieza a reproducir desde [startIndex].
  /// Este SÍ corta la reproducción (es una recarga completa).
  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;
    if (startIndex < 0 || startIndex >= songs.length) startIndex = 0;

    _songs = List<Song>.from(songs);
    _currentIndex = startIndex;

    // Actualiza el BehaviorSubject heredado de QueueHandler.
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));
    mediaItem.add(_toMediaItem(_songs[startIndex]));

    final sources = <AudioSource>[];
    for (final s in _songs) {
      final p = s.path;
      if (p == null || p.isEmpty) continue;
      sources.add(AudioSource.file(p));
    }
    if (sources.isEmpty) {
      _queueSource = null;
      return;
    }

    final concat = ConcatenatingAudioSource(children: sources);
    _queueSource = concat;

    final initialSourceIndex =
        _sourceIndexForQueue(startIndex) ?? 0;

    await _player.setAudioSource(
      concat,
      initialIndex: initialSourceIndex.clamp(0, sources.length - 1),
      initialPosition: Duration.zero,
    );
  }

  /// Añade una canción al final de la cola SIN cortar la reproducción.
  Future<void> addToQueue(Song song) async {
    final path = song.path;
    if (path == null || path.isEmpty) return;

    // Actualizamos el modelo de Songs y el BehaviorSubject heredado.
    _songs = [..._songs, song];
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));

    // Si no hay fuente activa todavía, no se puede añadir en caliente:
    // se delega a setQueue.
    final source = _queueSource;
    if (source == null) {
      await setQueue(
        _songs,
        startIndex: _currentIndex < 0 ? 0 : _currentIndex,
      );
      return;
    }

    // Añadido incremental: no toca la pista actual.
    await source.add(AudioSource.file(path));
  }

  /// Elimina la canción en [index] SIN recargar el resto de la cola.
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final wasCurrent = index == _currentIndex;
    final newSongs = List<Song>.from(_songs)..removeAt(index);

    // Caso especial: cola vacía tras el borrado.
    if (newSongs.isEmpty) {
      _songs = const [];
      _currentIndex = -1;
      _queueSource = null;
      super.queue.add(const []);
      mediaItem.add(null);
      await _player.stop();
      return;
    }

    // Calculamos el nuevo índice de la pista actual tras el borrado.
    int newIndex = _currentIndex;
    if (index < _currentIndex) {
      newIndex = _currentIndex - 1;
    } else if (wasCurrent) {
      newIndex = index.clamp(0, newSongs.length - 1);
    }

    // Índice en la fuente ANTES de actualizar _songs (necesitamos el
    // mapeo con la lista vieja).
    final sourceIndex = _sourceIndexForQueue(index);

    _songs = newSongs;
    _currentIndex = newIndex;
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));

    final source = _queueSource;
    if (source == null || sourceIndex == null) {
      // Canción sin path o sin fuente: solo actualizamos modelo/UI.
      if (_currentIndex >= 0 && _currentIndex < _songs.length) {
        mediaItem.add(_toMediaItem(_songs[_currentIndex]));
      }
      return;
    }

    // Borrado incremental: no recarga la pista actual.
    await source.removeAt(sourceIndex);

    // Aseguramos que el MediaItem mostrado apunte a la pista actual.
    if (_currentIndex >= 0 && _currentIndex < _songs.length) {
      mediaItem.add(_toMediaItem(_songs[_currentIndex]));
    }
  }

  Future<void> playSong(Song song) async {
    final idx = _songs.indexWhere((s) => s.path == song.path);
    if (idx >= 0) {
      await skipToQueueItem(idx);
    } else {
      await setQueue([song], startIndex: 0);
      await play();
    }
  }

  Future<void> playFromQueue(int index) => skipToQueueItem(index);

  // ---------- Overrides de BaseAudioHandler ----------

  @override
  Future<void> play() => _player.play();

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
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex - 1 < 0) return;
    await _player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final sourceIndex = _sourceIndexForQueue(index);
    if (sourceIndex == null) return;
    _currentIndex = index;
    await _player.seek(Duration.zero, index: sourceIndex);
    await _player.play();
  }
}
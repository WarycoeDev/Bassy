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

  PlaybackAudioHandler() {
    // Publica el estado del player como PlaybackState.
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Refresca el MediaItem actual cuando just_audio avanza solo.
    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _songs.length) {
        _currentIndex = index;
        mediaItem.add(_toMediaItem(_songs[index]));
      }
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
      if (s.path == null || s.path!.isEmpty) continue;
      sources.add(AudioSource.file(s.path!));
    }
    if (sources.isEmpty) return;

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: startIndex.clamp(0, sources.length - 1),
      initialPosition: Duration.zero,
    );
  }

  Future<void> addToQueue(Song song) async {
    if (song.path == null || song.path!.isEmpty) return;
    _songs = [..._songs, song];
    super.queue.add(_songs.map(_toMediaItem).toList(growable: false));
    // Si just_audio ya tiene una fuente concatenada, se puede añadir en caliente.
    // Para simplicidad, reusamos setQueue preservando el índice actual.
    await setQueue(_songs, startIndex: _currentIndex < 0 ? 0 : _currentIndex);
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
    _currentIndex = index;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }
}
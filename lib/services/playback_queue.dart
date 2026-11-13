// lib/services/playback_queue.dart
import '../models/song.dart';
import 'playback_audio_handler.dart' show PlayerRepeatMode;

/// Estado completo de UNA cola de reproducción (música o capítulos).
///
/// La cola activa mantiene además el `ConcatenatingAudioSource` vivo
/// dentro del handler; la inactiva solo guarda datos y se reconstruye
/// al activarse.
class PlaybackQueue {
  PlaybackQueue({required this.kind});

  /// `MediaKind.music` para la cola de música,
  /// `MediaKind.podcast` para la cola de capítulos.
  final MediaKind kind;

  List<Song> songs = const [];
  int currentIndex = -1;

  /// Posición guardada para restaurar al reactivar la cola.
  Duration savedPosition = Duration.zero;

  /// Si estaba reproduciendo al desactivarse.
  bool savedPlaying = false;

  PlayerRepeatMode repeatMode = PlayerRepeatMode.off;
  bool shuffleEnabled = false;

  /// Orden original (antes de shuffle) para poder deshacerlo.
  List<Song> originalOrder = const [];

  bool get isEmpty => songs.isEmpty;

  Song? get currentSong =>
      currentIndex >= 0 && currentIndex < songs.length
          ? songs[currentIndex]
          : null;

  bool get hasNext =>
      currentIndex >= 0 && currentIndex < songs.length - 1;

  bool get hasPrevious => currentIndex > 0 && currentIndex < songs.length;

  void reset() {
    songs = const [];
    currentIndex = -1;
    savedPosition = Duration.zero;
    savedPlaying = false;
    originalOrder = const [];
    shuffleEnabled = false;
  }

  /// Guarda el estado "vivo" que el reproductor tenía al desactivarse.
  void saveLiveState({
    required Duration position,
    required bool playing,
  }) {
    savedPosition = position;
    savedPlaying = playing;
  }
}
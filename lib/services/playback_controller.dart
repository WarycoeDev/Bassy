import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'playback_service.dart';

/// Fachada que la UI consume. Se inicializa en main() con `init()`.
class PlaybackController {
  PlaybackController._();
  static final PlaybackController instance = PlaybackController._();

  PlaybackAudioHandler? _handler;

  PlaybackAudioHandler get handler {
    final h = _handler;
    if (h == null) {
      throw StateError('PlaybackController.init() no se ha llamado.');
    }
    return h;
  }

  bool get isReady => _handler != null;

  Future<void> init() async {
    if (_handler != null) return;
    if (kIsWeb) return;

    _handler = await AudioService.init(
      builder: () => PlaybackAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.bassy.audio',
        androidNotificationChannelName: 'Reproducción',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  }

  // ---- Atajos ----

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) =>
      handler.setQueue(songs, startIndex: startIndex);

  Future<void> playSong(Song song) => handler.playSong(song);
  Future<void> play() => handler.play();
  Future<void> pause() => handler.pause();
  Future<void> next() => handler.skipToNext();
  Future<void> previous() => handler.skipToPrevious();
  Future<void> seek(Duration position) => handler.seek(position);
  Future<void> playFromQueue(int index) => handler.playFromQueue(index);
  Future<void> addToQueue(Song song) => handler.addToQueue(song);

  // ---- Streams (nativos, sin rxdart) ----

  Stream<MediaItem?> get currentItem => handler.mediaItem;
  Stream<PlaybackState> get playbackState => handler.playbackState;
  Stream<Duration> get position => handler.positionStream;
  Stream<Duration?> get duration => handler.durationStream;
  Stream<bool> get isPlaying => handler.playingStream;

  // ---- Getters de datos con guard ----

  List<Song> get songs => _handler?.songs ?? const [];
  Song? get currentSong => _handler?.currentSong;
  int get currentIndex => _handler?.currentIndex ?? -1;
}
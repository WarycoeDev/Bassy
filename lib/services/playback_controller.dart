// lib/services/playback_controller.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'playback_audio_handler.dart';
import 'playback_queue.dart';

const Duration kRewindThreshold = Duration(seconds: 3);

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
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  }

  // ============================================================
  // COLA ACTIVA (compatibilidad)
  // ============================================================

  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) =>
      handler.setQueue(songs, startIndex: startIndex, autoPlay: autoPlay);

  Future<void> playOnly(Song song) => handler.playOnly(song);
  Future<void> playSong(Song song) => handler.playSong(song);
  Future<void> play() => handler.play();
  Future<void> pause() => handler.pause();
  Future<void> next() => handler.skipToNext();

  Future<void> previous() async {
    final h = _handler;
    if (h == null) return;
    final pos = h.position;
    if (pos > kRewindThreshold) {
      await h.seek(Duration.zero);
      return;
    }
    if (h.hasPrevious) {
      await h.skipToPrevious();
    } else {
      await h.seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) => handler.seek(position);
  Future<void> playFromQueue(int index) => handler.playFromQueue(index);
  Future<void> addToQueue(Song song) => handler.addToQueue(song);

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      handler.reorderQueue(oldIndex, newIndex);

  Future<void> removeFromQueue(int index) => handler.removeFromQueue(index);

  Future<void> setSpeed(double speed) => handler.setSpeed(speed);
  Future<void> setVolume(double volume) => handler.setVolume(volume);

  Future<void> setShuffle(bool enabled) => handler.setShuffle(enabled);
  Future<void> setRepeatMode(PlayerRepeatMode mode) =>
      handler.setRepeatModeForUI(mode);

  Future<void> clearQueue() => handler.clearQueue();

  Future<void> clearQueueOf(MediaKind kind) => handler.clearQueueOf(kind);

  /// Limpia música **y** capítulos y deja el player parado.
  /// La cola activa vuelve a ser la de música por defecto.
  Future<void> clearAllQueues() => handler.clearAllQueues();

  // ============================================================
  // COLA POR KIND (nueva API)
  // ============================================================

  Future<void> switchToQueue(MediaKind kind) => handler.switchToQueue(kind);

  MediaKind get activeQueueKind => handler.activeQueueKind;

  Stream<MediaKind> get activeQueue => handler.activeQueueStream;

  List<Song> songsOf(MediaKind kind) => handler.songsOf(kind);

  Song? currentSongOf(MediaKind kind) => handler.currentSongOf(kind);

  Future<void> setQueueOf(
    MediaKind kind,
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) =>
      handler.setQueueOf(
        kind,
        songs,
        startIndex: startIndex,
        autoPlay: autoPlay,
      );

  Future<void> addToQueueOf(MediaKind kind, Song song) =>
      handler.addToQueueOf(kind, song);

  Future<void> removeFromQueueOf(MediaKind kind, int index) =>
      handler.removeFromQueueOf(kind, index);

  Future<void> reorderQueueOf(
    MediaKind kind,
    int oldIndex,
    int newIndex,
  ) =>
      handler.reorderQueueOf(kind, oldIndex, newIndex);

  // ============================================================
  // STREAMS
  // ============================================================

  Stream<MediaItem?> get currentItem => handler.mediaItem;
  Stream<PlaybackState> get playbackState => handler.playbackState;
  Stream<Duration> get position => handler.positionStream;
  Stream<Duration?> get duration => handler.durationStream;
  Stream<bool> get isPlaying => handler.playingStream;

  Stream<bool> get shuffle => handler.shuffleStream;
  Stream<PlayerRepeatMode> get repeat => handler.repeatStream;

  ValueListenable<double> get volume => handler.volumeListenable;

  Stream<bool> get canGoPrevious async* {
    final controller = StreamController<bool>();
    StreamSubscription<Duration>? posSub;
    StreamSubscription<MediaItem?>? itemSub;

    void emit() {
      if (controller.isClosed) return;
      final h = _handler;
      if (h == null) {
        controller.add(false);
        return;
      }
      final can = h.hasPrevious || h.position > kRewindThreshold;
      controller.add(can);
    }

    posSub = handler.positionStream.listen((_) => emit());
    itemSub = handler.mediaItem.listen((_) => emit());

    controller.onCancel = () async {
      await posSub?.cancel();
      await itemSub?.cancel();
    };

    emit();
    yield* controller.stream;
  }

  Stream<bool> get canGoNext async* {
    final controller = StreamController<bool>();
    StreamSubscription<MediaItem?>? itemSub;
    StreamSubscription<List<MediaItem>>? queueSub;

    void emit() {
      if (controller.isClosed) return;
      final h = _handler;
      controller.add(h?.hasNext ?? false);
    }

    itemSub = handler.mediaItem.listen((_) => emit());
    queueSub = handler.queue.listen((_) => emit());

    controller.onCancel = () async {
      await itemSub?.cancel();
      await queueSub?.cancel();
    };

    emit();
    yield* controller.stream;
  }

  // ============================================================
  // GETTERS SÍNCRONOS (cola activa)
  // ============================================================

  List<Song> get songs => _handler?.songs ?? const [];
  Song? get currentSong => _handler?.currentSong;
  int get currentIndex => _handler?.currentIndex ?? -1;

  bool get hasNext => _handler?.hasNext ?? false;
  bool get hasPrevious => _handler?.hasPrevious ?? false;
  Duration get positionNow => _handler?.position ?? Duration.zero;

  double get speedNow => _handler?.playerSpeed ?? 1.0;
  double get volumeNow => _handler?.volume ?? 1.0;

  bool get shuffleEnabled => _handler?.shuffleEnabled ?? false;
  PlayerRepeatMode get repeatModeNow =>
      _handler?.repeatMode ?? PlayerRepeatMode.off;
}
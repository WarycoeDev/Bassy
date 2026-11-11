// lib/services/playback_controller.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'playback_service.dart';

/// Umbral a partir del cual "previous" reinicia la canción en vez de
/// saltar a la anterior. Debe coincidir con el usado en el miniplayer.
const Duration kRewindThreshold = Duration(seconds: 3);

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

  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) =>
      handler.setQueue(songs, startIndex: startIndex, autoPlay: autoPlay);

  /// Vacía la cola, deja solo [song] y la reproduce desde 0,
  /// cortando lo que sonaba antes.
  Future<void> playOnly(Song song) => handler.playOnly(song);

  Future<void> playSong(Song song) => handler.playSong(song);
  Future<void> play() => handler.play();
  Future<void> pause() => handler.pause();
  Future<void> next() => handler.skipToNext();

  /// Si llevamos más de [kRewindThreshold] en la canción actual, reinicia;
  /// si no, salta a la anterior (si existe). Si no hay anterior y estamos
  /// al inicio, no hace nada.
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
      // Última red de seguridad: si no hay anterior, volver al inicio.
      await h.seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) => handler.seek(position);
  Future<void> playFromQueue(int index) => handler.playFromQueue(index);
  Future<void> addToQueue(Song song) => handler.addToQueue(song);

  /// Vacía la cola y detiene la reproducción (usado por el swipe del
  /// miniplayer para descartar lo que está sonando).
  Future<void> clearQueue() => handler.clearQueue();

  // ---- Streams (nativos, sin rxdart) ----

  Stream<MediaItem?> get currentItem => handler.mediaItem;
  Stream<PlaybackState> get playbackState => handler.playbackState;
  Stream<Duration> get position => handler.positionStream;
  Stream<Duration?> get duration => handler.durationStream;
  Stream<bool> get isPlaying => handler.playingStream;

  /// `true` cuando "previous" debe estar habilitado:
  /// hay canción anterior **o** ya se superó el umbral de rewind.
  /// Emite cada vez que cambia la posición o la cola.
  Stream<bool> get canGoPrevious async* {
    // Combine manual de positionStream + estado de cola.
    // Usamos un StreamController puente para no depender de rxdart.
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

    emit(); // valor inicial
    yield* controller.stream;
  }

  /// `true` cuando "next" debe estar habilitado.
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

  // ---- Getters de datos con guard ----

  List<Song> get songs => _handler?.songs ?? const [];
  Song? get currentSong => _handler?.currentSong;
  int get currentIndex => _handler?.currentIndex ?? -1;

  bool get hasNext => _handler?.hasNext ?? false;
  bool get hasPrevious => _handler?.hasPrevious ?? false;
  Duration get positionNow => _handler?.position ?? Duration.zero;
}
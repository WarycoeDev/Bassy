// lib/services/playback_audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import 'playback_queue.dart';

enum PlayerRepeatMode { off, all, one }

class PlaybackAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  // ----- Dos colas independientes -----
  final PlaybackQueue _musicQueue = PlaybackQueue(kind: MediaKind.music);
  final PlaybackQueue _chaptersQueue = PlaybackQueue(kind: MediaKind.podcast);

  PlaybackQueue _activeQueue = PlaybackQueue(kind: MediaKind.music);

  PlaybackQueue _queueFor(MediaKind kind) =>
      kind == MediaKind.podcast ? _chaptersQueue : _musicQueue;

  MediaKind get activeQueueKind => _activeQueue.kind;

  ConcatenatingAudioSource? _queueSource;

  Future<void> _loadChain = Future<void>.value();
  int _loadGeneration = 0;

  bool _loading = false;
  bool _resumeAfterLoad = false;
  bool _handlingCompleted = false;

  bool _isSeeking = false;
  int _seekGeneration = 0;
  List<MediaControl>? _lastControls;
  List<int>? _lastCompactActionIndices;
  String? _lastMediaItemKey;
  String? _lastQueueKey;

  DateTime _lastPositionPublish = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _positionPublishEvery = Duration(milliseconds: 250);

  static const _rewindThreshold = Duration(seconds: 3);

  double _volume = 1.0;
  final ValueNotifier<double> _volumeNotifier = ValueNotifier<double>(1.0);

  final _shuffleCtrl = StreamController<bool>.broadcast();
  final _repeatCtrl = StreamController<PlayerRepeatMode>.broadcast();
  final _canGoPreviousCtrl = StreamController<bool>.broadcast();
  final _canGoNextCtrl = StreamController<bool>.broadcast();
  final _activeQueueCtrl = StreamController<MediaKind>.broadcast();

  bool _canGoPrevious = false;
  bool _canGoNext = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  PlaybackAudioHandler() {
    // Inicializamos la activa con la cola de música.
    _activeQueue = _musicQueue;

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

    _subs.add(_player.currentIndexStream.listen((sourceIndex) {
      if (_loading) return;
      if (sourceIndex == null) return;
      if (sourceIndex < 0 || sourceIndex >= _activeQueue.songs.length) return;
      _activeQueue.currentIndex = sourceIndex;
      _emitControlsState();
    }));

    _subs.add(_player.durationStream.listen((_) => _publish()));
    _subs.add(_player.positionDiscontinuityStream.listen((_) => _publish()));
    _subs.add(_player.positionStream.listen(_onPosition));

    _subs.add(_player.speedStream.listen((_) => _publish()));

    _subs.add(_player.volumeStream.listen((v) {
      _volume = v;
      _volumeNotifier.value = v;
    }));

    _publish();
  }

  // ============================================================
  // STREAMS PÚBLICOS
  // ============================================================

  Stream<bool> get canGoPreviousStream => _canGoPreviousCtrl.stream;
  Stream<bool> get canGoNextStream => _canGoNextCtrl.stream;
  Stream<bool> get shuffleStream => _shuffleCtrl.stream;
  Stream<PlayerRepeatMode> get repeatStream => _repeatCtrl.stream;
  Stream<MediaKind> get activeQueueStream => _activeQueueCtrl.stream;

  // ============================================================
  // GETTERS SOBRE LA COLA ACTIVA (compatibilidad)
  // ============================================================

  List<Song> get songs => List.unmodifiable(_activeQueue.songs);

  Song? get currentSong => _activeQueue.currentSong;

  int get currentIndex => _activeQueue.currentIndex;

  bool get hasNext => _queueSource != null && _activeQueue.hasNext;

  bool get hasPrevious => _queueSource != null && _activeQueue.hasPrevious;

  Duration get position => _player.position;

  bool get canGoPrevious =>
      hasPrevious ||
      (_queueSource != null && _player.position > _rewindThreshold);

  bool get canGoNext => hasNext;

  bool get isPlaying => _player.playing;

  double get playerSpeed => _player.speed;

  double get volume => _volume;
  ValueListenable<double> get volumeListenable => _volumeNotifier;

  bool get shuffleEnabled => _activeQueue.shuffleEnabled;
  PlayerRepeatMode get repeatMode => _activeQueue.repeatMode;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  // ============================================================
  // GETTERS POR COLA EXPLÍCITA
  // ============================================================

  List<Song> songsOf(MediaKind kind) =>
      List.unmodifiable(_queueFor(kind).songs);

  Song? currentSongOf(MediaKind kind) => _queueFor(kind).currentSong;

  bool get isActiveQueueEmpty => _activeQueue.isEmpty;

  // ============================================================
  // PUBLICACIÓN DE ESTADO
  // ============================================================

  bool get _effectivePlaying {
    if (_activeQueue.songs.isEmpty) return false;
    if (_loading) return _resumeAfterLoad;
    if (_player.processingState == ProcessingState.completed) return false;
    return _player.playing;
  }

  AudioProcessingState get _effectiveProcessingState {
    if (_activeQueue.songs.isEmpty) return AudioProcessingState.idle;
    if (_loading) return AudioProcessingState.loading;
    if (_handlingCompleted) return AudioProcessingState.ready;

    return switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.ready,
    };
  }

  AudioServiceRepeatMode get _systemRepeatMode =>
      switch (_activeQueue.repeatMode) {
        PlayerRepeatMode.off => AudioServiceRepeatMode.none,
        PlayerRepeatMode.all => AudioServiceRepeatMode.all,
        PlayerRepeatMode.one => AudioServiceRepeatMode.one,
      };

  AudioServiceShuffleMode get _systemShuffleMode =>
      _activeQueue.shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none;

  void _publish({bool updateControls = true, bool updateQueue = true}) {
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
        final d = _loading ? null : _player.duration;
        final liveDuration = (d != null && d > Duration.zero) ? d : null;
        final key =
            '${_activeQueue.kind.name}|${song.path ?? song.title}|${liveDuration?.inMilliseconds}';

        if (key != _lastMediaItemKey) {
          mediaItem.add(_toMediaItem(song, liveDuration));
          _lastMediaItemKey = key;
        }
      }

      final queueKey =
          '${_activeQueue.kind.name}#${_activeQueue.songs.map((s) => s.path ?? s.title).join('|')}';
      if (queueKey != _lastQueueKey) {
        queue.add(
          _activeQueue.songs.map((s) => _toMediaItem(s)).toList(growable: false),
        );
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
        queueIndex:
            _activeQueue.currentIndex >= 0 ? _activeQueue.currentIndex : null,
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
      extras: {
        'path': song.path,
        'queueKind': _activeQueue.kind.name,
      },
      playable: song.path != null && song.path!.isNotEmpty,
    );
  }

  // ============================================================
  // POSICIÓN / COMPLETED
  // ============================================================

  void _onPosition(Duration _) {
    _emitCanGoPrevious();
    if (!_player.playing) return;
    final now = DateTime.now();
    if (now.difference(_lastPositionPublish) < _positionPublishEvery) return;
    _lastPositionPublish = now;
    _publish();
  }

  Future<void> _onCompleted() async {
    if (_handlingCompleted || _loading || _activeQueue.songs.isEmpty) return;
    _handlingCompleted = true;
    try {
      if (_activeQueue.repeatMode == PlayerRepeatMode.one) return;
      await _player.pause();
      await _player.seek(Duration.zero, index: 0);
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: normalizar completed falló -> $e\n$st');
    } finally {
      _handlingCompleted = false;
      _activeQueue.currentIndex = _activeQueue.songs.isEmpty ? -1 : 0;
      _emitControlsState();
    }
  }

  // ============================================================
  // EMISIÓN DE ESTADO DE CONTROLES
  // ============================================================

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

  void _emitControlsState() {
    _emitCanGoPrevious();
    _emitCanGoNext();
    _publish();
  }

  // ============================================================
  // SHUFFLE / REPEAT (por cola activa)
  // ============================================================

  Future<void> setShuffle(bool enabled) async {
    if (_activeQueue.shuffleEnabled == enabled) return;
    _activeQueue.shuffleEnabled = enabled;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(enabled);

    if (_activeQueue.songs.isEmpty || _queueSource == null) {
      _publish();
      return;
    }

    final currentPath = currentSong?.path;
    final currentPos = _player.position;

    List<Song> newOrder;
    if (enabled) {
      if (_activeQueue.originalOrder.isEmpty) {
        _activeQueue.originalOrder = List<Song>.from(_activeQueue.songs);
      }
      final current = currentPath == null
          ? null
          : _activeQueue.songs.firstWhere(
              (s) => s.path == currentPath,
              orElse: () => _activeQueue.songs.first,
            );
      final rest = _activeQueue.songs
          .where((s) => s.path != currentPath)
          .toList()
        ..shuffle(Random());
      newOrder = [
        if (current != null) current,
        ...rest,
      ];
    } else {
      newOrder = _activeQueue.originalOrder.isNotEmpty
          ? List<Song>.from(_activeQueue.originalOrder)
          : List<Song>.from(_activeQueue.songs);
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

  Future<void> setRepeatModeForUI(PlayerRepeatMode mode) async {
    if (_activeQueue.repeatMode == mode) return;
    _activeQueue.repeatMode = mode;
    await _applyLoopMode();
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(mode);
    _publish();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final next = switch (repeatMode) {
      AudioServiceRepeatMode.none => PlayerRepeatMode.off,
      AudioServiceRepeatMode.all => PlayerRepeatMode.all,
      AudioServiceRepeatMode.one => PlayerRepeatMode.one,
      AudioServiceRepeatMode.group => PlayerRepeatMode.off,
    };
    await setRepeatModeForUI(next);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = switch (shuffleMode) {
      AudioServiceShuffleMode.all => true,
      AudioServiceShuffleMode.none => false,
      AudioServiceShuffleMode.group => false,
    };
    await setShuffle(enable);
  }

  Future<void> _applyLoopMode() async {
    switch (_activeQueue.repeatMode) {
      case PlayerRepeatMode.off:
        await _player.setLoopMode(LoopMode.off);
      case PlayerRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
      case PlayerRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
    }
  }

  // ============================================================
  // CARGA DE COLA ACTIVA
  // ============================================================

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

      _activeQueue.songs = order;
      _activeQueue.currentIndex = startIndex;
      _publish();

      final concat = ConcatenatingAudioSource(
        children: [for (final s in _activeQueue.songs) AudioSource.file(s.path!)],
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
    await _player.setVolume(_volume);
    _emitControlsState();
  }

  bool _isPlayable(Song s) {
    final p = s.path;
    if (p == null || p.isEmpty) return false;
    if (!File(p).existsSync()) {
      debugPrint('PlaybackAudioHandler: path no existe -> $p');
      return false;
    }
    return true;
  }

  // ============================================================
  // SET QUEUE (activa + por kind)
  // ============================================================

  /// API compatible: usa la cola del `kind` de la primera canción,
  /// pero activándola si no lo está.
  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    final kind = songs.isEmpty
        ? _activeQueue.kind
        : (songs[startIndex.clamp(0, songs.length - 1)].kind ==
                MediaKind.podcast
            ? MediaKind.podcast
            : MediaKind.music);
    return setQueueOf(kind, songs, startIndex: startIndex, autoPlay: autoPlay);
  }

  /// Reemplaza la cola de [kind]. Si [kind] es la activa, recarga el
  /// reproductor; si no, solo guarda datos y NO interrumpe la reproducción.
  Future<void> setQueueOf(
    MediaKind kind,
    List<Song> songs, {
    int startIndex = 0,
    bool autoPlay = true,
  }) {
    final generation = ++_loadGeneration;
    final run = _loadChain.catchError((_) {}).then<void>((_) async {
      if (generation != _loadGeneration) return;
      await _setQueueImpl(kind, songs,
          startIndex: startIndex, autoPlay: autoPlay);
    });
    _loadChain = run;
    return run;
  }

  Future<void> playOnly(Song song) =>
      setQueueOf(song.kind, [song], startIndex: 0, autoPlay: true);

  Future<void> _setQueueImpl(
    MediaKind kind,
    List<Song> songs, {
    required int startIndex,
    required bool autoPlay,
  }) async {
    if (songs.isEmpty) {
      await _clearQueueOf(kind);
      return;
    }
    if (startIndex < 0 || startIndex >= songs.length) startIndex = 0;

    final target = songs[startIndex];
    final playable = songs.where(_isPlayable).toList();
    if (playable.isEmpty) {
      debugPrint('PlaybackAudioHandler: no hay fuentes válidas en la cola');
      await _clearQueueOf(kind);
      return;
    }
    var newStart = playable.indexWhere((s) => identical(s, target));
    if (newStart < 0) newStart = 0;

    final targetQueue = _queueFor(kind);

    // Si NO es la activa: solo guardamos datos y no tocamos el player.
    if (kind != _activeQueue.kind) {
      targetQueue.songs = playable;
      targetQueue.currentIndex = newStart;
      targetQueue.originalOrder = List<Song>.from(playable);
      targetQueue.shuffleEnabled = false;
      targetQueue.savedPosition = Duration.zero;
      targetQueue.savedPlaying = autoPlay;
      _emitControlsState();
      return;
    }

    // Es la activa: recarga real.
    _activeQueue.originalOrder = List<Song>.from(playable);
    _activeQueue.shuffleEnabled = false;
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);

    _loading = true;
    _resumeAfterLoad = autoPlay;

    try {
      await _player.pause();

      _activeQueue.songs = playable;
      _activeQueue.currentIndex = newStart;
      _publish();

      final concat = ConcatenatingAudioSource(
        children: [for (final s in _activeQueue.songs) AudioSource.file(s.path!)],
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
        _activeQueue.reset();
        _resumeAfterLoad = false;
        _loading = false;
        await _player.stop();
        _emitControlsState();
        rethrow;
      }
    } finally {
      _loading = false;
    }

    _activeQueue.currentIndex = newStart;

    await _applyLoopMode();
    await _player.setVolume(_volume);

    if (autoPlay) {
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
      }));
    }

    _emitControlsState();
  }

  // ============================================================
  // CAMBIO DE COLA ACTIVA
  // ============================================================

  /// Guarda posición/playing de la activa, pausa, carga [kind] y
  /// restaura posición/playing de la nueva.
  Future<void> switchToQueue(MediaKind kind) async {
    if (kind == _activeQueue.kind && _queueSource != null) {
      // Ya activa con fuente cargada: no-op.
      return;
    }

    final oldKind = _activeQueue.kind;

    // 1) Guardar estado de la activa.
    _activeQueue.saveLiveState(
      position: _player.position,
      playing: _player.playing,
    );

    // 2) Pausar siempre.
    try {
      await _player.pause();
    } catch (_) {}

    // 3) Cambiar activa.
    _activeQueue = _queueFor(kind);
    _lastMediaItemKey = null;
    _lastQueueKey = null;

    if (!_activeQueueCtrl.isClosed) _activeQueueCtrl.add(kind);

    // 4) Si la nueva cola está vacía, dejamos el player parado/vacío.
    if (_activeQueue.songs.isEmpty) {
      try {
        await _player.stop();
      } catch (_) {}
      _queueSource = null;
      _emitControlsState();
      return;
    }

    // 5) Reconstruir la fuente con la posición guardada.
    _loading = true;
    _resumeAfterLoad = _activeQueue.savedPlaying;
    final restorePos = _activeQueue.savedPosition;

    try {
      final concat = ConcatenatingAudioSource(
        children: [for (final s in _activeQueue.songs) AudioSource.file(s.path!)],
      );
      _queueSource = concat;

      await _player.setAudioSource(
        concat,
        initialIndex:
            _activeQueue.currentIndex >= 0 ? _activeQueue.currentIndex : 0,
        initialPosition: restorePos,
      );
    } catch (e, st) {
      debugPrint('PlaybackAudioHandler: switchToQueue falló -> $e\n$st');
    } finally {
      _loading = false;
    }

    await _applyLoopMode();
    await _player.setVolume(_volume);

    if (_resumeAfterLoad) {
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
      }));
    }

    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(_activeQueue.shuffleEnabled);
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(_activeQueue.repeatMode);

    debugPrint(
      'PlaybackAudioHandler: switchToQueue $oldKind -> $kind '
      '(songs=${_activeQueue.songs.length}, idx=${_activeQueue.currentIndex})',
    );

    _emitControlsState();
  }

  // ============================================================
  // CLEAR QUEUE
  // ============================================================

  Future<void> _clearQueueOf(MediaKind kind) async {
    final q = _queueFor(kind);
    q.reset();

    if (kind == _activeQueue.kind) {
      _queueSource = null;
      _resumeAfterLoad = false;
      await _player.stop();
    }
    _emitControlsState();
  }

  Future<void> clearQueue() async {
    _loadGeneration++;
    await _clearQueueOf(_activeQueue.kind);
  }

  Future<void> clearQueueOf(MediaKind kind) async {
    _loadGeneration++;
    await _clearQueueOf(kind);
  }

  /// Limpia **ambas** colas (música y capítulos) y deja el reproductor
  /// parado. La cola activa vuelve a ser la de música por defecto.
  Future<void> clearAllQueues() async {
    _loadGeneration++;

    // Guarda estado actual antes de limpiar.
    _activeQueue.saveLiveState(
      position: _player.position,
      playing: false,
    );

    // Limpia datos de ambas colas.
    _musicQueue.reset();
    _chaptersQueue.reset();

    // Detiene y vacía el player.
    _queueSource = null;
    _resumeAfterLoad = false;
    try {
      await _player.stop();
    } catch (e, st) {
      debugPrint(
        'PlaybackAudioHandler: stop en clearAllQueues falló -> $e\n$st',
      );
    }

    // Cola activa por defecto: música.
    _activeQueue = _musicQueue;

    // Notifica a la UI del cambio de cola activa.
    if (!_activeQueueCtrl.isClosed) {
      _activeQueueCtrl.add(MediaKind.music);
    }
    if (!_shuffleCtrl.isClosed) _shuffleCtrl.add(false);
    if (!_repeatCtrl.isClosed) _repeatCtrl.add(PlayerRepeatMode.off);

    // Fuerza republicación de mediaItem/queue vacíos.
    _lastMediaItemKey = null;
    _lastQueueKey = null;

    _emitControlsState();
  }

  // ============================================================
  // ADD / REMOVE / REORDER (activa + por kind)
  // ============================================================

  /// Smart: elige la cola por `song.kind`.
  Future<void> addToQueue(Song song) => addToQueueOf(song.kind, song);

  Future<void> addToQueueOf(MediaKind kind, Song song) async {
    if (!_isPlayable(song)) return;

    final q = _queueFor(kind);

    // Si la cola no está activa: solo datos.
    if (kind != _activeQueue.kind) {
      q.songs = [...q.songs, song];
      if (q.currentIndex < 0) q.currentIndex = 0;
      if (q.originalOrder.isNotEmpty) {
        q.originalOrder = [...q.originalOrder, song];
      }
      _emitControlsState();
      return;
    }

    // Activa sin fuente → setQueue.
    final source = _queueSource;
    if (source == null) {
      final newSongs = [...q.songs, song];
      await setQueueOf(
        kind,
        newSongs,
        startIndex: q.currentIndex < 0 ? newSongs.length - 1 : q.currentIndex,
        autoPlay: false,
      );
      return;
    }

    q.songs = [...q.songs, song];
    if (q.originalOrder.isNotEmpty) {
      q.originalOrder = [...q.originalOrder, song];
    }
    await source.add(AudioSource.file(song.path!));
    _emitControlsState();
  }

  Future<void> removeFromQueue(int index) =>
      removeFromQueueOf(_activeQueue.kind, index);

  Future<void> removeFromQueueOf(MediaKind kind, int index) async {
    final q = _queueFor(kind);
    if (index < 0 || index >= q.songs.length) return;

    final removed = q.songs[index];
    final wasCurrent = index == q.currentIndex;
    final newSongs = List<Song>.from(q.songs)..removeAt(index);

    if (newSongs.isEmpty) {
      await _clearQueueOf(kind);
      return;
    }

    int newIndex = q.currentIndex;
    if (index < q.currentIndex) {
      newIndex = q.currentIndex - 1;
    } else if (wasCurrent) {
      newIndex = index.clamp(0, newSongs.length - 1);
    }

    q.songs = newSongs;
    q.currentIndex = newIndex;
    q.originalOrder =
        q.originalOrder.where((s) => s.path != removed.path).toList();

    if (kind == _activeQueue.kind) {
      final source = _queueSource;
      if (source != null) {
        try {
          await source.removeAt(index);
        } catch (e, st) {
          debugPrint('PlaybackAudioHandler: removeAt falló -> $e\n$st');
        }
      }
    }

    _emitControlsState();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      reorderQueueOf(_activeQueue.kind, oldIndex, newIndex);

  Future<void> reorderQueueOf(
    MediaKind kind,
    int oldIndex,
    int newIndex,
  ) async {
    final q = _queueFor(kind);
    if (oldIndex < 0 || oldIndex >= q.songs.length) return;
    if (newIndex < 0 || newIndex > q.songs.length) return;
    if (oldIndex == newIndex) return;

    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (oldIndex == targetIndex) return;

    final updated = List<Song>.from(q.songs);
    final moved = updated.removeAt(oldIndex);
    updated.insert(targetIndex, moved);
    q.songs = updated;

    if (q.currentIndex == oldIndex) {
      q.currentIndex = targetIndex;
    } else if (oldIndex < q.currentIndex && targetIndex >= q.currentIndex) {
      q.currentIndex--;
    } else if (oldIndex > q.currentIndex && targetIndex <= q.currentIndex) {
      q.currentIndex++;
    }

    if (q.originalOrder.isNotEmpty && oldIndex < q.originalOrder.length) {
      final original = List<Song>.from(q.originalOrder);
      final movedOriginal = original.removeAt(oldIndex);
      original.insert(targetIndex.clamp(0, original.length), movedOriginal);
      q.originalOrder = original;
    }

    _emitControlsState();

    if (kind == _activeQueue.kind) {
      final source = _queueSource;
      if (source != null) {
        try {
          await source.move(oldIndex, targetIndex);
        } catch (e, st) {
          debugPrint('PlaybackAudioHandler: move falló -> $e\n$st');
        }
      }
    }
  }

  // ============================================================
  // REPRODUCCIÓN
  // ============================================================

  Future<void> playSong(Song song) async {
    final q = _queueFor(song.kind);
    final idx = q.songs.indexWhere((s) => s.path == song.path);
    if (idx >= 0) {
      if (_activeQueue.kind != song.kind || _queueSource == null) {
        await switchToQueue(song.kind);
      }
      await skipToQueueItem(idx);
    } else {
      await playOnly(song);
    }
  }

  Future<void> playFromQueue(int index) => skipToQueueItem(index);

  Future<void> setSpeed(double speed) async {
    if (speed <= 0) return;
    await _player.setSpeed(speed);
    _publish();
  }

  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    _volume = v;
    _volumeNotifier.value = v;

    if ((v - _player.volume).abs() < 0.001) return;
    await _player.setVolume(v);
  }

  @override
  Future<void> play() async {
    if (_queueSource == null) {
      debugPrint('PlaybackAudioHandler: play() sin fuente cargada');
      return;
    }
    unawaited(_player.play().catchError((Object e, StackTrace st) {
      debugPrint('PlaybackAudioHandler: play falló -> $e\n$st');
    }));
    _publish();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _publish();
  }

  @override
  Future<void> stop() async {
    _loadGeneration++;
    // Guarda estado de la activa antes de limpiar.
    _activeQueue.saveLiveState(
      position: _player.position,
      playing: false,
    );
    await _clearQueueOf(_activeQueue.kind);
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
    _emitControlsState();
  }

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
    final q = _activeQueue;
    if (index < 0 || index >= q.songs.length) return;

    if (_queueSource == null) {
      await setQueueOf(
        q.kind,
        q.songs,
        startIndex: index,
        autoPlay: true,
      );
      return;
    }

    q.currentIndex = index;
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
  Future<void> onTaskRemoved() async {}

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _canGoPreviousCtrl.close();
    await _canGoNextCtrl.close();
    await _shuffleCtrl.close();
    await _repeatCtrl.close();
    await _activeQueueCtrl.close();
    _volumeNotifier.dispose();
    await _player.dispose();
  }
}
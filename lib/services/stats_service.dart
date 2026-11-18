// lib/services/stats_service.dart
//
// Servicio de estadísticas de reproducción.
// SOLO guarda datos; no modifica el comportamiento del reproductor.
//
// Persistencia en ARCHIVO JSON:
//   - Android: Android/data/com.example.bassy/files/stats/stats.json
//   - Escritorio: <app support dir>/stats/stats.json
//   - iOS/macOS: <app support dir>/stats/stats.json
//
// Migra automáticamente desde SharedPreferences (versión anterior)
// la primera vez que arranca.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'playback_audio_handler.dart';
import 'playback_queue.dart';

/// Una entrada del historial de reproducciones.
class PlaybackHistoryEntry {
  final String songKey;
  final String title;
  final String? subtitle;
  final String? coverPath;
  final MediaKind kind;

  final DateTime startedAt;
  final Duration listenedDuration;
  final Duration positionAtEnd;
  final Duration? trackDuration;
  final bool completed;

  const PlaybackHistoryEntry({
    required this.songKey,
    required this.title,
    this.subtitle,
    this.coverPath,
    required this.kind,
    required this.startedAt,
    required this.listenedDuration,
    required this.positionAtEnd,
    this.trackDuration,
    required this.completed,
  });

  Map<String, dynamic> toJson() => {
        'songKey': songKey,
        'title': title,
        'subtitle': subtitle,
        'coverPath': coverPath,
        'kind': kind.name,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'listenedMs': listenedDuration.inMilliseconds,
        'positionAtEndMs': positionAtEnd.inMilliseconds,
        'trackDurationMs': trackDuration?.inMilliseconds,
        'completed': completed,
      };

  factory PlaybackHistoryEntry.fromJson(Map<String, dynamic> j) =>
      PlaybackHistoryEntry(
        songKey: j['songKey'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        coverPath: j['coverPath'] as String?,
        kind: MediaKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => MediaKind.music,
        ),
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(j['startedAt'] as int),
        listenedDuration: Duration(milliseconds: j['listenedMs'] as int? ?? 0),
        positionAtEnd:
            Duration(milliseconds: j['positionAtEndMs'] as int? ?? 0),
        trackDuration: j['trackDurationMs'] == null
            ? null
            : Duration(milliseconds: j['trackDurationMs'] as int),
        completed: j['completed'] as bool? ?? false,
      );
}

/// Progreso guardado por pista (para "dónde te quedaste").
class TrackProgress {
  final String songKey;
  final MediaKind kind;
  final Duration position;
  final Duration? duration;
  final DateTime updatedAt;
  final bool completed;

  const TrackProgress({
    required this.songKey,
    required this.kind,
    required this.position,
    this.duration,
    required this.updatedAt,
    required this.completed,
  });

  double get fraction {
    final d = duration?.inMilliseconds ?? 0;
    if (d <= 0) return 0.0;
    return (position.inMilliseconds / d).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'songKey': songKey,
        'kind': kind.name,
        'positionMs': position.inMilliseconds,
        'durationMs': duration?.inMilliseconds,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'completed': completed,
      };

  factory TrackProgress.fromJson(Map<String, dynamic> j) => TrackProgress(
        songKey: j['songKey'] as String,
        kind: MediaKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => MediaKind.music,
        ),
        position: Duration(milliseconds: j['positionMs'] as int? ?? 0),
        duration: j['durationMs'] == null
            ? null
            : Duration(milliseconds: j['durationMs'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int),
        completed: j['completed'] as bool? ?? false,
      );
}

/// Estadísticas agregadas por canción.
class SongStats {
  final String songKey;
  final String title;
  final String? subtitle;
  final String? coverPath;
  final MediaKind kind;

  final int playCount;
  final Duration totalListened;
  final DateTime? lastPlayedAt;

  const SongStats({
    required this.songKey,
    required this.title,
    this.subtitle,
    this.coverPath,
    required this.kind,
    required this.playCount,
    required this.totalListened,
    this.lastPlayedAt,
  });

  SongStats copyWith({
    int? playCount,
    Duration? totalListened,
    DateTime? lastPlayedAt,
  }) =>
      SongStats(
        songKey: songKey,
        title: title,
        subtitle: subtitle,
        coverPath: coverPath,
        kind: kind,
        playCount: playCount ?? this.playCount,
        totalListened: totalListened ?? this.totalListened,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      );

  Map<String, dynamic> toJson() => {
        'songKey': songKey,
        'title': title,
        'subtitle': subtitle,
        'coverPath': coverPath,
        'kind': kind.name,
        'playCount': playCount,
        'totalListenedMs': totalListened.inMilliseconds,
        'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
      };

  factory SongStats.fromJson(Map<String, dynamic> j) => SongStats(
        songKey: j['songKey'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        coverPath: j['coverPath'] as String?,
        kind: MediaKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => MediaKind.music,
        ),
        playCount: j['playCount'] as int? ?? 0,
        totalListened:
            Duration(milliseconds: j['totalListenedMs'] as int? ?? 0),
        lastPlayedAt: j['lastPlayedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['lastPlayedAt'] as int),
      );
}

class StatsService {
  StatsService._();
  static final StatsService instance = StatsService._();

  // Claves de SharedPreferences solo para migración desde la versión vieja.
  static const String _kLegacyHistory = 'stats_history_v1';
  static const String _kLegacyProgress = 'stats_progress_v1';
  static const String _kLegacySongs = 'stats_songs_v1';

  static const String _statsDirName = 'stats';
  static const String _statsFileName = 'stats.json';
  static const String _schemaVersion = '1';

  static const int _maxHistoryEntries = 500;
  static const int _maxProgressEntries = 2000;

  /// Tolerancia para considerar una canción "terminada".
  static const Duration _endTolerance = Duration(seconds: 2);

  /// En podcasts se considera terminado si faltan menos de esto
  /// (créditos, despedida, etc.).
  static const Duration _podcastEndTolerance = Duration(seconds: 15);

  /// Mínimo de escucha real para guardar progreso. Evita que sesiones
  /// que solo se cargaron (sin sonar) pisen el progreso guardado.
  static const Duration _minListenToSave = Duration(seconds: 1);

  /// Cada cuánto se guarda el progreso de un podcast mientras suena.
  static const Duration _progressSaveEvery = Duration(seconds: 5);

  bool _initialized = false;
  File? _statsFile;
  PlaybackAudioHandler? _handler;

  final List<PlaybackHistoryEntry> _history = [];
  final Map<String, TrackProgress> _progress = {};
  final Map<String, SongStats> _songs = {};

  _ActiveSession? _session;

  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<String>? _trackCompletedSub;
  Timer? _persistDebounce;
  bool _persisting = false;
  bool _persistAgain = false;

  // ============================================================
  // INIT
  // ============================================================

  /// Llamar una vez después de `PlaybackController.init()`.
  Future<void> init(PlaybackAudioHandler handler) async {
    if (_initialized) return;
    _initialized = true;
    _handler = handler;

    _statsFile = await _resolveStatsFile();
    await _loadFromDisk();
    await _migrateFromPrefsIfNeeded();
    _bind(handler);
  }

  /// Resuelve la ruta:
  /// - Android: Android/data/<package>/files/stats/stats.json
  /// - Escritorio / iOS / macOS: <app support>/stats/stats.json
  Future<File> _resolveStatsFile() async {
    Directory base;
    if (Platform.isAndroid) {
      Directory? ext;
      try {
        ext = await getExternalStorageDirectory();
      } catch (e) {
        debugPrint('StatsService: sin almacenamiento externo -> $e');
      }
      base = ext ?? await getApplicationSupportDirectory();
    } else {
      base = await getApplicationSupportDirectory();
    }
    final dir = Directory('${base.path}/$_statsDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_statsFileName');
  }

  /// Ruta pública del archivo (para mostrarla en ajustes o debug).
  String? get statsFilePath => _statsFile?.path;

  // ============================================================
  // CARGA / GUARDADO EN DISCO
  // ============================================================

  Future<void> _loadFromDisk() async {
    final f = _statsFile;
    if (f == null || !await f.exists()) return;
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;

      // Cada entrada se parsea por separado: una entrada corrupta no
      // debe tirar abajo todo el historial/progreso.
      _history.clear();
      for (final e in (json['history'] as List<dynamic>? ?? const [])) {
        try {
          _history
              .add(PlaybackHistoryEntry.fromJson(e as Map<String, dynamic>));
        } catch (_) {}
      }

      _progress.clear();
      final p = (json['progress'] as Map<String, dynamic>? ?? const {});
      p.forEach((k, v) {
        try {
          _progress[k] = TrackProgress.fromJson(v as Map<String, dynamic>);
        } catch (_) {}
      });

      _songs.clear();
      final s = (json['songs'] as Map<String, dynamic>? ?? const {});
      s.forEach((k, v) {
        try {
          _songs[k] = SongStats.fromJson(v as Map<String, dynamic>);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('StatsService: no se pudo leer $f -> $e');
      // Respaldamos el archivo dañado para no sobrescribirlo y perderlo.
      try {
        await f.copy('${f.path}.corrupt');
      } catch (_) {}
    }
  }

  Future<void> _persistNow() async {
    final f = _statsFile;
    if (f == null) return;
    if (_persisting) {
      _persistAgain = true;
      return;
    }
    _persisting = true;
    try {
      final payload = <String, dynamic>{
        'schemaVersion': _schemaVersion,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'history': _history.map((e) => e.toJson()).toList(),
        'progress': _progress.map((k, v) => MapEntry(k, v.toJson())),
        'songs': _songs.map((k, v) => MapEntry(k, v.toJson())),
      };
      // Escritura atómica: tmp + rename. Evita JSON truncado si la app
      // muere a mitad de escritura.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('StatsService: no se pudo guardar -> $e');
    } finally {
      _persisting = false;
      if (_persistAgain) {
        _persistAgain = false;
        unawaited(_persistNow());
      }
    }
  }

  /// Migra datos de la versión anterior basada en SharedPreferences.
  /// Si ya hay un archivo en disco con datos, no toca nada.
  Future<void> _migrateFromPrefsIfNeeded() async {
    if (_history.isNotEmpty || _progress.isNotEmpty || _songs.isNotEmpty) {
      return; // ya hay datos en disco
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHistory = prefs.getString(_kLegacyHistory);
      final rawProgress = prefs.getString(_kLegacyProgress);
      final rawSongs = prefs.getString(_kLegacySongs);
      if (rawHistory == null && rawProgress == null && rawSongs == null) {
        return;
      }
      if (rawHistory != null && rawHistory.isNotEmpty) {
        final list = jsonDecode(rawHistory) as List<dynamic>;
        _history.addAll(list.map(
            (e) => PlaybackHistoryEntry.fromJson(e as Map<String, dynamic>)));
      }
      if (rawProgress != null && rawProgress.isNotEmpty) {
        final map = jsonDecode(rawProgress) as Map<String, dynamic>;
        _progress.addAll(map.map((k, v) =>
            MapEntry(k, TrackProgress.fromJson(v as Map<String, dynamic>))));
      }
      if (rawSongs != null && rawSongs.isNotEmpty) {
        final map = jsonDecode(rawSongs) as Map<String, dynamic>;
        _songs.addAll(map.map((k, v) =>
            MapEntry(k, SongStats.fromJson(v as Map<String, dynamic>))));
      }
      debugPrint('StatsService: migrados datos viejos de SharedPreferences');
      await _persistNow();
      // No borramos prefs por si el usuario quiere volver atrás.
    } catch (e) {
      debugPrint('StatsService: migración falló -> $e');
    }
  }

  // ============================================================
  // BINDING AL HANDLER
  // ============================================================

  void _bind(PlaybackAudioHandler handler) {
    _mediaItemSub = handler.mediaItem.listen(_onMediaItem);
    _stateSub = handler.playbackState.listen(_onPlaybackState);
    _positionSub = handler.positionStream.listen(_onPosition);
    _trackCompletedSub =
        handler.trackCompletedStream.listen(_onTrackCompleted);

    final current = handler.currentSong;
    if (current != null) {
      _startSession(current, handler.position);
    }
  }

  void _onMediaItem(MediaItem? item) {
    final handler = _handler;
    if (handler == null) return;
    final song = handler.currentSong;
    if (song == null) {
      _closeSession(completed: false);
      return;
    }
    final key = _keyOf(song);
    if (_session == null) {
      _startSession(song, handler.position);
      return;
    }
    if (_session!.songKey == key) return;

    final s = _session!;
    final nearEnd = _isNearEnd(s.lastPosition, _durationOf(s), s.kind);
    _closeSession(completed: nearEnd);
    _startSession(song, handler.position);
  }

  void _onPlaybackState(PlaybackState state) {
    final s = _session;
    if (s == null) return;

    if (state.playing) {
      if (!s.wasPlaying) {
        s.wasPlaying = true;
        s.lastTickAt = DateTime.now();
      }
    } else if (s.wasPlaying) {
      // Solo en la TRANSICIÓN reproduciendo -> pausa. Antes se guardaba
      // en cada emisión de estado en pausa (cada pocos cientos de ms),
      // pisando el progreso y el flag `completed`.
      _accumulateListening(s, DateTime.now());
      s.wasPlaying = false;
      _saveProgressForSession(immediate: true);
    }
  }

  void _onPosition(Duration pos) {
    final s = _session;
    final h = _handler;
    if (s == null || h == null) return;

    // Solo aceptamos posiciones de la pista de la sesión. Durante un
    // cambio de pista o un stop/clear el handler emite posiciones que
    // pertenecen a otra cosa (p. ej. Duration.zero al limpiar colas) y
    // pisaban el progreso real.
    final cur = h.currentSong;
    if (cur == null || _keyOf(cur) != s.songKey) return;

    s.lastPosition = pos;
    final d = h.durationNow;
    if (d > Duration.zero) s.duration = d;

    if (s.wasPlaying) {
      _accumulateListening(s, DateTime.now());
      _maybeSavePeriodic(s);
    }
  }

  void _onTrackCompleted(String songKey) {
    final s = _session;
    if (s == null || s.songKey != songKey) return;
    _closeSession(completed: true);
  }

  void _accumulateListening(_ActiveSession s, DateTime now) {
    final delta = now.difference(s.lastTickAt);
    if (delta > Duration.zero && delta < const Duration(seconds: 5)) {
      s.listened += delta;
    }
    s.lastTickAt = now;
  }

  // ============================================================
  // SESIONES
  // ============================================================

  void _startSession(Song song, Duration startPos) {
    final h = _handler;
    final liveDur = h?.durationNow ?? Duration.zero;
    _session = _ActiveSession(
      songKey: _keyOf(song),
      title: song.title,
      subtitle: song.subtitle,
      coverPath: song.coverPath,
      kind: song.kind,
      startedAt: DateTime.now(),
      lastPosition: startPos,
      lastTickAt: DateTime.now(),
    )
      ..song = song
      ..duration = liveDur > Duration.zero ? liveDur : null
      ..lastProgressSaveAt = DateTime.now();
  }

  /// Duración real de la sesión: la del reproductor si es la pista
  /// actual; si no, la cacheada; si no, la de los metadatos.
  Duration? _durationOf(_ActiveSession s) {
    final h = _handler;
    final cur = h?.currentSong;
    if (h != null && cur != null && _keyOf(cur) == s.songKey) {
      final d = h.durationNow;
      if (d > Duration.zero) {
        s.duration = d;
        return d;
      }
    }
    final cached = s.duration;
    if (cached != null && cached > Duration.zero) return cached;
    final meta = s.song?.duration;
    if (meta != null && meta > Duration.zero) return meta;
    return null;
  }

  bool _isNearEnd(Duration pos, Duration? dur, MediaKind kind) {
    if (dur == null || dur <= Duration.zero) return false;
    final tol =
        kind == MediaKind.podcast ? _podcastEndTolerance : _endTolerance;
    return pos >= dur - tol;
  }

  void _closeSession({required bool completed}) {
    final s = _session;
    if (s == null) return;

    if (s.wasPlaying) {
      _accumulateListening(s, DateTime.now());
      s.wasPlaying = false;
    }
    _session = null;

    // Sesión que solo se cargó pero no sonó: no es una reproducción.
    // No creamos historial ni tocamos el progreso guardado.
    if (!completed && s.listened < _minListenToSave) return;

    final posAtEnd = s.lastPosition;
    final trackDuration = _durationOf(s);

    _history.insert(
      0,
      PlaybackHistoryEntry(
        songKey: s.songKey,
        title: s.title,
        subtitle: s.subtitle,
        coverPath: s.coverPath,
        kind: s.kind,
        startedAt: s.startedAt,
        listenedDuration: s.listened,
        positionAtEnd: posAtEnd,
        trackDuration: trackDuration,
        completed: completed,
      ),
    );
    if (_history.length > _maxHistoryEntries) {
      _history.removeRange(_maxHistoryEntries, _history.length);
    }

    _progress[s.songKey] = TrackProgress(
      songKey: s.songKey,
      kind: s.kind,
      position: completed ? Duration.zero : posAtEnd,
      duration: trackDuration ?? _progress[s.songKey]?.duration,
      updatedAt: DateTime.now(),
      completed: completed,
    );
    _pruneProgress();

    final prev = _songs[s.songKey];
    _songs[s.songKey] = (prev ??
            SongStats(
              songKey: s.songKey,
              title: s.title,
              subtitle: s.subtitle,
              coverPath: s.coverPath,
              kind: s.kind,
              playCount: 0,
              totalListened: Duration.zero,
            ))
        .copyWith(
      playCount: completed ? (prev?.playCount ?? 0) + 1 : prev?.playCount ?? 0,
      totalListened: (prev?.totalListened ?? Duration.zero) + s.listened,
      lastPlayedAt: DateTime.now(),
    );

    // Cambio de pista / stop: guardamos ya, no esperamos al debounce.
    unawaited(_persistNow());
  }

  /// Guarda el progreso de la sesión actual (pausa o guardado periódico).
  void _saveProgressForSession({bool immediate = false}) {
    final s = _session;
    final h = _handler;
    if (s == null) return;

    // Si no ha sonado nada real, no pisamos lo que ya había guardado.
    if (s.listened < _minListenToSave) return;

    // Posición más exacta: la del handler si sigue siendo esta pista.
    final cur = h?.currentSong;
    if (h != null && cur != null && _keyOf(cur) == s.songKey) {
      s.lastPosition = h.position;
    }

    final dur = _durationOf(s);
    final completed = _isNearEnd(s.lastPosition, dur, s.kind);

    _progress[s.songKey] = TrackProgress(
      songKey: s.songKey,
      kind: s.kind,
      position: completed ? Duration.zero : s.lastPosition,
      duration: dur ?? _progress[s.songKey]?.duration,
      updatedAt: DateTime.now(),
      completed: completed,
    );
    s.lastProgressSaveAt = DateTime.now();
    _pruneProgress();

    if (immediate) {
      _persistDebounce?.cancel();
      unawaited(_persistNow());
    } else {
      _schedulePersist();
    }
  }

  /// Guardado periódico mientras suena (solo podcasts): si la app muere
  /// sin pausar, se conserva el punto donde te quedaste.
  void _maybeSavePeriodic(_ActiveSession s) {
    if (s.kind != MediaKind.podcast) return;
    if (s.listened < _minListenToSave) return;
    final now = DateTime.now();
    if (now.difference(s.lastProgressSaveAt) < _progressSaveEvery) return;
    _saveProgressForSession();
  }

  void _pruneProgress() {
    if (_progress.length <= _maxProgressEntries) return;
    final sorted = _progress.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final toRemove = sorted.take(_progress.length - _maxProgressEntries);
    for (final p in toRemove) {
      _progress.remove(p.songKey);
    }
  }

  // ============================================================
  // PERSISTENCIA (debounced)
  // ============================================================

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 2), _persistNow);
  }

  Future<void> flush() => _persistNow();

  // ============================================================
  // API PÚBLICA (solo lectura)
  // ============================================================

  List<PlaybackHistoryEntry> get history => List.unmodifiable(_history);

  List<PlaybackHistoryEntry> historyFor(MediaKind kind) =>
      List.unmodifiable(_history.where((e) => e.kind == kind));

  TrackProgress? getProgress(String songKey) => _progress[songKey];

  /// Progreso de [song]. Si la pista está sonando ahora mismo devuelve
  /// el progreso EN VIVO (no hay que esperar a pausar para verlo).
  TrackProgress? progressOf(Song song) {
    final key = _keyOf(song);
    final stored = _progress[key];
    final s = _session;
    if (s != null && s.songKey == key && s.listened >= _minListenToSave) {
      return TrackProgress(
        songKey: key,
        kind: s.kind,
        position: s.lastPosition,
        duration: _durationOf(s) ?? stored?.duration,
        updatedAt: DateTime.now(),
        completed: false,
      );
    }
    return stored;
  }

  SongStats? statsOf(Song song) => _songs[_keyOf(song)];

  Map<String, SongStats> get allSongStats => Map.unmodifiable(_songs);

  int playCountOf(Song song) => _songs[_keyOf(song)]?.playCount ?? 0;

  Duration totalListenedOf(Song song) =>
      _songs[_keyOf(song)]?.totalListened ?? Duration.zero;

  void clearAll() {
    _history.clear();
    _progress.clear();
    _songs.clear();
    _schedulePersist();
  }

  Future<void> dispose() async {
    _closeSession(completed: false);
    await _persistNow();
    _persistDebounce?.cancel();
    await _mediaItemSub?.cancel();
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _trackCompletedSub?.cancel();
    _handler = null;
    _initialized = false;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _keyOf(Song s) =>
      (s.path != null && s.path!.isNotEmpty) ? s.path! : s.title;
}

class _ActiveSession {
  final String songKey;
  final String title;
  final String? subtitle;
  final String? coverPath;
  final MediaKind kind;
  final DateTime startedAt;

  Song? song;
  Duration lastPosition;
  Duration? duration;
  Duration listened = Duration.zero;
  DateTime lastTickAt;
  DateTime lastProgressSaveAt = DateTime.now();
  bool wasPlaying = false;

  _ActiveSession({
    required this.songKey,
    required this.title,
    this.subtitle,
    this.coverPath,
    required this.kind,
    required this.startedAt,
    required this.lastPosition,
    required this.lastTickAt,
  });
}
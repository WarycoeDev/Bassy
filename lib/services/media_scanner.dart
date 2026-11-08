import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/song.dart';
import 'metadata_cache.dart';
import 'metadata_reader.dart';
import 'settings_service.dart';

class ScanResult {
  final List<Song> songs;
  final List<Song> podcasts;
  final List<String> errors;

  const ScanResult({
    required this.songs,
    required this.podcasts,
    required this.errors,
  });

  int get totalCount => songs.length + podcasts.length;

  static const empty = ScanResult(songs: [], podcasts: [], errors: []);
}

class ScanProgress {
  final List<Song> songs;
  final List<Song> podcasts;
  final int processedFiles;
  final List<String> errors;
  final bool done;

  const ScanProgress({
    required this.songs,
    required this.podcasts,
    required this.processedFiles,
    required this.errors,
    required this.done,
  });

  int get totalCount => songs.length + podcasts.length;
}

class MediaScanner {
  MediaScanner._();
  static final MediaScanner instance = MediaScanner._();

  static const Set<String> _audioExts = {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'ogg',
    'opus',
    'wav',
    'wma',
  };

  bool _scanning = false;
  bool get isScanning => _scanning;

  ScanResult? _lastResult;
  ScanResult? get lastResult => _lastResult;

  bool _initialScanDone = false;
  Completer<void>? _initialScanCompleter;

  // Estado vivo del watcher (mutable entre eventos).
  final List<Song> _liveSongs = [];
  final List<Song> _livePodcasts = [];
  final List<String> _liveErrors = [];

  // Watcher persistente: se crea una sola vez.
  StreamController<ScanProgress>? _watchController;
  final List<StreamSubscription<FileSystemEvent>> _watchSubs = [];
  final Map<String, Timer> _debounce = {};
  final List<FileSystemEvent> _pending = [];
  bool _draining = false;

  // ─────────────────────────────────────────────────────────────
  // ESCANEO INICIAL (llamar UNA vez al arrancar la app)
  // ─────────────────────────────────────────────────────────────
  Future<void> ensureInitialScan() {
    if (_initialScanDone) return Future.value();
    if (_initialScanCompleter != null) return _initialScanCompleter!.future;

    _initialScanCompleter = Completer<void>();
    _doInitialScan()
        .then((_) {
          _initialScanDone = true;
          _initialScanCompleter!.complete();
        })
        .catchError((Object e, StackTrace st) {
          _initialScanCompleter!.completeError(e, st);
        });
    return _initialScanCompleter!.future;
  }

  Future<void> _doInitialScan() async {
    _liveErrors.clear();
    _liveSongs.clear();
    _livePodcasts.clear();

    final settings = await SettingsService.instance.load();

    await for (final s in _scanDirsStream(
      dirs: settings.musicDirs,
      kind: MediaKind.music,
      errors: _liveErrors,
    )) {
      _liveSongs.add(s);
    }

    await for (final s in _scanDirsStream(
      dirs: settings.podcastDirs,
      kind: MediaKind.podcast,
      errors: _liveErrors,
    )) {
      _livePodcasts.add(s);
    }

    _sortInPlace(_liveSongs);
    _sortInPlace(_livePodcasts);

    final existing = <String>{
      ..._liveSongs.map((s) => s.path),
      ..._livePodcasts.map((s) => s.path),
    };
    await MetadataCache.instance.prune(existing);
    await MetadataCache.instance.flush();

    _publishResult();
    _emitSnapshot();
  }

  // ─────────────────────────────────────────────────────────────
  // WATCHER (solo observa; no escanea)
  // ─────────────────────────────────────────────────────────────
  Stream<ScanProgress> watchStream() {
    if (_watchController == null || _watchController!.isClosed) {
      _watchController = StreamController<ScanProgress>.broadcast(
        onListen: _startWatcher,
        onCancel: _stopWatcherIfNoListeners,
      );
    }

    if (_lastResult != null) {
      scheduleMicrotask(() {
        if (_watchController == null || _watchController!.isClosed) return;
        _watchController!.add(
          ScanProgress(
            songs: _lastResult!.songs,
            podcasts: _lastResult!.podcasts,
            processedFiles: _lastResult!.totalCount,
            errors: _lastResult!.errors,
            done: false,
          ),
        );
      });
    }

    return _watchController!.stream;
  }

  Future<void> _startWatcher() async {
    if (_watchSubs.isNotEmpty) return;

    try {
      final settings = await SettingsService.instance.load();
      final allDirs = <String>{...settings.musicDirs, ...settings.podcastDirs};

      for (final dirPath in allDirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          _liveErrors.add('No existe: $dirPath');
          continue;
        }
        try {
          final sub = dir
              .watch(recursive: true)
              .listen(
                _schedule,
                onError: (Object e) => _liveErrors.add('Watcher $dirPath: $e'),
              );
          _watchSubs.add(sub);
        } catch (e) {
          _liveErrors.add('No se pudo observar $dirPath: $e');
        }
      }
    } catch (e) {
      _liveErrors.add('Watcher: $e');
    }
  }

  void _stopWatcherIfNoListeners() {
    if (_watchController == null || _watchController!.isClosed) return;
    if (!_watchController!.hasListener) {
      for (final s in _watchSubs) {
        s.cancel();
      }
      _watchSubs.clear();
      for (final t in _debounce.values) {
        t.cancel();
      }
      _debounce.clear();
      _pending.clear();
    }
  }

  void _emitSnapshot() {
    if (_watchController == null || _watchController!.isClosed) return;
    _watchController!.add(
      ScanProgress(
        songs: List.unmodifiable(_liveSongs),
        podcasts: List.unmodifiable(_livePodcasts),
        processedFiles: _liveSongs.length + _livePodcasts.length,
        errors: List.unmodifiable(_liveErrors),
        done: false,
      ),
    );
  }

  void _schedule(FileSystemEvent ev) {
    final key = ev.path;
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(milliseconds: 400), () {
      _pending.add(ev);
      _drain();
    });
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final ev = _pending.removeAt(0);
        try {
          await _handleFsEvent(ev);
          _publishResult();
          _emitSnapshot();
        } catch (e) {
          debugPrint('Watcher: error en ${ev.path}: $e');
        }
      }
    } finally {
      _draining = false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // HANDLER DE EVENTOS FS
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleFsEvent(FileSystemEvent ev) async {
    final path = ev.path;
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final isAudio = _audioExts.contains(ext);

    switch (ev.type) {
      case FileSystemEvent.create:
      case FileSystemEvent.modify:
        if (isAudio) {
          final file = File(path);
          if (!await file.exists()) return;
          final kind = await _kindForPath(path);
          final song = await _buildSong(
            entity: file,
            ext: ext,
            kind: kind,
            cache: MetadataCache.instance,
            coversDir: await MetadataCache.instance.coversDir(),
          );
          if (song == null) return;
          final list = kind == MediaKind.music ? _liveSongs : _livePodcasts;
          final idx = list.indexWhere((s) => s.path == path);
          if (idx >= 0) {
            list[idx] = song;
          } else {
            list.add(song);
          }
          _sortInPlace(list);
        } else if (ev is FileSystemCreateEvent && ev.isDirectory) {
          final kind = await _kindForPath(path);
          await for (final s in _scanDirsStream(
            dirs: [path],
            kind: kind,
            errors: _liveErrors,
          )) {
            final list = kind == MediaKind.music ? _liveSongs : _livePodcasts;
            if (!list.any((x) => x.path == s.path)) list.add(s);
          }
          _sortInPlace(_liveSongs);
          _sortInPlace(_livePodcasts);
        }
        break;

      case FileSystemEvent.delete:
        if (isAudio) {
          _liveSongs.removeWhere((s) => s.path == path);
          _livePodcasts.removeWhere((s) => s.path == path);
          await MetadataCache.instance.prune({
            ..._liveSongs.map((s) => s.path),
            ..._livePodcasts.map((s) => s.path),
          });
        } else {
          final prefix = path.endsWith(p.separator)
              ? path
              : '$path${p.separator}';
          final had =
              _liveSongs.any((s) => s.path.startsWith(prefix)) ||
              _livePodcasts.any((s) => s.path.startsWith(prefix));
          if (had) {
            _liveSongs.removeWhere((s) => s.path.startsWith(prefix));
            _livePodcasts.removeWhere((s) => s.path.startsWith(prefix));
            await MetadataCache.instance.prune({
              ..._liveSongs.map((s) => s.path),
              ..._livePodcasts.map((s) => s.path),
            });
          }
        }
        break;

      case FileSystemEvent.move:
        _liveSongs.removeWhere((s) => s.path == path);
        _livePodcasts.removeWhere((s) => s.path == path);
        break;
    }
  }

  Future<MediaKind> _kindForPath(String path) async {
    final settings = await SettingsService.instance.load();
    for (final d in settings.podcastDirs) {
      if (path == d || p.isWithin(d, path)) return MediaKind.podcast;
    }
    return MediaKind.music;
  }

  void _sortInPlace(List<Song> list) {
    list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  void _publishResult() {
    _lastResult = ScanResult(
      songs: List.unmodifiable(_liveSongs),
      podcasts: List.unmodifiable(_livePodcasts),
      errors: List.unmodifiable(_liveErrors),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ONE-SHOT para refresh manual
  // ─────────────────────────────────────────────────────────────
  Future<ScanResult> scan() async {
    _initialScanDone = false;
    _initialScanCompleter = null;
    await ensureInitialScan();
    return _lastResult ?? ScanResult.empty;
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers de walk / build
  // ─────────────────────────────────────────────────────────────
  Stream<Song> _scanDirsStream({
    required List<String> dirs,
    required MediaKind kind,
    required List<String> errors,
  }) async* {
    for (final path in dirs) {
      try {
        final dir = Directory(path);
        if (!await dir.exists()) {
          errors.add('No existe: $path');
          continue;
        }
        yield* _walkStream(dir, kind, errors);
      } catch (e) {
        errors.add('Error en $path: $e');
      }
    }
  }

  Stream<Song> _walkStream(
    Directory dir,
    MediaKind kind,
    List<String> errors,
  ) async* {
    final cache = MetadataCache.instance;
    Directory coversDir;
    try {
      coversDir = await cache.coversDir();
    } catch (e) {
      errors.add('No se pudo preparar carpeta de carátulas: $e');
      return;
    }

    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final ext = p
            .extension(entity.path)
            .replaceFirst('.', '')
            .toLowerCase();
        if (!_audioExts.contains(ext)) continue;
        try {
          final song = await _buildSong(
            entity: entity,
            ext: ext,
            kind: kind,
            cache: cache,
            coversDir: coversDir,
          );
          if (song != null) yield song;
        } catch (e) {
          debugPrint('No se pudo leer ${entity.path}: $e');
        }
      }
    } catch (e) {
      errors.add('Error recorriendo ${dir.path}: $e');
    }
  }

  Future<Song?> _buildSong({
    required File entity,
    required String ext,
    required MediaKind kind,
    required MetadataCache cache,
    required Directory coversDir,
  }) async {
    final stat = await entity.stat();
    final cached = await cache.get(entity.path);

    String title = '';
    String artist = '';
    String album = '';
    Duration duration = Duration.zero;
    String? coverPath;

    if (cached != null && cached.matchesFile(stat)) {
      title = cached.title;
      artist = cached.artist;
      album = cached.album;
      duration = cached.duration;
      coverPath = cached.coverPath;
      if (coverPath != null && !await File(coverPath).exists()) {
        coverPath = null;
      }
    }

    final needsRead =
        cached == null ||
        !cached.matchesFile(stat) ||
        title.isEmpty ||
        (coverPath == null && cached.coverPath != null);

    if (needsRead) {
      final raw = await MetadataReader.instance.read(entity);
      final base = p.basenameWithoutExtension(entity.path);

      title = (raw?.title.isNotEmpty ?? false) ? raw!.title : base;
      artist = raw?.artist ?? '';
      album = raw?.album ?? '';
      duration = raw?.duration ?? Duration.zero;

      if (raw?.coverBytes != null && raw!.coverBytes!.isNotEmpty) {
        final name = cache.coverFileName(entity.path, album);
        final coverFile = File(p.join(coversDir.path, name));
        if (!await coverFile.exists()) {
          await coverFile.writeAsBytes(raw.coverBytes!, flush: true);
        }
        coverPath = coverFile.path;
      } else {
        coverPath = null;
      }

      await cache.put(
        CachedMetadata(
          path: entity.path,
          title: title,
          artist: artist,
          album: album,
          duration: duration,
          coverPath: coverPath,
          sizeBytes: stat.size,
          mtimeMs: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }

    return Song(
      path: entity.path,
      fileName: p.basename(entity.path),
      title: _cleanTitle(title),
      artist: artist,
      album: album,
      extension: ext,
      sizeBytes: stat.size,
      modified: stat.modified,
      kind: kind,
      duration: duration,
      coverPath: coverPath,
    );
  }

  String _cleanTitle(String raw) {
    var s = raw.replaceAll('_', ' ').trim();
    s = s.replaceFirst(RegExp(r'^\d{1,3}[\s\-\.]+'), '');
    return s.isEmpty ? raw : s;
  }
}

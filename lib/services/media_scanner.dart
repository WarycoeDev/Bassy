import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

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
  final bool scanning;
  final String? statusMessage;

  const ScanProgress({
    required this.songs,
    required this.podcasts,
    required this.processedFiles,
    required this.errors,
    required this.done,
    this.scanning = false,
    this.statusMessage,
  });

  int get totalCount => songs.length + podcasts.length;
}

class _FsEvent {
  final String path;
  final String? oldPath;
  final _FsEventKind kind;

  const _FsEvent(this.kind, this.path, {this.oldPath});
}

enum _FsEventKind { create, modify, delete, move }

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

  /// Cada cuántos archivos procesados emitimos snapshot + cedemos event loop.
  static const int _progressEvery = 10;

  /// Umbral de "archivo recién creado". Si `mtime` está dentro de esta
  /// ventana, hacemos la comprobación de estabilidad (stat doble con delay)
  /// para evitar listar archivos que se están copiando todavía.
  static const Duration _recentFileWindow = Duration(seconds: 5);

  /// Delay entre los dos `stat` de la comprobación de estabilidad.
  static const Duration _stabilityDelay = Duration(milliseconds: 150);

  bool _scanning = false;
  bool get isScanning => _scanning;

  bool _cancelRequested = false;
  int _scanProcessedCount = 0;

  ScanResult? _lastResult;
  ScanResult? get lastResult => _lastResult;

  bool _initialScanDone = false;
  Future<void>? _initialScanFuture;
  Completer<void>? _rescanCompleter;
  bool _forceRescan = false;

  final List<Song> _liveSongs = [];
  final List<Song> _livePodcasts = [];
  final List<String> _liveErrors = [];

  StreamController<ScanProgress>? _watchController;
  final List<StreamSubscription<WatchEvent>> _watchSubs = [];
  final Map<String, Timer> _debounce = {};
  final List<_FsEvent> _pending = [];
  bool _draining = false;
  bool _watcherStarting = false;

  // ---------------------------------------------------------------------------
  // Orden estable (inserción con búsqueda binaria)
  // ---------------------------------------------------------------------------

  static int _compareSongs(Song a, Song b) {
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (byTitle != 0) return byTitle;
    final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    if (byArtist != 0) return byArtist;
    return a.path.compareTo(b.path);
  }

  int _insertSorted(List<Song> list, Song song) {
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_compareSongs(list[mid], song) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo < list.length && list[lo].path == song.path) {
      list[lo] = song;
      return lo;
    }
    list.insert(lo, song);
    return lo;
  }

  void _sortInPlace(List<Song> list) {
    list.sort(_compareSongs);
  }

  // ---------------------------------------------------------------------------
  // Comprobación de estabilidad de archivo
  // ---------------------------------------------------------------------------

  /// Devuelve `true` si el archivo parece completamente escrito.
  ///
  /// Hace dos `stat` separados por [_stabilityDelay] y compara `size` +
  /// `mtime`. Si no cambian y `size > 0`, el archivo está estable.
  ///
  /// Solo se invoca cuando el archivo es reciente (`mtime < 5s`), así que
  /// el coste de ~150ms por archivo solo se paga durante una copia activa.
  Future<bool> _isFileStable(File file) async {
    try {
      final s1 = await file.stat();
      if (s1.size <= 0) return false;
      await Future<void>.delayed(_stabilityDelay);
      final s2 = await file.stat();
      return s1.size == s2.size && s1.modified == s2.modified;
    } catch (_) {
      return false;
    }
  }

  /// Decide si el archivo se puede procesar ahora.
  ///
  /// - Archivos "viejos" (mtime fuera de [_recentFileWindow]): sí.
  /// - Archivos recientes: solo si [_isFileStable] confirma que ya no crecen.
  ///
  /// Si devuelve `false`, el archivo se ignora en este pase; el watcher lo
  /// recogerá cuando termine de escribirse (evento MODIFY/ADD posterior).
  Future<bool> _canProcessNow(File file, FileStat stat) async {
    final age = DateTime.now().difference(stat.modified);
    if (age >= _recentFileWindow) return true;
    return _isFileStable(file);
  }

  // ---------------------------------------------------------------------------
  // Escaneo inicial / rescan
  // ---------------------------------------------------------------------------

  Future<void> ensureInitialScan() {
    if (_initialScanDone && !_forceRescan) return Future.value();

    final inFlight = _initialScanFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    final future = completer.future;
    _initialScanFuture = future;

    _doInitialScan()
        .then((_) {
          if (!completer.isCompleted) completer.complete();
        })
        .catchError((Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        })
        .whenComplete(() {
          _initialScanDone = true;
          _initialScanFuture = null;
          _forceRescan = false;
        });

    return future;
  }

  Future<void> _doInitialScan() async {
    _scanning = true;
    _cancelRequested = false;
    _scanProcessedCount = 0;
    _emitSnapshot(statusMessage: 'Escaneando biblioteca…');

    _liveErrors.clear();
    _liveSongs.clear();
    _livePodcasts.clear();

    try {
      final settings = await SettingsService.instance.load();

      // --- Música ---
      await for (final s in _scanDirsStream(
        dirs: settings.musicDirs,
        kind: MediaKind.music,
        errors: _liveErrors,
      )) {
        if (_cancelRequested) break;
        _insertSorted(_liveSongs, s);
        _scanProcessedCount++;
        if (_scanProcessedCount % _progressEvery == 0) {
          _emitSnapshot(
            statusMessage:
                'Escaneando… $_scanProcessedCount archivos · ${_liveSongs.length} música',
          );
          await Future<void>.delayed(Duration.zero);
        }
      }

      // --- Podcasts ---
      if (!_cancelRequested) {
        await for (final s in _scanDirsStream(
          dirs: settings.podcastDirs,
          kind: MediaKind.podcast,
          errors: _liveErrors,
        )) {
          if (_cancelRequested) break;
          _insertSorted(_livePodcasts, s);
          _scanProcessedCount++;
          if (_scanProcessedCount % _progressEvery == 0) {
            _emitSnapshot(
              statusMessage:
                  'Escaneando… $_scanProcessedCount archivos · ${_livePodcasts.length} podcasts',
            );
            await Future<void>.delayed(Duration.zero);
          }
        }
      }

      if (_cancelRequested) {
        debugPrint('MediaScanner: scan cancelado');
        return;
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
      _emitSnapshot(
        statusMessage:
            'Listo: ${_liveSongs.length} canciones · ${_livePodcasts.length} podcasts',
      );
    } finally {
      _scanning = false;
      _scanProcessedCount = 0;
      _emitSnapshot(clearStatus: true);
    }
  }

  Future<ScanResult> rescanNow() => scan();

  Future<ScanResult> scan() async {
    _cancelRequested = true;

    final pending = _rescanCompleter;
    if (pending != null) {
      await pending.future;
      return _lastResult ?? ScanResult.empty;
    }

    final completer = Completer<void>();
    _rescanCompleter = completer;

    try {
      final inFlight = _initialScanFuture;
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {}
      }

      _initialScanDone = false;
      _forceRescan = true;

      final newFuture = _runForcedScan();
      _initialScanFuture = newFuture;
      await newFuture;

      return _lastResult ?? ScanResult.empty;
    } finally {
      if (!completer.isCompleted) completer.complete();
      _rescanCompleter = null;
      _forceRescan = false;
    }
  }

  Future<void> _runForcedScan() async {
    final completer = Completer<void>();
    _doInitialScan()
        .then((_) {
          if (!completer.isCompleted) completer.complete();
        })
        .catchError((Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        })
        .whenComplete(() {
          _initialScanDone = true;
          _forceRescan = false;
          if (identical(_initialScanFuture, completer.future)) {
            _initialScanFuture = null;
          }
        });
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Stream público
  // ---------------------------------------------------------------------------

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
            scanning: _scanning,
          ),
        );
      });
    }

    return _watchController!.stream;
  }

  // ---------------------------------------------------------------------------
  // Watchers
  // ---------------------------------------------------------------------------

  Future<void> _startWatcher() async {
    if (_watchSubs.isNotEmpty || _watcherStarting) return;
    _watcherStarting = true;
    try {
      final settings = await SettingsService.instance.load();
      final allDirs = <String>{...settings.musicDirs, ...settings.podcastDirs};

      for (final dirPath in allDirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          if (!_liveErrors.any((e) => e.contains(dirPath))) {
            _liveErrors.add('No existe: $dirPath');
          }
          continue;
        }
        try {
          final sub = DirectoryWatcher(dirPath).events.listen(
            _onWatchEvent,
            onError: (Object e) {
              if (!_liveErrors.any((x) => x.contains(dirPath))) {
                _liveErrors.add('Watcher $dirPath: $e');
              }
            },
          );
          _watchSubs.add(sub);
        } catch (e) {
          _liveErrors.add('No se pudo observar $dirPath: $e');
        }
      }
    } catch (e) {
      _liveErrors.add('Watcher: $e');
    } finally {
      _watcherStarting = false;
    }
  }

  void _stopWatcherIfNoListeners() {
    if (_watchController == null || _watchController!.isClosed) return;
    if (_watchController!.hasListener) return;
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

  Future<void> _restartWatcher() async {
    for (final s in _watchSubs) {
      await s.cancel();
    }
    _watchSubs.clear();
    for (final t in _debounce.values) {
      t.cancel();
    }
    _debounce.clear();
    _pending.clear();

    if (_watchController != null &&
        !_watchController!.isClosed &&
        _watchController!.hasListener) {
      await _startWatcher();
    }
  }

  // ---------------------------------------------------------------------------
  // Debounce + drenaje
  // ---------------------------------------------------------------------------

  void _onWatchEvent(WatchEvent ev) {
    _FsEventKind kind;
    switch (ev.type) {
      case ChangeType.ADD:
        kind = _FsEventKind.create;
        break;
      case ChangeType.MODIFY:
        kind = _FsEventKind.modify;
        break;
      case ChangeType.REMOVE:
        kind = _FsEventKind.delete;
        break;
      default:
        kind = _FsEventKind.modify;
        break;
    }

    final e = _FsEvent(kind, ev.path);
    final key = ev.path;
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(milliseconds: 400), () {
      _debounce.remove(key);
      _pending.add(e);
      _drain();
    });
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    _scanning = true;
    _emitSnapshot(statusMessage: 'Actualizando biblioteca…');
    try {
      while (_pending.isNotEmpty) {
        final ev = _pending.removeAt(0);
        try {
          await _handleFsEvent(ev);
          _publishResult();
          _emitSnapshot();
        } catch (e, st) {
          debugPrint('Watcher: error en ${ev.path}: $e\n$st');
        }
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _draining = false;
      _scanning = false;
      _emitSnapshot(clearStatus: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Manejo de eventos del filesystem
  // ---------------------------------------------------------------------------

  Future<void> _handleFsEvent(_FsEvent ev) async {
    switch (ev.kind) {
      case _FsEventKind.create:
      case _FsEventKind.modify:
        await _upsertPath(ev.path);
        break;
      case _FsEventKind.delete:
        await _removePath(ev.path);
        break;
      case _FsEventKind.move:
        final oldPath = ev.oldPath;
        if (oldPath != null) {
          await _removePath(oldPath);
        } else {
          await _removePath(ev.path);
        }
        await _upsertPath(ev.path);
        break;
    }
  }

  Future<void> _upsertPath(String path) async {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final isAudio = _audioExts.contains(ext);

    final file = File(path);
    final stat = await file.stat();
    final exists = await file.exists();

    if (exists && isAudio) {
      // Mismo blindaje que en _walkStream: si el archivo acaba de crearse
      // y aún se está copiando, no lo procesamos todavía. El watcher
      // disparará otro MODIFY cuando termine.
      if (!await _canProcessNow(file, stat)) return;

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
      _insertSorted(list, song);
      return;
    }

    if (!exists) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final kind = await _kindForPath(path);
        final target = kind == MediaKind.music ? _liveSongs : _livePodcasts;
        await for (final s in _scanDirsStream(
          dirs: [path],
          kind: kind,
          errors: _liveErrors,
        )) {
          _insertSorted(target, s);
        }
        return;
      }
      await _removePath(path);
      return;
    }

    if (stat.type == FileSystemEntityType.directory) {
      final kind = await _kindForPath(path);
      final target = kind == MediaKind.music ? _liveSongs : _livePodcasts;
      await for (final s in _scanDirsStream(
        dirs: [path],
        kind: kind,
        errors: _liveErrors,
      )) {
        _insertSorted(target, s);
      }
    }
  }

  Future<void> _removePath(String path) async {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final isAudio = _audioExts.contains(ext);

    if (isAudio) {
      final had =
          _liveSongs.any((s) => s.path == path) ||
          _livePodcasts.any((s) => s.path == path);
      _liveSongs.removeWhere((s) => s.path == path);
      _livePodcasts.removeWhere((s) => s.path == path);
      if (had) {
        await MetadataCache.instance.prune({
          ..._liveSongs.map((s) => s.path),
          ..._livePodcasts.map((s) => s.path),
        });
      }
      return;
    }

    final prefix = path.endsWith(p.separator) ? path : '$path${p.separator}';
    bool matches(String p0) => p0 == path || p0.startsWith(prefix);
    final had =
        _liveSongs.any((s) => matches(s.path)) ||
        _livePodcasts.any((s) => matches(s.path));
    if (had) {
      _liveSongs.removeWhere((s) => matches(s.path));
      _livePodcasts.removeWhere((s) => matches(s.path));
      await MetadataCache.instance.prune({
        ..._liveSongs.map((s) => s.path),
        ..._livePodcasts.map((s) => s.path),
      });
    }
  }

  Future<MediaKind> _kindForPath(String path) async {
    final settings = await SettingsService.instance.load();
    for (final d in settings.podcastDirs) {
      if (path == d || p.isWithin(d, path)) return MediaKind.podcast;
    }
    return MediaKind.music;
  }

  void _publishResult() {
    _lastResult = ScanResult(
      songs: List.unmodifiable(_liveSongs),
      podcasts: List.unmodifiable(_livePodcasts),
      errors: List.unmodifiable(_liveErrors),
    );
  }

  void _emitSnapshot({
    bool? scanning,
    String? statusMessage,
    bool clearStatus = false,
  }) {
    if (_watchController == null || _watchController!.isClosed) return;
    _watchController!.add(
      ScanProgress(
        songs: List.unmodifiable(_liveSongs),
        podcasts: List.unmodifiable(_livePodcasts),
        processedFiles: _liveSongs.length + _livePodcasts.length,
        errors: List.unmodifiable(_liveErrors),
        done: false,
        scanning: scanning ?? _scanning,
        statusMessage: clearStatus ? null : statusMessage,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // API pública de carpetas
  // ---------------------------------------------------------------------------

  Future<void> onDirectoryAdded(String dirPath, MediaKind kind) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      if (!_liveErrors.any((e) => e.contains(dirPath))) {
        _liveErrors.add('No existe: $dirPath');
      }
      _emitSnapshot();
      return;
    }

    _liveErrors.removeWhere((e) => e.contains(dirPath));

    _scanning = true;
    _cancelRequested = false;
    _scanProcessedCount = 0;

    final label = kind == MediaKind.music ? 'música' : 'podcasts';
    _emitSnapshot(statusMessage: 'Agregando carpeta de $label…');

    try {
      final target = kind == MediaKind.music ? _liveSongs : _livePodcasts;

      await for (final s in _scanDirsStream(
        dirs: [dirPath],
        kind: kind,
        errors: _liveErrors,
      )) {
        if (_cancelRequested) break;
        _insertSorted(target, s);
        _scanProcessedCount++;
        if (_scanProcessedCount % _progressEvery == 0) {
          _emitSnapshot(
            statusMessage:
                'Agregando carpeta de $label… $_scanProcessedCount archivos · ${target.length} encontradas',
          );
          await Future<void>.delayed(Duration.zero);
        }
      }

      _sortInPlace(_liveSongs);
      _sortInPlace(_livePodcasts);
      _publishResult();
    } finally {
      _scanning = false;
      _scanProcessedCount = 0;
      _emitSnapshot(clearStatus: true);
      await _restartWatcher();
    }
  }

  Future<void> onDirectoryRemoved(String dirPath) async {
    final prefix = dirPath.endsWith(p.separator)
        ? dirPath
        : '$dirPath${p.separator}';

    bool matches(String path) => path == dirPath || path.startsWith(prefix);

    _scanning = true;
    _emitSnapshot(statusMessage: 'Quitando carpeta…');

    try {
      final removed =
          _liveSongs.where((s) => matches(s.path)).length +
          _livePodcasts.where((s) => matches(s.path)).length;

      _liveSongs.removeWhere((s) => matches(s.path));
      _livePodcasts.removeWhere((s) => matches(s.path));
      _liveErrors.removeWhere((e) => e.contains(dirPath));

      if (removed > 0) {
        await MetadataCache.instance.prune({
          ..._liveSongs.map((s) => s.path),
          ..._livePodcasts.map((s) => s.path),
        });
      }

      _publishResult();
    } finally {
      _scanning = false;
      _emitSnapshot(clearStatus: true);
      await _restartWatcher();
    }
  }

  // ---------------------------------------------------------------------------
  // Recorrido de directorios
  // ---------------------------------------------------------------------------

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
        if (_cancelRequested) return;
        if (entity is! File) continue;
        final ext =
            p.extension(entity.path).replaceFirst('.', '').toLowerCase();
        if (!_audioExts.contains(ext)) continue;

        // Comprobación de estabilidad: solo para archivos recientes.
        // Si aún se están copiando, se ignora en este pase y el watcher
        // lo recogerá cuando termine (evento MODIFY/ADD posterior).
        try {
          final stat = await entity.stat();
          if (!await _canProcessNow(entity, stat)) {
            continue;
          }
        } catch (e) {
          debugPrint('No se pudo stat ${entity.path}: $e');
          continue;
        }

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
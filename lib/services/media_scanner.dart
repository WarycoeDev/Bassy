import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/song.dart';
import 'metadata_cache.dart';
import 'metadata_reader.dart';
import 'settings_service.dart';

/// Resultado final del escaneo.
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

/// Progreso emitido durante el escaneo (para feedback en vivo).
class ScanProgress {
  /// Canciones encontradas hasta ahora (solo música).
  final List<Song> songs;

  /// Podcasts encontrados hasta ahora.
  final List<Song> podcasts;

  /// Archivos ya procesados (música + podcasts).
  final int processedFiles;

  /// Errores acumulados hasta ahora.
  final List<String> errors;

  /// `true` cuando el escaneo terminó.
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

  /// Último resultado completo (para no reescanear al volver a Library).
  ScanResult? _lastResult;
  ScanResult? get lastResult => _lastResult;

  /// Escanea y emite progreso en vivo. El último evento tiene `done = true`.
  Stream<ScanProgress> scanStream() async* {
    if (_scanning) {
      debugPrint('MediaScanner: ya hay un escaneo en curso');
      // Emitimos el último resultado si lo hay; si no, vacío.
      yield ScanProgress(
        songs: _lastResult?.songs ?? const [],
        podcasts: _lastResult?.podcasts ?? const [],
        processedFiles: _lastResult?.totalCount ?? 0,
        errors: _lastResult?.errors ?? const [],
        done: true,
      );
      return;
    }
    _scanning = true;

    final errors = <String>[];
    final songs = <Song>[];
    final podcasts = <Song>[];
    int processed = 0;

    // Emitimos estado inicial.
    yield ScanProgress(
      songs: List.unmodifiable(songs),
      podcasts: List.unmodifiable(podcasts),
      processedFiles: processed,
      errors: List.unmodifiable(errors),
      done: false,
    );

    try {
      final settings = await SettingsService.instance.load();

      // Música
      await for (final s in _scanDirsStream(
        dirs: settings.musicDirs,
        kind: MediaKind.music,
        errors: errors,
      )) {
        songs.add(s);
        processed++;
        yield ScanProgress(
          songs: List.unmodifiable(songs),
          podcasts: List.unmodifiable(podcasts),
          processedFiles: processed,
          errors: List.unmodifiable(errors),
          done: false,
        );
      }

      // Podcasts
      await for (final s in _scanDirsStream(
        dirs: settings.podcastDirs,
        kind: MediaKind.podcast,
        errors: errors,
      )) {
        podcasts.add(s);
        processed++;
        yield ScanProgress(
          songs: List.unmodifiable(songs),
          podcasts: List.unmodifiable(podcasts),
          processedFiles: processed,
          errors: List.unmodifiable(errors),
          done: false,
        );
      }

      // Orden final + caché
      songs.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      podcasts.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );

      final existing = <String>{
        ...songs.map((s) => s.path),
        ...podcasts.map((s) => s.path),
      };
      await MetadataCache.instance.prune(existing);
      await MetadataCache.instance.flush();

      _lastResult = ScanResult(
        songs: List.unmodifiable(songs),
        podcasts: List.unmodifiable(podcasts),
        errors: List.unmodifiable(errors),
      );
    } catch (e) {
      errors.add('Error general: $e');
      debugPrint('MediaScanner.scan error: $e');
    } finally {
      _scanning = false;
    }

    debugPrint(
      'MediaScanner: ${songs.length} canciones, ${podcasts.length} podcasts',
    );

    yield ScanProgress(
      songs: List.unmodifiable(songs),
      podcasts: List.unmodifiable(podcasts),
      processedFiles: processed,
      errors: List.unmodifiable(errors),
      done: true,
    );
  }

  /// Versión "one-shot" que consume el stream y devuelve el resultado final.
  Future<ScanResult> scan() async {
    ScanProgress? last;
    await for (final p in scanStream()) {
      last = p;
    }
    if (last == null) return ScanResult.empty;
    return ScanResult(
      songs: last.songs,
      podcasts: last.podcasts,
      errors: last.errors,
    );
  }

  /// Emite cada [Song] encontrado en [dirs].
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

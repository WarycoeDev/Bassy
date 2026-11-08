import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/song.dart';
import 'metadata_cache.dart';
import 'metadata_reader.dart';
import 'settings_service.dart';

/// Resultado del escaneo.
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

class MediaScanner {
  MediaScanner._();
  static final MediaScanner instance = MediaScanner._();

  /// Extensiones de audio soportadas.
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

  /// Escanea las carpetas configuradas en [AppSettings].
  Future<ScanResult> scan() async {
    if (_scanning) {
      debugPrint('MediaScanner: ya hay un escaneo en curso');
      return ScanResult.empty;
    }
    _scanning = true;

    final errors = <String>[];
    final songs = <Song>[];
    final podcasts = <Song>[];

    try {
      final settings = await SettingsService.instance.load();

      await _scanDirs(
        dirs: settings.musicDirs,
        kind: MediaKind.music,
        out: songs,
        errors: errors,
      );
      await _scanDirs(
        dirs: settings.podcastDirs,
        kind: MediaKind.podcast,
        out: podcasts,
        errors: errors,
      );

      // Persistir caché + limpiar entradas huérfanas.
      final existing = <String>{
        ...songs.map((s) => s.path),
        ...podcasts.map((s) => s.path),
      };
      await MetadataCache.instance.prune(existing);
      await MetadataCache.instance.flush();
    } catch (e) {
      errors.add('Error general: $e');
      debugPrint('MediaScanner.scan error: $e');
    } finally {
      _scanning = false;
    }

    songs.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    podcasts.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    debugPrint(
      'MediaScanner: ${songs.length} canciones, ${podcasts.length} podcasts',
    );
    return ScanResult(songs: songs, podcasts: podcasts, errors: errors);
  }

  Future<void> _scanDirs({
    required List<String> dirs,
    required MediaKind kind,
    required List<Song> out,
    required List<String> errors,
  }) async {
    for (final path in dirs) {
      try {
        final dir = Directory(path);
        if (!await dir.exists()) {
          errors.add('No existe: $path');
          continue;
        }
        await _walk(dir, kind, out, errors);
      } catch (e) {
        errors.add('Error en $path: $e');
      }
    }
  }

  Future<void> _walk(
    Directory dir,
    MediaKind kind,
    List<Song> out,
    List<String> errors,
  ) async {
    final cache = MetadataCache.instance;
    final coversDir = await cache.coversDir();

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
          final stat = await entity.stat();
          final cached = await cache.get(entity.path);

          String title = '';
          String artist = '';
          String album = '';
          Duration duration = Duration.zero;
          String? coverPath;

          // ── Cache hit válido ──
          if (cached != null && cached.matchesFile(stat)) {
            title = cached.title;
            artist = cached.artist;
            album = cached.album;
            duration = cached.duration;
            coverPath = cached.coverPath;

            // Si la carátula desapareció del disco, invalidamos para reextraer.
            if (coverPath != null && !await File(coverPath).exists()) {
              coverPath = null;
            }
          }

          // ── Cache miss, o falta título / carátula ──
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

          out.add(
            Song(
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
            ),
          );
        } catch (e) {
          // Archivo ilegible, seguir.
          debugPrint('No se pudo leer ${entity.path}: $e');
        }
      }
    } catch (e) {
      errors.add('Error recorriendo ${dir.path}: $e');
    }
  }

  /// "01 - Blinding Lights" -> "Blinding Lights"
  String _cleanTitle(String raw) {
    var s = raw.replaceAll('_', ' ').trim();
    s = s.replaceFirst(RegExp(r'^\d{1,3}[\s\-\.]+'), '');
    return s.isEmpty ? raw : s;
  }
}

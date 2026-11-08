import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/song.dart';
import 'settings_service.dart'; // ajusta la ruta si tu archivo se llama distinto

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
  /// Devuelve canciones y podcasts separados por directorio de origen.
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
    } catch (e) {
      errors.add('Error general: $e');
      debugPrint('MediaScanner.scan error: $e');
    } finally {
      _scanning = false;
    }

    // Orden por título para presentación estable.
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
          final base = p.basenameWithoutExtension(entity.path);
          out.add(
            Song(
              path: entity.path,
              fileName: p.basename(entity.path),
              title: _cleanTitle(base),
              artist: '',
              album: '',
              extension: ext,
              sizeBytes: stat.size,
              modified: stat.modified,
              kind: kind,
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
    // Quita prefijo numérico tipo "01 ", "01- ", "01. "
    s = s.replaceFirst(RegExp(r'^\d{1,3}[\s\-\.]+'), '');
    return s.isEmpty ? raw : s;
  }
}

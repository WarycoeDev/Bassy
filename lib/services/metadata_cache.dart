import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'settings_service.dart'; // reutilizamos la resolución de carpeta

/// Metadatos persistidos por pista. `mtimeMs` + `sizeBytes` permiten
/// invalidar la entrada cuando el archivo cambia sin releer tags.
class CachedMetadata {
  final String path;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? coverPath; // ruta absoluta al jpg extraído, o null
  final int sizeBytes;
  final int mtimeMs;

  const CachedMetadata({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.coverPath,
    required this.sizeBytes,
    required this.mtimeMs,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': duration.inMilliseconds,
    'coverPath': coverPath,
    'sizeBytes': sizeBytes,
    'mtimeMs': mtimeMs,
  };

  factory CachedMetadata.fromJson(Map<String, dynamic> j) => CachedMetadata(
    path: j['path'] as String,
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    album: j['album'] as String? ?? '',
    duration: Duration(milliseconds: (j['durationMs'] as num?)?.toInt() ?? 0),
    coverPath: j['coverPath'] as String?,
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    mtimeMs: (j['mtimeMs'] as num?)?.toInt() ?? 0,
  );

  bool matchesFile(FileStat stat) =>
      sizeBytes == stat.size && mtimeMs == stat.modified.millisecondsSinceEpoch;
}

class MetadataCache {
  MetadataCache._();
  static final MetadataCache instance = MetadataCache._();

  static const _fileName = 'metadata_cache.json';
  static const _coversDir = 'covers';

  File? _file;
  Directory? _covers;
  Map<String, CachedMetadata>? _map;
  bool _dirty = false;

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    // Reutilizamos la misma carpeta que settings.json.
    final settingsFile = await SettingsService.instance.filePath;
    final dir = Directory(p.dirname(settingsFile));
    await dir.create(recursive: true);
    _covers = Directory(p.join(dir.path, _coversDir));
    await _covers!.create(recursive: true);
    _file = File(p.join(dir.path, _fileName));
    return _file!;
  }

  Future<Directory> coversDir() async {
    await _resolveFile();
    return _covers!;
  }

  Future<void> _ensureLoaded() async {
    if (_map != null) return;
    final file = await _resolveFile();
    if (!await file.exists()) {
      _map = {};
      return;
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _map = {};
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _map = decoded.map(
        (k, v) =>
            MapEntry(k, CachedMetadata.fromJson(v as Map<String, dynamic>)),
      );
    } catch (e) {
      debugPrint('MetadataCache: load error $e');
      _map = {};
    }
  }

  Future<CachedMetadata?> get(String path) async {
    await _ensureLoaded();
    return _map![path];
  }

  Future<void> put(CachedMetadata meta) async {
    await _ensureLoaded();
    _map![meta.path] = meta;
    _dirty = true;
  }

  /// Guarda si hubo cambios. Llamar al final del escaneo.
  Future<void> flush() async {
    if (!_dirty) return;
    await _ensureLoaded();
    try {
      final file = await _resolveFile();
      final json = _map!.map((k, v) => MapEntry(k, v.toJson()));
      const enc = JsonEncoder.withIndent('  ');
      await file.writeAsString(enc.convert(json), flush: true);
      _dirty = false;
    } catch (e) {
      debugPrint('MetadataCache: flush error $e');
    }
  }

  /// Elimina entradas cuyo archivo ya no exista (limpieza opcional).
  Future<void> prune(Set<String> existingPaths) async {
    await _ensureLoaded();
    final before = _map!.length;
    _map!.removeWhere((k, _) => !existingPaths.contains(k));
    if (_map!.length != before) _dirty = true;
  }

  /// Nombre de archivo de carátula determinista por ruta de pista + album.
  String coverFileName(String trackPath, String albumKey) {
    final h = sha1.convert(utf8.encode('$trackPath|$albumKey')).toString();
    return '$h.jpg';
  }
}

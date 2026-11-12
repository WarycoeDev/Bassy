import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'media_scanner.dart' show MediaKind, ScanResult;

/// Persiste el último `ScanResult` (lista de canciones + podcasts) en disco
/// para que la app pueda listar la biblioteca al instante sin escanear.
///
/// NO sustituye a `MetadataCache`:
///  - `MetadataCache` cachea **tags por archivo** (título, artista, carátula…).
///  - `ScanResultCache` cachea **la lista de archivos que existían** en el
///    último escaneo.
///
/// Ubicación del archivo (misma lógica que `SettingsService`):
///  - Android: `/storage/emulated/0/Android/data/<appId>/files/scan_result.json`
///             (vía `getExternalStorageDirectory()`; fallback a
///              `getApplicationSupportDirectory()` si el externo no existe).
///  - Linux:   `~/.local/share/<app>/scan_result.json`
///  - Windows: `%APPDATA%\<app>\scan_result.json`
///  - macOS:   `~/Library/Application Support/<app>/scan_result.json`
class ScanResultCache {
  ScanResultCache._();
  static final ScanResultCache instance = ScanResultCache._();

  static const _fileName = 'scan_result.json';

  File? _file;

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;

    Directory dir;
    if (!kIsWeb && Platform.isAndroid) {
      // Android: /storage/emulated/0/Android/data/<appId>/files/scan_result.json
      // getExternalStorageDirectory() apunta justo a esa carpeta "files".
      // Mismo criterio que SettingsService para que ambos archivos
      // vivan juntos.
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        dir = ext;
      } else {
        // Fallback si el almacenamiento externo no está disponible.
        dir = await getApplicationSupportDirectory();
      }
    } else {
      // PC / desktop: carpeta de soporte de la app.
      dir = await getApplicationSupportDirectory();
    }

    await dir.create(recursive: true);
    _file = File(p.join(dir.path, _fileName));
    return _file!;
  }

  /// Ruta pública del archivo (útil para debug / ajustes).
  Future<String> get filePath async => (await _resolveFile()).path;

  Future<ScanResult?> load() async {
    try {
      final f = await _resolveFile();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _fromJson(map);
    } catch (e) {
      debugPrint('ScanResultCache: load error $e');
      return null;
    }
  }

  Future<void> save(ScanResult result) async {
    try {
      final f = await _resolveFile();
      final json = _toJson(result);
      // Escritura atómica: escribe a .tmp y renombra.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(json), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('ScanResultCache: save error $e');
    }
  }

  Future<void> clear() async {
    try {
      final f = await _resolveFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Serialización
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _toJson(ScanResult r) => {
        'version': 1,
        'songs': r.songs.map(_songToJson).toList(growable: false),
        'podcasts': r.podcasts.map(_songToJson).toList(growable: false),
        'errors': r.errors,
      };

  ScanResult _fromJson(Map<String, dynamic> m) {
    final songs = (m['songs'] as List? ?? const [])
        .map((e) => _songFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final podcasts = (m['podcasts'] as List? ?? const [])
        .map((e) => _songFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final errors =
        (m['errors'] as List? ?? const []).map((e) => '$e').toList();
    return ScanResult(songs: songs, podcasts: podcasts, errors: errors);
  }

  Map<String, dynamic> _songToJson(Song s) => {
        'path': s.path,
        'fileName': s.fileName,
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'extension': s.extension,
        'sizeBytes': s.sizeBytes,
        'modifiedMs': s.modified.millisecondsSinceEpoch,
        'kind': s.kind.name,
        'durationMs': s.duration.inMilliseconds,
        'coverPath': s.coverPath,
      };

  Song _songFromJson(Map<String, dynamic> m) => Song(
        path: m['path'] as String,
        fileName: m['fileName'] as String? ?? '',
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        album: m['album'] as String? ?? '',
        extension: m['extension'] as String? ?? '',
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        modified: DateTime.fromMillisecondsSinceEpoch(
          (m['modifiedMs'] as num?)?.toInt() ?? 0,
        ),
        kind: MediaKind.values.firstWhere(
          (e) => e.name == m['kind'],
          orElse: () => MediaKind.music,
        ),
        duration: Duration(
          milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0,
        ),
        coverPath: m['coverPath'] as String?,
      );
}
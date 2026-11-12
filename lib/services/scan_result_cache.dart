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

  // ---------------------------------------------------------------------------
  // Serialización de escrituras
  //
  // `save()` se llama desde varios sitios (watcher, verify, escaneo) con
  // `unawaited`. Sin serializar, dos escrituras concurrentes al mismo
  // `.tmp` producen JSON entrelazado/corrupto (visto en Linux).
  //
  // Estrategia: si ya hay un save en vuelo, marcamos `_saveQueued` y
  // salimos. Cuando el save actual termina, si hubo cola, vuelve a
  // guardar el estado más reciente (no hace falta guardar cada
  // intermedio: siempre queremos el último).
  // ---------------------------------------------------------------------------
  bool _saving = false;
  bool _saveQueued = false;

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
    debugPrint('ScanResultCache: archivo → ${_file!.path}');
    return _file!;
  }

  /// Ruta pública del archivo (útil para debug / ajustes).
  Future<String> get filePath async => (await _resolveFile()).path;

  Future<ScanResult?> load() async {
    try {
      final f = await _resolveFile();
      if (!await f.exists()) {
        debugPrint('ScanResultCache: no existe ${f.path}');
        return null;
      }
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) {
        debugPrint('ScanResultCache: archivo vacío ${f.path}');
        return null;
      }

      Map<String, dynamic> map;
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException catch (e) {
        // JSON corrupto (p. ej. por escrituras concurrentes previas al
        // fix). Lo borramos para que el próximo save() parta limpio y
        // no volvamos a fallar en cada arranque.
        debugPrint(
          'ScanResultCache: JSON corrupto en ${f.path} ($e). '
          'Borrando archivo y continuando sin caché.',
        );
        try {
          await f.delete();
        } catch (_) {}
        return null;
      }

      final result = _fromJson(map);
      debugPrint(
        'ScanResultCache: cargado ${result.songs.length} songs + '
        '${result.podcasts.length} podcasts desde ${f.path}',
      );
      return result;
    } catch (e, st) {
      debugPrint('ScanResultCache: load error $e\n$st');
      return null;
    }
  }

  Future<void> save(ScanResult result) async {
    // Si ya hay una escritura en vuelo, no la duplicamos: marcamos
    // cola y salimos. Al terminar la actual, se re-guarda el estado
    // más reciente (que es lo que queremos; los intermedios no
    // aportan nada).
    if (_saving) {
      _saveQueued = true;
      return;
    }

    _saving = true;
    try {
      do {
        _saveQueued = false;
        await _writeAtomic(result);
      } while (_saveQueued);
    } finally {
      _saving = false;
    }
  }

  Future<void> _writeAtomic(ScanResult result) async {
    try {
      final f = await _resolveFile();
      final json = _toJson(result);

      // Escritura atómica: escribe a .tmp y renombra.
      // `writeAsString` trunca por defecto (FileMode.write), pero lo
      // dejamos explícito para que no queden restos si el archivo
      // existía de una escritura anterior más grande.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(json),
        mode: FileMode.write,
        flush: true,
      );
      await tmp.rename(f.path);

      debugPrint(
        'ScanResultCache: guardado ${result.songs.length} songs + '
        '${result.podcasts.length} podcasts en ${f.path}',
      );
    } catch (e, st) {
      debugPrint('ScanResultCache: save error $e\n$st');
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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Modelo con todas las opciones persistibles de la pantalla de ajustes.
class AppSettings {
  // ReplayGain
  bool replayGainEnabled;

  // Reproducción
  double volumeBoost; // dB, -12 .. +12
  bool transitionsEnabled;
  int transitionMode; // 0 = Crossfade, 1 = Fade In/Out
  double crossfadeSeconds; // 0 .. 12
  double fadeSeconds; // 0 .. 12

  // Almacenamiento
  List<String> musicDirs;
  List<String> podcastDirs;

  AppSettings({
    this.replayGainEnabled = true,
    this.volumeBoost = 0.0,
    this.transitionsEnabled = true,
    this.transitionMode = 0,
    this.crossfadeSeconds = 4.0,
    this.fadeSeconds = 3.0,
    List<String>? musicDirs,
    List<String>? podcastDirs,
  }) : musicDirs = musicDirs ?? ['/storage/emulated/0/Music'],
       podcastDirs = podcastDirs ?? ['/storage/emulated/0/Podcasts'];

  Map<String, dynamic> toJson() => {
    'replayGainEnabled': replayGainEnabled,
    'volumeBoost': volumeBoost,
    'transitionsEnabled': transitionsEnabled,
    'transitionMode': transitionMode,
    'crossfadeSeconds': crossfadeSeconds,
    'fadeSeconds': fadeSeconds,
    'musicDirs': musicDirs,
    'podcastDirs': podcastDirs,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    replayGainEnabled: json['replayGainEnabled'] as bool? ?? true,
    volumeBoost: (json['volumeBoost'] as num?)?.toDouble() ?? 0.0,
    transitionsEnabled: json['transitionsEnabled'] as bool? ?? true,
    transitionMode: (json['transitionMode'] as num?)?.toInt() ?? 0,
    crossfadeSeconds: (json['crossfadeSeconds'] as num?)?.toDouble() ?? 4.0,
    fadeSeconds: (json['fadeSeconds'] as num?)?.toDouble() ?? 3.0,
    musicDirs:
        (json['musicDirs'] as List?)?.map((e) => e.toString()).toList() ??
        ['/storage/emulated/0/Music'],
    podcastDirs:
        (json['podcastDirs'] as List?)?.map((e) => e.toString()).toList() ??
        ['/storage/emulated/0/Podcasts'],
  );
}

/// Servicio singleton que lee/escribe el JSON en disco.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _fileName = 'settings.json';
  static const _androidAppId = 'com.example.bassy';

  File? _cachedFile;
  Map<String, dynamic>? _cache;

  /// Devuelve el archivo donde se persisten los ajustes.
  Future<File> _resolveFile() async {
    if (_cachedFile != null) return _cachedFile!;

    Directory dir;
    if (!kIsWeb && Platform.isAndroid) {
      // Android: /storage/emulated/0/Android/data/<appId>/files/settings.json
      // getExternalStorageDirectory() apunta justo a esa carpeta "files".
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        dir = ext;
      } else {
        // Fallback si el almacenamiento externo no está disponible.
        dir = await getApplicationSupportDirectory();
      }
    } else {
      // PC / desktop: carpeta de documentos de la app.
      dir = await getApplicationSupportDirectory();
    }

    await dir.create(recursive: true);
    _cachedFile = File(p.join(dir.path, _fileName));
    return _cachedFile!;
  }

  /// Ruta legible (útil para mostrar en "Acerca de" o depurar).
  Future<String> get filePath async => (await _resolveFile()).path;

  /// Carga los ajustes. Si no existe el archivo o está corrupto,
  /// devuelve los valores por defecto.
  Future<AppSettings> load() async {
    try {
      if (_cache != null) {
        return AppSettings.fromJson(_cache!);
      }
      final file = await _resolveFile();
      if (!await file.exists()) {
        return AppSettings();
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return AppSettings();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = decoded;
      return AppSettings.fromJson(decoded);
    } catch (e) {
      debugPrint('SettingsService.load error: $e');
      return AppSettings();
    }
  }

  /// Guarda los ajustes en disco (sobrescribe el archivo).
  Future<void> save(AppSettings settings) async {
    try {
      final file = await _resolveFile();
      final json = settings.toJson();
      _cache = json;
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(json), flush: true);
    } catch (e) {
      debugPrint('SettingsService.save error: $e');
    }
  }
}

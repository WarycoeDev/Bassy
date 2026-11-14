// lib/models/replay_gain_data.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Valores ReplayGain de una pista.
class ReplayGainEntry {
  /// Ganancia en dB (típicamente -18..+18).
  final double trackGain;

  /// Peak lineal (0.0..~1.5).
  final double trackPeak;

  /// dB del loudness integrado (LUFS). Útil para mostrar.
  final double integratedLufs;

  /// Cuándo se analizó (para invalidar si cambia el archivo).
  final DateTime analyzedAt;

  const ReplayGainEntry({
    required this.trackGain,
    required this.trackPeak,
    required this.integratedLufs,
    required this.analyzedAt,
  });

  Map<String, dynamic> toJson() => {
        'trackGain': trackGain,
        'trackPeak': trackPeak,
        'integratedLufs': integratedLufs,
        'analyzedAt': analyzedAt.toIso8601String(),
      };

  factory ReplayGainEntry.fromJson(Map<String, dynamic> json) => ReplayGainEntry(
        trackGain: (json['trackGain'] as num).toDouble(),
        trackPeak: (json['trackPeak'] as num).toDouble(),
        integratedLufs: (json['integratedLufs'] as num?)?.toDouble() ?? -70.0,
        analyzedAt:
            DateTime.tryParse(json['analyzedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Almacén persistente de valores ReplayGain indexado por path de archivo.
class ReplayGainStore {
  ReplayGainStore._();
  static final ReplayGainStore instance = ReplayGainStore._();

  static const _fileName = 'replaygain.json';

  File? _cachedFile;
  Map<String, ReplayGainEntry>? _cache;
  Future<void>? _loading;

  Future<File> _resolveFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _cachedFile = File(p.join(dir.path, _fileName));
    return _cachedFile!;
  }

  Future<void> _ensureLoaded() {
    if (_cache != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        _cache = {};
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cache = {};
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = decoded.map(
        (k, v) => MapEntry(k, ReplayGainEntry.fromJson(v as Map<String, dynamic>)),
      );
    } catch (e) {
      debugPrint('ReplayGainStore._load error: $e');
      _cache = {};
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _resolveFile();
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(
        encoder.convert(
          _cache!.map((k, v) => MapEntry(k, v.toJson())),
        ),
        flush: true,
      );
    } catch (e) {
      debugPrint('ReplayGainStore._persist error: $e');
    }
  }

  /// Devuelve el entry para [path] o null si no existe.
  Future<ReplayGainEntry?> get(String path) async {
    await _ensureLoaded();
    return _cache![path];
  }

  /// Devuelve el entry síncrono (asume cache cargado).
  ReplayGainEntry? getSync(String path) => _cache?[path];

  Future<void> put(String path, ReplayGainEntry entry) async {
    await _ensureLoaded();
    _cache![path] = entry;
    await _persist();
  }

  Future<void> putAll(Map<String, ReplayGainEntry> entries) async {
    await _ensureLoaded();
    _cache!.addAll(entries);
    await _persist();
  }

  Future<void> remove(String path) async {
    await _ensureLoaded();
    if (_cache!.remove(path) != null) await _persist();
  }

  /// Borra todos los registros.
  Future<void> clear() async {
    await _ensureLoaded();
    _cache!.clear();
    await _persist();
  }

  Future<int> count() async {
    await _ensureLoaded();
    return _cache!.length;
  }

  Future<void> ensureLoaded() => _ensureLoaded();

  Set<String> get allPaths => _cache?.keys.toSet() ?? <String>{};
}
// lib/services/replay_gain_analyzer.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/replay_gain_data.dart';
import '../models/song.dart';

/// Analizador de ReplayGain.
///
/// Implementación de referencia (placeholder): estima loudness a partir
/// de tamaño/duración/bitrate. Para producción, sustituir `_analyzeFile`
/// por una llamada a ffmpeg con el filtro `ebur128`, o por una librería
/// nativa tipo `replaygain`.
class ReplayGainAnalyzer {
  ReplayGainAnalyzer._();
  static final ReplayGainAnalyzer instance = ReplayGainAnalyzer._();

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<ReplayGainEntry> analyze(Song song) async {
    final path = song.path;
    if (path == null || path.isEmpty) {
      throw StateError('Song sin path');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Archivo no encontrado: $path');
    }
    return _analyzeFile(file, song);
  }

  /// Analiza un lote con progreso. `onProgress(hechas, total)`.
  Future<Map<String, ReplayGainEntry>> analyzeBatch(
    List<Song> songs, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _cancelled = false;
    final out = <String, ReplayGainEntry>{};
    final total = songs.length;
    var done = 0;
    for (final song in songs) {
      if (_cancelled || (isCancelled?.call() ?? false)) break;
      final path = song.path;
      if (path == null || path.isEmpty) {
        done++;
        onProgress?.call(done, total);
        continue;
      }
      try {
        final entry = await analyze(song);
        out[path] = entry;
      } catch (e) {
        debugPrint('ReplayGainAnalyzer: fallo en $path -> $e');
      }
      done++;
      onProgress?.call(done, total);
    }
    return out;
  }

  /// --- PLACEHOLDER ---
  /// Estima loudness a partir del tamaño/duración/bitrate.
  /// Reemplazar por análisis real (ffmpeg/ebur128) en producción.
  Future<ReplayGainEntry> _analyzeFile(File file, Song song) async {
    final size = await file.length();
    final durationMs = song.duration?.inMilliseconds ?? 0;
    final durationSec = math.max(1.0, durationMs / 1000.0);

    // Bitrate medio aproximado (kbps).
    final kbps = (size * 8) / (durationSec * 1000);
    // Heurística: pistas más "pesadas" → más loudness típico.
    // Rango típico de loudness integrado: -30 .. -6 LUFS.
    final normalized = (kbps / 320).clamp(0.0, 1.0);
    final integratedLufs = -30.0 + normalized * 24.0; // -30 .. -6

    // Ganancia para llevar a -18 LUFS (objetivo ReplayGain estándar).
    const targetLufs = -18.0;
    final trackGain = (targetLufs - integratedLufs).clamp(-18.0, 18.0);

    // Peak "estimado": cuanto más fuerte, más cerca de 1.0.
    final peak = (0.7 + normalized * 0.3).clamp(0.0, 1.5);

    return ReplayGainEntry(
      trackGain: trackGain,
      trackPeak: peak,
      integratedLufs: integratedLufs,
      analyzedAt: DateTime.now(),
    );
  }
}
// lib/services/replay_gain_analyzer.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as sl;

import '../models/replay_gain_data.dart';
import '../models/song.dart';
import 'playback_controller.dart';

/// Analizador de ReplayGain.
///
/// Mide el nivel real (≈ RMS) del audio leyendo las muestras del archivo
/// con flutter_soloud y calcula la ganancia necesaria para llevar la pista
/// a un nivel objetivo común.
class ReplayGainAnalyzer {
  ReplayGainAnalyzer._();
  static final ReplayGainAnalyzer instance = ReplayGainAnalyzer._();

  /// Nivel objetivo común para todas las pistas (dBFS RMS).
  static const double _targetDb = -16.0;

  /// Muestras por canal que se leen del archivo para estimar el nivel.
  static const int _samplesToRead = 16000;

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

  Future<void> _ensureEngine() async {
    final soloud = sl.SoLoud.instance;
    if (soloud.isInitialized) return;
    try {
      if (PlaybackController.instance.isReady) {
        await PlaybackController.instance.handler.ensureEngine();
      } else {
        await soloud.init();
      }
    } catch (_) {
      if (!soloud.isInitialized) rethrow;
    }
  }

  /// Mide el nivel real de la pista.
  ///
  /// NOTA: `readSamplesFromFile` es la API de flutter_soloud ≥ 3.2 para
  /// leer muestras de un archivo. Si tu versión la expone con otra firma,
  /// solo hay que ajustar esas dos llamadas; el resto del cálculo no
  /// depende de ella.
  Future<ReplayGainEntry> _analyzeFile(File file, Song song) async {
    await _ensureEngine();
    final soloud = sl.SoLoud.instance;

    // Promedio de |muestra| por tramo (≈ nivel RMS) y picos por tramo.
    final avg = await soloud.readSamplesFromFile(
      file.path,
      _samplesToRead,
      average: true,
    );
    final pk = await soloud.readSamplesFromFile(file.path, _samplesToRead);

    double sumSq = 0;
    int n = 0;
    for (final v in avg) {
      final a = v.abs();
      if (a > 0.001) {
        // Puerta de silencio: -60 dBFS.
        sumSq += a * a;
        n++;
      }
    }
    if (n == 0) throw StateError('Pista silenciosa o ilegible');

    var peak = 0.0;
    for (final v in pk) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    peak = peak.clamp(0.05, 1.5).toDouble();

    // mean|x| ≈ 0.8 · RMS  →  RMS ≈ mean · 1.25
    final rms = math.sqrt(sumSq / n) * 1.25;
    final rmsDb = 20 * math.log(rms) / math.ln10;

    final trackGain = (_targetDb - rmsDb).clamp(-18.0, 6.0).toDouble();

    return ReplayGainEntry(
      trackGain: trackGain,
      trackPeak: peak,
      integratedLufs: rmsDb,
      analyzedAt: DateTime.now(),
    );
  }
}
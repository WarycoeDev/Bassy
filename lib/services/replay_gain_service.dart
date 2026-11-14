// lib/services/replay_gain_service.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/replay_gain_data.dart';
import '../models/song.dart';
import 'replay_gain_analyzer.dart';

enum ReplayGainTask { idle, analyzing, clearing }

class ReplayGainService extends ChangeNotifier {
  ReplayGainService._() {
    // Propaga cambios de los ValueNotifier como notificaciones del servicio.
    enabled.addListener(_forward);
    task.addListener(_forward);
    progress.addListener(_forward);
    analyzedCount.addListener(_forward);
    activeGainDb.addListener(_forward);
  }

  static final ReplayGainService instance = ReplayGainService._();

  final ReplayGainStore _store = ReplayGainStore.instance;
  final ReplayGainAnalyzer _analyzer = ReplayGainAnalyzer.instance;

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<ReplayGainTask> task =
      ValueNotifier<ReplayGainTask>(ReplayGainTask.idle);
  final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
  final ValueNotifier<int> analyzedCount = ValueNotifier<int>(0);
  final ValueNotifier<double> activeGainDb = ValueNotifier<double>(0.0);

  bool _analyzing = false;
  bool _clearing = false;
  String? _currentSongPath;

  void _forward() => notifyListeners();

  Future<void> init({required bool enabledInitially}) async {
    enabled.value = enabledInitially;
    await _store.ensureLoaded();
    analyzedCount.value = await _store.count();
    _recomputeActiveGain(_currentSongPath);
  }

  void setEnabled(bool value) {
    enabled.value = value;
    _recomputeActiveGain(_currentSongPath);
  }

  void notifyCurrentSong(String? path) {
    _currentSongPath = path;
    _recomputeActiveGain(path);
  }

  void _recomputeActiveGain(String? path) {
    if (!enabled.value || path == null) {
      activeGainDb.value = 0.0;
      return;
    }
    final entry = _store.getSync(path);
    if (entry == null) {
      activeGainDb.value = 0.0;
      return;
    }
    var gain = entry.trackGain;
    if (entry.trackPeak > 0) {
      final maxGainWithoutClip =
          -20 * (math.log(entry.trackPeak) / math.ln10);
      if (gain > maxGainWithoutClip) gain = maxGainWithoutClip;
    }
    activeGainDb.value = gain.clamp(-18.0, 18.0);
  }

  Future<void> analyzeMissing(List<Song> songs) =>
      _runAnalysis(songs, onlyMissing: true);

  Future<void> analyzeAll(List<Song> songs) =>
      _runAnalysis(songs, onlyMissing: false);

  Future<void> _runAnalysis(
    List<Song> songs, {
    required bool onlyMissing,
  }) async {
    if (_analyzing) return;
    _analyzing = true;
    task.value = ReplayGainTask.analyzing;
    progress.value = 0.0;
    _analyzer.cancel();

    try {
      await _store.ensureLoaded();
      final targets = onlyMissing
          ? songs.where((s) {
              final p = s.path;
              return p != null && !_store.allPaths.contains(p);
            }).toList()
          : songs;

      if (targets.isEmpty) {
        progress.value = 1.0;
        analyzedCount.value = await _store.count();
        return;
      }

      final result = await _analyzer.analyzeBatch(
        targets,
        onProgress: (done, t) => progress.value = done / t,
        isCancelled: () => !_analyzing,
      );

      await _store.putAll(result);
      analyzedCount.value = await _store.count();
      _recomputeActiveGain(_currentSongPath);
    } finally {
      _analyzing = false;
      task.value = ReplayGainTask.idle;
      progress.value = 1.0;
    }
  }

  void cancelAnalysis() {
    if (!_analyzing) return;
    _analyzing = false;
    _analyzer.cancel();
  }

  Future<void> clearAll() async {
    if (_clearing) return;
    _clearing = true;
    task.value = ReplayGainTask.clearing;
    try {
      await _store.clear();
      analyzedCount.value = 0;
      _recomputeActiveGain(_currentSongPath);
    } finally {
      _clearing = false;
      task.value = ReplayGainTask.idle;
    }
  }

  bool hasEntryFor(String? path) =>
      path != null && _store.getSync(path) != null;

  double gainFor(String? path) {
    if (!enabled.value || path == null) return 0.0;
    return _store.getSync(path)?.trackGain ?? 0.0;
  }

  @override
  void dispose() {
    enabled.removeListener(_forward);
    task.removeListener(_forward);
    progress.removeListener(_forward);
    analyzedCount.removeListener(_forward);
    activeGainDb.removeListener(_forward);
    super.dispose();
  }
}
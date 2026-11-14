// lib/services/reverb_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reverb global sobre el filtro freeverb de SoLoud.
/// Funciona igual en Android, Windows, Linux, macOS e iOS.
class ReverbService {
  ReverbService._();
  static final ReverbService instance = ReverbService._();

  static const _prefKey = 'reverb_level';

  /// Nivel 0..1 (0 = apagado).
  final ValueNotifier<double> level = ValueNotifier<double>(0.0);

  bool _active = false;

  bool get isSupported => !kIsWeb;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      level.value = (prefs.getDouble(_prefKey) ?? 0.0).clamp(0.0, 1.0);
    } catch (_) {}
    applyToEngine();
  }

  Future<void> setLevel(double v) async {
    level.value = v.clamp(0.0, 1.0).toDouble();
    applyToEngine();
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKey, level.value);
    } catch (_) {}
  }

  /// Aplica el nivel actual al motor. Si SoLoud aún no está inicializado
  /// no hace nada: el handler lo vuelve a llamar justo después del init.
  void applyToEngine() {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      _active = false;
      return;
    }

    final amount = level.value;
    try {
      final reverb = soloud.filters.freeverbFilter;

      if (amount <= 0.001) {
        if (_active) {
          reverb.deactivate();
          _active = false;
        }
        return;
      }

      if (!_active) {
        reverb.activate();
        _active = true;
      }

      // amount 0..1 → mezcla húmeda 10-55 % y sala mediana-grande.
      reverb.wet.value = 0.10 + amount * 0.45;
      reverb.roomSize.value = 0.60 + amount * 0.35;
      reverb.width.value = 1.0;
    } catch (e) {
      debugPrint('ReverbService: no se pudo aplicar el reverb -> $e');
    }
  }
}
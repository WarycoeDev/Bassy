import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionResult {
  final bool granted;
  final bool permanentlyDenied;

  const PermissionResult({
    required this.granted,
    this.permanentlyDenied = false,
  });
}

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  /// Pide todos los permisos necesarios para escanear audio.
  /// Devuelve `granted=true` solo si el acceso a archivos está concedido.
  Future<PermissionResult> requestStoragePermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const PermissionResult(granted: true);
    }

    // 1) MANAGE_EXTERNAL_STORAGE (Android 11+)
    //    Si ya está concedido, no volvemos a pedirlo.
    var manage = await Permission.manageExternalStorage.status;
    if (!manage.isGranted) {
      manage = await Permission.manageExternalStorage.request();
    }

    // 2) READ_MEDIA_AUDIO (Android 13+) y READ_EXTERNAL_STORAGE (<=12)
    //    Pedimos los dos; el sistema ignora el que no aplique a la versión.
    final audio = await Permission.audio.status;
    if (!audio.isGranted) {
      await Permission.audio.request();
    }

    // Releemos el estado real después de los diálogos.
    final manageAfter = await Permission.manageExternalStorage.status;
    final audioAfter = await Permission.audio.status;
    final storageAfter = await Permission.storage.status;

    // Basta con MANAGE_EXTERNAL_STORAGE o (audio/storage).
    final granted =
        manageAfter.isGranted || audioAfter.isGranted || storageAfter.isGranted;

    final permanentlyDenied =
        manageAfter.isPermanentlyDenied ||
        (audioAfter.isPermanentlyDenied && storageAfter.isPermanentlyDenied);

    debugPrint(
      'PermissionService → granted=$granted '
      'manage=${manageAfter.isGranted} '
      'audio=${audioAfter.isGranted} '
      'storage=${storageAfter.isGranted}',
    );

    return PermissionResult(
      granted: granted,
      permanentlyDenied: permanentlyDenied,
    );
  }

  /// Abre la pantalla de ajustes de la app (para permisos denegados permanentemente).
  Future<void> openAppSettingsPage() => openAppSettings();
}

import 'package:flutter/material.dart';

import '../services/permission_service.dart';

class PermissionGate extends StatefulWidget {
  final Widget child;

  const PermissionGate({super.key, required this.child});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _checking = true;
  bool _granted = false;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (mounted) {
      setState(() {
        _checking = true;
      });
    }

    final result = await PermissionService.instance.requestStoragePermissions();
    if (!mounted) return;

    setState(() {
      _granted = result.granted;
      _permanentlyDenied = result.permanentlyDenied;
      _checking = false;
    });
  }

  Future<void> _openSettings() async {
    await PermissionService.instance.openAppSettingsPage();
    // Al volver de ajustes, revalidamos.
    if (!mounted) return;
    _check();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_checking) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Comprobando permisos…',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_granted) return widget.child;

    // Permiso denegado
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.folder_off_outlined,
                size: 72,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 20),
              Text(
                'Necesitamos acceso a tus archivos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _permanentlyDenied
                    ? 'Has denegado el permiso permanentemente. '
                          'Ábrelo en los ajustes del sistema para que Bassy '
                          'pueda escanear tu música y podcasts.'
                    : 'Bassy necesita leer tus archivos de audio para '
                          'mostrar tu biblioteca. Concede el permiso para continuar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              if (_permanentlyDenied)
                FilledButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Abrir ajustes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _check,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Conceder permiso'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _check,
                child: Text(
                  'Reintentar',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

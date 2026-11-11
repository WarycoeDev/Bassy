import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app/app_shell.dart';
import 'services/media_scanner.dart';
import 'services/settings_service.dart';
import 'widgets/permission_gate.dart';
import 'package:audio_session/audio_session.dart';
import 'services/playback_controller.dart';

class _LifecycleRescanObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (kIsWeb) return;
    // Solo desktop: en Android/iOS el watcher nativo ya maneja los cambios.
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    unawaited(MediaScanner.instance.rescanNow());
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX #1: just_audio_media_kit SOLO en desktop.
  // En Android carga libmpv y buffers nativos innecesarios que inflan
  // el heap Java desde el arranque (causa del OOM sin escanear).
  if (!kIsWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    JustAudioMediaKit.ensureInitialized(
      linux: true,
      windows: true,
    );
  }

  // 1) Configuración de sesión de audio (foco, bluetooth, etc.)
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // 2) Arranca audio_service / audio handler ANTES de runApp
  await PlaybackController.instance.init();

  WidgetsBinding.instance.addObserver(_LifecycleRescanObserver());
  runApp(const BassyApp());
}

class BassyApp extends StatefulWidget {
  const BassyApp({super.key});

  @override
  State<BassyApp> createState() => _BassyAppState();
}

class _BassyAppState extends State<BassyApp> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await SettingsService.instance.load();
    } catch (e, st) {
      debugPrint('SettingsService.load failed: $e\n$st');
    }
    // FIX #2: NO escanear automáticamente al arrancar en Android.
    // El escaneo inicial + watchers + audio_service al mismo tiempo
    // saturan el heap Java. Dejamos que la UI lo dispare cuando el
    // usuario entre a la biblioteca (o cuando PermissionGate lo permita).
    // Si prefieres el comportamiento anterior, descomenta la línea
    // y asegúrate de aplicar el fix de carátulas en media_scanner.dart.
    // unawaited(MediaScanner.instance.ensureInitialScan());
  }

  @override
  Widget build(BuildContext context) {
    const grey50 = Color(0xFF0A0A0A);
    const grey100 = Color(0xFF121212);
    const grey200 = Color(0xFF1E1E1E);
    const grey300 = Color(0xFF2A2A2A);
    const grey600 = Color(0xFF6B6B6B);
    const grey700 = Color(0xFF8A8A8A);
    const grey800 = Color(0xFFB0B0B0);
    const grey900 = Color(0xFFD6D6D6);
    const grey950 = Color(0xFFEAEAEA);

    final scheme = const ColorScheme(
      brightness: Brightness.dark,
      primary: grey950,
      onPrimary: grey50,
      primaryContainer: grey300,
      onPrimaryContainer: grey950,
      secondary: grey800,
      onSecondary: grey50,
      secondaryContainer: grey200,
      onSecondaryContainer: grey900,
      tertiary: grey700,
      onTertiary: grey50,
      surface: grey100,
      onSurface: grey950,
      surfaceContainerLowest: grey50,
      surfaceContainerLow: grey100,
      surfaceContainer: grey200,
      surfaceContainerHigh: grey300,
      surfaceContainerHighest: const Color(0xFF333333),
      onSurfaceVariant: grey700,
      outline: grey600,
      outlineVariant: grey300,
      error: Color(0xFFCF6679),
      onError: grey50,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bassy',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: scheme.surface,
          scrimColor: Colors.black54,
        ),
        dividerTheme: DividerThemeData(
          color: scheme.outlineVariant,
          thickness: 1,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      home: const PermissionGate(child: AppShell()),
    );
  }
}
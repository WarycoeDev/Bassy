import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'services/media_scanner.dart';
import 'services/settings_service.dart';
import 'widgets/permission_gate.dart';

class _LifecycleRescanObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (kIsWeb) return;
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    unawaited(MediaScanner.instance.rescanNow());
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    unawaited(MediaScanner.instance.ensureInitialScan());
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
      surfaceContainerHighest: Color(0xFF333333),
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

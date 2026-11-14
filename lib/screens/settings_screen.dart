// lib/screens/settings_screen.dart
import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:bassy/widgets/directory_picker_dialog.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/media_scanner.dart';
import '../services/replay_gain_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService.instance;
  final _rg = ReplayGainService.instance;

  AppSettings _settings = AppSettings();
  bool _loaded = false;
  Timer? _saveDebounce;

  /// Total de canciones en la biblioteca. Se refresca al cargar settings
  /// y cuando el análisis cambia el contador (por si la biblioteca creció
  /// en background mientras Settings estaba abierto).
  int _libraryTotal = 0;

  @override
  void initState() {
    super.initState();
    _rg.addListener(_onRgUpdate);
    _loadSettings();
  }

  @override
  void dispose() {
    _rg.removeListener(_onRgUpdate);
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _onRgUpdate() {
    if (!mounted) return;
    setState(() {});
    _refreshLibraryTotal();
  }

  Future<void> _loadSettings() async {
    final loaded = await _service.load();
    if (!mounted) return;
    await _rg.init(enabledInitially: loaded.replayGainEnabled);
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _loaded = true;
    });
    _refreshLibraryTotal();
  }

  void _refreshLibraryTotal() {
    final total = _allSongsForAnalysis().length;
    if (total != _libraryTotal) {
      if (mounted) {
        setState(() => _libraryTotal = total);
      } else {
        _libraryTotal = total;
      }
    }
  }

  void _persist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      _service.save(_settings);
    });
  }

  Future<void> _persistNow() async {
    _saveDebounce?.cancel();
    await _service.save(_settings);
  }

  void _update(void Function(AppSettings s) mutate) {
    setState(() => mutate(_settings));
    _persist();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Devuelve la biblioteca completa para analizar.
  /// Usa `MediaScanner.instance.allSongs` (música + podcasts).
  List<Song> _allSongsForAnalysis() {
    try {
      return List<Song>.from(MediaScanner.instance.allSongs);
    } catch (_) {
      return const <Song>[];
    }
  }

  Future<void> _addMusicDir(String path) async {
    setState(() => _settings.musicDirs.add(path));
    await _persistNow();
    _showSnack('Escaneando carpeta de música…');
    await MediaScanner.instance.onDirectoryAdded(path, MediaKind.music);
    _showSnack('Carpeta agregada');
    _refreshLibraryTotal();
  }

  Future<void> _removeMusicDir(String path) async {
    setState(() => _settings.musicDirs.remove(path));
    await _persistNow();
    await MediaScanner.instance.onDirectoryRemoved(path);
    _showSnack('Carpeta eliminada');
    _refreshLibraryTotal();
  }

  Future<void> _addPodcastDir(String path) async {
    setState(() => _settings.podcastDirs.add(path));
    await _persistNow();
    _showSnack('Escaneando carpeta de podcasts…');
    await MediaScanner.instance.onDirectoryAdded(path, MediaKind.podcast);
    _showSnack('Carpeta agregada');
    _refreshLibraryTotal();
  }

  Future<void> _removePodcastDir(String path) async {
    setState(() => _settings.podcastDirs.remove(path));
    await _persistNow();
    await MediaScanner.instance.onDirectoryRemoved(path);
    _showSnack('Carpeta eliminada');
    _refreshLibraryTotal();
  }

  // ---------------------------------------------------------------------------
  // Popup modal de progreso ReplayGain (no cancelable)
  // ---------------------------------------------------------------------------

  /// Muestra un diálogo modal sin cierre posible mientras corre la tarea
  /// de ReplayGain. Se cierra solo cuando `_rg.task` vuelve a idle.
  Future<void> _showRgProgressDialog({required bool isClearing}) async {
    if (!mounted) return;

    final scheme = Theme.of(context).colorScheme;
    final navigator = Navigator.of(context, rootNavigator: true);

    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _RgBlockingProgressDialog(
        isClearing: isClearing,
        color: isClearing ? scheme.error : scheme.primary,
      ),
    );

    final closed = navigator.push(route);

    await _waitForTaskIdle();

    if (mounted) {
      navigator.removeRoute(route);
      unawaited(closed.catchError((_) {}));
    }
  }

  /// Completa cuando `_rg.task.value == ReplayGainTask.idle`.
  Future<void> _waitForTaskIdle() async {
    if (_rg.task.value == ReplayGainTask.idle) return;
    final completer = Completer<void>();
    void listener() {
      if (_rg.task.value == ReplayGainTask.idle && !completer.isCompleted) {
        completer.complete();
      }
    }

    _rg.task.addListener(listener);
    try {
      await completer.future;
    } finally {
      _rg.task.removeListener(listener);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildHeader(context),
              const SizedBox(height: 24),

              _buildSectionTitle(context, 'Cuenta'),
              const SizedBox(height: 12),
              _buildAccountCard(context),
              const SizedBox(height: 24),

              _buildSectionTitle(context, 'ReplayGain'),
              const SizedBox(height: 12),
              _buildReplayGainGroup(context),
              const SizedBox(height: 24),

              _buildSectionTitle(context, 'Reproducción'),
              const SizedBox(height: 12),
              _buildPlaybackGroup(context),
              const SizedBox(height: 24),

              _buildSectionTitle(context, 'Almacenamiento'),
              const SizedBox(height: 12),
              _buildStorageGroup(context),
              const SizedBox(height: 24),

              _buildSectionTitle(context, 'Apariencia'),
              const SizedBox(height: 12),
              _buildSettingsGroup(context, [
                _SettingItem(
                  icon: Icons.dark_mode,
                  title: 'Tema oscuro',
                  subtitle: 'Seguir sistema',
                  trailing: Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                _SettingItem(
                  icon: Icons.language,
                  title: 'Idioma',
                  subtitle: 'Español',
                  trailing: Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ]),
              const SizedBox(height: 24),

              _buildSectionTitle(context, 'Acerca de'),
              const SizedBox(height: 12),
              _buildSettingsGroup(context, [
                _SettingItem(
                  icon: Icons.info_outline,
                  title: 'Versión',
                  subtitle: '1.0.0',
                  trailing: Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                _SettingItem(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacidad',
                  subtitle: 'Política y términos',
                  trailing: Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ]),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Personaliza tu experiencia',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        Row(
          children: [
            _buildIconButton(context, Icons.search),
            const SizedBox(width: 12),
            _buildIconButton(context, Icons.help_outline),
          ],
        ),
      ],
    );
  }

  Widget _buildIconButton(BuildContext context, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: scheme.onSurface, size: 22),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      title,
      style: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ReplayGain
  // ---------------------------------------------------------------------------

  Widget _buildReplayGainGroup(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _settings.replayGainEnabled;
    final task = _rg.task.value;
    final analyzing = task == ReplayGainTask.analyzing;
    final clearing = task == ReplayGainTask.clearing;
    final count = _rg.analyzedCount.value;
    final total = _libraryTotal;
    final analyzedDisplay = total > 0 ? '$count / $total' : '$count';
    final progress = _rg.progress.value.clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -------- Cabecera: icono + título + switch --------
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: enabled
                        ? scheme.primary.withOpacity(0.12)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ReplayGain',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          enabled
                              ? (count > 0
                                  ? '$count pista${count == 1 ? '' : 's'} analizada${count == 1 ? '' : 's'}'
                                  : 'Activado · sin pistas analizadas')
                              : 'Normaliza el volumen entre pistas',
                          key: ValueKey('$enabled-$count'),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: (v) {
                    _update((s) => s.replayGainEnabled = v);
                    _rg.setEnabled(v);
                  },
                ),
              ],
            ),
          ),

          // -------- Stat chips --------
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  _RgStatChip(
                    icon: Icons.library_music_outlined,
                    label: 'Analizadas',
                    value: analyzedDisplay,
                    highlighted: count > 0,
                  ),
                  const SizedBox(width: 8),
                  _RgStatChip(
                    icon: task == ReplayGainTask.analyzing
                        ? Icons.hourglass_top
                        : task == ReplayGainTask.clearing
                            ? Icons.delete_sweep_outlined
                            : Icons.check_circle_outline,
                    label: 'Estado',
                    value: switch (task) {
                      ReplayGainTask.analyzing =>
                        '${(progress * 100).toStringAsFixed(0)}%',
                      ReplayGainTask.clearing => 'Borrando',
                      ReplayGainTask.idle => count > 0 ? 'Listo' : 'Sin datos',
                    },
                    highlighted: task == ReplayGainTask.analyzing,
                  ),
                ],
              ),
            ),

          // -------- Fila única de acciones --------
          if (enabled) ...[
            _divider(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              child: Row(
                children: [
                  // Acción principal: Analizar
                  Expanded(
                    child: InkWell(
                      onTap: (analyzing || clearing)
                          ? null
                          : () async {
                              final songs = _allSongsForAnalysis();
                              if (songs.isEmpty) {
                                _showSnack(
                                  'No hay canciones en la biblioteca',
                                );
                                return;
                              }
                              unawaited(
                                _showRgProgressDialog(isClearing: false),
                              );
                              await _rg.analyzeMissing(songs);
                              if (!mounted) return;
                              _showSnack(
                                'Análisis completado '
                                '(${_rg.analyzedCount.value} pistas)',
                              );
                            },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: scheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.playlist_add_check_rounded,
                                color: scheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Analizar canciones',
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Pistas sin analizar',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 4),

                  // IconButton: Recalcular todo (solo si hay registros)
                  _RgIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: count == 0
                        ? 'Primero analiza algunas pistas'
                        : 'Recalcular todo',
                    color: scheme.tertiary,
                    enabled: !(analyzing || clearing) && count > 0,
                    onTap: () async {
                      final songs = _allSongsForAnalysis();
                      if (songs.isEmpty) {
                        _showSnack('No hay canciones en la biblioteca');
                        return;
                      }
                      unawaited(
                        _showRgProgressDialog(isClearing: false),
                      );
                      await _rg.analyzeAll(songs);
                      if (!mounted) return;
                      _showSnack(
                        'Recálculo completado '
                        '(${_rg.analyzedCount.value} pistas)',
                      );
                    },
                  ),

                  const SizedBox(width: 4),

                  // IconButton: Borrar registros
                  _RgIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Borrar registros',
                    color: scheme.error,
                    enabled: !(analyzing || clearing) && count > 0,
                    onTap: () async {
                      unawaited(
                        _showRgProgressDialog(isClearing: true),
                      );
                      await _rg.clearAll();
                      if (!mounted) return;
                      _showSnack('Registros borrados');
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Reproducción
  // ---------------------------------------------------------------------------

  Widget _buildPlaybackGroup(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _SliderItem(
            icon: Icons.graphic_eq,
            title: 'Amplificación de volumen',
            subtitle: _formatDb(_settings.volumeBoost),
            enabled: true,
            child: Slider(
              value: _settings.volumeBoost,
              min: -12,
              max: 12,
              divisions: 48,
              label: _formatDb(_settings.volumeBoost),
              onChanged: (v) => _update((s) => s.volumeBoost = v),
            ),
          ),
          _divider(context),
          _buildTransitionBlock(context),
        ],
      ),
    );
  }

  Widget _buildTransitionBlock(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _settings.transitionsEnabled;
    final mode = _settings.transitionMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.swap_horiz,
                  color: scheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transiciones',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enabled
                          ? (mode == 0 ? 'Crossfade' : 'Fade In / Fade Out')
                          : 'Desactivado',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (v) => _update((s) => s.transitionsEnabled = v),
              ),
            ],
          ),
          Opacity(
            opacity: enabled ? 1.0 : 0.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TransitionChip(
                        label: 'Crossfade',
                        selected: mode == 0,
                        onTap: enabled
                            ? () => _update((s) => s.transitionMode = 0)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TransitionChip(
                        label: 'Fade In / Out',
                        selected: mode == 1,
                        onTap: enabled
                            ? () => _update((s) => s.transitionMode = 1)
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      mode == 0
                          ? 'Duración del crossfade'
                          : 'Duración del fade',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      mode == 0
                          ? '${_settings.crossfadeSeconds.toStringAsFixed(1)} s'
                          : '${_settings.fadeSeconds.toStringAsFixed(1)} s',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (mode == 0)
                  Slider(
                    value: _settings.crossfadeSeconds,
                    min: 0,
                    max: 12,
                    divisions: 24,
                    label:
                        '${_settings.crossfadeSeconds.toStringAsFixed(1)} s',
                    onChanged: enabled
                        ? (v) => _update((s) => s.crossfadeSeconds = v)
                        : null,
                  )
                else
                  Slider(
                    value: _settings.fadeSeconds,
                    min: 0,
                    max: 12,
                    divisions: 24,
                    label: '${_settings.fadeSeconds.toStringAsFixed(1)} s',
                    onChanged: enabled
                        ? (v) => _update((s) => s.fadeSeconds = v)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Almacenamiento
  // ---------------------------------------------------------------------------

  Widget _buildStorageGroup(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStorageCategory(
            context,
            icon: Icons.music_note,
            title: 'Música',
            subtitle: 'Directorios donde se escanean canciones',
            dirs: _settings.musicDirs,
            onRemove: _removeMusicDir,
            onAdd: () => _pickDirectory(
              context,
              title: 'Agregar directorio de música',
              existing: _settings.musicDirs,
              onAdded: _addMusicDir,
            ),
          ),
          _divider(context),
          _buildStorageCategory(
            context,
            icon: Icons.podcasts,
            title: 'Podcasts',
            subtitle: 'Directorios donde se escanean episodios',
            dirs: _settings.podcastDirs,
            onRemove: _removePodcastDir,
            onAdd: () => _pickDirectory(
              context,
              title: 'Agregar directorio de podcasts',
              existing: _settings.podcastDirs,
              onAdded: _addPodcastDir,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCategory(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> dirs,
    required Future<void> Function(String) onRemove,
    required VoidCallback onAdd,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: scheme.onSurfaceVariant, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${dirs.length}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (dirs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              'Sin directorios añadidos',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ...dirs.map(
            (dir) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dir,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => onRemove(dir),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Icon(Icons.add, color: scheme.primary, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Agregar directorio',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Diálogos / helpers
  // ---------------------------------------------------------------------------

  Future<void> _pickDirectory(
    BuildContext context, {
    required String title,
    required Future<void> Function(String) onAdded,
    required List<String> existing,
  }) async {
    try {
      final selected = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DirectoryPickerDialog(
          title: title,
          initialPath: existing.isNotEmpty ? existing.first : null,
        ),
      );

      if (selected == null || selected.trim().isEmpty) return;

      final normalized = selected.trim().replaceAll(RegExp(r'/+$'), '');
      final alreadyExists = existing.any(
        (d) => d.replaceAll(RegExp(r'/+$'), '') == normalized,
      );

      if (alreadyExists) {
        if (context.mounted) {
          await _showInfoDialog(
            context,
            title: 'Directorio duplicado',
            message: 'Esa carpeta ya está en la lista.',
          );
        }
        return;
      }

      await onAdded(normalized);
    } catch (e) {
      if (context.mounted) {
        await _showInfoDialog(
          context,
          title: 'Error',
          message: 'No se pudo abrir el selector de carpetas:\n$e',
        );
      }
    }
  }

  Future<void> _showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.info_outline, color: scheme.primary),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  String _formatDb(double db) {
    final sign = db > 0 ? '+' : '';
    return '$sign${db.toStringAsFixed(1)} dB';
  }

  Widget _divider(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      color: scheme.outlineVariant.withOpacity(0.4),
      indent: 64,
      endIndent: 12,
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.surfaceContainerHigh,
            child: Icon(Icons.person, color: scheme.onSurfaceVariant, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usuario Demo',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'usuario@ejemplo.com',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(BuildContext context, List<_SettingItem> items) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i != items.length - 1) _divider(context),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets auxiliares
// ---------------------------------------------------------------------------

class _SettingItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: scheme.onSurfaceVariant, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _SliderItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final Widget child;

  const _SliderItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opacity = enabled ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: scheme.onSurfaceVariant, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
  }
}

class _TransitionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _TransitionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? scheme.onPrimary : scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ReplayGain widgets
// ---------------------------------------------------------------------------

class _RgStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlighted;

  const _RgStatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = highlighted ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RgIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _RgIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = enabled ? color : scheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: enabled
                  ? effectiveColor.withOpacity(0.10)
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? effectiveColor
                  : scheme.onSurfaceVariant.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _RgBlockingProgressDialog extends StatelessWidget {
  final bool isClearing;
  final Color color;

  const _RgBlockingProgressDialog({
    required this.isClearing,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: ReplayGainService.instance,
        builder: (context, _) {
          final rg = ReplayGainService.instance;
          final progress = rg.progress.value.clamp(0.0, 1.0);
          final pct = isClearing ? null : (progress * 100).toStringAsFixed(0);

          return Dialog(
            backgroundColor: scheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 24,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isClearing
                              ? Icons.delete_sweep_outlined
                              : Icons.auto_awesome,
                          color: color,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isClearing
                                  ? 'Borrando registros'
                                  : 'Analizando ReplayGain',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isClearing
                                  ? 'Eliminando datos guardados…'
                                  : 'No cierres la app. Esto puede tardar…',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: isClearing ? null : progress,
                      minHeight: 8,
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isClearing
                            ? 'Eliminando…'
                            : (progress < 1.0
                                ? 'Procesando pistas…'
                                : 'Finalizando…'),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (pct != null)
                        Text(
                          '$pct%',
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
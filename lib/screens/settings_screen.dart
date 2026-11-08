import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService.instance;

  AppSettings _settings = AppSettings();
  bool _loaded = false;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final loaded = await _service.load();
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _loaded = true;
    });
  }

  /// Guarda con debounce para no escribir en disco en cada tick del slider.
  void _persist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      _service.save(_settings);
    });
  }

  /// Muta el modelo + setState + persiste en un solo paso.
  void _update(void Function(AppSettings s) mutate) {
    setState(() => mutate(_settings));
    _persist();
  }

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

              // ── Cuenta ──
              _buildSectionTitle(context, 'Cuenta'),
              const SizedBox(height: 12),
              _buildAccountCard(context),
              const SizedBox(height: 24),

              // ── ReplayGain ──
              _buildSectionTitle(context, 'ReplayGain'),
              const SizedBox(height: 12),
              _buildReplayGainGroup(context),
              const SizedBox(height: 24),

              // ── Reproducción ──
              _buildSectionTitle(context, 'Reproducción'),
              const SizedBox(height: 12),
              _buildPlaybackGroup(context),
              const SizedBox(height: 24),

              // ── Almacenamiento ──
              _buildSectionTitle(context, 'Almacenamiento'),
              const SizedBox(height: 12),
              _buildStorageGroup(context),
              const SizedBox(height: 24),

              // ── Apariencia ──
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

              // ── Acerca de ──
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

  // ─────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────
  // REPLAYGAIN
  // ─────────────────────────────────────────────────────────────
  Widget _buildReplayGainGroup(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _settings.replayGainEnabled;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _SettingItem(
            icon: Icons.volume_up,
            title: 'ReplayGain',
            subtitle: 'Normalizar el volumen entre pistas',
            trailing: Switch(
              value: enabled,
              onChanged: (v) => _update((s) => s.replayGainEnabled = v),
            ),
          ),
          if (enabled) ...[
            _divider(context),
            _ActionButton(
              icon: Icons.playlist_add_check,
              title: 'Analizar canciones',
              subtitle: 'Calcular ReplayGain de pistas sin analizar',
              onTap: () {},
            ),
            _divider(context),
            _ActionButton(
              icon: Icons.refresh,
              title: 'Recalcular todo',
              subtitle: 'Volver a analizar la biblioteca completa',
              onTap: () {},
            ),
            _divider(context),
            _ActionButton(
              icon: Icons.delete_outline,
              title: 'Borrar registros',
              subtitle: 'Eliminar datos de ReplayGain guardados',
              destructive: true,
              onTap: () {},
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // REPRODUCCIÓN
  // ─────────────────────────────────────────────────────────────
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
                    label: '${_settings.crossfadeSeconds.toStringAsFixed(1)} s',
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

  // ─────────────────────────────────────────────────────────────
  // ALMACENAMIENTO
  // ─────────────────────────────────────────────────────────────
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
            onRemove: (dir) => _update((s) => s.musicDirs.remove(dir)),
            onAdd: () => _pickDirectory(
              context,
              title: 'Agregar directorio de música',
              existing: _settings.musicDirs,
              onAdded: (path) => _update((s) => s.musicDirs.add(path)),
            ),
          ),
          _divider(context),
          _buildStorageCategory(
            context,
            icon: Icons.podcasts,
            title: 'Podcasts',
            subtitle: 'Directorios donde se escanean episodios',
            dirs: _settings.podcastDirs,
            onRemove: (dir) => _update((s) => s.podcastDirs.remove(dir)),
            onAdd: () => _pickDirectory(
              context,
              title: 'Agregar directorio de podcasts',
              existing: _settings.podcastDirs,
              onAdded: (path) => _update((s) => s.podcastDirs.add(path)),
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
    required void Function(String) onRemove,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        style: TextStyle(color: scheme.onSurface, fontSize: 12),
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

  // ─────────────────────────────────────────────────────────────
  // SELECTOR DE DIRECTORIOS (nativo con file_picker)
  // ─────────────────────────────────────────────────────────────
  Future<void> _pickDirectory(
    BuildContext context, {
    required String title,
    required void Function(String) onAdded,
    required List<String> existing,
  }) async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: title,
      );

      if (selected == null || selected.trim().isEmpty) return;

      // Normaliza (evita duplicados con o sin slash final)
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

      onAdded(normalized);
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

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────
// WIDGETS REUTILIZABLES
// ─────────────────────────────────────────────────────────────
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = destructive ? scheme.error : scheme.primary;

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
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: destructive ? scheme.error : scheme.onSurface,
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
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

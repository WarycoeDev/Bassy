import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── ReplayGain ──
  bool _replayGainEnabled = true;

  // ── Reproducción ──
  double _volumeBoost = 0.0; // dB, rango -12 .. +12
  bool _transitionsEnabled = true;
  int _transitionMode = 0; // 0 = Crossfade, 1 = Fade In / Fade Out
  double _crossfadeSeconds = 4.0; // 0 .. 12 s
  double _fadeSeconds = 3.0; // 0 .. 12 s

  // ── Recordatorios ──
  bool _remindersEnabled = true;
  bool _dailyReminder = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 18, minute: 0);
  bool _unplayedAlbums = false;
  bool _forgottenPlaylists = false;

  // ── Almacenamiento ──
  final List<String> _musicDirs = ['/storage/emulated/0/Music'];
  final List<String> _podcastDirs = ['/storage/emulated/0/Podcasts'];

  @override
  Widget build(BuildContext context) {
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

              // ── Recordatorios ──
              _buildSectionTitle(context, 'Recordatorios'),
              const SizedBox(height: 12),
              _buildRemindersGroup(context),
              const SizedBox(height: 24),

              // ── Almacenamiento ──
              _buildSectionTitle(context, 'Almacenamiento'),
              const SizedBox(height: 12),
              _buildScanDirsCard(
                context,
                icon: Icons.music_note,
                title: 'Música',
                subtitle: 'Directorios donde se escanean canciones',
                dirs: _musicDirs,
                onRemove: (dir) => setState(() => _musicDirs.remove(dir)),
                onAdd: () => _addDirectory(
                  context,
                  title: 'Agregar directorio de música',
                  onAdded: (path) => setState(() => _musicDirs.add(path)),
                  existing: _musicDirs,
                ),
              ),
              const SizedBox(height: 12),
              _buildScanDirsCard(
                context,
                icon: Icons.podcasts,
                title: 'Podcasts',
                subtitle: 'Directorios donde se escanean episodios',
                dirs: _podcastDirs,
                onRemove: (dir) => setState(() => _podcastDirs.remove(dir)),
                onAdd: () => _addDirectory(
                  context,
                  title: 'Agregar directorio de podcasts',
                  onAdded: (path) => setState(() => _podcastDirs.add(path)),
                  existing: _podcastDirs,
                ),
              ),
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
              value: _replayGainEnabled,
              onChanged: (v) => setState(() => _replayGainEnabled = v),
            ),
          ),
          if (_replayGainEnabled) ...[
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
          _buildTransitionBlock(context),
          _divider(context),
          _SliderItem(
            icon: Icons.graphic_eq,
            title: 'Amplificación de volumen',
            subtitle: _formatDb(_volumeBoost),
            enabled: true,
            child: Slider(
              value: _volumeBoost,
              min: -12,
              max: 12,
              divisions: 48,
              label: _formatDb(_volumeBoost),
              onChanged: (v) => setState(() => _volumeBoost = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionBlock(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                      _transitionsEnabled
                          ? (_transitionMode == 0
                                ? 'Crossfade'
                                : 'Fade In / Fade Out')
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
                value: _transitionsEnabled,
                onChanged: (v) => setState(() => _transitionsEnabled = v),
              ),
            ],
          ),
          Opacity(
            opacity: _transitionsEnabled ? 1.0 : 0.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TransitionChip(
                        label: 'Crossfade',
                        selected: _transitionMode == 0,
                        onTap: _transitionsEnabled
                            ? () => setState(() => _transitionMode = 0)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TransitionChip(
                        label: 'Fade In / Out',
                        selected: _transitionMode == 1,
                        onTap: _transitionsEnabled
                            ? () => setState(() => _transitionMode = 1)
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
                      _transitionMode == 0
                          ? 'Duración del crossfade'
                          : 'Duración del fade',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _transitionMode == 0
                          ? '${_crossfadeSeconds.toStringAsFixed(1)} s'
                          : '${_fadeSeconds.toStringAsFixed(1)} s',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (_transitionMode == 0)
                  Slider(
                    value: _crossfadeSeconds,
                    min: 0,
                    max: 12,
                    divisions: 24,
                    label: '${_crossfadeSeconds.toStringAsFixed(1)} s',
                    onChanged: _transitionsEnabled
                        ? (v) => setState(() => _crossfadeSeconds = v)
                        : null,
                  )
                else
                  Slider(
                    value: _fadeSeconds,
                    min: 0,
                    max: 12,
                    divisions: 24,
                    label: '${_fadeSeconds.toStringAsFixed(1)} s',
                    onChanged: _transitionsEnabled
                        ? (v) => setState(() => _fadeSeconds = v)
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
  // RECORDATORIOS
  // ─────────────────────────────────────────────────────────────
  Widget _buildRemindersGroup(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _SettingItem(
            icon: Icons.notifications_active,
            title: 'Recordatorios',
            subtitle: 'Avisos para no dejar de escuchar música',
            trailing: Switch(
              value: _remindersEnabled,
              onChanged: (v) => setState(() => _remindersEnabled = v),
            ),
          ),
          if (_remindersEnabled) ...[
            _divider(context),
            _SettingItem(
              icon: Icons.today,
              title: 'Recordarme reproducir algo hoy',
              subtitle: 'Un aviso diario para escuchar música',
              trailing: Switch(
                value: _dailyReminder,
                onChanged: (v) => setState(() => _dailyReminder = v),
              ),
            ),
            _divider(context),
            _SettingItem(
              icon: Icons.schedule,
              title: 'Hora del recordatorio',
              subtitle: _formatTime(_reminderTime),
              onTap: _dailyReminder ? _pickReminderTime : null,
              trailing: Opacity(
                opacity: _dailyReminder ? 1.0 : 0.4,
                child: Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            _divider(context),
            _SettingItem(
              icon: Icons.album,
              title: 'Álbumes sin escuchar',
              subtitle: 'Sugerir álbumes que no has reproducido',
              trailing: Switch(
                value: _unplayedAlbums,
                onChanged: (v) => setState(() => _unplayedAlbums = v),
              ),
            ),
            _divider(context),
            _SettingItem(
              icon: Icons.queue_music,
              title: 'Playlists olvidadas',
              subtitle: 'Recordar playlists que no escuchas hace tiempo',
              trailing: Switch(
                value: _forgottenPlaylists,
                onChanged: (v) => setState(() => _forgottenPlaylists = v),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (picked != null) {
      setState(() => _reminderTime = picked);
    }
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ─────────────────────────────────────────────────────────────
  // ALMACENAMIENTO — tarjetas por categoría (Opción A)
  // ─────────────────────────────────────────────────────────────
  Widget _buildScanDirsCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> dirs,
    required void Function(String) onRemove,
    required VoidCallback onAdd,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado de la tarjeta ──
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
                // Badge con contador
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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

          // ── Lista de directorios ──
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
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

          // ── Botón agregar ──
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
      ),
    );
  }

  Future<void> _addDirectory(
    BuildContext context, {
    required String title,
    required void Function(String) onAdded,
    required List<String> existing,
  }) async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Ruta del directorio',
            hintText: '/storage/emulated/0/...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty && !existing.contains(value)) {
                Navigator.pop(ctx, value);
              }
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      onAdded(path);
    }
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

  // ─────────────────────────────────────────────────────────────
  // TARJETA DE CUENTA
  // ─────────────────────────────────────────────────────────────
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

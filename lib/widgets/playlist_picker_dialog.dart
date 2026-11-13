// lib/widgets/playlist_picker_dialog.dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playlists_store.dart';
import 'input_menu.dart';

/// Diálogo de selección múltiple de playlists con el estilo visual
/// de [ActionMenu] (carátula redondeada, header, tiles con hover,
/// contenedores `surfaceContainer`).
///
/// El usuario marca/desmarca playlists y al pulsar **Guardar** se
/// aplican todos los cambios en lote con
/// [PlaylistsStore.setSongInPlaylists].
class PlaylistPickerDialog extends StatefulWidget {
  final Song song;

  const PlaylistPickerDialog({super.key, required this.song});

  /// Abre el diálogo y devuelve `true` si el usuario guardó cambios.
  static Future<bool> show(BuildContext context, Song song) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => PlaylistPickerDialog(song: song),
    );
    return result ?? false;
  }

  @override
  State<PlaylistPickerDialog> createState() => _PlaylistPickerDialogState();
}

class _PlaylistPickerDialogState extends State<PlaylistPickerDialog> {
  /// Estado "deseado" (lo que quedará al guardar).
  final Set<String> _selected = {};
  bool _saving = false;
  bool _primed = false;

  @override
  void initState() {
    super.initState();
    _primeFromStore();
  }

  Future<void> _primeFromStore() async {
    final store = PlaylistsStore.instance;
    if (!store.isLoaded) await store.load();
    if (!mounted) return;
    setState(() {
      _primed = true;
      _selected
        ..clear()
        ..addAll(
          store.playlists
              .where((p) => p.songPaths.contains(widget.song.path))
              .map((p) => p.id),
        );
    });
  }

  Future<void> _createNew() async {
    final result = await InputMenu.show(
      context,
      title: 'Nueva playlist',
      subtitle: 'Se guardará como archivo .bassy',
      hintText: 'Nombre de la playlist…',
      confirmLabel: 'Crear',
      cancelLabel: 'Cancelar',
      maxLength: 60,
    );
    if (result == null || !result.confirmed) return;
    final name = result.text.trim();
    if (name.isEmpty) return;

    try {
      final created = await PlaylistsStore.instance.create(name);
      if (!mounted) return;
      setState(() => _selected.add(created.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la playlist: $e')),
      );
    }
  }

  Future<void> _save() async {
    final store = PlaylistsStore.instance;
    final original = store.playlists
        .where((p) => p.songPaths.contains(widget.song.path))
        .map((p) => p.id)
        .toSet();

    final addTo = _selected.difference(original);
    final removeFrom = original.difference(_selected);

    if (addTo.isEmpty && removeFrom.isEmpty) {
      Navigator.pop(context, false);
      return;
    }

    setState(() => _saving = true);
    try {
      await store.setSongInPlaylists(
        widget.song,
        addToIds: addTo,
        removeFromIds: removeFrom,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  bool get _hasChanges {
    final store = PlaylistsStore.instance;
    final original = store.playlists
        .where((p) => p.songPaths.contains(widget.song.path))
        .map((p) => p.id)
        .toSet();
    return !setEquals(_selected, original);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: PlaylistsStore.instance,
      builder: (context, _) {
        final playlists = PlaylistsStore.instance.playlists;

        return Dialog(
          backgroundColor: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
              maxHeight: 640,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ----- Header con carátula redondeada (estilo ActionMenu) -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PickerHeader(
                          title: 'Añadir a playlist',
                          subtitle: widget.song.title,
                          coverPath: widget.song.coverPath,
                          fallbackIcon: Icons.playlist_add,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Cerrar',
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // ----- Contenido scrolleable -----
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Botón "Crear nueva" con el mismo estilo que las
                        // acciones del menú.
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _saving ? null : _createNew,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.add,
                                      color: scheme.primary,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Crear nueva playlist…',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Lista de playlists en un contenedor
                        // `surfaceContainer` con esquinas 16.
                        if (playlists.isEmpty)
                          _EmptyPlaylistsHint(scheme: scheme)
                        else
                          Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Material(
                              color: Colors.transparent,
                              clipBehavior: Clip.antiAlias,
                              borderRadius: BorderRadius.circular(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0;
                                      i < playlists.length;
                                      i++) ...[
                                    _PickerCheckboxTile(
                                      playlist: playlists[i],
                                      checked: _selected
                                          .contains(playlists[i].id),
                                      onChanged: _saving
                                          ? null
                                          : (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _selected
                                                      .add(playlists[i].id);
                                                } else {
                                                  _selected.remove(
                                                    playlists[i].id,
                                                  );
                                                }
                                              });
                                            },
                                    ),
                                    if (i != playlists.length - 1)
                                      Divider(
                                        height: 1,
                                        indent: 52,
                                        color: scheme.outlineVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // ----- Botones Cancelar / Guardar -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PickerButton(
                          label: 'Cancelar',
                          onTap: _saving
                              ? null
                              : () => Navigator.pop(context, false),
                          background: scheme.surfaceContainer,
                          foreground: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PickerButton(
                          label: _saving ? 'Guardando…' : 'Guardar',
                          icon: _saving
                              ? null
                              : Icons.check,
                          showSpinner: _saving,
                          onTap: (_saving || !_hasChanges || !_primed)
                              ? null
                              : _save,
                          background: scheme.primary,
                          foreground: scheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// Widgets internos (mismo estilo visual que ActionMenu)
// ============================================================

/// Header con carátula redondeada + título + subtítulo, igual que
/// `_MenuHeader` de `ActionMenu`.
class _PickerHeader extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final String? coverPath;
  final IconData fallbackIcon;

  const _PickerHeader({
    this.title,
    this.subtitle,
    this.coverPath,
    required this.fallbackIcon,
  });

  bool get _hasCover {
    final p = coverPath;
    if (p == null || p.isEmpty) return false;
    try {
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget cover = _hasCover
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(coverPath!),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              cacheWidth: 144,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _fallbackCover(scheme),
            ),
          )
        : _fallbackCover(scheme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          cover,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackCover(ColorScheme scheme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        fallbackIcon,
        color: scheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }
}

/// Fila con checkbox, mismo padding/hover que `_MenuActionTile`.
class _PickerCheckboxTile extends StatelessWidget {
  final UserPlaylist playlist;
  final bool checked;
  final ValueChanged<bool?>? onChanged;

  const _PickerCheckboxTile({
    required this.playlist,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onChanged == null
          ? null
          : () => onChanged!(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Row(
          children: [
            Icon(
              Icons.queue_music,
              color: scheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.name,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.songPaths.length} canciones',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Checkbox(
              value: checked,
              onChanged: onChanged,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón inferior con el mismo estilo que `ActionMenu.confirm`.
class _PickerButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final bool showSpinner;

  const _PickerButton({
    required this.label,
    this.icon,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    final Color bg = enabled
        ? background
        : background.withValues(alpha: 0.5);
    final Color fg = enabled
        ? foreground
        : foreground.withValues(alpha: 0.5);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showSpinner) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hint vacío con el mismo lenguaje visual.
class _EmptyPlaylistsHint extends StatelessWidget {
  final ColorScheme scheme;
  const _EmptyPlaylistsHint({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.queue_music_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Aún no tienes playlists',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Crea una para empezar a organizar tu música.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// `setEquals` ligero para evitar depender de `package:collection`.
bool setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  for (final e in a) {
    if (!b.contains(e)) return false;
  }
  return true;
}
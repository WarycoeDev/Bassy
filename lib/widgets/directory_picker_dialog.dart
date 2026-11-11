import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DirectoryPickerDialog extends StatefulWidget {
  const DirectoryPickerDialog({
    super.key,
    required this.title,
    this.initialPath,
  });

  final String title;
  final String? initialPath;

  @override
  State<DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<DirectoryPickerDialog> {
  Directory? _current;
  List<Directory> _entries = const [];
  List<_QuickAccess> _quickAccess = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadQuickAccess();
    final start = widget.initialPath;
    Directory? dir;
    if (start != null && await Directory(start).exists()) {
      dir = Directory(start);
    } else {
      dir = _quickAccess.isNotEmpty ? _quickAccess.first.dir : null;
    }
    await _open(dir);
  }

  Future<void> _loadQuickAccess() async {
    final shortcuts = <_QuickAccess>[];
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          // /storage/emulated/0/Android/data/<appId>/files
          // subimos a /storage/emulated/0
          final root = Directory(
            p.joinAll(ext.path.split(Platform.pathSeparator).take(4)),
          );
          shortcuts.add(_QuickAccess('Almacenamiento', Icons.sd_storage, root));
        }
      } else {
        final home =
            Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
        if (home != null && home.isNotEmpty) {
          shortcuts.add(_QuickAccess('Inicio', Icons.home, Directory(home)));
        }
        try {
          final docs = await getApplicationDocumentsDirectory();
          // En desktop getApplicationDocumentsDirectory suele ser ~/Documents
          shortcuts.add(_QuickAccess('Documentos', Icons.description, docs));
        } catch (_) {}
        try {
          final downloads = Directory(
            p.join(
              Platform.environment['HOME'] ??
                  Platform.environment['USERPROFILE'] ??
                  '',
              'Downloads',
            ),
          );
          if (await downloads.exists()) {
            shortcuts.add(
              _QuickAccess('Descargas', Icons.download, downloads),
            );
          }
        } catch (_) {}
        final music = Directory(
          p.join(
            Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                '',
            'Music',
          ),
        );
        if (await music.exists()) {
          shortcuts.add(_QuickAccess('Música', Icons.music_note, music));
        }
      }
      // Raíz del sistema siempre disponible.
      if (!kIsWeb && Platform.isAndroid) {
        shortcuts.add(
          const _QuickAccess('Raíz', Icons.folder_special, null, path: '/'),
        );
      } else {
        final rootPath = Platform.isWindows
            ? (Platform.environment['SystemDrive'] ?? 'C:') + r'\'
            : '/';
        shortcuts.add(
          _QuickAccess(
            'Raíz',
            Icons.folder_special,
            Directory(rootPath),
          ),
        );
      }
    } catch (e) {
      debugPrint('quick access error: $e');
    }
    if (mounted) setState(() => _quickAccess = shortcuts);
  }

  Future<void> _open(Directory? dir) async {
    if (dir == null) {
      setState(() {
        _loading = false;
        _error = 'No hay carpetas disponibles';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await dir.exists()) {
        throw const FileSystemException('La carpeta no existe');
      }
      final children = await dir
          .list(followLinks: false)
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();
      children.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _current = dir;
        _entries = children;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo abrir la carpeta';
      });
    }
  }

  Directory? get _parent {
    final c = _current;
    if (c == null) return null;
    final parent = c.parent;
    if (parent.path == c.path) return null;
    return parent;
  }

  Future<void> _createFolder() async {
    final c = _current;
    if (c == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameFolderDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final newDir = Directory(p.join(c.path, name.trim()));
      if (await newDir.exists()) {
        if (mounted) _showError('Ya existe una carpeta con ese nombre');
        return;
      }
      await newDir.create(recursive: false);
      await _open(c);
    } catch (e) {
      if (mounted) _showError('No se pudo crear la carpeta: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(scheme),
            _buildBreadcrumb(scheme),
            if (_quickAccess.isNotEmpty) ...[
              _buildQuickChips(scheme),
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withOpacity(0.4),
              ),
            ],
            Flexible(child: _buildList(scheme)),
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withOpacity(0.4),
            ),
            _buildFooter(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.folder_open,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
            tooltip: 'Cerrar',
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(ColorScheme scheme) {
    final parts = _breadcrumbParts();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Subir',
            onPressed: _parent == null ? null : () => _open(_parent),
            icon: Icon(
              Icons.arrow_upward,
              size: 18,
              color: _parent == null
                  ? scheme.onSurfaceVariant.withOpacity(0.4)
                  : scheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (int i = 0; i < parts.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _open(Directory(parts[i].$2)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Text(
                          parts[i].$1,
                          style: TextStyle(
                            color: i == parts.length - 1
                                ? scheme.onSurface
                                : scheme.primary,
                            fontSize: 12,
                            fontWeight: i == parts.length - 1
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _breadcrumbParts() {
    final c = _current;
    if (c == null) return const [];
    final sep = Platform.pathSeparator;
    final parts = c.path.split(sep).where((e) => e.isNotEmpty).toList();
    final result = <(String, String)>[];
    var acc = Platform.isWindows ? '' : sep;
    for (var i = 0; i < parts.length; i++) {
      final seg = parts[i];
      if (Platform.isWindows && i == 0) {
        acc = '$seg$sep';
      } else {
        acc = p.join(acc, seg);
      }
      result.add((seg, acc));
    }
    return result;
  }

  Widget _buildQuickChips(ColorScheme scheme) {
    return Container(
      color: scheme.surface, // fondo sólido para que no se vea la lista debajo
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          itemCount: _quickAccess.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final q = _quickAccess[i];
            final selected = _current != null && _current!.path == q.dir?.path;
            return _Chip(
              icon: q.icon,
              label: q.label,
              selected: selected,
              onTap: () => _open(
                q.dir ?? Directory(q.path ?? '/'),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(ColorScheme scheme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 32),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              color: scheme.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'No hay subcarpetas',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        indent: 56,
        endIndent: 8,
        color: scheme.outlineVariant.withOpacity(0.3),
      ),
      itemBuilder: (_, i) {
        final dir = _entries[i];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(dir),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.folder,
                    color: scheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.basename(dir.path),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
  final current = _current;
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
    child: Row(
      children: [
        IconButton(
          onPressed: _createFolder,
          tooltip: 'Nueva carpeta',
          icon: Icon(
            Icons.create_new_folder_outlined,
            color: scheme.primary,
            size: 22,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: current == null
              ? null
              : () => Navigator.of(context).pop(current.path),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Seleccionar'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
        ),
      ],
    ),
  );
}
}

class _QuickAccess {
  const _QuickAccess(this.label, this.icon, this.dir, {this.path});
  final String label;
  final IconData icon;
  final Directory? dir;
  final String? path;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withOpacity(0.15)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? scheme.primary.withOpacity(0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameFolderDialog extends StatefulWidget {
  @override
  State<_NameFolderDialog> createState() => _NameFolderDialogState();
}

class _NameFolderDialogState extends State<_NameFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Nueva carpeta'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
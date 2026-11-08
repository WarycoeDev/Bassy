import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class DirectoryPickerTile extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final List<String> directories;
  final ValueChanged<List<String>> onChanged;

  const DirectoryPickerTile({
    super.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.directories,
    required this.onChanged,
  });

  Future<void> _add(BuildContext context) async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecciona una carpeta',
      );
      if (selected == null || selected.trim().isEmpty) return;
      if (directories.contains(selected)) return;
      onChanged([...directories, selected]);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el selector: $e')),
      );
    }
  }

  void _remove(int index) {
    final copy = [...directories]..removeAt(index);
    onChanged(copy);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.onSurface, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Añadir'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (directories.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Text(
                'Sin carpetas configuradas',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...List.generate(directories.length, (i) {
              final dir = directories[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      color: scheme.onSurfaceVariant,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dir,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _remove(i),
                      icon: Icon(
                        Icons.close,
                        color: scheme.onSurfaceVariant,
                        size: 18,
                      ),
                      visualDensity: VisualDensity.compact,
                      splashRadius: 18,
                      tooltip: 'Quitar',
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

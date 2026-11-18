// lib/widgets/song_details_dialog.dart
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/stats_service.dart';

/// Dialog que muestra todos los metadatos disponibles del archivo de
/// audio, junto con la carátula en grande.
///
/// Comparte el lenguaje visual de [ActionMenu]:
///  - `Dialog` con `surfaceContainerLow` y esquinas redondeadas.
///  - Header con portada + título + subtítulo.
///  - Bloque central `surfaceContainer` con filas etiqueta/valor.
///  - Botón inferior "Cerrar" con el mismo estilo que "Cancelar".
class SongDetailsDialog {
  SongDetailsDialog._();

  static Future<void> show(BuildContext context, Song song) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => _SongDetailsDialogView(song: song),
    );
  }
}

class _SongDetailsDialogView extends StatelessWidget {
  final Song song;
  const _SongDetailsDialogView({required this.song});

  bool get _hasCover {
    final p = song.coverPath;
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
    final isPodcast = song.kind == MediaKind.podcast;

    final rows = _buildRows(isPodcast);

    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
          maxHeight: 720,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- Header ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ---------- Contenido scrollable ----------
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CoverBlock(
                      song: song,
                      hasCover: _hasCover,
                      isPodcast: isPodcast,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              height: 1.2,
                            ),
                          ),
                          if (song.subtitle != null &&
                              song.subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              song.subtitle!,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ---------- Bloque de metadatos ----------
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
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
                            for (var i = 0; i < rows.length; i++) ...[
                              _MetaRow(
                                label: rows[i].label,
                                value: rows[i].value,
                                icon: rows[i].icon,
                                selectable: rows[i].selectable,
                              ),
                              if (i != rows.length - 1)
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
                  ],
                ),
              ),
            ),

            // ---------- Botón cerrar ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Material(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        'Cerrar',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_MetaRowData> _buildRows(bool isPodcast) {
    final rows = <_MetaRowData>[];

    rows.add(
      _MetaRowData(
        icon: Icons.title,
        label: 'Título',
        value: song.title,
      ),
    );

    rows.add(
      _MetaRowData(
        icon: Icons.person_outline,
        label: 'Artista',
        value: song.hasArtist ? song.artistOrUnknown : 'Desconocido',
      ),
    );

    rows.add(
      _MetaRowData(
        icon: Icons.album_outlined,
        label: 'Álbum',
        value: song.hasAlbum ? song.albumOrUnknown : 'Sin álbum',
      ),
    );

    rows.add(
      _MetaRowData(
        icon: Icons.timer_outlined,
        label: 'Duración',
        value: song.durationLabel,
      ),
    );

    rows.add(
      _MetaRowData(
        icon: Icons.audio_file_outlined,
        label: 'Formato',
        value: song.extension.toUpperCase(),
      ),
    );

    rows.add(
      _MetaRowData(
        icon: Icons.sd_storage_outlined,
        label: 'Tamaño',
        value: song.sizeLabel,
      ),
    );

    rows.add(
      _MetaRowData(
        icon: isPodcast ? Icons.mic : Icons.music_note,
        label: 'Tipo',
        value: isPodcast ? 'Podcast' : 'Música',
      ),
    );

    rows.add(
      _MetaRowData(
        icon: Icons.folder_outlined,
        label: 'Ruta',
        value: song.path,
        selectable: true,
      ),
    );
    // Estado de reproducción (podcast).
    if (isPodcast) {
      final stats = StatsService.instance;
      final played = stats.isPlayed(song);
      final progress = stats.progressOf(song);
      final position = progress?.position ?? Duration.zero;
      final hasProgress = position > Duration.zero && !played;

      rows.add(
        _MetaRowData(
          icon: played
              ? Icons.check_circle
              : Icons.check_circle_outline,
          label: 'Estado',
          value: played
              ? 'Completado'
              : hasProgress
                  ? 'En progreso'
                  : 'Sin reproducir',
        ),
      );

      if (hasProgress) {
        rows.add(
          _MetaRowData(
            icon: Icons.play_circle_outline,
            label: 'Progreso',
            value: _formatDuration(position),
          ),
        );
      }
    }

    return rows;
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

// ---------- Sub-widgets ----------

class _CoverBlock extends StatelessWidget {
  final Song song;
  final bool hasCover;
  final bool isPodcast;

  const _CoverBlock({
    required this.song,
    required this.hasCover,
    required this.isPodcast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 220,
            height: 220,
            child: Container(
              color: scheme.surfaceContainerHigh,
              child: hasCover
                  ? Image.file(
                      File(song.coverPath!),
                      fit: BoxFit.cover,
                      cacheWidth: 660,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => Icon(
                        isPodcast ? Icons.mic : Icons.music_note,
                        size: 64,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Icon(
                      isPodcast ? Icons.mic : Icons.music_note,
                      size: 64,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaRowData {
  final IconData icon;
  final String label;
  final String value;
  final bool selectable;

  const _MetaRowData({
    required this.icon,
    required this.label,
    required this.value,
    this.selectable = false,
  });
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool selectable;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.selectable,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                selectable
                    ? SelectableText(
                        value,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      )
                    : Text(
                        value,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
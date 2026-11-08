import 'package:flutter/material.dart';

import '../models/song.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  const SongTile({super.key, required this.song, this.onTap, this.onMore});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPodcast = song.kind == MediaKind.podcast;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Cover / icono
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPodcast ? Icons.mic : Icons.music_note,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),

            // Título + subtítulo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Extensión + tamaño
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  song.extension.toUpperCase(),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.sizeLabel,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: onMore,
              icon: Icon(
                Icons.more_vert,
                color: scheme.onSurfaceVariant,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

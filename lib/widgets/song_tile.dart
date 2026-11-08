import 'dart:io';

import 'package:flutter/material.dart';

import '../models/song.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  const SongTile({super.key, required this.song, this.onTap, this.onMore});

  // Cache estático por path: evita repetir existsSync() en cada build.
  static final Map<String, bool> _coverCache = <String, bool>{};

  static bool _hasCover(String? cover) {
    if (cover == null) return false;
    return _coverCache.putIfAbsent(cover, () {
      try {
        return File(cover).existsSync();
      } catch (_) {
        return false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPodcast = song.kind == MediaKind.podcast;
    final cover = song.coverPath;
    final hasCover = _hasCover(cover);

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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 52,
                height: 52,
                color: scheme.surfaceContainerHigh,
                child: hasCover
                    ? Image.file(
                        File(cover!),
                        fit: BoxFit.cover,
                        // cacheWidth reduce memoria y acelera decode.
                        cacheWidth: 156,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => Icon(
                          isPodcast ? Icons.mic : Icons.music_note,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        isPodcast ? Icons.mic : Icons.music_note,
                        color: scheme.onSurfaceVariant,
                      ),
              ),
            ),
            const SizedBox(width: 12),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  song.durationLabel,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${song.extension.toUpperCase()} · ${song.sizeLabel}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
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

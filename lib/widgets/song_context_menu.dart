// lib/widgets/song_context_menu.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';
import 'action_menu.dart';

/// Centraliza los dos menús que puede abrir un tile:
///
///  - **Menú de cola** ([showQueueSheet]): tap normal cuando ya hay cola.
///    Solo acciones de reproducción/cola.
///  - **Menú de contexto** ([showSheet] / [showAt]): ⋮, long-press o clic
///    derecho. Acciones completas según el tipo (canción vs podcast).
class SongContextMenu {
  SongContextMenu._();

  // ============================================================
  // MENÚ DE COLA (tap normal)
  // ============================================================

  /// Menú reducido al tocar un tile cuando la cola ya tiene canciones.
  static Future<void> showQueueSheet(
    BuildContext context,
    Song song,
  ) async {
    final actions = _buildQueueActions(song);
    await ActionMenu.show(
      context,
      title: song.title,
      subtitle: song.subtitle,
      coverPath: song.coverPath,
      fallbackIcon: _fallbackIcon(song),
      actions: actions,
    );
  }

  static List<ActionMenuItem> _buildQueueActions(Song song) {
    final c = PlaybackController.instance;
    final handler = c.isReady ? c.handler : null;

    final inQueue =
        handler?.songs.any((s) => s.path == song.path) ?? false;
    final isCurrent = handler?.currentSong?.path == song.path;

    return [
      ActionMenuItem(
        icon: Icons.playlist_play,
        label: 'Sobrescribir cola y reproducir',
        onTap: () async {
          if (handler == null) return;
          await handler.setQueue([song], startIndex: 0);
          await handler.play();
        },
      ),
      if (!inQueue)
        ActionMenuItem(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          onTap: () async {
            if (handler == null) return;
            await handler.addToQueue(song);
          },
        )
      else
        ActionMenuItem(
          icon: Icons.playlist_remove,
          label: 'Quitar de la cola',
          isDestructive: true,
          enabled: !(isCurrent ?? false),
          onTap: () async {
            if (handler == null) return;
            final idx =
                handler.songs.indexWhere((s) => s.path == song.path);
            if (idx >= 0) await handler.removeFromQueue(idx);
          },
        ),
    ];
  }

  // ============================================================
  // MENÚ DE CONTEXTO (⋮ / long-press / clic derecho)
  // ============================================================

  /// Bottom sheet con todas las acciones según tipo.
  static Future<void> showSheet(
    BuildContext context,
    Song song,
  ) async {
    final actions = _buildContextActions(context, song);
    await ActionMenu.show(
      context,
      title: song.title,
      subtitle: song.subtitle,
      coverPath: song.coverPath,
      fallbackIcon: _fallbackIcon(song),
      actions: actions,
    );
  }

  /// Popup anclado a [globalPosition] (long-press / clic derecho).
  static Future<void> showAt(
    BuildContext context,
    Song song, {
    required Offset globalPosition,
  }) {
    final actions = _buildContextActions(context, song);
    return ActionMenu.showAt(
      context,
      actions: actions,
      globalPosition: globalPosition,
      title: song.title,
      subtitle: song.subtitle,
      coverPath: song.coverPath,
      fallbackIcon: _fallbackIcon(song),
    );
  }

  static List<ActionMenuItem> _buildContextActions(
    BuildContext context,
    Song song,
  ) {
    // Acciones comunes (canción y podcast): cola + organización.
    final common = <ActionMenuItem>[
      ActionMenuItem(
        icon: Icons.play_arrow,
        label: 'Reproducir ahora',
        onTap: () => _playNow(song),
      ),
      ..._queueAddRemove(song),
      ActionMenuItem(
        icon: Icons.playlist_add,
        label: 'Añadir a playlist',
        onTap: () => _todo(context, 'Añadir a playlist'),
      ),
      ActionMenuItem(
        icon: Icons.favorite_border,
        label: 'Añadir a favoritos',
        onTap: () => _todo(context, 'Añadir a favoritos'),
      ),
    ];

    final specific = song.kind == MediaKind.podcast
        ? _podcastActions(context, song)
        : _musicActions(context, song);

    return [...common, ...specific];
  }

  /// Bloque reutilizable "Añadir / Quitar de la cola" según estado.
  static List<ActionMenuItem> _queueAddRemove(Song song) {
    final c = PlaybackController.instance;
    final handler = c.isReady ? c.handler : null;
    final inQueue =
        handler?.songs.any((s) => s.path == song.path) ?? false;
    final isCurrent = handler?.currentSong?.path == song.path;

    if (!inQueue) {
      return [
        ActionMenuItem(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          onTap: () async {
            if (handler == null) return;
            await handler.addToQueue(song);
          },
        ),
      ];
    }
    return [
      ActionMenuItem(
        icon: Icons.playlist_remove,
        label: 'Quitar de la cola',
        isDestructive: true,
        enabled: !(isCurrent ?? false),
        onTap: () async {
          if (handler == null) return;
          final idx =
              handler.songs.indexWhere((s) => s.path == song.path);
          if (idx >= 0) await handler.removeFromQueue(idx);
        },
      ),
    ];
  }

  static Future<void> _playNow(Song song) async {
    final c = PlaybackController.instance;
    if (!c.isReady) return;
    await c.handler.playSong(song);
  }

  // ---------- Acciones específicas de canción ----------

  static List<ActionMenuItem> _musicActions(
    BuildContext context,
    Song song,
  ) {
    return [
      ActionMenuItem(
        icon: Icons.album_outlined,
        label: 'Ir al álbum',
        onTap: () => _todo(context, 'Ir al álbum'),
      ),
      ActionMenuItem(
        icon: Icons.person_outline,
        label: 'Ir al artista',
        onTap: () => _todo(context, 'Ir al artista'),
      ),
      ActionMenuItem(
        icon: Icons.info_outline,
        label: 'Detalles',
        onTap: () => _todo(context, 'Detalles'),
      ),
    ];
  }

  // ---------- Acciones específicas de podcast ----------

  static List<ActionMenuItem> _podcastActions(
    BuildContext context,
    Song song,
  ) {
    final isPlayed = _isPlayed(song);
    final position = _playbackPosition(song);

    return [
      ActionMenuItem(
        icon: isPlayed
            ? Icons.check_circle
            : Icons.check_circle_outline,
        label: isPlayed
            ? 'Marcar como no reproducido'
            : 'Marcar como reproducido',
        onTap: () => _todo(
          context,
          isPlayed
              ? 'Marcar como no reproducido'
              : 'Marcar como reproducido',
        ),
      ),
      if (position > Duration.zero)
        ActionMenuItem(
          icon: Icons.restart_alt,
          label: 'Reiniciar progreso',
          onTap: () => _todo(context, 'Reiniciar progreso'),
        ),
      ActionMenuItem(
        icon: Icons.speed,
        label: 'Velocidad de reproducción',
        onTap: () => _todo(context, 'Velocidad de reproducción'),
      ),
      ActionMenuItem(
        icon: Icons.timer_outlined,
        label: 'Dormir después de…',
        onTap: () => _todo(context, 'Sleep timer'),
      ),
      ActionMenuItem(
        icon: Icons.share_outlined,
        label: 'Compartir episodio',
        onTap: () => _todo(context, 'Compartir episodio'),
      ),
      ActionMenuItem(
        icon: Icons.info_outline,
        label: 'Detalles del episodio',
        onTap: () => _todo(context, 'Detalles del episodio'),
      ),
    ];
  }

  // ---------- Helpers ----------

  static IconData _fallbackIcon(Song song) =>
      song.kind == MediaKind.podcast ? Icons.mic : Icons.music_note;

  static bool _isPlayed(Song song) {
    // TODO: ajusta al campo real (p.ej. song.isPlayed).
    return false;
  }

  static Duration _playbackPosition(Song song) {
    // TODO: ajusta al campo real (p.ej. song.playbackPosition).
    return Duration.zero;
  }

  static void _todo(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('TODO: $label')),
    );
  }
}
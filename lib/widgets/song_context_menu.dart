// lib/widgets/song_context_menu.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../screens/library_screen.dart';
import '../screens/playlist_detail_screen.dart';
import '../services/favorites_store.dart';
import '../services/playback_controller.dart';
import 'action_menu.dart';
import 'input_menu.dart';

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
    return [
      ActionMenuItem(
        icon: Icons.playlist_play,
        label: 'Sobrescribir cola y reproducir',
        onTap: () => _replaceQueueAndPlay(song),
      ),
      ..._queueAddRemove(song),
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
    // Para podcasts: solo reproducción + acciones propias de podcast.
    if (song.kind == MediaKind.podcast) {
      return [
        ActionMenuItem(
          icon: Icons.play_arrow,
          label: 'Reproducir ahora',
          onTap: () => _playNow(song),
        ),
        ..._podcastActions(context, song),
      ];
    }

    // Canciones: acciones completas (cola + organización + navegación).
    final favorites = FavoritesStore.instance;
    final isFav = favorites.contains(song);

    return [
      ActionMenuItem(
        icon: Icons.play_arrow,
        label: 'Reproducir ahora',
        onTap: () => _playNow(song),
      ),
      ..._queueAddRemove(song),
      ActionMenuItem(
        icon: Icons.playlist_add,
        label: 'Añadir a playlist',
        onTap: () => _addToPlaylist(context, song),
      ),
      ActionMenuItem(
        icon: isFav ? Icons.favorite : Icons.favorite_border,
        label: isFav ? 'Quitar de favoritos' : 'Añadir a favoritos',
        onTap: () async {
          await favorites.toggle(song);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isFav ? 'Quitado de favoritos' : 'Añadido a favoritos',
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
      ..._musicActions(context, song),
    ];
  }

  /// Bloque reutilizable "Añadir / Quitar de la cola" según estado.
  static List<ActionMenuItem> _queueAddRemove(Song song) {
    final c = PlaybackController.instance;
    final handler = c.isReady ? c.handler : null;
    final inQueue = handler?.songs.any((s) => s.path == song.path) ?? false;
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
        enabled: !isCurrent,
        onTap: () async {
          if (handler == null) return;
          final idx = handler.songs.indexWhere((s) => s.path == song.path);
          if (idx >= 0) await handler.removeFromQueue(idx);
        },
      ),
    ];
  }

  // ---------- Reproducción ----------

  static Future<void> _playNow(Song song) => _replaceQueueAndPlay(song);

  /// Vacía la cola, deja solo [song] y la reproduce desde 0,
  /// deteniendo lo que sonaba antes.
  static Future<void> _replaceQueueAndPlay(Song song) async {
    final c = PlaybackController.instance;
    if (!c.isReady) return;
    try {
      await c.playOnly(song);
    } catch (e) {
      debugPrint('SongContextMenu: no se pudo reproducir -> $e');
    }
  }

  // ---------- Acciones específicas de canción ----------

  static List<ActionMenuItem> _musicActions(
    BuildContext context,
    Song song,
  ) {
    final album = _findAlbum(song);
    final artist = _findArtist(song);

    final hasAlbum = song.hasAlbum && album != null;
    final hasArtist = song.hasArtist && artist != null;

    return [
      ActionMenuItem(
        icon: Icons.album_outlined,
        label: 'Ir al álbum',
        enabled: hasAlbum,
        onTap: () {
          if (!hasAlbum) return;
          _openPlaylist(context, album!);
        },
      ),
      ActionMenuItem(
        icon: Icons.person_outline,
        label: 'Ir al artista',
        enabled: hasArtist,
        onTap: () {
          if (!hasArtist) return;
          _openPlaylist(context, artist!);
        },
      ),
      ActionMenuItem(
        icon: Icons.info_outline,
        label: 'Detalles',
        onTap: () => _todo(context, 'Detalles'),
      ),
    ];
  }

  // ---------- Añadir a playlist (placeholder con InputMenu) ----------

  static Future<void> _addToPlaylist(
    BuildContext context,
    Song song,
  ) async {
    // TODO: conectar PlaylistsStore cuando exista.
    final result = await InputMenu.show(
      context,
      title: 'Añadir a playlist',
      subtitle: song.title,
      hintText: 'Nombre de la playlist',
      confirmLabel: 'Añadir',
      suggestions: const ['Favoritos', 'Escuchar luego', 'En el coche'],
    );
    if (result == null || !result.confirmed) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'TODO: añadir a "${result.text}" (playlist store pendiente)',
        ),
      ),
    );
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
        icon: isPlayed ? Icons.check_circle : Icons.check_circle_outline,
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
        icon: Icons.info_outline,
        label: 'Detalles del episodio',
        onTap: () => _todo(context, 'Detalles del episodio'),
      ),
    ];
  }

  // ---------- Navegación a álbum / artista ----------

  /// Abre la playlist en el Navigator correcto:
  ///
  ///  - Si este [context] resuelve al Navigator anidado de Library,
  ///    empuja allí (mantiene el drawer lateral visible en PC).
  ///  - En cualquier otro caso (Search, otra pestaña, raíz), empuja en
  ///    el Navigator que corresponda a este [context], que es el anidado
  ///    de esa pestaña. El back lo gestionará el [NestedNavigatorScope]
  ///    de esa pestaña (o el de [PlaylistDetailScreen] como respaldo).
    // ---------- Navegación a álbum / artista ----------

  /// Abre la playlist (álbum/artista) como una ventana flotante centrada
  /// sobre el contexto actual, en lugar de empujar una ruta completa.
  /// El layout interno de [PlaylistDetailScreen] no se modifica: solo se
  /// envuelve en un [Dialog] con tamaño acotado y esquinas redondeadas.
  static void _openPlaylist(BuildContext context, Playlist playlist) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final media = MediaQuery.of(dialogContext);
        // Tamaño acotado: hasta 480px de ancho y 80% de alto.
        final maxWidth = 480.0;
        final width = media.size.width < maxWidth + 48
            ? media.size.width * 0.92
            : maxWidth;
        final maxHeight = media.size.height * 0.8;

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: maxHeight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Material(
                color: scheme.surface,
                child: PlaylistDetailScreen(playlist: playlist),
              ),
            ),
          ),
        );
      },
    );
  }

  static Playlist? _findAlbum(Song song) {
    if (!song.hasAlbum) return null;
    final target = song.albumOrUnknown;
    for (final p in LibraryScreen.currentAlbums) {
      if (p.title == target) return p;
    }
    return null;
  }

  static Playlist? _findArtist(Song song) {
    if (!song.hasArtist) return null;
    final target = song.artistOrUnknown;
    for (final p in LibraryScreen.currentArtists) {
      if (p.title == target) return p;
    }
    return null;
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
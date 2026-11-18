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
import '../services/stats_service.dart';
import 'action_menu.dart';
import 'input_menu.dart';
import 'playlist_picker_dialog.dart';

class SongContextMenu {
  SongContextMenu._();

  // ============================================================
  // MENÚ DE COLA SIN CONTEXTO (tap normal en listado plano)
  // ============================================================

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
        icon: Icons.play_arrow,
        label: 'Reproducir ahora',
        onTap: () => _replaceQueueAndPlay(song),
      ),
      ..._queueAddRemove(song),
    ];
  }

  // ============================================================
  // MENÚ DE COLA CON CONTEXTO (ej. desde un álbum o playlist)
  // ============================================================

  static Future<void> showQueueSheetForContext(
    BuildContext context,
    Song song, {
    required List<Song> contextSongs,
    required int startIndex,
  }) async {
    if (contextSongs.isEmpty) return;

    final controller = PlaybackController.instance;
    if (!controller.isReady) return;

    final kind = song.kind;
    final safeIndex =
        startIndex >= 0 && startIndex < contextSongs.length ? startIndex : 0;

    final actions = <ActionMenuItem>[
      ActionMenuItem(
        icon: Icons.play_arrow,
        label: 'Reproducir ahora',
        onTap: () async {
          await controller.switchToQueue(kind);
          await controller.setQueueOf(
            kind,
            contextSongs,
            startIndex: safeIndex,
            autoPlay: true,
          );
        },
      ),
      ActionMenuItem(
        icon: Icons.queue_play_next,
        label: 'Añadir a la cola',
        onTap: () async {
          await controller.switchToQueue(kind);
          await controller.addToQueueOf(kind, song);
        },
      ),
      ActionMenuItem(
        icon: Icons.playlist_add,
        label: 'Añadir todo a la cola',
        onTap: () async {
          for (final s in contextSongs) {
            await controller.addToQueueOf(kind, s);
          }
        },
      ),
      ..._queueAddRemove(song),
    ];

    await ActionMenu.show(
      context,
      title: song.title,
      subtitle: song.subtitle,
      coverPath: song.coverPath,
      fallbackIcon: _fallbackIcon(song),
      actions: actions,
    );
  }

  // ============================================================
  // MENÚ DE CONTEXTO (long-press / tap derecho)
  // ============================================================

  static Future<void> showSheet(
    BuildContext context,
    Song song, {
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    final actions = _buildContextActions(
      context,
      song,
      queueContext: queueContext,
      queueIndex: queueIndex,
    );
    await ActionMenu.show(
      context,
      title: song.title,
      subtitle: song.subtitle,
      coverPath: song.coverPath,
      fallbackIcon: _fallbackIcon(song),
      actions: actions,
    );
  }

  static Future<void> showAt(
    BuildContext context,
    Song song, {
    required Offset globalPosition,
    List<Song>? queueContext,
    int? queueIndex,
  }) {
    final actions = _buildContextActions(
      context,
      song,
      queueContext: queueContext,
      queueIndex: queueIndex,
    );
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
    Song song, {
    List<Song>? queueContext,
    int? queueIndex,
  }) {
    if (song.kind == MediaKind.podcast) {
      final hasProgress = _hasProgress(song);

      return [
        // --- Reproducción ---
        // Sin progreso guardado: un solo botón "Reproducir" (desde 0).
        // Con progreso: "Reproducir desde el principio" + "Reanudar".
        ActionMenuItem(
          icon: hasProgress ? Icons.replay : Icons.play_arrow,
          label: hasProgress
              ? 'Reproducir desde el principio'
              : 'Reproducir',
          onTap: () => _playPodcastFromStart(
            song,
            queueContext: queueContext,
            queueIndex: queueIndex,
          ),
        ),
        if (hasProgress)
          ActionMenuItem(
            icon: Icons.play_circle_outline,
            label: 'Reanudar',
            onTap: () => _resumePodcast(
              song,
              queueContext: queueContext,
              queueIndex: queueIndex,
            ),
          ),

        // --- Cola (solo añadir; sin "Quitar de la cola" en podcast) ---
        ..._queueAddOnly(song),

        // --- Stats / marcado ---
        ..._podcastActions(context, song),
      ];
    }

    final favorites = FavoritesStore.instance;
    final isFav = favorites.contains(song);

    return [
      ActionMenuItem(
        icon: Icons.play_arrow,
        label: 'Reproducir ahora',
        onTap: () => _playNow(
          song,
          queueContext: queueContext,
          queueIndex: queueIndex,
        ),
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
        },
      ),
      ..._musicActions(context, song),
    ];
  }

  /// Solo la acción de añadir a la cola (si no está ya). No incluye
  /// "Quitar de la cola". Se usa en el menú de podcast.
  static List<ActionMenuItem> _queueAddOnly(Song song) {
    final c = PlaybackController.instance;
    final handler = c.isReady ? c.handler : null;
    final kind = song.kind;

    final queueSongs = handler?.songsOf(kind) ?? const <Song>[];
    final inQueue = queueSongs.any((s) => s.path == song.path);

    if (inQueue) return const [];
    return [
      ActionMenuItem(
        icon: Icons.queue_music,
        label: 'Añadir a la cola',
        onTap: () async {
          if (handler == null) return;
          await handler.addToQueueOf(kind, song);
        },
      ),
    ];
  }

  static List<ActionMenuItem> _queueAddRemove(Song song) {
    final c = PlaybackController.instance;
    final handler = c.isReady ? c.handler : null;
    final kind = song.kind;

    final queueSongs = handler?.songsOf(kind) ?? const <Song>[];
    final inQueue = queueSongs.any((s) => s.path == song.path);
    final isCurrent =
        handler != null &&
        handler.activeQueueKind == kind &&
        handler.currentSong?.path == song.path;

    if (!inQueue) {
      return [
        ActionMenuItem(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          onTap: () async {
            if (handler == null) return;
            await handler.addToQueueOf(kind, song);
          },
        ),
      ];
    }
    return [
      ActionMenuItem(
        icon: Icons.playlist_remove,
        label: isCurrent
            ? 'Quitar de la cola (sonando ahora)'
            : 'Quitar de la cola',
        isDestructive: true,
        enabled: !isCurrent,
        onTap: () async {
          if (handler == null) return;
          final idx = queueSongs.indexWhere((s) => s.path == song.path);
          if (idx >= 0) {
            await handler.removeFromQueueOf(kind, idx);
          }
        },
      ),
    ];
  }

  static Future<void> _playNow(
    Song song, {
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    final c = PlaybackController.instance;
    if (!c.isReady) return;

    final ctx = queueContext;
    if (ctx == null || ctx.isEmpty) {
      await _replaceQueueAndPlay(song);
      return;
    }

    final kind = song.kind;
    final safeIndex = (queueIndex != null &&
            queueIndex >= 0 &&
            queueIndex < ctx.length &&
            ctx[queueIndex].path == song.path)
        ? queueIndex
        : ctx.indexWhere((s) => s.path == song.path);

    final startIndex = safeIndex >= 0 ? safeIndex : 0;

    try {
      await c.switchToQueue(kind);
      await c.setQueueOf(
        kind,
        ctx,
        startIndex: startIndex,
        autoPlay: true,
      );
    } catch (e) {
      debugPrint('SongContextMenu: no se pudo reproducir contexto -> $e');
    }
  }

  static Future<void> _replaceQueueAndPlay(Song song) async {
    final c = PlaybackController.instance;
    if (!c.isReady) return;
    try {
      await c.playOnly(song);
    } catch (e) {
      debugPrint('SongContextMenu: no se pudo reproducir -> $e');
    }
  }

  // ============================================================
  // Reproducción de podcast: desde el principio / reanudar
  // ============================================================

  /// ¿Hay progreso guardado pendiente de terminar para [song]?
  /// Devuelve `false` si nunca se ha empezado o si ya está completado.
  static bool _hasProgress(Song song) {
    final stats = StatsService.instance;
    if (stats.isPlayed(song)) return false;
    final progress = stats.progressOf(song);
    final position = progress?.position ?? Duration.zero;
    return position > Duration.zero && !(progress?.completed ?? false);
  }

  /// Indica si el episodio tiene progreso guardado pendiente de terminar.
  static bool _canResume(Song song) => _hasProgress(song);

  /// Carga en la cola todos los episodios de [queueContext] (si se
  /// proporciona) y reproduce [song] desde [start]. Si no hay contexto,
  /// se comporta como antes: cola de un solo episodio.
  static Future<void> _playPodcastInContext(
    Song song, {
    required Duration start,
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    final c = PlaybackController.instance;
    if (!c.isReady) return;

    final ctx = queueContext
        ?.where((s) => s.kind == MediaKind.podcast)
        .toList();

    if (kDebugMode) {
      debugPrint(
        'SongContextMenu._playPodcastInContext: '
        'ctx=${ctx?.length ?? 0}, queueIndex=$queueIndex, start=$start',
      );
    }

    try {
      if (ctx == null || ctx.isEmpty) {
        await c.setQueueOf(
          song.kind,
          [song],
          startIndex: 0,
          autoPlay: true,
          startPosition: start,
        );
        return;
      }

      int index;
      final provided = queueIndex;
      if (provided != null &&
          provided >= 0 &&
          provided < ctx.length &&
          ctx[provided].path == song.path) {
        index = provided;
      } else {
        index = ctx.indexWhere((s) => s.path == song.path);
      }

      if (index < 0) {
        ctx.insert(0, song);
        index = 0;
      }

      if (kDebugMode) {
        debugPrint(
          'SongContextMenu._playPodcastInContext: setQueueOf con '
          '${ctx.length} episodios, startIndex=$index',
        );
      }

      await c.setQueueOf(
        song.kind,
        ctx,
        startIndex: index,
        autoPlay: true,
        startPosition: start,
      );
    } catch (e) {
      debugPrint('SongContextMenu: no se pudo reproducir podcast -> $e');
    }
  }

  /// Reproduce el episodio clicado desde el inicio (posición 0) y deja
  /// todos los capítulos del podcast en la cola.
  static Future<void> _playPodcastFromStart(
    Song song, {
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    StatsService.instance.markAsUnplayed(song);

    await _playPodcastInContext(
      song,
      start: Duration.zero,
      queueContext: queueContext,
      queueIndex: queueIndex,
    );
  }

  /// Reanuda el episodio clicado desde su progreso guardado y deja
  /// todos los capítulos del podcast en la cola.
  static Future<void> _resumePodcast(
    Song song, {
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    final progress = StatsService.instance.progressOf(song);
    final position = progress?.position ?? Duration.zero;

    await _playPodcastInContext(
      song,
      start: position,
      queueContext: queueContext,
      queueIndex: queueIndex,
    );
  }

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
        label: hasAlbum ? 'Ver álbum' : 'Sin álbum disponible',
        enabled: hasAlbum,
        onTap: () {
          if (!hasAlbum) return;
          _openPlaylist(context, album!);
        },
      ),
      ActionMenuItem(
        icon: Icons.person_outline,
        label: hasArtist ? 'Ver artista' : 'Sin artista disponible',
        enabled: hasArtist,
        onTap: () {
          if (!hasArtist) return;
          _openPlaylist(context, artist!);
        },
      ),
      ActionMenuItem(
        icon: Icons.info_outline,
        label: 'Ver detalles',
        onTap: () => _todo(context, 'Detalles'),
      ),
    ];
  }

  static Future<void> _addToPlaylist(
    BuildContext context,
    Song song,
  ) async {
    final changed = await PlaylistPickerDialog.show(context, song);
    if (!changed || !context.mounted) return;
  }

  static List<ActionMenuItem> _podcastActions(
    BuildContext context,
    Song song,
  ) {
    final stats = StatsService.instance;
    final progress = stats.progressOf(song);
    final isPlayed = stats.isPlayed(song);
    final position = progress?.position ?? Duration.zero;
    final hasProgress = position > Duration.zero && !isPlayed;

    return [
      ActionMenuItem(
        icon: isPlayed ? Icons.check_circle : Icons.check_circle_outline,
        label: isPlayed
            ? 'Marcar como no reproducido'
            : 'Marcar como reproducido',
        onTap: () {
          stats.togglePlayed(song);
          if (!context.mounted) return;
          _showToast(
            context,
            isPlayed
                ? 'Marcado como no reproducido'
                : 'Marcado como reproducido',
          );
        },
      ),
      if (hasProgress)
        ActionMenuItem(
          icon: Icons.restart_alt,
          label: 'Borrar progreso',
          onTap: () {
            stats.markAsUnplayed(song);
            if (!context.mounted) return;
          },
        ),
      ActionMenuItem(
        icon: Icons.info_outline,
        label: 'Ver detalles',
        onTap: () => _todo(context, 'Detalles del episodio'),
      ),
    ];
  }

  static void _showToast(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  static void _openPlaylist(BuildContext context, Playlist playlist) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 380,
              maxHeight: 640,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Material(
                color: scheme.surface,
                child: PlaylistDetailScreen(
                  playlist: playlist,
                  showBackButton: false,
                ),
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

  static IconData _fallbackIcon(Song song) =>
      song.kind == MediaKind.podcast ? Icons.mic : Icons.music_note;

  static void _todo(BuildContext context, String label) {
    // Placeholder para acciones aún no implementadas.
  }
}
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
import 'song_details_dialog.dart';

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
      ..._queueToggleAction(song),
    ];
  }

  // ============================================================
  // MENÚ DE COLA CON CONTEXTO
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
        startIndex >= 0 && startIndex < contextSongs.length
            ? startIndex
            : 0;

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

      // Una sola acción que cambia entre:
      // "Añadir a la cola" / "Quitar de la cola"
      ..._queueToggleAction(song),
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

        // --- Cola ---
        //
        // Los podcasts mantienen solamente la opción de añadir.
        // No se muestra "Quitar de la cola" aquí.
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

      // Una sola acción dinámica:
      // "Añadir a la cola" si no está
      // "Quitar de la cola" si ya está
      ..._queueToggleAction(song),

      ActionMenuItem(
        icon: Icons.playlist_add,
        label: 'Añadir a playlist',
        onTap: () => _addToPlaylist(context, song),
      ),

      ActionMenuItem(
        icon: isFav ? Icons.favorite : Icons.favorite_border,
        label: isFav
            ? 'Quitar de favoritos'
            : 'Añadir a favoritos',
        onTap: () async {
          await favorites.toggle(song);

          if (!context.mounted) return;
        },
      ),

      ..._musicActions(context, song),
    ];
  }

  // ============================================================
  // ACCIÓN DE COLA DINÁMICA
  // ============================================================

  /// Devuelve UNA sola acción relacionada con la cola.
  ///
  /// Si la canción NO está en la cola:
  ///   -> "Añadir a la cola"
  ///
  /// Si la canción YA está en la cola:
  ///   -> "Quitar de la cola"
  ///
  /// Si es la canción que está sonando:
  ///   -> "Quitar de la cola (sonando ahora)"
  ///      pero permanece deshabilitada para evitar eliminar
  ///      accidentalmente la canción actual.
  static List<ActionMenuItem> _queueToggleAction(Song song) {
    final controller = PlaybackController.instance;
    final handler = controller.isReady ? controller.handler : null;

    if (handler == null) {
      return [
        ActionMenuItem(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          enabled: false,
          onTap: () {},
        ),
      ];
    }

    final kind = song.kind;

    final queueSongs = handler.songsOf(kind);

    final queueIndex = queueSongs.indexWhere(
      (s) => s.path == song.path,
    );

    final inQueue = queueIndex >= 0;

    final isCurrent =
        handler.activeQueueKind == kind &&
        handler.currentSong?.path == song.path;

    // ----------------------------------------------------------
    // NO ESTÁ EN LA COLA -> AÑADIR
    // ----------------------------------------------------------

    if (!inQueue) {
      return [
        ActionMenuItem(
          icon: Icons.queue_music,
          label: 'Añadir a la cola',
          onTap: () async {
            await handler.addToQueueOf(kind, song);
          },
        ),
      ];
    }

    // ----------------------------------------------------------
    // YA ESTÁ EN LA COLA -> QUITAR
    // ----------------------------------------------------------

    return [
      ActionMenuItem(
        icon: Icons.playlist_remove,
        label: isCurrent
            ? 'Quitar de la cola (sonando ahora)'
            : 'Quitar de la cola',
        isDestructive: true,
        enabled: !isCurrent,
        onTap: () async {
          if (isCurrent) return;

          final currentIndex = handler
              .songsOf(kind)
              .indexWhere((s) => s.path == song.path);

          if (currentIndex < 0) return;

          await handler.removeFromQueueOf(
            kind,
            currentIndex,
          );
        },
      ),
    ];
  }

  // ============================================================
  // SOLO AÑADIR A COLA
  // ============================================================

  /// Acción exclusiva para podcasts.
  ///
  /// Si el podcast ya está en la cola no muestra ninguna acción.
  static List<ActionMenuItem> _queueAddOnly(Song song) {
    final controller = PlaybackController.instance;
    final handler = controller.isReady
        ? controller.handler
        : null;

    final kind = song.kind;

    final queueSongs =
        handler?.songsOf(kind) ?? const <Song>[];

    final inQueue = queueSongs.any(
      (s) => s.path == song.path,
    );

    if (inQueue) {
      return const [];
    }

    return [
      ActionMenuItem(
        icon: Icons.queue_music,
        label: 'Añadir a la cola',
        onTap: () async {
          if (handler == null) return;

          await handler.addToQueueOf(
            kind,
            song,
          );
        },
      ),
    ];
  }

  // ============================================================
  // REPRODUCCIÓN
  // ============================================================

  static Future<void> _playNow(
    Song song, {
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    // "Reproducir ahora" debe reproducir ÚNICAMENTE la canción
    // seleccionada, incluso cuando el menú fue abierto desde una
    // playlist/listado que proporciona queueContext.
    //
    // No usamos queueContext aquí porque eso cargaría todas las
    // canciones del contexto en la cola.
    await _replaceQueueAndPlay(song);
  }

  static Future<void> _replaceQueueAndPlay(
    Song song,
  ) async {
    final controller = PlaybackController.instance;

    if (!controller.isReady) return;

    try {
      await controller.playOnly(song);
    } catch (e) {
      debugPrint(
        'SongContextMenu: no se pudo reproducir -> $e',
      );
    }
  }

  // ============================================================
  // REPRODUCCIÓN DE PODCAST
  // ============================================================

  /// ¿Hay progreso guardado pendiente de terminar para [song]?
  ///
  /// Devuelve false si nunca se ha empezado o si ya está completado.
  static bool _hasProgress(Song song) {
    final stats = StatsService.instance;

    if (stats.isPlayed(song)) return false;

    final progress = stats.progressOf(song);
    final position =
        progress?.position ?? Duration.zero;

    return position > Duration.zero &&
        !(progress?.completed ?? false);
  }

  static bool _canResume(Song song) {
    return _hasProgress(song);
  }

  /// Carga en la cola todos los episodios de [queueContext]
  /// y reproduce [song] desde [start].
  ///
  /// Si no hay contexto, se comporta como antes:
  /// cola de un solo episodio.
  static Future<void> _playPodcastInContext(
    Song song, {
    required Duration start,
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    final controller = PlaybackController.instance;

    if (!controller.isReady) return;

    final contextSongs = queueContext
        ?.where(
          (s) => s.kind == MediaKind.podcast,
        )
        .toList();

    if (kDebugMode) {
      debugPrint(
        'SongContextMenu._playPodcastInContext: '
        'ctx=${contextSongs?.length ?? 0}, '
        'queueIndex=$queueIndex, '
        'start=$start',
      );
    }

    try {
      if (contextSongs == null ||
          contextSongs.isEmpty) {
        await controller.setQueueOf(
          song.kind,
          [song],
          startIndex: 0,
          autoPlay: true,
          startPosition: start,
        );

        return;
      }

      int index;

      final providedIndex = queueIndex;

      if (providedIndex != null &&
          providedIndex >= 0 &&
          providedIndex < contextSongs.length &&
          contextSongs[providedIndex].path == song.path) {
        index = providedIndex;
      } else {
        index = contextSongs.indexWhere(
          (s) => s.path == song.path,
        );
      }

      if (index < 0) {
        contextSongs.insert(0, song);
        index = 0;
      }

      if (kDebugMode) {
        debugPrint(
          'SongContextMenu._playPodcastInContext: '
          'setQueueOf con ${contextSongs.length} episodios, '
          'startIndex=$index',
        );
      }

      await controller.setQueueOf(
        song.kind,
        contextSongs,
        startIndex: index,
        autoPlay: true,
        startPosition: start,
      );
    } catch (e) {
      debugPrint(
        'SongContextMenu: no se pudo reproducir podcast -> $e',
      );
    }
  }

  /// Reproduce el episodio desde el principio.
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

  /// Reanuda el episodio desde su progreso guardado.
  static Future<void> _resumePodcast(
    Song song, {
    List<Song>? queueContext,
    int? queueIndex,
  }) async {
    final progress =
        StatsService.instance.progressOf(song);

    final position =
        progress?.position ?? Duration.zero;

    await _playPodcastInContext(
      song,
      start: position,
      queueContext: queueContext,
      queueIndex: queueIndex,
    );
  }

  // ============================================================
  // ACCIONES MUSICALES
  // ============================================================

  static List<ActionMenuItem> _musicActions(
    BuildContext context,
    Song song,
  ) {
    final album = _findAlbum(song);
    final artist = _findArtist(song);

    final hasAlbum =
        song.hasAlbum && album != null;

    final hasArtist =
        song.hasArtist && artist != null;

    return [
      ActionMenuItem(
        icon: Icons.album_outlined,
        label: hasAlbum
            ? 'Ver álbum'
            : 'Sin álbum disponible',
        enabled: hasAlbum,
        onTap: () {
          if (!hasAlbum) return;

          _openPlaylist(
            context,
            album!,
          );
        },
      ),
      ActionMenuItem(
        icon: Icons.person_outline,
        label: hasArtist
            ? 'Ver artista'
            : 'Sin artista disponible',
        enabled: hasArtist,
        onTap: () {
          if (!hasArtist) return;

          _openPlaylist(
            context,
            artist!,
          );
        },
      ),
      ActionMenuItem(
        icon: Icons.info_outline,
        label: 'Ver detalles',
        onTap: () => SongDetailsDialog.show(context, song),
      ),
    ];
  }

  static Future<void> _addToPlaylist(
    BuildContext context,
    Song song,
  ) async {
    final changed =
        await PlaylistPickerDialog.show(
      context,
      song,
    );

    if (!changed || !context.mounted) return;
  }

  // ============================================================
  // ACCIONES DE PODCAST
  // ============================================================

  static List<ActionMenuItem> _podcastActions(
    BuildContext context,
    Song song,
  ) {
    final stats = StatsService.instance;

    final progress =
        stats.progressOf(song);

    final isPlayed =
        stats.isPlayed(song);

    final position =
        progress?.position ?? Duration.zero;

    final hasProgress =
        position > Duration.zero && !isPlayed;

    return [
      ActionMenuItem(
        icon: isPlayed
            ? Icons.check_circle
            : Icons.check_circle_outline,
        label: isPlayed
            ? 'Marcar como no completado'
            : 'Marcar como completado',
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
        onTap: () => SongDetailsDialog.show(context, song),
      ),
    ];
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  static void _showToast(
    BuildContext context,
    String message,
  ) {
    final messenger =
        ScaffoldMessenger.maybeOf(context);

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

  static void _openPlaylist(
    BuildContext context,
    Playlist playlist,
  ) {
    showDialog<void>(
      context: context,
      barrierColor:
          Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        final scheme =
            Theme.of(dialogContext).colorScheme;

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding:
              const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 380,
              maxHeight: 640,
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(18),
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

    for (final playlist
        in LibraryScreen.currentAlbums) {
      if (playlist.title == target) {
        return playlist;
      }
    }

    return null;
  }

  static Playlist? _findArtist(Song song) {
    if (!song.hasArtist) return null;

    final target = song.artistOrUnknown;

    for (final playlist
        in LibraryScreen.currentArtists) {
      if (playlist.title == target) {
        return playlist;
      }
    }

    return null;
  }

  static IconData _fallbackIcon(Song song) =>
      song.kind == MediaKind.podcast
          ? Icons.mic
          : Icons.music_note;
}
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_controller.dart';
import 'music_player_screen.dart';
import 'podcast_player_screen.dart';

/// Breakpoint a partir del cual el player se muestra como popup flotante
/// en lugar de pantalla completa (coherente con el usado en el player).
const double _kDesktopBreakpoint = 900.0;

/// Abre el player adecuado según [Song.kind].
///
/// En pantallas grandes (escritorio/web) el reproductor se abre como un
/// **popup flotante** con bordes redondeados y sombra. En móvil se mantiene
/// la transición de pantalla completa deslizante.
///
/// Una vez abierto, el player **cambia en vivo** si la cola activa cambia
/// de `MediaKind` (música ↔ capítulos), sin necesidad de cerrar y reabrir.
///
/// [heroTagPrefix] indica qué miniplayer está abriendo el player, para que
/// el `Hero` del cover use un tag coherente con el del origen. Si es `null`
/// (p. ej. abierto desde otra ruta), no se aplica Hero.
Future<void> openPlayerFor(
  BuildContext context,
  Song song, {
  String? heroTagPrefix,
}) {
  final isDesktop =
      MediaQuery.sizeOf(context).width >= _kDesktopBreakpoint;

  if (isDesktop) {
    return _showFloatingPlayer(context, song, heroTagPrefix);
  }

  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => _AdaptivePlayerScreen(
        fallbackSong: song,
        heroTagPrefix: heroTagPrefix,
      ),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    ),
  );
}

/// Popup flotante para escritorio: diálogo redimensionable con el player.
Future<void> _showFloatingPlayer(
  BuildContext context,
  Song song,
  String? heroTagPrefix,
) {
  final scheme = Theme.of(context).colorScheme;
  final media = MediaQuery.sizeOf(context);

  // Tamaño inicial del popup: cómodo para el layout de escritorio
  // (izquierda player + derecha cola). Nunca mayor que la ventana.
  final initialWidth = (media.width * 0.82).clamp(720.0, 1280.0);
  final initialHeight = (media.height * 0.86).clamp(520.0, 820.0);

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    useSafeArea: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      elevation: 24,
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      // Diálogo flotante: altura máxima acotada a la ventana.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: initialWidth,
          maxHeight: initialHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: _DraggablePlayerContent(
            fallbackSong: song,
            heroTagPrefix: heroTagPrefix,
          ),
        ),
      ),
    ),
  );
}

/// Contenido del popup de escritorio: envuelve el player adaptativo.
class _DraggablePlayerContent extends StatelessWidget {
  final Song fallbackSong;
  final String? heroTagPrefix;

  const _DraggablePlayerContent({
    required this.fallbackSong,
    required this.heroTagPrefix,
  });

  @override
  Widget build(BuildContext context) {
    return _AdaptivePlayerScreen(
      fallbackSong: fallbackSong,
      heroTagPrefix: heroTagPrefix,
    );
  }
}

/// Selecciona el screen (música o podcast) según la **cola activa** del
/// reproductor, y se reconstruye cuando esa cola cambia.
///
/// Usa [fallbackSong] para decidir el screen del primer frame si el
/// `PlaybackController` todavía no está listo (no debería ocurrir en la
/// práctica, porque el player solo se abre con reproducción activa).
class _AdaptivePlayerScreen extends StatelessWidget {
  final Song fallbackSong;
  final String? heroTagPrefix;

  const _AdaptivePlayerScreen({
    required this.fallbackSong,
    required this.heroTagPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    if (!controller.isReady) {
      // Sin controller listo: nos guiamos por el kind de la canción.
      return _screenFor(fallbackSong.kind);
    }

    return StreamBuilder<MediaKind>(
      stream: controller.activeQueue,
      initialData: controller.activeQueueKind,
      builder: (context, snap) {
        final kind = snap.data ?? fallbackSong.kind;
        return _screenFor(kind);
      },
    );
  }

  Widget _screenFor(MediaKind kind) {
    return kind == MediaKind.podcast
        ? PodcastPlayerScreen(heroTagPrefix: heroTagPrefix)
        : MusicPlayerScreen(heroTagPrefix: heroTagPrefix);
  }
}
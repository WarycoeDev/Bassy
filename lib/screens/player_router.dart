import 'package:flutter/material.dart';

import '../models/song.dart';
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
      pageBuilder: (_, __, ___) => song.kind == MediaKind.podcast
          ? PodcastPlayerScreen(heroTagPrefix: heroTagPrefix)
          : MusicPlayerScreen(heroTagPrefix: heroTagPrefix),
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
            song: song,
            heroTagPrefix: heroTagPrefix,
          ),
        ),
      ),
    ),
  );
}

/// Contenido del popup: header arrastrable + player embebido.
///
/// Como el player tiene su propio `AppBar` con botón de cerrar, aquí solo
/// envolvemos el screen para que se adapte al diálogo (sin `Scaffold` extra).
class _DraggablePlayerContent extends StatelessWidget {
  final Song song;
  final String? heroTagPrefix;

  const _DraggablePlayerContent({
    required this.song,
    required this.heroTagPrefix,
  });

  @override
  Widget build(BuildContext context) {
    // El screen ya trae Scaffold + AppBar; dentro de un Dialog se ve bien
    // como tarjeta flotante. Usamos ClipRect para respetar bordes.
    return song.kind == MediaKind.podcast
        ? PodcastPlayerScreen(heroTagPrefix: heroTagPrefix)
        : MusicPlayerScreen(heroTagPrefix: heroTagPrefix);
  }
}
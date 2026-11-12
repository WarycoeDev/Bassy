// lib/screens/player_router.dart
import 'package:flutter/material.dart';

import '../models/song.dart';
import 'music_player_screen.dart';
import 'podcast_player_screen.dart';

/// Abre el player adecuado según [Song.kind].
///
/// [heroTagPrefix] indica qué miniplayer está abriendo el player, para que
/// el `Hero` del cover use un tag coherente con el del origen. Si es `null`
/// (p. ej. abierto desde otra ruta), no se aplica Hero.
Future<void> openPlayerFor(
  BuildContext context,
  Song song, {
  String? heroTagPrefix,
}) {
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
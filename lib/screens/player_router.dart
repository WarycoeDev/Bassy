// lib/screens/player_router.dart
import 'package:flutter/material.dart';

import '../models/song.dart';
import 'music_player_screen.dart';
import 'podcast_player_screen.dart';

/// Abre el player adecuado según [Song.kind].
Future<void> openPlayerFor(BuildContext context, Song song) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => song.kind == MediaKind.podcast
          ? const PodcastPlayerScreen()
          : const MusicPlayerScreen(),
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
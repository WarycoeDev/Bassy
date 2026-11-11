// lib/widgets/playback_menu.dart
import 'package:flutter/material.dart';

import 'action_menu.dart';

/// Acción específica de reproducción.
///
/// Es un alias semántico de [ActionMenuItem] para que el código de
/// playback siga leyéndose igual, pero la presentación vive en [ActionMenu].
typedef PlaybackMenuAction = ActionMenuItem;

/// Fachada de playback sobre [ActionMenu].
///
/// Aporta valores por defecto orientados a audio (icono de fallback
/// musical) y deja la presentación y el estilo al menú genérico.
class PlaybackMenu {
  PlaybackMenu._();

  static Future<bool> show(
    BuildContext context, {
    required List<PlaybackMenuAction> actions,
    String? title,
    String? subtitle,
    Widget? leading,
    String? coverPath,
    bool isPodcast = false,
    String cancelLabel = 'Cancelar',
  }) {
    return ActionMenu.show(
      context,
      actions: actions,
      title: title,
      subtitle: subtitle,
      leading: leading,
      coverPath: coverPath,
      fallbackIcon: isPodcast ? Icons.mic : Icons.music_note,
      cancelLabel: cancelLabel,
    );
  }

  static Future<void> showAt(
    BuildContext context, {
    required List<PlaybackMenuAction> actions,
    required Offset globalPosition,
    String? title,
    String? subtitle,
    String? coverPath,
    bool isPodcast = false,
  }) {
    return ActionMenu.showAt(
      context,
      actions: actions,
      globalPosition: globalPosition,
      title: title,
      subtitle: subtitle,
      coverPath: coverPath,
      fallbackIcon: isPodcast ? Icons.mic : Icons.music_note,
    );
  }
}
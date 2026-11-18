// lib/widgets/playback_menu.dart
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/playback_queue.dart';
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

  /// Construye la acción "Añadir a la cola" para una colección de canciones
  /// (p. ej. todas las de una playlist), deshabilitándola si no hay nada
  /// nuevo que añadir a [queue].
  ///
  /// [onAdd] recibe solo las canciones que faltan, para que el caller no
  /// tenga que filtrar de nuevo.
  ///
  /// El `enabled` se evalúa en el momento de construir la acción, es decir,
  /// justo cuando se va a abrir el menú.
  static PlaybackMenuAction addToQueueActionFor({
    required PlaybackQueue queue,
    required List<Song> candidates,
    required void Function(List<Song> missing) onAdd,
    String label = 'Añadir a la cola',
    IconData icon = Icons.queue_music,
    String? id,
  }) {
    final missing = queue.missingFrom(candidates);
    final enabled = missing.isNotEmpty;
    return PlaybackMenuAction(
      id: id ?? 'add_to_queue',
      icon: icon,
      label: label,
      enabled: enabled,
      onTap: enabled ? () => onAdd(missing) : null,
    );
  }
}
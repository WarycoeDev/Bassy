// lib/widgets/action_menu.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Acción individual que se muestra en el [ActionMenu].
class ActionMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  /// Si es `false`, la acción se muestra atenuada y no responde a toques.
  final bool enabled;

  const ActionMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.enabled = true,
  });
}

/// Menú de acciones reutilizable y con estilo global.
///
/// Pensado como "placeholder" común para cualquier parte de la app:
/// canciones, podcasts, playlists, ajustes, etc.
///
/// Dos modos:
///  - [show]: bottom sheet (móvil / por defecto).
///  - [showAt]: popup anclado a una posición (clic derecho / long-press).
///  - [confirm]: diálogo de confirmación con el mismo estilo del menú.
class ActionMenu {
  ActionMenu._();

  // ---------- Bottom sheet ----------

  static Future<bool> show(
    BuildContext context, {
    required List<ActionMenuItem> actions,
    String? title,
    String? subtitle,
    Widget? leading,
    String? coverPath,
    IconData fallbackIcon = Icons.more_horiz,
    String cancelLabel = 'Cancelar',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 380,
              maxHeight: 640,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null ||
                    subtitle != null ||
                    leading != null ||
                    coverPath != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MenuHeader(
                            title: title,
                            subtitle: subtitle,
                            leading: leading,
                            coverPath: coverPath,
                            fallbackIcon: fallbackIcon,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(ctx, false),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      // Material con clip para que el hover/ripple de las
                      // opciones se recorte a las esquinas redondeadas.
                      child: Material(
                        color: Colors.transparent,
                        clipBehavior: Clip.antiAlias,
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              _MenuActionTile(
                                action: actions[i],
                                onTap: actions[i].enabled
                                    ? () {
                                        Navigator.pop(ctx, true);
                                        actions[i].onTap?.call();
                                      }
                                    : null,
                              ),
                              if (i != actions.length - 1)
                                Divider(
                                  height: 1,
                                  indent: 52,
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Material(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: Text(
                            cancelLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  // ---------- Popup anclado ----------

  /// Abre un menú flotante en [globalPosition] (coordenadas globales).
  static Future<void> showAt(
    BuildContext context, {
    required List<ActionMenuItem> actions,
    required Offset globalPosition,
    String? title,
    String? subtitle,
    String? coverPath,
    IconData fallbackIcon = Icons.more_horiz,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final scheme = Theme.of(context).colorScheme;

    await showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _MenuHeader(
            title: title,
            subtitle: subtitle,
            coverPath: coverPath,
            fallbackIcon: fallbackIcon,
          ),
        ),
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: 1,
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        for (final action in actions)
          PopupMenuItem<void>(
            enabled: action.enabled,
            onTap: action.enabled ? action.onTap : null,
            child: _PopupActionRow(action: action),
          ),
      ],
    );
  }

  // ---------- Confirmación ----------

  /// Diálogo de confirmación con el mismo estilo que el resto del menú.
  ///
  /// Reutiliza el header (portada + título + subtítulo) para dar contexto,
  /// y ofrece un par de botones: cancelar (no destructivo) y confirmar
  /// (destructivo por defecto). Devuelve `true` si el usuario confirma.
  static Future<bool> confirm(
    BuildContext context, {
    required String message,
    String? title,
    String? subtitle,
    String? coverPath,
    IconData fallbackIcon = Icons.more_horiz,
    String confirmLabel = 'Quitar',
    String cancelLabel = 'Cancelar',
    IconData confirmIcon = Icons.delete_outline_rounded,
  }) async {
    HapticFeedback.mediumImpact();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header con el mismo estilo que el menú.
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _MenuHeader(
                          title: title,
                          subtitle: subtitle,
                          coverPath: coverPath,
                          fallbackIcon: fallbackIcon,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Mensaje de confirmación.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                ),
                // Botones con el mismo lenguaje visual que las acciones.
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx, false),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              child: Center(
                                child: Text(
                                  cancelLabel,
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Material(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx, true),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    confirmIcon,
                                    size: 18,
                                    color: scheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    confirmLabel,
                                    style: TextStyle(
                                      color: scheme.onErrorContainer,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}

// ---------- Widgets internos ----------

class _PopupActionRow extends StatelessWidget {
  final ActionMenuItem action;
  const _PopupActionRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !action.enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : action.isDestructive
            ? scheme.error
            : scheme.onSurface;

    return Row(
      children: [
        Icon(action.icon, color: color, size: 20),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            action.label,
            style: TextStyle(color: color, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MenuHeader extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final String? coverPath;
  final IconData fallbackIcon;

  const _MenuHeader({
    this.title,
    this.subtitle,
    this.leading,
    this.coverPath,
    required this.fallbackIcon,
  });

  bool get _hasCover {
    final p = coverPath;
    if (p == null || p.isEmpty) return false;
    try {
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget? leadingWidget = leading ??
        (_hasCover
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(coverPath!),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  cacheWidth: 144,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _fallbackCover(scheme),
                ),
              )
            : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (leadingWidget != null) ...[
            leadingWidget,
            const SizedBox(width: 10),
          ] else ...[
            _fallbackCover(scheme),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackCover(ColorScheme scheme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        fallbackIcon,
        color: scheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }
}

class _MenuActionTile extends StatelessWidget {
  final ActionMenuItem action;
  final VoidCallback? onTap;

  const _MenuActionTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    final Color color;
    if (!enabled) {
      color = scheme.onSurface.withValues(alpha: 0.38);
    } else if (action.isDestructive) {
      color = scheme.error;
    } else {
      color = scheme.onSurface;
    }

    return ListTile(
      enabled: enabled,
      leading: Icon(action.icon, color: color),
      title: Text(
        action.label,
        style: TextStyle(color: color, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.standard,
    );
  }
}
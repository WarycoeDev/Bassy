// lib/widgets/nested_navigator_scope.dart
import 'package:flutter/material.dart';

/// Envuelve un [Navigator] anidado y gestiona el botón/gesto de atrás:
///
///  - Si el Navigator interno tiene rutas que popear → las popea.
///  - Si está en la raíz → delega en [onExitRoot] (o lo ignora si es null).
///
/// Esto permite que CUALQUIER ruta empujada dentro de la pestaña
/// (playlists, álbumes, artistas, podcasts, detalles…) se cierre con el
/// back de Android, sin importar desde qué pestaña se haya abierto.
class NestedNavigatorScope extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final VoidCallback? onExitRoot;

  const NestedNavigatorScope({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.onExitRoot,
  });

  @override
  State<NestedNavigatorScope> createState() => _NestedNavigatorScopeState();
}

class _NestedNavigatorScopeState extends State<NestedNavigatorScope> {
  int _depth = 1;

  /// Escucha los cambios de ruta del Navigator interno para mantener
  /// `_depth` sincronizado (push/pop/replace) sin depender solo de
  /// callbacks manuales.
  void _syncDepth() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    final canPop = nav.canPop();
    final newDepth = canPop ? 2 : 1;
    if (newDepth != _depth && mounted) {
      setState(() => _depth = newDepth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final innerCanPop =
        widget.navigatorKey.currentState?.canPop() ?? (_depth > 1);

    return PopScope(
      // Si hay algo dentro: bloqueamos y popemos a mano.
      // Si estamos en la raíz: NO bloqueamos, dejamos que el sistema
      // (AppShell) reciba el back.
      canPop: !innerCanPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final nav = widget.navigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
          _syncDepth();
          return;
        }
        // Sin rutas internas: delegamos al padre.
        widget.onExitRoot?.call();
      },
      child: Navigator(
        key: widget.navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => widget.child,
        ),
        // Sincroniza la profundidad tras cada cambio de ruta (incluye
        // pops disparados por gestos internos, AppBar, etc.).
        observers: [_DepthObserver(_syncDepth)],
      ),
    );
  }
}

class _DepthObserver extends NavigatorObserver {
  final VoidCallback onChanged;
  _DepthObserver(this.onChanged);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onChanged();
  }
}
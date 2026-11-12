// lib/screens/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/mini_player.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _homeIndex = 0;
  static const int _libraryIndex = 1;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = _homeIndex;

  /// Lazy-mount: cada pestaña se construye la primera vez que se visita
  /// y se mantiene montada después.
  late final List<bool> _visited = <bool>[
    true, // Inicio siempre montada
    false,
    false,
    false,
  ];

  final List<Widget> _screens = const [
    HomeScreen(),
    LibraryScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  static const _destinations = <_NavDestination>[
    _NavDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Inicio',
    ),
    _NavDestination(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music_rounded,
      label: 'Biblioteca',
    ),
    _NavDestination(
      icon: Icons.search_rounded,
      selectedIcon: Icons.search_rounded,
      label: 'Búsqueda',
    ),
    _NavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: 'Configuración',
    ),
  ];

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _visited[index] = true; // marcar como visitada → se monta
    });
  }

  /// Móvil: cierra el drawer y cambia de pestaña inmediatamente.
  void _onDrawerItemTapped(int index) {
    _scaffoldKey.currentState?.closeDrawer();
    _onItemTapped(index);
  }

  /// Único punto que maneja el botón/gesto de atrás de Android.
  /// Orden de prioridad:
  ///  1. Drawer abierto → cerrarlo.
  ///  2. Biblioteca: playlist/álbum/artista inline abierto → cerrarlo.
  ///  3. Biblioteca: ruta empujada en su Navigator anidado → popearla.
  ///  4. Pestaña distinta de Inicio → volver a Inicio.
  ///  5. Si no, salir de la app.
  void _handleBack() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }

    if (_selectedIndex == _libraryIndex) {
      if (LibraryScreen.handleBack?.call() ?? false) return;

      final nav = LibraryScreen.currentNavigator;
      if (nav != null && nav.mounted && nav.canPop()) {
        nav.pop();
        return;
      }
    }

    if (_selectedIndex != _homeIndex) {
      setState(() => _selectedIndex = _homeIndex);
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 800;
    final scheme = Theme.of(context).colorScheme;

    // IndexedStack lazy: las pestañas no visitadas NO se construyen hasta
    // el primer tap (se sustituyen por un SizedBox vacío). Una vez
    // visitadas, quedan montadas y conservan su estado.
    // Todo va envuelto en una transición que se dispara al cambiar de índice.
    final content = _TabTransition(
      index: _selectedIndex,
      child: IndexedStack(
        index: _selectedIndex,
        sizing: StackFit.expand,
        children: [
          for (var i = 0; i < _screens.length; i++)
            _visited[i]
                ? RepaintBoundary(child: _screens[i])
                : const SizedBox.shrink(),
        ],
      ),
    );

    final Widget scaffold;

    if (isWide) {
      // ---------- Tablet / PC ----------
      scaffold = Scaffold(
        key: _scaffoldKey,
        body: Row(
          children: [
            SizedBox(
              width: 280,
              child: _DrawerPanel(
                selectedIndex: _selectedIndex,
                onItemTapped: _onItemTapped,
                destinations: _destinations,
                scheme: scheme,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: scheme.outlineVariant,
            ),
            Expanded(child: content),
          ],
        ),
      );
    } else {
      // ---------- Móvil ----------
      scaffold = Scaffold(
        key: _scaffoldKey,
        drawerEdgeDragWidth: 40,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 48,
          leadingWidth: 48,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        drawer: _StyledDrawer(
          selectedIndex: _selectedIndex,
          onItemTapped: _onDrawerItemTapped,
          destinations: _destinations,
          scheme: scheme,
        ),
        body: Stack(
          children: [
            Positioned.fill(child: content),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                // Aislado: sus actualizaciones (progreso, etc.) no repintan
                // el resto y viceversa.
                child: RepaintBoundary(child: MiniPlayerBar()),
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: scaffold,
    );
  }
}

// ============================================================
// TRANSICIÓN ENTRE PESTAÑAS (fade + slide sutil)
// ============================================================
class _TabTransition extends StatefulWidget {
  final int index;
  final Widget child;

  const _TabTransition({required this.index, required this.child});

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1, // primera carga sin animación
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void didUpdateWidget(covariant _TabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;

    // Respeta "reducir animaciones" del sistema.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}

// ============================================================
// HEADER ESTÁTICO (compartido móvil / PC)
// ============================================================
class _DrawerHeader extends StatelessWidget {
  final ColorScheme scheme;

  const _DrawerHeader({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.surfaceContainerHigh,
              scheme.surfaceContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.music_note_rounded,
                color: scheme.onSurface,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bassy Music',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Bienvenido de nuevo',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PANEL LATERAL (tablet / PC)
// ============================================================
class _DrawerPanel extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<_NavDestination> destinations;
  final ColorScheme scheme;

  const _DrawerPanel({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.destinations,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrawerHeader(scheme: scheme),
          const SizedBox(height: 8),
          Expanded(
            child: _NavList(
              selectedIndex: selectedIndex,
              onItemTapped: onItemTapped,
              destinations: destinations,
              scheme: scheme,
            ),
          ),
          const RepaintBoundary(child: MiniPlayerCard()),
        ],
      ),
    );
  }
}

// ============================================================
// LISTA DE NAVEGACIÓN
// ============================================================
class _NavList extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<_NavDestination> destinations;
  final ColorScheme scheme;

  static const double _itemExtent = 56;

  const _NavList({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.destinations,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final count = destinations.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Stack(
        children: [
          // Indicador en la posición del índice seleccionado.
          Positioned(
            top: selectedIndex * _itemExtent,
            left: 0,
            right: 0,
            height: _itemExtent,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: List.generate(count, (i) {
              final d = destinations[i];
              final selected = i == selectedIndex;
              return SizedBox(
                height: _itemExtent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _HoverableDrawerItem(
                    icon: selected ? d.selectedIcon : d.icon,
                    label: d.label,
                    selected: selected,
                    scheme: scheme,
                    onTap: () => onItemTapped(i),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ITEM CON HOVER (PC)
// ============================================================
class _HoverableDrawerItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _HoverableDrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  @override
  State<_HoverableDrawerItem> createState() => _HoverableDrawerItemState();
}

class _HoverableDrawerItemState extends State<_HoverableDrawerItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final selected = widget.selected;

    final color = (selected || _hovering)
        ? scheme.onSurface
        : scheme.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: (!selected && _hovering)
                ? scheme.surfaceContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 22, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurface,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DRAWER ESTILIZADO (móvil)
// ============================================================
class _StyledDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<_NavDestination> destinations;
  final ColorScheme scheme;

  const _StyledDrawer({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.destinations,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: RepaintBoundary(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DrawerHeader(scheme: scheme),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _DrawerItem(
                          icon: i == selectedIndex
                              ? destinations[i].selectedIcon
                              : destinations[i].icon,
                          label: destinations[i].label,
                          selected: i == selectedIndex,
                          scheme: scheme,
                          onTap: () => onItemTapped(i),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ITEM COMPARTIDO (Drawer móvil)
// ============================================================
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return Material(
      color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurface,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MODELO
// ============================================================
class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
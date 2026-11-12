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

  /// Lo que tarda en cerrarse el Drawer (~246 ms en Material). Esperamos a que
  /// termine antes de cambiar de pestaña para no pintar dos cosas pesadas
  /// a la vez (drawer deslizándose + pestaña nueva apareciendo).
  static const Duration _drawerCloseDelay = Duration(milliseconds: 240);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = _homeIndex;

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
    });
  }

  /// Móvil: cierra el drawer y DESPUÉS cambia de pestaña.
  void _onDrawerItemTapped(int index) {
    _scaffoldKey.currentState?.closeDrawer();
    if (index == _selectedIndex) return;
    Future.delayed(_drawerCloseDelay, () {
      if (mounted) _onItemTapped(index);
    });
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

    // Todas las pestañas siguen montadas (IndexedStack). Solo hacemos un fade
    // corto y cada pestaña está aislada en su propio RepaintBoundary.
    final content = _AnimatedIndexedStack(
      index: _selectedIndex,
      children: _screens,
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
// INDEXED STACK ANIMADO (solo fade corto, sin slide ni ClipRect)
// ============================================================
class _AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const _AnimatedIndexedStack({
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 180),
  });

  @override
  State<_AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<_AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  // Cada pestaña en su propio RepaintBoundary: se rasteriza una vez y el fade
  // solo compone esa capa en vez de repintar todo el árbol en cada frame.
  late final List<Widget> _wrapped = [
    for (final c in widget.children) RepaintBoundary(child: c),
  ];

  @override
  void didUpdateWidget(covariant _AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: IndexedStack(
        index: widget.index,
        children: _wrapped,
      ),
    );
  }
}

// ============================================================
// ENTRADA ESCALONADA (UN solo controller para todo el panel)
// ============================================================
class _Entrance extends StatelessWidget {
  final Animation<double> animation;
  final double begin;
  final double end;
  final Offset offset;
  final Widget child;

  const _Entrance({
    required this.animation,
    required this.begin,
    required this.end,
    required this.child,
    this.offset = const Offset(-0.15, 0),
  });

  @override
  Widget build(BuildContext context) {
    // drive() no crea objetos que haya que hacer dispose.
    final t = animation.drive(
      CurveTween(
        curve: Interval(begin, end.clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      ),
    );
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: t.drive(Tween(begin: offset, end: Offset.zero)),
        child: child,
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
class _DrawerPanel extends StatefulWidget {
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
  State<_DrawerPanel> createState() => _DrawerPanelState();
}

class _DrawerPanelState extends State<_DrawerPanel>
    with SingleTickerProviderStateMixin {
  // Un único controller: reemplaza 4 controllers + 4 Future.delayed + el
  // TweenAnimationBuilder con Opacity/elasticOut del header.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Entrance(
            animation: _entrance,
            begin: 0.0,
            end: 0.6,
            offset: const Offset(0, 0.05),
            child: _DrawerHeader(scheme: scheme),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _AnimatedNavList(
              entrance: _entrance,
              selectedIndex: widget.selectedIndex,
              onItemTapped: widget.onItemTapped,
              destinations: widget.destinations,
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
// LISTA DE NAVEGACIÓN CON INDICADOR DESLIZANTE (sin layout por frame)
// ============================================================
class _AnimatedNavList extends StatelessWidget {
  final Animation<double> entrance;
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<_NavDestination> destinations;
  final ColorScheme scheme;

  static const double _itemExtent = 56;

  const _AnimatedNavList({
    required this.entrance,
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
          // Pill: AnimatedSlide = solo Transform (no relayout del Stack, que
          // sí ocurría con AnimatedPositioned). El offset es en múltiplos de
          // su propia altura, por eso basta con el índice.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _itemExtent,
            child: IgnorePointer(
              child: AnimatedSlide(
                offset: Offset(0, selectedIndex.toDouble()),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
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
          ),
          Column(
            children: List.generate(count, (i) {
              final d = destinations[i];
              final selected = i == selectedIndex;
              final start = 0.1 + i * 0.1;
              return SizedBox(
                height: _itemExtent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _Entrance(
                    animation: entrance,
                    begin: start,
                    end: start + 0.5,
                    child: _HoverableDrawerItem(
                      icon: selected ? d.selectedIcon : d.icon,
                      label: d.label,
                      selected: selected,
                      scheme: scheme,
                      onTap: () => onItemTapped(i),
                    ),
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
// ITEM CON HOVER (PC) — solo animaciones que no provocan layout
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
        child: AnimatedContainer(
          // Solo cambia el color de fondo (repaint, sin layout).
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: (!selected && _hovering)
                ? scheme.surfaceContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: (_hovering && !selected) ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Icon(widget.icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                // Antes: AnimatedDefaultTextStyle cambiando fontWeight, lo que
                // re-mide el texto en cada frame. Ahora es un Text normal.
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: selected ? 1.0 : 0.0,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurface,
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
// DRAWER ESTILIZADO (móvil) — SIN animaciones internas
// El propio Drawer ya se desliza; animar además el contenido mientras se
// abre es lo que más se notaba trabado.
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
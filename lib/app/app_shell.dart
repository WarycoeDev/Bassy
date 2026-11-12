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

    // _AnimatedIndexedStack mantiene TODAS las pestañas montadas (solo hay un
    // LibraryScreen vivo a la vez, así su Navigator anidado y sus estáticos
    // no se reasignan durante transiciones), y añade fade + slide al cambiar.
    final content = ClipRect(
      child: _AnimatedIndexedStack(
        index: _selectedIndex,
        children: _screens,
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
      // El miniplayer se dibuja en un Stack ENCIMA del contenido.
      scaffold = Scaffold(
        key: _scaffoldKey,
        // Zona de gesto desde el borde izquierdo (por defecto ~20 px).
        drawerEdgeDragWidth: 40,
        // AppBar simple: solo ☰ (abre drawer) + título de la pestaña.
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
          onItemTapped: (i) {
            _onItemTapped(i);
            Navigator.pop(context);
          },
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
                child: MiniPlayerBar(),
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
// INDEXED STACK ANIMADO (fade + slide al cambiar de pestaña)
// ============================================================
class _AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const _AnimatedIndexedStack({
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 280),
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
    curve: Curves.easeOutCubic,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

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
      child: SlideTransition(
        position: _slide,
        child: IndexedStack(
          index: widget.index,
          children: widget.children,
        ),
      ),
    );
  }
}

// ============================================================
// ITEM ESCALONADO (para animar el drawer / panel)
// ============================================================
class _StaggeredDrawerItem extends StatefulWidget {
  final Widget child;
  final int index;

  const _StaggeredDrawerItem({required this.child, required this.index});

  @override
  State<_StaggeredDrawerItem> createState() => _StaggeredDrawerItemState();
}

class _StaggeredDrawerItemState extends State<_StaggeredDrawerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(-0.2, 0),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _controller.forward();
    });
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
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

// ============================================================
// HEADER ANIMADO (fade + slide al montarse)
// ============================================================
class _AnimatedDrawerHeader extends StatelessWidget {
  final Widget child;

  const _AnimatedDrawerHeader({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 12),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ============================================================
// PANEL LATERAL ESTILO DRAWER (tablet / PC) — MEJORADO
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
          _AnimatedDrawerHeader(
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
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) => Transform.scale(
                      scale: 0.6 + v * 0.4,
                      child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
                    ),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: scheme.onSurface,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mi App',
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
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _AnimatedNavList(
              selectedIndex: selectedIndex,
              onItemTapped: onItemTapped,
              destinations: destinations,
              scheme: scheme,
            ),
          ),
          const MiniPlayerCard(),
        ],
      ),
    );
  }
}

// ============================================================
// LISTA DE NAVEGACIÓN CON INDICADOR ANIMADO DESLIZANTE
// ============================================================
class _AnimatedNavList extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<_NavDestination> destinations;
  final ColorScheme scheme;

  // Altura fija por item para calcular la posición del indicador.
  static const double _itemExtent = 56;

  const _AnimatedNavList({
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
          // Indicador deslizante de fondo (pill)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            top: selectedIndex * _itemExtent,
            left: 0,
            right: 0,
            height: _itemExtent,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Lista de items
          Column(
            children: List.generate(count, (i) {
              final d = destinations[i];
              final selected = i == selectedIndex;
              return SizedBox(
                height: _itemExtent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _StaggeredDrawerItem(
                    index: i,
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
// ITEM CON HOVER + MICRO-ANIMACIONES (PC)
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

    final color = selected
        ? scheme.onSurface
        : (_hovering ? scheme.onSurface : scheme.onSurfaceVariant);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            // Sutil tinte al hacer hover (solo si no está seleccionado)
            color: (!selected && _hovering)
                ? scheme.surfaceContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              // Icono animado: escala al hover
              AnimatedScale(
                scale: (_hovering && !selected) ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(widget.icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                  child: Text(widget.label),
                ),
              ),
              // Chevron animado: aparece/desaparece con scale+fade
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: selected ? 1.0 : 0.0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: selected ? Offset.zero : const Offset(-0.3, 0),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurface,
                  ),
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
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AnimatedDrawerHeader(
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
                      'Mi App',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
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
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: destinations.length,
                itemBuilder: (context, i) {
                  final d = destinations[i];
                  final selected = i == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: _StaggeredDrawerItem(
                      index: i,
                      child: _DrawerItem(
                        icon: selected ? d.selectedIcon : d.icon,
                        label: d.label,
                        selected: selected,
                        scheme: scheme,
                        onTap: () => onItemTapped(i),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
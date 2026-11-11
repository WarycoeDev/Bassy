// lib/screens/app_shell.dart
import 'package:flutter/material.dart';

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
  int _selectedIndex = 0;

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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 800;
    final scheme = Theme.of(context).colorScheme;

    // IndexedStack mantiene TODAS las pestañas montadas: solo hay un
    // LibraryScreen vivo a la vez, así su Navigator anidado (y los estáticos
    // de LibraryScreen) no se reasignan durante transiciones.
    final content = ClipRect(
      child: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
    );

    if (isWide) {
      // ---------- Tablet / PC ----------
      return Scaffold(
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
    }

    // ---------- Móvil ----------
    // El miniplayer se dibuja en un Stack ENCIMA del contenido.
    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            _destinations[_selectedIndex].label,
            key: ValueKey<int>(_selectedIndex),
          ),
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
}

// ============================================================
// PANEL LATERAL ESTILO DRAWER (tablet / PC)
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
          Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.surfaceContainerHigh, scheme.surfaceContainer],
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
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: destinations.length,
              itemBuilder: (context, i) {
                final d = destinations[i];
                final selected = i == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _DrawerItem(
                    icon: selected ? d.selectedIcon : d.icon,
                    label: d.label,
                    selected: selected,
                    scheme: scheme,
                    onTap: () => onItemTapped(i),
                  ),
                );
              },
            ),
          ),
          const MiniPlayerCard(),
        ],
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
            Container(
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
                    child: _DrawerItem(
                      icon: selected ? d.selectedIcon : d.icon,
                      label: d.label,
                      selected: selected,
                      scheme: scheme,
                      onTap: () => onItemTapped(i),
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
// ITEM COMPARTIDO (Drawer móvil + Panel PC/tablet)
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
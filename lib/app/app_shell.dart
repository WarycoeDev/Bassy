import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';

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
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 800;
    final scheme = Theme.of(context).colorScheme;

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
            Expanded(child: _screens[_selectedIndex]),
          ],
        ),
      );
    }

    // ---------- Móvil ----------
    return Scaffold(
      appBar: AppBar(title: Text(_destinations[_selectedIndex].label)),
      drawer: _StyledDrawer(
        selectedIndex: _selectedIndex,
        onItemTapped: (i) {
          _onItemTapped(i);
          Navigator.pop(context);
        },
        destinations: _destinations,
        scheme: scheme,
      ),
      body: _screens[_selectedIndex],
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
          // Header con degradado (igual que el Drawer)
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
          // Items
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
          // Footer
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.surfaceContainerHigh,
                  child: Icon(
                    Icons.person,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Usuario',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: () {},
                  tooltip: 'Salir',
                ),
              ],
            ),
          ),
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
            // Header con degradado en escala de grises
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
            // Items
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
            // Footer
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.surfaceContainerHigh,
                    child: Icon(
                      Icons.person,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Usuario',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () {},
                    tooltip: 'Salir',
                  ),
                ],
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

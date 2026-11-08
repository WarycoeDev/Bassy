import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _selectedFilter = 0;

  // Filtros superiores — todos funcionales
  final List<String> _filters = const [
    'Todo',
    'Playlist',
    'Canciones',
    'Álbum',
    'Artista',
    'Podcast',
  ];

  // Búsquedas recientes (contenido por defecto cuando no hay query)
  final List<Map<String, dynamic>> _recentSearches = const [
    {'title': 'The Weeknd', 'subtitle': 'Artista', 'icon': Icons.person},
    {
      'title': 'Blinding Lights',
      'subtitle': 'Canción',
      'icon': Icons.music_note,
    },
    {'title': 'After Hours', 'subtitle': 'Álbum', 'icon': Icons.album},
    {'title': 'Chill Vibes', 'subtitle': 'Playlist', 'icon': Icons.queue_music},
  ];

  // Contenido local completo (se filtra por query y por chip)
  final List<Map<String, dynamic>> _allItems = const [
    // Artistas
    {
      'title': 'The Weeknd',
      'subtitle': 'Artista',
      'icon': Icons.person,
      'type': 'Artista',
    },
    {
      'title': 'Dua Lipa',
      'subtitle': 'Artista',
      'icon': Icons.person,
      'type': 'Artista',
    },
    {
      'title': 'Bad Bunny',
      'subtitle': 'Artista',
      'icon': Icons.person,
      'type': 'Artista',
    },
    {
      'title': 'Karol G',
      'subtitle': 'Artista',
      'icon': Icons.person,
      'type': 'Artista',
    },
    // Canciones
    {
      'title': 'Blinding Lights',
      'subtitle': 'The Weeknd',
      'icon': Icons.music_note,
      'type': 'Canciones',
    },
    {
      'title': 'Levitating',
      'subtitle': 'Dua Lipa',
      'icon': Icons.music_note,
      'type': 'Canciones',
    },
    {
      'title': 'Peaches',
      'subtitle': 'Justin Bieber',
      'icon': Icons.music_note,
      'type': 'Canciones',
    },
    {
      'title': 'Stay',
      'subtitle': 'Kid Laroi',
      'icon': Icons.music_note,
      'type': 'Canciones',
    },
    // Álbumes
    {
      'title': 'After Hours',
      'subtitle': 'The Weeknd',
      'icon': Icons.album,
      'type': 'Álbum',
    },
    {
      'title': 'Future Nostalgia',
      'subtitle': 'Dua Lipa',
      'icon': Icons.album,
      'type': 'Álbum',
    },
    {
      'title': 'Justice',
      'subtitle': 'Justin Bieber',
      'icon': Icons.album,
      'type': 'Álbum',
    },
    // Playlists
    {
      'title': 'Chill Vibes',
      'subtitle': 'Playlist',
      'icon': Icons.queue_music,
      'type': 'Playlist',
    },
    {
      'title': 'Road Trip',
      'subtitle': 'Playlist',
      'icon': Icons.queue_music,
      'type': 'Playlist',
    },
    {
      'title': 'Workout',
      'subtitle': 'Playlist',
      'icon': Icons.queue_music,
      'type': 'Playlist',
    },
    // Podcasts
    {
      'title': 'Tecnología Hoy',
      'subtitle': 'Podcast',
      'icon': Icons.mic,
      'type': 'Podcast',
    },
    {
      'title': 'Ciencia Curiosa',
      'subtitle': 'Podcast',
      'icon': Icons.mic,
      'type': 'Podcast',
    },
    {
      'title': 'Historias Reales',
      'subtitle': 'Podcast',
      'icon': Icons.mic,
      'type': 'Podcast',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Devuelve el contenido filtrado por query + chip activo
  List<Map<String, dynamic>> get _filteredResults {
    final query = _query.toLowerCase();
    final activeFilter = _filters[_selectedFilter];

    return _allItems.where((item) {
      final matchesQuery =
          query.isEmpty ||
          (item['title'] as String).toLowerCase().contains(query) ||
          (item['subtitle'] as String).toLowerCase().contains(query);
      final matchesFilter =
          activeFilter == 'Todo' || item['type'] == activeFilter;
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildHeader(context),
              const SizedBox(height: 20),
              _buildSearchBar(context),
              const SizedBox(height: 16),
              _buildFilterChips(context),
              const SizedBox(height: 20),
              if (_query.isNotEmpty) ...[
                _buildYouTubeButton(context),
                const SizedBox(height: 20),
                _buildResults(context),
              ] else ...[
                _buildRecentSearches(context),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buscar',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Encuentra en tu música local',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        _buildIconButton(context, Icons.mic_none),
      ],
    );
  }

  Widget _buildIconButton(BuildContext context, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: scheme.onSurface, size: 22),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SEARCH BAR
  // ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        style: TextStyle(color: scheme.onSurface, fontSize: 14),
        cursorColor: scheme.primary,
        decoration: InputDecoration(
          hintText: 'Canciones, artistas, álbumes...',
          hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          prefixIcon: Icon(
            Icons.search,
            color: scheme.onSurfaceVariant,
            size: 22,
          ),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  child: Icon(
                    Icons.close,
                    color: scheme.onSurfaceVariant,
                    size: 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FILTER CHIPS — funcionales (Todo, Playlist, Canciones, Álbum, Artista, Podcast)
  // ─────────────────────────────────────────────────────────────
  Widget _buildFilterChips(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedFilter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  _filters[index],
                  style: TextStyle(
                    color: isSelected ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BOTÓN BUSCAR EN YOUTUBE — visible cuando hay texto
  // ─────────────────────────────────────────────────────────────
  Widget _buildYouTubeButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // TODO: abrir YouTube con la query:
            // final url = 'https://www.youtube.com/results?search_query='
            //     '${Uri.encodeComponent(_query)}';
            // launchUrl(Uri.parse(url));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Buscando "$_query" en YouTube'),
                backgroundColor: scheme.inverseSurface,
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 255, 255),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Color.fromARGB(255, 0, 0, 0),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buscar en YouTube',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '"$_query"',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  color: scheme.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BÚSQUEDAS RECIENTES (contenido por defecto)
  // ─────────────────────────────────────────────────────────────
  Widget _buildRecentSearches(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Búsquedas recientes',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Limpiar',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._recentSearches.map((item) => _buildResultTile(context, item)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // RESULTADOS FILTRADOS
  // ─────────────────────────────────────────────────────────────
  Widget _buildResults(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _filteredResults;

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Sin resultados',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Prueba con otra palabra o cambia el filtro',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Resultados',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${results.length} encontrados',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...results.map((item) => _buildResultTile(context, item)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TILE reutilizable de resultado
  // ─────────────────────────────────────────────────────────────
  Widget _buildResultTile(BuildContext context, Map<String, dynamic> item) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              item['icon'] as IconData,
              color: scheme.onSurfaceVariant,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] as String,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item['subtitle'] as String,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.north_west, color: scheme.onSurfaceVariant, size: 18),
        ],
      ),
    );
  }
}

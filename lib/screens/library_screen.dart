import 'package:flutter/material.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  // Filtro activo: 0 = Todo, 1 = Canciones, 2 = Playlists, 3 = Álbumes,
  //               4 = Artistas, 5 = Podcasts, 6 = Descargas
  int _selectedFilter = 0;

  final List<String> _filters = const [
    'Todo',
    'Canciones',
    'Playlists',
    'Álbumes',
    'Artistas',
    'Podcasts',
    'Descargas',
  ];

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
              const SizedBox(height: 24),
              _buildFilterChips(context),
              const SizedBox(height: 24),

              // ── Contenido según el filtro activo ──
              ..._buildFilteredContent(context),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Construye las secciones según el filtro seleccionado
  // ─────────────────────────────────────────────────────────────
  List<Widget> _buildFilteredContent(BuildContext context) {
    // "Todo" muestra todas las secciones
    if (_selectedFilter == 0) {
      return [
        _buildSectionTitle(context, 'Canciones'),
        const SizedBox(height: 12),
        _buildSongs(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Playlists'),
        const SizedBox(height: 12),
        _buildPlaylists(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Álbumes'),
        const SizedBox(height: 12),
        _buildAlbums(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Artistas'),
        const SizedBox(height: 12),
        _buildArtists(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Podcasts'),
        const SizedBox(height: 12),
        _buildPodcasts(context),
      ];
    }

    // Filtros individuales
    switch (_selectedFilter) {
      case 1: // Canciones
        return [
          _buildSectionTitle(context, 'Canciones'),
          const SizedBox(height: 12),
          _buildSongs(context),
        ];
      case 2: // Playlists
        return [
          _buildSectionTitle(context, 'Playlists'),
          const SizedBox(height: 12),
          _buildPlaylists(context),
        ];
      case 3: // Álbumes
        return [
          _buildSectionTitle(context, 'Álbumes'),
          const SizedBox(height: 12),
          _buildAlbums(context),
        ];
      case 4: // Artistas
        return [
          _buildSectionTitle(context, 'Artistas'),
          const SizedBox(height: 12),
          _buildArtists(context),
        ];
      case 5: // Podcasts
        return [
          _buildSectionTitle(context, 'Podcasts'),
          const SizedBox(height: 12),
          _buildPodcasts(context),
        ];
      case 6: // Descargas
        return [
          _buildSectionTitle(context, 'Descargas'),
          const SizedBox(height: 12),
          _buildDownloads(context),
        ];
      default:
        return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER (mismo patrón que HomeScreen)
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
              'Tu biblioteca',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Música local en tu dispositivo',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        Row(
          children: [
            _buildIconButton(context, Icons.search),
            const SizedBox(width: 12),
            _buildIconButton(context, Icons.sort),
          ],
        ),
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
  // FILTER CHIPS — ahora FUNCIONALES (onTap actualiza el estado)
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
  // SECTION TITLE (mismo patrón que HomeScreen)
  // ─────────────────────────────────────────────────────────────
  Widget _buildSectionTitle(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Ver todo',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CANCIONES — lista vertical compacta estilo "Escuchado recientemente"
  // ─────────────────────────────────────────────────────────────
  Widget _buildSongs(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final songs = [
      {'title': 'Blinding Lights', 'artist': 'The Weeknd', 'duration': '3:20'},
      {'title': 'Levitating', 'artist': 'Dua Lipa', 'duration': '3:23'},
      {'title': 'Peaches', 'artist': 'Justin Bieber', 'duration': '3:18'},
      {'title': 'Stay', 'artist': 'Kid Laroi', 'duration': '2:21'},
    ];

    return Column(
      children: songs.map((song) {
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
                child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song['title'] as String,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song['artist'] as String,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                song['duration'] as String,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Icon(Icons.more_vert, color: scheme.onSurfaceVariant, size: 20),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PLAYLISTS — tarjetas grandes con icono y botón play
  // ─────────────────────────────────────────────────────────────
  Widget _buildPlaylists(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playlists = [
      {
        'title': 'Road Trip',
        'count': '42 canciones',
        'icon': Icons.directions_car,
      },
      {
        'title': 'Chill Vibes',
        'count': '28 canciones',
        'icon': Icons.nightlight,
      },
      {
        'title': 'Workout',
        'count': '35 canciones',
        'icon': Icons.fitness_center,
      },
      {'title': 'Focus', 'count': '19 canciones', 'icon': Icons.psychology},
    ];

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return Container(
            width: 150,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          playlist['icon'] as IconData,
                          size: 52,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow,
                            color: scheme.onPrimary,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  playlist['title'] as String,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  playlist['count'] as String,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ÁLBUMES — tarjetas con degradado (mismo patrón que "Mix para ti")
  // ─────────────────────────────────────────────────────────────
  Widget _buildAlbums(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final albums = [
      {'title': 'After Hours', 'artist': 'The Weeknd', 'year': '2020'},
      {'title': 'Future Nostalgia', 'artist': 'Dua Lipa', 'year': '2020'},
      {'title': 'Justice', 'artist': 'Justin Bieber', 'year': '2021'},
    ];

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return Container(
            width: 150,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.surfaceContainerHigh,
                        scheme.surfaceContainer,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Text(
                          album['title'] as String,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow,
                            color: scheme.onPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${album['artist']} · ${album['year']}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ARTISTAS — círculos con nombre
  // ─────────────────────────────────────────────────────────────
  Widget _buildArtists(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artists = [
      {'name': 'The Weeknd', 'songs': '12 canciones'},
      {'name': 'Dua Lipa', 'songs': '8 canciones'},
      {'name': 'Bad Bunny', 'songs': '15 canciones'},
      {'name': 'Karol G', 'songs': '10 canciones'},
    ];

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: scheme.surfaceContainerHigh,
                  child: Icon(
                    Icons.person,
                    color: scheme.onSurfaceVariant,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  artist['name'] as String,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  artist['songs'] as String,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PODCASTS — tarjetas horizontales con icono
  // ─────────────────────────────────────────────────────────────
  Widget _buildPodcasts(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final podcasts = [
      {'title': 'Tecnología Hoy', 'episodes': '124 episodios'},
      {'title': 'Ciencia Curiosa', 'episodes': '87 episodios'},
      {'title': 'Historias Reales', 'episodes': '56 episodios'},
    ];

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: podcasts.length,
        itemBuilder: (context, index) {
          final podcast = podcasts[index];
          return Container(
            width: 220,
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.mic,
                    color: scheme.onSurfaceVariant,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        podcast['title'] as String,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        podcast['episodes'] as String,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DESCARGAS — lista con estado descargado
  // ─────────────────────────────────────────────────────────────
  Widget _buildDownloads(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final downloads = [
      {'title': 'Blinding Lights', 'artist': 'The Weeknd', 'size': '8.2 MB'},
      {'title': 'Levitating', 'artist': 'Dua Lipa', 'size': '7.8 MB'},
      {'title': 'Peaches', 'artist': 'Justin Bieber', 'size': '6.4 MB'},
    ];

    return Column(
      children: downloads.map((item) {
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
                child: Icon(Icons.download_done, color: scheme.primary),
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
                      item['artist'] as String,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                item['size'] as String,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

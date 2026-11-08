import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/media_scanner.dart';
import '../widgets/song_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  // Filtro activo: 0 = Todo, 1 = Canciones, 2 = Playlists, 3 = Álbumes,
  //               4 = Artistas, 5 = Podcasts, 6 = Descargas
  int _selectedFilter = 0;

  bool _slideFromRight = true;

  late final AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  final ScrollController _scrollController = ScrollController();

  // ── Estado del scanner ──
  List<Song> _songs = const [];
  List<Song> _podcasts = const [];
  bool _loadingLibrary = true;
  String? _scanError;

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
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1.0,
    );

    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    );

    _loadLibrary();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _loadingLibrary = true;
      _scanError = null;
    });
    final result = await MediaScanner.instance.scan();
    if (!mounted) return;
    setState(() {
      _songs = result.songs;
      _podcasts = result.podcasts;
      _loadingLibrary = false;
      _scanError = result.errors.isEmpty ? null : result.errors.first;
    });
  }

  // Cambia el filtro con animación de slide y scroll al inicio.
  void _changeFilter(int index) {
    if (index == _selectedFilter) return;

    // 1) Resetear scroll PRIMERO, mientras el ScrollController sigue montado.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    // 2) Dirección según el índice destino.
    _slideFromRight = index > _selectedFilter;

    // 3) Reconfigurar la animación para que entre desde el lado correcto.
    final begin = _slideFromRight
        ? const Offset(0.30, 0)
        : const Offset(-0.30, 0);

    _slideAnimation = Tween<Offset>(begin: begin, end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    // 4) setState para que build() se ejecute y el nuevo child se construya.
    setState(() {
      _selectedFilter = index;
    });

    // 5) Reiniciar y lanzar la animación.
    _slideController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildHeader(context),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildFilterChips(context),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _slideController,
                  builder: (context, _) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: SingleChildScrollView(
                          key: ValueKey<int>(_selectedFilter),
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._buildFilteredContent(context),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Construye las secciones según el filtro seleccionado.
  // ─────────────────────────────────────────────────────────────
  List<Widget> _buildFilteredContent(BuildContext context) {
    if (_selectedFilter == 0) {
      return [
        _buildSectionTitle(
          context,
          'Canciones',
          onSeeAll: () => _changeFilter(1),
        ),
        const SizedBox(height: 12),
        _buildSongs(context),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Playlists',
          onSeeAll: () => _changeFilter(2),
        ),
        const SizedBox(height: 12),
        _buildPlaylists(context),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Álbumes',
          onSeeAll: () => _changeFilter(3),
        ),
        const SizedBox(height: 12),
        _buildAlbums(context),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Artistas',
          onSeeAll: () => _changeFilter(4),
        ),
        const SizedBox(height: 12),
        _buildArtists(context),
        const SizedBox(height: 24),
        _buildSectionTitle(
          context,
          'Podcasts',
          onSeeAll: () => _changeFilter(5),
        ),
        const SizedBox(height: 12),
        _buildPodcasts(context),
      ];
    }

    switch (_selectedFilter) {
      case 1:
        return [
          _buildSectionTitle(context, 'Canciones', showSeeAll: false),
          const SizedBox(height: 12),
          _buildSongs(context),
        ];
      case 2:
        return [
          _buildSectionTitle(context, 'Playlists', showSeeAll: false),
          const SizedBox(height: 12),
          _buildPlaylistsDetailed(context),
        ];
      case 3:
        return [
          _buildSectionTitle(context, 'Álbumes', showSeeAll: false),
          const SizedBox(height: 12),
          _buildAlbumsDetailed(context),
        ];
      case 4:
        return [
          _buildSectionTitle(context, 'Artistas', showSeeAll: false),
          const SizedBox(height: 12),
          _buildArtistsDetailed(context),
        ];
      case 5:
        return [
          _buildSectionTitle(context, 'Podcasts', showSeeAll: false),
          const SizedBox(height: 12),
          _buildPodcasts(context),
        ];
      case 6:
        return [
          _buildSectionTitle(context, 'Descargas', showSeeAll: false),
          const SizedBox(height: 12),
          _buildDownloads(context),
        ];
      default:
        return [];
    }
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
            const SizedBox(width: 12),
            _buildIconButton(
              context,
              Icons.refresh,
              onTap: _loadingLibrary ? null : _loadLibrary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIconButton(
    BuildContext context,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: onTap == null
              ? scheme.onSurfaceVariant.withOpacity(0.4)
              : scheme.onSurface,
          size: 22,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FILTER CHIPS
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
            onTap: () => _changeFilter(index),
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
  // SECTION TITLE
  // ─────────────────────────────────────────────────────────────
  Widget _buildSectionTitle(
    BuildContext context,
    String title, {
    bool showSeeAll = true,
    VoidCallback? onSeeAll,
  }) {
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
        if (showSeeAll)
          GestureDetector(
            onTap: onSeeAll,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'Ver todo',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════
  // CANCIONES (datos reales del scanner)
  // ═════════════════════════════════════════════════════════════
  Widget _buildSongs(BuildContext context) {
    if (_loadingLibrary) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_songs.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.library_music_outlined,
        title: 'No hay canciones',
        subtitle:
            _scanError ??
            'Configura tus carpetas en Ajustes y vuelve a escanear.',
      );
    }
    return Column(
      children: _songs
          .map(
            (song) => SongTile(
              song: song,
              onTap: () {
                // TODO: reproducir
              },
              onMore: () {
                // TODO: menú contextual
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _loadLibrary,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Escanear de nuevo'),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // PLAYLISTS (mock horizontal)
  // ═════════════════════════════════════════════════════════════
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

  // ═════════════════════════════════════════════════════════════
  // ÁLBUMES (mock horizontal)
  // ═════════════════════════════════════════════════════════════
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

  // ═════════════════════════════════════════════════════════════
  // ARTISTAS (mock horizontal)
  // ═════════════════════════════════════════════════════════════
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

  // ═════════════════════════════════════════════════════════════
  // PODCASTS (datos reales del scanner)
  // ═════════════════════════════════════════════════════════════
  Widget _buildPodcasts(BuildContext context) {
    if (_loadingLibrary) {
      return const SizedBox.shrink();
    }
    if (_podcasts.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.podcasts_outlined,
        title: 'No hay podcasts',
        subtitle: 'Agrega carpetas de podcasts en Ajustes.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _podcasts.length,
        itemBuilder: (context, index) {
          final pod = _podcasts[index];
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
                        pod.title,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${pod.extension.toUpperCase()} · ${pod.sizeLabel}',
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

  // ═════════════════════════════════════════════════════════════
  // DESCARGAS (mock)
  // ═════════════════════════════════════════════════════════════
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

  // ═════════════════════════════════════════════════════════════
  // VISTAS DETALLADAS (mock, no dependen del scanner)
  // ═════════════════════════════════════════════════════════════
  Widget _buildPlaylistsDetailed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playlists = [
      {
        'title': 'Road Trip',
        'count': 42,
        'total': '2 h 48 min',
        'icon': Icons.directions_car,
        'color': scheme.primaryContainer,
      },
      {
        'title': 'Chill Vibes',
        'count': 28,
        'total': '1 h 52 min',
        'icon': Icons.nightlight,
        'color': scheme.secondaryContainer,
      },
      {
        'title': 'Workout',
        'count': 35,
        'total': '2 h 14 min',
        'icon': Icons.fitness_center,
        'color': scheme.tertiaryContainer,
      },
      {
        'title': 'Focus',
        'count': 19,
        'total': '1 h 08 min',
        'icon': Icons.psychology,
        'color': scheme.surfaceContainerHigh,
      },
      {
        'title': 'Party Mix',
        'count': 51,
        'total': '3 h 22 min',
        'icon': Icons.celebration,
        'color': scheme.primaryContainer,
      },
      {
        'title': 'Acoustic',
        'count': 23,
        'total': '1 h 30 min',
        'icon': Icons.piano,
        'color': scheme.secondaryContainer,
      },
    ];

    return Column(
      children: playlists.map((playlist) {
        return _buildDetailCard(
          context: context,
          leading: _buildCover(
            context,
            icon: playlist['icon'] as IconData,
            color: playlist['color'] as Color,
            size: 64,
            rounded: 12,
          ),
          title: playlist['title'] as String,
          subtitle: '${playlist['count']} canciones',
          meta: playlist['total'] as String,
          trailing: _buildPlayTrailing(context),
        );
      }).toList(),
    );
  }

  Widget _buildAlbumsDetailed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final albums = [
      {
        'title': 'After Hours',
        'artist': 'The Weeknd',
        'year': '2020',
        'songs': 14,
        'total': '56 min',
      },
      {
        'title': 'Future Nostalgia',
        'artist': 'Dua Lipa',
        'year': '2020',
        'songs': 11,
        'total': '43 min',
      },
      {
        'title': 'Justice',
        'artist': 'Justin Bieber',
        'year': '2021',
        'songs': 16,
        'total': '58 min',
      },
      {
        'title': 'Un Verano Sin Ti',
        'artist': 'Bad Bunny',
        'year': '2022',
        'songs': 23,
        'total': '1 h 22 min',
      },
      {
        'title': 'KG0516',
        'artist': 'Karol G',
        'year': '2021',
        'songs': 16,
        'total': '54 min',
      },
      {
        'title': "Harry's House",
        'artist': 'Harry Styles',
        'year': '2022',
        'songs': 13,
        'total': '47 min',
      },
    ];

    return Column(
      children: albums.map((album) {
        return _buildDetailCard(
          context: context,
          leading: _buildCover(
            context,
            icon: Icons.album,
            color: scheme.surfaceContainerHigh,
            size: 64,
            rounded: 10,
            label: album['title'] as String,
          ),
          title: album['title'] as String,
          subtitle: '${album['artist']} · ${album['year']}',
          meta: '${album['songs']} pistas · ${album['total']}',
          trailing: Icon(
            Icons.more_vert,
            color: scheme.onSurfaceVariant,
            size: 20,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildArtistsDetailed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artists = [
      {'name': 'The Weeknd', 'songs': 12, 'albums': 4},
      {'name': 'Dua Lipa', 'songs': 8, 'albums': 3},
      {'name': 'Bad Bunny', 'songs': 15, 'albums': 5},
      {'name': 'Karol G', 'songs': 10, 'albums': 3},
      {'name': 'Harry Styles', 'songs': 9, 'albums': 2},
      {'name': 'Taylor Swift', 'songs': 20, 'albums': 8},
      {'name': 'Drake', 'songs': 14, 'albums': 6},
      {'name': 'Ariana Grande', 'songs': 11, 'albums': 4},
    ];

    return Column(
      children: artists.map((artist) {
        return _buildDetailCard(
          context: context,
          leading: CircleAvatar(
            radius: 32,
            backgroundColor: scheme.surfaceContainerHigh,
            child: Icon(Icons.person, color: scheme.onSurfaceVariant, size: 32),
          ),
          title: artist['name'] as String,
          subtitle:
              '${artist['songs']} canciones · ${artist['albums']} álbumes',
          trailing: Icon(
            Icons.chevron_right,
            color: scheme.onSurfaceVariant,
            size: 24,
          ),
        );
      }).toList(),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // WIDGETS REUTILIZABLES
  // ═════════════════════════════════════════════════════════════
  Widget _buildDetailCard({
    required BuildContext context,
    required Widget leading,
    required String title,
    String? subtitle,
    String? meta,
    required Widget trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (meta != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        meta,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _buildCover(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required double size,
    required double rounded,
    String? label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rounded),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, scheme.surfaceContainerHigh],
        ),
      ),
      child: Stack(
        children: [
          if (label != null)
            Positioned(
              top: 6,
              left: 6,
              right: 6,
              child: Text(
                label,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Center(
            child: Icon(
              icon,
              color: label == null
                  ? scheme.onSurface
                  : scheme.onSurface.withOpacity(0.35),
              size: label == null ? size * 0.42 : size * 0.32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayTrailing(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow, color: scheme.primary, size: 22),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/media_scanner.dart';
import '../widgets/song_tile.dart';
import 'playlist_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _prefsKey = 'search_history_v1';
  static const _maxHistory = 12;
  static const _debounceMs = 250;
  static const _libraryApplyMs = 300;

  /// En el filtro "Todo", cuántos álbumes/artistas/podcasts se muestran
  /// antes del botón "Ver todo".
  static const _previewCount = 5;

  static const List<String> _filters = [
    'Todo',
    'Canciones',
    'Álbumes',
    'Artistas',
    'Podcasts',
  ];

  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  /// Query committed (ya con debounce, trimmed).
  String _query = '';
  int _selectedFilter = 0;

  Timer? _debounce;
  Timer? _applyTimer;
  ScanProgress? _pendingProgress;

  // ---- Biblioteca ----
  List<Song> _songs = const [];
  List<Song> _podcasts = const [];
  List<Playlist> _albums = const [];
  List<Playlist> _artists = const [];
  List<Playlist> _podcastPlaylists = const [];
  int _songsSig = -1;
  int _podcastsSig = -1;

  bool _loading = true;
  StreamSubscription<ScanProgress>? _sub;

  // ---- Índice + resultados ----
  _SearchIndex _index = _SearchIndex.empty;
  _SearchResults _results = _SearchResults.empty;
  String _resultsQuery = '';
  int _resultsFilter = -1;

  // ---- Historial ----
  List<_HistoryEntry> _history = const [];

  // ---- Notifiers: cada parte de la UI se reconstruye por separado ----
  final ValueNotifier<int> _bodyRev = ValueNotifier<int>(0);
  final ValueNotifier<bool> _hasText = ValueNotifier<bool>(false);
  final ValueNotifier<int> _filterN = ValueNotifier<int>(0);
  final ValueNotifier<int> _libCount = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _bindLibrary();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _applyTimer?.cancel();
    _sub?.cancel();
    _searchController.dispose();
    _bodyRev.dispose();
    _hasText.dispose();
    _filterN.dispose();
    _libCount.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Historial
  // ===========================================================================

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    if (!mounted) return;
    _history = raw
        .map((e) {
          try {
            return _HistoryEntry.fromJson(
              jsonDecode(e) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<_HistoryEntry>()
        .toList();
    _bodyRev.value++;
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _history.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  void _pushHistory(_HistoryEntry entry) {
    if (entry.query.trim().isEmpty) return;
    final list = [
      entry,
      ..._history.where(
        (e) => !(e.query == entry.query && e.kind == entry.kind),
      ),
    ];
    if (list.length > _maxHistory) list.removeRange(_maxHistory, list.length);
    _history = list;
    _bodyRev.value++;
    _persistHistory();
  }

  void _saveQueryToHistory() {
    final q = _query.trim();
    if (q.isEmpty) return;
    _pushHistory(
      _HistoryEntry(query: q, kind: _HistoryKind.query, icon: Icons.search),
    );
  }

  Future<void> _clearHistory() async {
    _history = const [];
    _bodyRev.value++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  void _removeHistoryEntry(_HistoryEntry entry) {
    _history = _history
        .where((e) => !(e.query == entry.query && e.kind == entry.kind))
        .toList();
    _bodyRev.value++;
    _persistHistory();
  }

  void _applyHistoryEntry(_HistoryEntry entry) {
    _debounce?.cancel();
    _searchController.text = entry.query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: entry.query.length),
    );
    _hasText.value = entry.query.isNotEmpty;
    _commitQuery(entry.query);
  }

  // ===========================================================================
  // Biblioteca
  // ===========================================================================

  void _bindLibrary() {
    final last = MediaScanner.instance.lastResult;
    if (last != null) {
      _applyLibrary(last.songs, last.podcasts, loading: false);
    }

    // El scanner puede emitir muchos snapshots seguidos (watcher). Se agrupan
    // en una ventana corta para no reagrupar álbumes/artistas en cada uno.
    _sub = MediaScanner.instance.watchStream().listen((p) {
      _pendingProgress = p;
      _applyTimer ??= Timer(
        const Duration(milliseconds: _libraryApplyMs),
        () {
          _applyTimer = null;
          final pp = _pendingProgress;
          _pendingProgress = null;
          if (!mounted || pp == null) return;
          _applyLibrary(
            pp.songs,
            pp.podcasts,
            loading: pp.scanning && pp.songs.isEmpty && pp.podcasts.isEmpty,
          );
        },
      );
    });

    if (last == null) MediaScanner.instance.ensureInitialScan();
  }

  void _applyLibrary(
    List<Song> songs,
    List<Song> podcasts, {
    required bool loading,
  }) {
    final sSig = _signature(songs);
    final pSig = _signature(podcasts);

    var changed = false;

    if (sSig != _songsSig) {
      _songsSig = sSig;
      _songs = songs;
      _albums = Playlist.fromAlbums(songs);
      _artists = Playlist.fromArtists(songs);
      changed = true;
    }
    if (pSig != _podcastsSig) {
      _podcastsSig = pSig;
      _podcasts = podcasts;
      _podcastPlaylists = Playlist.fromPodcasts(podcasts);
      changed = true;
    }

    final loadingChanged = loading != _loading;
    _loading = loading;

    if (changed) {
      _index = _SearchIndex.build(
        songs: _songs,
        albums: _albums,
        artists: _artists,
        podcasts: _podcastPlaylists,
      );
      _libCount.value = _songs.length + _podcasts.length;
      _runSearch(force: true);
    } else if (loadingChanged) {
      _bodyRev.value++;
    }
  }

  /// Firma barata (O(n) con enteros) de una lista: detecta cambios en
  /// cualquier posición, no solo en el primero/último elemento.
  int _signature(List<Song> list) {
    var h = list.length;
    for (final s in list) {
      h = Object.hash(
        h,
        s.path,
        s.sizeBytes,
        s.modified.millisecondsSinceEpoch,
      );
    }
    return h;
  }

  // ===========================================================================
  // Búsqueda
  // ===========================================================================

  void _runSearch({bool force = false}) {
    final folded = _fold(_query);
    if (!force &&
        folded == _resultsQuery &&
        _selectedFilter == _resultsFilter) {
      return;
    }

    if (folded.isEmpty) {
      _results = _SearchResults.empty;
    } else {
      // Refinamiento: si la nueva query extiende la anterior (mismo filtro),
      // basta con filtrar los resultados previos.
      final canRefine = !force &&
          _resultsFilter == _selectedFilter &&
          _resultsQuery.isNotEmpty &&
          folded.startsWith(_resultsQuery);

      _results = _index.search(
        folded,
        _selectedFilter,
        previous: canRefine ? _results : null,
      );
    }

    _resultsQuery = folded;
    _resultsFilter = _selectedFilter;
    _bodyRev.value++;
  }

  void _commitQuery(String q) {
    final trimmed = q.trim();
    if (trimmed == _query) return;
    _query = trimmed;
    _runSearch();
  }

  void _onTextChanged(String raw) {
    _hasText.value = raw.isNotEmpty;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: _debounceMs),
      () => _commitQuery(raw),
    );
  }

  void _onSubmitted(String raw) {
    _debounce?.cancel();
    _commitQuery(raw);
    if (_query.isNotEmpty) _saveQueryToHistory();
  }

  void _clearText() {
    _debounce?.cancel();
    _searchController.clear();
    _hasText.value = false;
    _commitQuery('');
  }

  void _changeFilter(int index) {
    if (index == _selectedFilter) return;
    _selectedFilter = index;
    _filterN.value = index;
    _runSearch();
  }

  void _openPlaylist(Playlist playlist) {
    if (_query.isNotEmpty) _saveQueryToHistory();
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlist: playlist),
      ),
    );
  }

  void _openSong(Song song) {
    if (_query.isNotEmpty) _saveQueryToHistory();
    // TODO: conectar con tu reproductor real, p. ej.:
    // PlayerService.instance.play(song);
  }

  // ===========================================================================
  // build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navKey,
      onGenerateRoute: (_) => MaterialPageRoute(builder: _buildHome),
    );
  }

  Widget _buildHome(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
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
              const SizedBox(height: 16),
              // Solo el cuerpo se reconstruye al buscar.
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _bodyRev,
                  builder: (ctx, _, __) => _buildBody(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.isNotEmpty) return _buildResults(context);
    return _buildRecentSearches(context);
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
            ValueListenableBuilder<int>(
              valueListenable: _libCount,
              builder: (_, count, __) => Text(
                '$count elementos en tu biblioteca',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
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
        textInputAction: TextInputAction.search,
        onSubmitted: _onSubmitted,
        onChanged: _onTextChanged,
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
          suffixIcon: ValueListenableBuilder<bool>(
            valueListenable: _hasText,
            builder: (_, has, __) => has
                ? GestureDetector(
                    onTap: _clearText,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close,
                      color: scheme.onSurfaceVariant,
                      size: 20,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
      child: ValueListenableBuilder<int>(
        valueListenable: _filterN,
        builder: (_, selected, __) => ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          itemBuilder: (context, index) {
            final isSelected = index == selected;
            return GestureDetector(
              onTap: () => _changeFilter(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BOTÓN YOUTUBE
  // ─────────────────────────────────────────────────────────────
  Widget _buildYouTubeButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.black,
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
  // BÚSQUEDAS RECIENTES
  // ─────────────────────────────────────────────────────────────
  Widget _buildRecentSearches(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_history.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(top: 24),
        children: [
          Center(
            child: Column(
              children: [
                Icon(Icons.history, size: 56, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'Sin búsquedas recientes',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lo que busques aparecerá aquí',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _history.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
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
                GestureDetector(
                  onTap: _clearHistory,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Limpiar',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return _buildHistoryTile(ctx, _history[i - 1]);
      },
    );
  }

  Widget _buildHistoryTile(BuildContext context, _HistoryEntry h) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _applyHistoryEntry(h),
      behavior: HitTestBehavior.opaque,
      child: Container(
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
              child: Icon(h.icon, color: scheme.onSurfaceVariant, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.query,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    h.kind.label,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _applyHistoryEntry(h),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.north_west,
                  color: scheme.onSurfaceVariant,
                  size: 18,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _removeHistoryEntry(h),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close,
                  color: scheme.onSurfaceVariant,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // RESULTADOS (slivers lazy: solo se construye lo visible)
  // ─────────────────────────────────────────────────────────────
  Widget _buildResults(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _results;
    final total = r.total;

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildYouTubeButton(context),
            const SizedBox(height: 20),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle(context, 'Resultados'),
                    Text(
                      '$total encontrados',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];

    if (total == 0) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.search_off,
                    size: 56,
                    color: scheme.onSurfaceVariant,
                  ),
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
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // 1) Canciones primero
      final songs = r.songs.ranked;
      if (songs.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _sectionTitle(context, 'Canciones'),
            ),
          ),
        );
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final s = songs[i].song!;
                return GestureDetector(
                  key: ValueKey(s.path),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openSong(s),
                  child: SongTile(song: s),
                );
              },
              childCount: songs.length,
              addAutomaticKeepAlives: false,
            ),
          ),
        );
        if (r.artists.length + r.albums.length + r.podcasts.length > 0) {
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
        }
      }

      // 2) Artistas (cover redonda)
      slivers.addAll(
        _playlistSection(
          context,
          title: 'Artistas',
          bucket: r.artists,
          filterIndex: 3,
          icon: Icons.person,
          metaLabel: 'canciones',
          roundCover: true,
        ),
      );
      // 3) Álbumes
      slivers.addAll(
        _playlistSection(
          context,
          title: 'Álbumes',
          bucket: r.albums,
          filterIndex: 2,
          icon: Icons.album,
          metaLabel: 'pistas',
        ),
      );
      // 4) Podcasts
      slivers.addAll(
        _playlistSection(
          context,
          title: 'Podcasts',
          bucket: r.podcasts,
          filterIndex: 4,
          icon: Icons.mic,
          metaLabel: 'episodios',
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: slivers,
    );
  }

  List<Widget> _playlistSection(
    BuildContext context, {
    required String title,
    required _Bucket bucket,
    required int filterIndex,
    required IconData icon,
    required String metaLabel,
    bool roundCover = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final items = bucket.ranked;
    if (items.isEmpty) return const [];

    final preview = _selectedFilter == 0 && items.length > _previewCount;
    final count = preview ? _previewCount : items.length;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle(context, title),
              if (preview)
                GestureDetector(
                  onTap: () => _changeFilter(filterIndex),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Ver todo (${items.length})',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _playlistTile(
            ctx,
            entry: items[i],
            icon: icon,
            meta: '${items[i].playlist!.count} $metaLabel',
            roundCover: roundCover,
          ),
          childCount: count,
          addAutomaticKeepAlives: false,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      title,
      style: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TILE para playlists (álbum/artista/podcast) — más alto
  // ─────────────────────────────────────────────────────────────
  Widget _playlistTile(
    BuildContext context, {
    required _SearchEntry entry,
    required IconData icon,
    required String meta,
    bool roundCover = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final playlist = entry.playlist!;
    final cover = entry.cover; // precalculada en el índice

    const double coverSize = 68;
    final radius = roundCover
        ? BorderRadius.circular(coverSize / 2)
        : BorderRadius.circular(10);

    return GestureDetector(
      onTap: () => _openPlaylist(playlist),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: coverSize,
              height: coverSize,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: radius,
              ),
              clipBehavior: Clip.antiAlias,
              child: cover != null
                  ? Image.file(
                      File(cover),
                      fit: BoxFit.cover,
                      cacheWidth: 160, // decodifica pequeño, no la portada full
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon, size: 28, color: scheme.onSurfaceVariant),
                    )
                  : Icon(icon, size: 28, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    playlist.title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${playlist.subtitle} · $meta',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 22),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Normalización (minúsculas + sin acentos)
// ===========================================================================

const String _accentFrom = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const String _accentTo = 'aaaaaeeeeiiiiooooouuuunc';

String _fold(String input) {
  final lower = input.toLowerCase();

  // Camino rápido: ASCII puro.
  var ascii = true;
  for (var i = 0; i < lower.length; i++) {
    if (lower.codeUnitAt(i) > 127) {
      ascii = false;
      break;
    }
  }
  if (ascii) return lower;

  final sb = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final c = lower[i];
    final idx = _accentFrom.indexOf(c);
    sb.write(idx >= 0 ? _accentTo[idx] : c);
  }
  return sb.toString();
}

// ===========================================================================
// Índice de búsqueda (precomputado)
// ===========================================================================

class _SearchEntry {
  final Song? song;
  final Playlist? playlist;

  /// Todos los campos en minúsculas/sin acentos para un solo `contains`.
  final String haystack;

  /// Título normalizado (para ordenar por relevancia).
  final String title;

  /// Portada precalculada (solo playlists).
  final String? cover;

  const _SearchEntry({
    this.song,
    this.playlist,
    required this.haystack,
    required this.title,
    this.cover,
  });
}

class _Bucket {
  /// Coincidencias en el orden original (sirve para refinar).
  final List<_SearchEntry> matches;

  /// Coincidencias ordenadas por relevancia (las que empiezan con la query primero).
  final List<_SearchEntry> ranked;

  const _Bucket(this.matches, this.ranked);

  static const empty = _Bucket([], []);

  int get length => ranked.length;

  factory _Bucket.from(List<_SearchEntry> matches, String firstToken) {
    if (matches.length < 2) return _Bucket(matches, matches);
    final starts = <_SearchEntry>[];
    final rest = <_SearchEntry>[];
    for (final e in matches) {
      (e.title.startsWith(firstToken) ? starts : rest).add(e);
    }
    if (starts.isEmpty) return _Bucket(matches, matches);
    return _Bucket(matches, [...starts, ...rest]);
  }
}

class _SearchIndex {
  final List<_SearchEntry> songs;
  final List<_SearchEntry> albums;
  final List<_SearchEntry> artists;
  final List<_SearchEntry> podcasts;

  const _SearchIndex({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.podcasts,
  });

  static const empty = _SearchIndex(
    songs: [],
    albums: [],
    artists: [],
    podcasts: [],
  );

  static _SearchIndex build({
    required List<Song> songs,
    required List<Playlist> albums,
    required List<Playlist> artists,
    required List<Playlist> podcasts,
  }) {
    _SearchEntry songEntry(Song s) => _SearchEntry(
          song: s,
          title: _fold(s.title),
          haystack: _fold(
            '${s.title}\u0000${s.artist}\u0000${s.album}\u0000${s.fileName}',
          ),
        );

    _SearchEntry plEntry(Playlist p) {
      String? cover;
      for (final s in p.songs) {
        final c = s.coverPath;
        if (c != null && c.isNotEmpty) {
          cover = c;
          break;
        }
      }
      return _SearchEntry(
        playlist: p,
        title: _fold(p.title),
        haystack: _fold('${p.title}\u0000${p.subtitle}'),
        cover: cover,
      );
    }

    return _SearchIndex(
      songs: [for (final s in songs) songEntry(s)],
      albums: [for (final a in albums) plEntry(a)],
      artists: [for (final a in artists) plEntry(a)],
      podcasts: [for (final p in podcasts) plEntry(p)],
    );
  }

  /// [query] ya viene normalizada con `_fold`.
  /// Filtro: 0=Todo, 1=Canciones, 2=Álbumes, 3=Artistas, 4=Podcasts.
  /// Todas las palabras de la query deben aparecer (AND).
  _SearchResults search(
    String query,
    int filter, {
    _SearchResults? previous,
  }) {
    final tokens = query
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return _SearchResults.empty;
    final first = tokens.first;

    _Bucket run(List<_SearchEntry> source, bool enabled, _Bucket? prev) {
      if (!enabled) return _Bucket.empty;
      final src = prev?.matches ?? source;
      final out = <_SearchEntry>[];
      for (final e in src) {
        var ok = true;
        for (final t in tokens) {
          if (!e.haystack.contains(t)) {
            ok = false;
            break;
          }
        }
        if (ok) out.add(e);
      }
      return _Bucket.from(out, first);
    }

    final all = filter == 0;
    return _SearchResults(
      songs: run(songs, all || filter == 1, previous?.songs),
      albums: run(albums, all || filter == 2, previous?.albums),
      artists: run(artists, all || filter == 3, previous?.artists),
      podcasts: run(podcasts, all || filter == 4, previous?.podcasts),
    );
  }
}

class _SearchResults {
  final _Bucket songs;
  final _Bucket albums;
  final _Bucket artists;
  final _Bucket podcasts;

  const _SearchResults({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.podcasts,
  });

  static const empty = _SearchResults(
    songs: _Bucket.empty,
    albums: _Bucket.empty,
    artists: _Bucket.empty,
    podcasts: _Bucket.empty,
  );

  int get total =>
      songs.length + albums.length + artists.length + podcasts.length;
}

// ===========================================================================
// Historial
// ===========================================================================

enum _HistoryKind {
  query('Búsqueda'),
  song('Canción'),
  album('Álbum'),
  artist('Artista'),
  podcast('Podcast');

  final String label;
  const _HistoryKind(this.label);
}

class _HistoryEntry {
  final String query;
  final _HistoryKind kind;
  final IconData icon;

  const _HistoryEntry({
    required this.query,
    required this.kind,
    required this.icon,
  });

  Map<String, dynamic> toJson() => {'q': query, 'k': kind.name};

  factory _HistoryEntry.fromJson(Map<String, dynamic> json) {
    final kind = _HistoryKind.values.firstWhere(
      (e) => e.name == json['k'],
      orElse: () => _HistoryKind.query,
    );
    return _HistoryEntry(
      query: json['q'] as String? ?? '',
      kind: kind,
      icon: switch (kind) {
        _HistoryKind.query => Icons.search,
        _HistoryKind.song => Icons.music_note,
        _HistoryKind.album => Icons.album,
        _HistoryKind.artist => Icons.person,
        _HistoryKind.podcast => Icons.mic,
      },
    );
  }
}
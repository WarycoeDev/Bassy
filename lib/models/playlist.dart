import 'package:flutter/foundation.dart';

import 'song.dart';

/// Categoría agrupadora: álbum, artista, podcast o playlist de usuario.
enum PlaylistKind { album, artist, podcast, favorites, custom }

@immutable
class Playlist {
  static const String unknownAlbum = 'Álbum desconocido';
  static const String unknownArtist = 'Artista desconocido';

  final String id;
  final String title;
  final String subtitle;
  final PlaylistKind kind;
  final List<Song> songs;

  const Playlist({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.songs,
  });

  int get count => songs.length;

  Duration get totalDuration =>
      songs.fold(Duration.zero, (acc, s) => acc + s.duration);

  bool get isFavorites => kind == PlaylistKind.favorites;

  /// Solo los favoritos permiten reordenar manualmente.
  bool get canReorder => kind == PlaylistKind.favorites;

  String get totalDurationLabel {
    final total = totalDuration.inSeconds;
    if (total <= 0) return '--:--';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
    return '$m min';
  }

  /// Agrupa canciones por álbum. Las que no tienen álbum van a
  /// "Álbum desconocido" (al final del listado).
  static List<Playlist> fromAlbums(List<Song> songs) {
    final map = <String, List<Song>>{};
    for (final s in songs) {
      if (s.kind != MediaKind.music) continue;
      final key = s.albumOrUnknown;
      map.putIfAbsent(key, () => []).add(s);
    }
    final result =
        map.entries.map((e) {
          final isUnknown = e.key == unknownAlbum;
          final artist = e.value.first.artist.trim();
          final String subtitle;
          if (isUnknown) {
            subtitle = 'Sin metadatos';
          } else if (artist.isEmpty) {
            subtitle = 'Álbum';
          } else {
            subtitle = artist;
          }
          return Playlist(
            id: 'album:${e.key}',
            title: e.key,
            subtitle: subtitle,
            kind: PlaylistKind.album,
            songs: List<Song>.unmodifiable(e.value),
          );
        }).toList()..sort(
          (a, b) => _compareWithUnknownLast(
            a.title,
            b.title,
            unknownAlbum,
          ),
        );
    return List<Playlist>.unmodifiable(result);
  }

  static List<Playlist> fromArtists(List<Song> songs) {
    final map = <String, List<Song>>{};
    for (final s in songs) {
      if (s.kind != MediaKind.music) continue;
      final key = s.artistOrUnknown;
      map.putIfAbsent(key, () => []).add(s);
    }
    final result =
        map.entries.map((e) {
          final isUnknown = e.key == unknownArtist;
          final albums = e.value
              .map((s) => s.album.trim())
              .where((a) => a.isNotEmpty)
              .toSet();
          final String subtitle;
          if (isUnknown) {
            subtitle = albums.isEmpty
                ? '${e.value.length} canciones · sin metadatos'
                : '${e.value.length} canciones · ${albums.length} álbumes';
          } else {
            subtitle = albums.isEmpty
                ? '${e.value.length} canciones'
                : '${e.value.length} canciones · ${albums.length} álbumes';
          }
          return Playlist(
            id: 'artist:${e.key}',
            title: e.key,
            subtitle: subtitle,
            kind: PlaylistKind.artist,
            songs: List<Song>.unmodifiable(e.value),
          );
        }).toList()..sort(
          (a, b) => _compareWithUnknownLast(
            a.title,
            b.title,
            unknownArtist,
          ),
        );
    return List<Playlist>.unmodifiable(result);
  }

  static List<Playlist> fromPodcasts(List<Song> podcasts) {
    final map = <String, List<Song>>{};
    for (final s in podcasts) {
      final parts = s.path.split(RegExp(r'[/\\]'));
      final folder =
          parts.length >= 2 ? parts[parts.length - 2] : 'Podcasts';
      map.putIfAbsent(folder, () => []).add(s);
    }
    final result =
        map.entries.map((e) {
          return Playlist(
            id: 'podcast:${e.key}',
            title: e.key,
            subtitle: '${e.value.length} episodios',
            kind: PlaylistKind.podcast,
            songs: List<Song>.unmodifiable(e.value),
          );
        }).toList()..sort(
          (a, b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    return List<Playlist>.unmodifiable(result);
  }

  static int _compareWithUnknownLast(
    String a,
    String b,
    String unknownLabel, {
    bool unknownFirst = false,
  }) {
    final aUnknown = a == unknownLabel;
    final bUnknown = b == unknownLabel;
    if (aUnknown && bUnknown) return 0;
    if (aUnknown) return unknownFirst ? -1 : 1;
    if (bUnknown) return unknownFirst ? 1 : -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }
}
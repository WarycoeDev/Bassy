import 'package:flutter/foundation.dart';

import 'song.dart';

/// Categoría agrupadora: álbum, artista o podcast.
enum PlaylistKind { album, artist, podcast }

@immutable
class Playlist {
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

  String get totalDurationLabel {
    final total = totalDuration.inSeconds;
    if (total <= 0) return '--:--';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
    return '$m min';
  }

  /// Agrupa canciones por álbum. Omite las que no tienen álbum.
  static List<Playlist> fromAlbums(List<Song> songs) {
    final map = <String, List<Song>>{};
    for (final s in songs) {
      final key = s.album.trim();
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => []).add(s);
    }
    final result =
        map.entries.map((e) {
          final artist = e.value.first.artist.trim();
          return Playlist(
            id: 'album:${e.key}',
            title: e.key,
            subtitle: artist.isEmpty ? 'Álbum' : artist,
            kind: PlaylistKind.album,
            songs: List<Song>.unmodifiable(e.value),
          );
        }).toList()..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    return List<Playlist>.unmodifiable(result);
  }

  /// Agrupa canciones por artista. Omite las que no tienen artista.
  static List<Playlist> fromArtists(List<Song> songs) {
    final map = <String, List<Song>>{};
    for (final s in songs) {
      final key = s.artist.trim();
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => []).add(s);
    }
    final result =
        map.entries.map((e) {
          final albums = e.value
              .map((s) => s.album.trim())
              .where((a) => a.isNotEmpty)
              .toSet();
          return Playlist(
            id: 'artist:${e.key}',
            title: e.key,
            subtitle: albums.isEmpty
                ? '${e.value.length} canciones'
                : '${e.value.length} canciones · ${albums.length} álbumes',
            kind: PlaylistKind.artist,
            songs: List<Song>.unmodifiable(e.value),
          );
        }).toList()..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    return List<Playlist>.unmodifiable(result);
  }

  /// Agrupa podcasts por carpeta padre (cada carpeta = un "show").
  static List<Playlist> fromPodcasts(List<Song> podcasts) {
    final map = <String, List<Song>>{};
    for (final s in podcasts) {
      final parts = s.path.split(RegExp(r'[/\\]'));
      final folder = parts.length >= 2 ? parts[parts.length - 2] : 'Podcasts';
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
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    return List<Playlist>.unmodifiable(result);
  }
}

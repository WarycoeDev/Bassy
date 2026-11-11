import 'package:flutter/foundation.dart';

/// Tipo de medio detectado por el scanner.
enum MediaKind { music, podcast }

@immutable
class Song {
  final String path;
  final String fileName;
  final String title;
  final String artist;
  final String album;
  final String extension;
  final int sizeBytes;
  final DateTime modified;
  final MediaKind kind;
  final Duration duration;
  final String? coverPath;

  const Song({
    required this.path,
    required this.fileName,
    required this.title,
    required this.artist,
    required this.album,
    required this.extension,
    required this.sizeBytes,
    required this.modified,
    required this.kind,
    this.duration = Duration.zero,
    this.coverPath,
  });

  /// Artista normalizado: valor real o "Artista desconocido".
  String get artistOrUnknown =>
      artist.trim().isNotEmpty ? artist.trim() : 'Artista desconocido';

  /// Álbum normalizado: valor real o "Álbum desconocido".
  String get albumOrUnknown =>
      album.trim().isNotEmpty ? album.trim() : 'Álbum desconocido';

  /// `true` si el artista está vacío (para no mostrar subtítulos redundantes).
  bool get hasArtist => artist.trim().isNotEmpty;
  bool get hasAlbum => album.trim().isNotEmpty;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    const units = ['KB', 'MB', 'GB'];
    double v = sizeBytes / 1024;
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }

  String get durationLabel {
    final total = duration.inSeconds;
    if (total <= 0) return '--:--';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  /// Subtítulo para el tile: artista · álbum si existen, si no "Artista desconocido".
  String get subtitle {
    if (hasArtist) {
      return hasAlbum ? '$artist · $album' : artist;
    }
    if (hasAlbum) return album;
    return 'Artista desconocido';
  }

  String get id => path;

  Song copyWith({
    String? path,
    String? fileName,
    String? title,
    String? artist,
    String? album,
    String? extension,
    int? sizeBytes,
    DateTime? modified,
    MediaKind? kind,
    Duration? duration,
    String? coverPath,
  }) {
    return Song(
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      extension: extension ?? this.extension,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modified: modified ?? this.modified,
      kind: kind ?? this.kind,
      duration: duration ?? this.duration,
      coverPath: coverPath ?? this.coverPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Song && other.path == path);

  @override
  int get hashCode => path.hashCode;
}
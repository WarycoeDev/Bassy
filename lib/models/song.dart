import 'package:flutter/foundation.dart';

/// Tipo de medio detectado por el scanner.
enum MediaKind { music, podcast }

@immutable
class Song {
  /// Ruta absoluta del archivo.
  final String path;

  /// Nombre del archivo sin extensión (título "fallback").
  final String fileName;

  /// Título mostrado (por ahora = fileName, luego puedes leer tags ID3).
  final String title;

  /// Artista (si se lee de tags, si no queda vacío).
  final String artist;

  /// Álbum (idem).
  final String album;

  /// Extensión en minúsculas sin punto: mp3, m4a, flac, ogg, opus, wav, aac.
  final String extension;

  /// Tamaño en bytes.
  final int sizeBytes;

  /// Última modificación (útil para invalidar caché).
  final DateTime modified;

  /// Música o podcast, según el directorio donde se encontró.
  final MediaKind kind;

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
  });

  /// Tamaño legible tipo "8.2 MB".
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

  /// Subtítulo para el tile: artista si existe, si no la carpeta padre.
  String get subtitle {
    if (artist.isNotEmpty) {
      return album.isNotEmpty ? '$artist · $album' : artist;
    }
    final parts = path.split(RegExp(r'[/\\]'));
    if (parts.length >= 2) return parts[parts.length - 2];
    return kind == MediaKind.podcast ? 'Podcast' : 'Música';
  }

  /// Clave estable para identificar la canción (ruta).
  String get id => path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Song && other.path == path);

  @override
  int get hashCode => path.hashCode;
}

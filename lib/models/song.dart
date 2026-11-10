import 'package:flutter/foundation.dart';

/// Tipo de medio detectado por el scanner.
enum MediaKind { music, podcast }

@immutable
class Song {
  /// Ruta absoluta del archivo.
  final String path;

  /// Nombre del archivo sin extensión (título "fallback").
  final String fileName;

  /// Título mostrado.
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

  /// Duración leída de los tags. `Duration.zero` si no se pudo leer.
  final Duration duration;

  /// Ruta absoluta al JPG de carátula extraído (o `null` si no hay).
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

  /// Duración formateada "3:42" o "1:02:03" si supera la hora.
  /// "--:--" cuando aún no se conoce.
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

  /// Subtítulo para el tile: artista · álbum si existen, si no la carpeta padre.
  String get subtitle {
    if (artist.isNotEmpty) {
      return album.isNotEmpty ? '$artist · $album' : artist;
    }
    if (album.isNotEmpty) return album;
    final parts = path.split(RegExp(r'[/\\]'));
    if (parts.length >= 2) return parts[parts.length - 2];
    return kind == MediaKind.podcast ? 'Podcast' : 'Música';
  }

  /// Clave estable para identificar la canción (ruta).
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

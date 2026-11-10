import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class RawMetadata {
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final Uint8List? coverBytes;

  const RawMetadata({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.coverBytes,
  });
}

class MetadataReader {
  MetadataReader._();
  static final MetadataReader instance = MetadataReader._();

  /// Lee tags de un archivo de audio. Devuelve null si falla.
  Future<RawMetadata?> read(File file) async {
    try {
      final meta = readMetadata(file, getImage: true);
      return RawMetadata(
        title: meta.title?.trim().isNotEmpty == true
            ? meta.title!.trim()
            : p.basenameWithoutExtension(file.path),
        artist: meta.artist?.trim() ?? '',
        album: meta.album?.trim() ?? '',
        duration: meta.duration ?? Duration.zero,
        coverBytes: meta.pictures.isNotEmpty ? meta.pictures.first.bytes : null,
      );
    } catch (e) {
      debugPrint('MetadataReader: no se pudo leer ${file.path}: $e');
      return null;
    }
  }
}

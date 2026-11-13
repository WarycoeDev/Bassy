// lib/services/playlists_store.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

/// Playlist de usuario creada manualmente.
@immutable
class UserPlaylist {
  final String id;
  final String name;
  final List<String> songPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserPlaylist({
    required this.id,
    required this.name,
    required this.songPaths,
    required this.createdAt,
    required this.updatedAt,
  });

  UserPlaylist copyWith({
    String? name,
    List<String>? songPaths,
    DateTime? updatedAt,
  }) {
    return UserPlaylist(
      id: id,
      name: name ?? this.name,
      songPaths: songPaths ?? this.songPaths,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songPaths': songPaths,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UserPlaylist.fromJson(Map<String, dynamic> json) {
    return UserPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      songPaths: (json['songPaths'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Store persistente de playlists de usuario (.bassy / JSON).
///
///  - Android: `<externalFilesDir>/playlists/`
///    → `Android/data/com.example.bassy/files/playlists/`
///  - Desktop: `<documentsDir>/Bassy/playlists/`
class PlaylistsStore extends ChangeNotifier {
  PlaylistsStore._();
  static final PlaylistsStore instance = PlaylistsStore._();

  static const String fileExtension = '.bassy';
  static const String _folderName = 'playlists';
  static const String _exportsFolder = 'exports';

  final Map<String, UserPlaylist> _playlists = {};
  Directory? _dir;
  bool _loaded = false;
  bool _loading = false;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;

  List<UserPlaylist> get playlists {
    final list = _playlists.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(list);
  }

  UserPlaylist? byId(String id) => _playlists[id];

  // ============================================================
  // Directorios
  // ============================================================

  Future<Directory> _resolveDirectory() async {
    if (_dir != null) return _dir!;

    Directory base;
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      base = external ?? await getApplicationDocumentsDirectory();
    } else {
      final docs = await getApplicationDocumentsDirectory();
      base = Directory('${docs.path}${Platform.pathSeparator}Bassy');
    }

    final playlistDir =
        Directory('${base.path}${Platform.pathSeparator}$_folderName');
    if (!await playlistDir.exists()) {
      await playlistDir.create(recursive: true);
    }
    _dir = playlistDir;
    return playlistDir;
  }

  /// Expone la ruta del directorio de playlists para debug/UI.
  Future<String> directoryPath() async {
    final d = await _resolveDirectory();
    return d.path;
  }

  // ============================================================
  // Carga
  // ============================================================

  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      final dir = await _resolveDirectory();
      final entries = await dir.list().toList();
      for (final entry in entries) {
        if (entry is! File) continue;
        if (!entry.path.endsWith(fileExtension)) continue;
        try {
          final raw = await entry.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final pl = UserPlaylist.fromJson(json);
          _playlists[pl.id] = pl;
        } catch (e) {
          debugPrint('PlaylistsStore: archivo inválido ${entry.path}: $e');
        }
      }
      _loaded = true;
    } catch (e) {
      debugPrint('PlaylistsStore.load error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // CRUD
  // ============================================================

  Future<UserPlaylist> create(String name) async {
    final dir = await _resolveDirectory();
    final now = DateTime.now();
    final id = 'pl_${now.microsecondsSinceEpoch}';
    final playlist = UserPlaylist(
      id: id,
      name: name.trim(),
      songPaths: const [],
      createdAt: now,
      updatedAt: now,
    );

    final file =
        File('${dir.path}${Platform.pathSeparator}$id$fileExtension');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(playlist.toJson()),
    );

    _playlists[id] = playlist;
    notifyListeners();
    return playlist;
  }

  Future<void> save(UserPlaylist playlist) async {
    final dir = await _resolveDirectory();
    final updated = playlist.copyWith(updatedAt: DateTime.now());
    final file = File(
        '${dir.path}${Platform.pathSeparator}${updated.id}$fileExtension');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(updated.toJson()),
    );
    _playlists[updated.id] = updated;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final dir = await _resolveDirectory();
    final file =
        File('${dir.path}${Platform.pathSeparator}$id$fileExtension');
    if (await file.exists()) {
      await file.delete();
    }
    _playlists.remove(id);
    notifyListeners();
  }

  // ============================================================
  // Canciones dentro de una playlist
  // ============================================================

  Future<void> addSong(String playlistId, Song song) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    if (pl.songPaths.contains(song.path)) return;
    await save(pl.copyWith(songPaths: [...pl.songPaths, song.path]));
  }

  Future<void> removeSong(String playlistId, Song song) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    await save(
      pl.copyWith(
        songPaths: pl.songPaths.where((p) => p != song.path).toList(),
      ),
    );
  }

  /// Aplica cambios en lote: añade la canción a [addToIds] y la quita de
  /// [removeFromIds]. Es lo que usa `PlaylistPickerDialog` al pulsar
  /// "Guardar".
  Future<void> setSongInPlaylists(
    Song song, {
    required Set<String> addToIds,
    required Set<String> removeFromIds,
  }) async {
    for (final id in removeFromIds) {
      final pl = _playlists[id];
      if (pl == null) continue;
      if (!pl.songPaths.contains(song.path)) continue;
      await save(
        pl.copyWith(
          songPaths: pl.songPaths.where((p) => p != song.path).toList(),
        ),
      );
    }
    for (final id in addToIds) {
      final pl = _playlists[id];
      if (pl == null) continue;
      if (pl.songPaths.contains(song.path)) continue;
      await save(pl.copyWith(songPaths: [...pl.songPaths, song.path]));
    }
  }

  /// Reordena: mueve el elemento en [oldIndex] a [newIndex].
  /// Acepta `newIndex == songPaths.length` (soltar al final).
  Future<void> reorder(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    final paths = [...pl.songPaths];
    if (oldIndex < 0 || oldIndex >= paths.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= paths.length) newIndex = paths.length - 1;
    if (oldIndex == newIndex) return;
    final item = paths.removeAt(oldIndex);
    paths.insert(newIndex, item);
    await save(pl.copyWith(songPaths: paths));
  }

  /// Aplica un orden explícito de paths (usado por la UI al salir del
  /// modo reordenar). Filtra paths que ya no pertenezcan a la playlist
  /// y preserva los que falten para no perder nada.
  Future<void> reorderToPaths(
    String playlistId,
    List<String> orderedPaths,
  ) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    final current = pl.songPaths.toSet();
    final filtered = <String>[
      for (final p in orderedPaths)
        if (current.contains(p)) p,
    ];
    final seen = filtered.toSet();
    for (final p in pl.songPaths) {
      if (!seen.contains(p)) filtered.add(p);
    }
    if (listEquals(filtered, pl.songPaths)) return;
    await save(pl.copyWith(songPaths: filtered));
  }

  /// Quita la canción en [index] de la playlist.
  Future<void> removeAt(String playlistId, int index) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    if (index < 0 || index >= pl.songPaths.length) return;
    final paths = [...pl.songPaths]..removeAt(index);
    await save(pl.copyWith(songPaths: paths));
  }

  // ============================================================
  // Exportación
  // ============================================================

  /// Exporta el archivo `.bassy` a una carpeta pública accesible:
  ///  - Android: intenta `<externalFilesDir>/../Downloads/` y, si no
  ///    existe, cae a `<externalFilesDir>/exports/`.
  ///  - Desktop: `<documentsDir>/Bassy/exports/`.
  /// Devuelve la ruta final del archivo exportado.
  Future<String> exportTo(String id) async {
    final dir = await _resolveDirectory();
    final source =
        File('${dir.path}${Platform.pathSeparator}$id$fileExtension');
    if (!await source.exists()) {
      throw FileSystemException('No existe el archivo', source.path);
    }

    final Directory targetDir;
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        // `<pkg>/files` → `<pkg>` → `Android/data`
        //         → `Android` → `Android/data/../..` = storage root
        final storageRoot = ext.parent?.parent?.parent?.parent;
        if (storageRoot != null) {
          final downloads = Directory(
            '${storageRoot.path}${Platform.pathSeparator}Downloads',
          );
          if (await downloads.exists()) {
            targetDir = downloads;
          } else {
            targetDir = Directory(
              '${ext.path}${Platform.pathSeparator}$_exportsFolder',
            );
          }
        } else {
          targetDir = Directory(
            '${ext.path}${Platform.pathSeparator}$_exportsFolder',
          );
        }
      } else {
        final docs = await getApplicationDocumentsDirectory();
        targetDir = Directory(
          '${docs.path}${Platform.pathSeparator}$_exportsFolder',
        );
      }
    } else {
      final docs = await getApplicationDocumentsDirectory();
      targetDir = Directory(
        '${docs.path}${Platform.pathSeparator}Bassy'
        '${Platform.pathSeparator}$_exportsFolder',
      );
    }

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final target = File(
      '${targetDir.path}${Platform.pathSeparator}$id$fileExtension',
    );
    await source.copy(target.path);
    return target.path;
  }
}
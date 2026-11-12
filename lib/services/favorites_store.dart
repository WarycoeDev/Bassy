// lib/services/favorites_store.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';
import '../models/song.dart';

/// Almacén persistente de favoritos.
///
/// Se guarda como un archivo `.bassy` (JSON) en:
///   Android/data/com.example.bassy/favorites.bassy
///
/// El archivo guarda SOLO los `path` de las canciones, en orden. Al cargar,
/// se resuelven contra el catálogo actual (las que ya no existan se omiten).
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._();
  static final FavoritesStore instance = FavoritesStore._();

  static const String _fileName = 'favorites.bassy';
  static const String _dirHint = 'com.example.bassy';

  final List<String> _paths = <String>[];
  File? _file;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<String> get paths => List.unmodifiable(_paths);
  int get count => _paths.length;
  bool contains(Song song) => _paths.contains(song.path);

  /// Directorio objetivo.
  ///
  /// En Android: `getExternalStorageDirectory()` devuelve
  /// `.../Android/data/<pkg>/files`; subimos un nivel para quedar en
  /// `.../Android/data/<pkg>` y, si el pkg no coincide con `_dirHint`,
  /// creamos `com.example.bassy` junto a él.
  ///
  /// En otras plataformas / tests: `getApplicationSupportDirectory()`.
  Future<Directory> _resolveDir() async {
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final pkgDir = ext.parent; // .../Android/data/<pkg>
          if (pkgDir.path.endsWith(_dirHint)) return pkgDir;
          final target = Directory('${pkgDir.path}/$_dirHint');
          await target.create(recursive: true);
          return target;
        }
      } catch (e) {
        debugPrint('FavoritesStore: external dir falló -> $e');
      }
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/$_dirHint');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final dir = await _resolveDir();
      final f = File('${dir.path}/$_fileName');
      _file = f;
      if (await f.exists()) {
        final raw = await f.readAsString();
        if (raw.trim().isEmpty) {
          _loaded = true;
          notifyListeners();
          return;
        }
        final data = jsonDecode(raw);
        if (data is Map && data['paths'] is List) {
          _paths
            ..clear()
            ..addAll((data['paths'] as List).whereType<String>());
        } else if (data is List) {
          // compat: archivo con solo un array de paths
          _paths
            ..clear()
            ..addAll(data.whereType<String>());
        }
      }
    } catch (e) {
      debugPrint('FavoritesStore: load falló -> $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final f = _file ??= File(
        '${(await _resolveDir()).path}/$_fileName',
      );
      final payload = jsonEncode({
        'version': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'paths': _paths,
      });
      await f.writeAsString(payload, flush: true);
    } catch (e) {
      debugPrint('FavoritesStore: persist falló -> $e');
    }
  }

  Future<bool> add(Song song) async {
    if (_paths.contains(song.path)) return false;
    _paths.add(song.path);
    notifyListeners();
    await _persist();
    return true;
  }

  Future<bool> remove(Song song) async {
    final removed = _paths.remove(song.path);
    if (removed) {
      notifyListeners();
      await _persist();
    }
    return removed;
  }

  Future<bool> toggle(Song song) =>
      contains(song) ? remove(song) : add(song);

  /// Reordena: mueve el elemento en [oldIndex] a [newIndex].
  /// Acepta `newIndex == _paths.length` (soltar al final).
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _paths.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= _paths.length) newIndex = _paths.length - 1;
    final item = _paths.removeAt(oldIndex);
    _paths.insert(newIndex, item);
    notifyListeners();
    await _persist();
  }

  /// Construye la `Playlist` de favoritos resolviendo contra [catalog].
  /// Las canciones que ya no existen en el catálogo se omiten.
  Playlist buildPlaylist(List<Song> catalog) {
    final byPath = {for (final s in catalog) s.path: s};
    final resolved = <Song>[];
    for (final p in _paths) {
      final s = byPath[p];
      if (s != null) resolved.add(s);
    }
    return Playlist(
      id: 'favorites',
      title: 'Favoritos',
      subtitle: '${resolved.length} canciones',
      kind: PlaylistKind.favorites,
      songs: List<Song>.unmodifiable(resolved),
    );
  }
}
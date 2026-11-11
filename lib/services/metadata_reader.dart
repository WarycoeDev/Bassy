import 'dart:async';
import 'dart:io';
import 'dart:isolate';
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

/// Wrapper serializable para mandar el resultado de vuelta desde el isolate.
/// `RawMetadata` contiene `Uint8List`, que sí es transferible, así que
/// podemos pasarlo directamente — pero usamos un map para desacoplar.
class _WorkerResponse {
  final int id;
  final Map<String, dynamic>? data;
  final String? error;
  const _WorkerResponse({required this.id, this.data, this.error});
}

class MetadataReader {
  MetadataReader._();
  static final MetadataReader instance = MetadataReader._();

  Isolate? _worker;
  SendPort? _workerSendPort;
  final Map<int, Completer<RawMetadata?>> _pending = {};
  int _nextId = 0;
  bool _starting = false;
  Future<void>? _startFuture;
  ReceivePort? _mainPort;

  /// Arranca (una sola vez) el isolate persistente.
  Future<void> _ensureWorker() async {
    if (_workerSendPort != null) return;
    if (_starting) {
      await _startFuture;
      return;
    }
    _starting = true;
    _startFuture = _spawnWorker();
    try {
      await _startFuture;
    } finally {
      _starting = false;
      _startFuture = null;
    }
  }

  Future<void> _spawnWorker() async {
    final mainPort = ReceivePort();
    _mainPort = mainPort;

    final ready = Completer<SendPort>();
    final initPort = ReceivePort();
    final initSub = initPort.listen((msg) {
      if (msg is SendPort && !ready.isCompleted) {
        ready.complete(msg);
      }
    });

    // mainPort recibe respuestas del worker.
    mainPort.listen((msg) {
      if (msg is _WorkerResponse) {
        final c = _pending.remove(msg.id);
        if (c == null) return;
        if (msg.error != null) {
          c.complete(null);
        } else {
          final d = msg.data!;
          c.complete(
            RawMetadata(
              title: d['title'] as String,
              artist: d['artist'] as String,
              album: d['album'] as String,
              duration: Duration(milliseconds: d['durationMs'] as int),
              coverBytes: d['coverBytes'] as Uint8List?,
            ),
          );
        }
      }
    });

    try {
      _worker = await Isolate.spawn(
        _workerMain,
        [initPort.sendPort, mainPort.sendPort],
        debugName: 'MetadataReaderWorker',
      );
      _workerSendPort = await ready.future;
    } catch (e, st) {
      debugPrint('MetadataReader: no se pudo arrancar worker: $e\n$st');
      _worker = null;
      _workerSendPort = null;
      rethrow;
    } finally {
      initSub.cancel();
      initPort.close();
    }
  }

  /// Punto de entrada del isolate worker.
  static void _workerMain(List<dynamic> args) {
    final initSendPort = args[0] as SendPort;
    final mainSendPort = args[1] as SendPort;

    final cmdPort = ReceivePort();
    initSendPort.send(cmdPort.sendPort);

    cmdPort.listen((msg) {
      if (msg is! Map) return;
      final id = msg['id'] as int;
      final path = msg['path'] as String;

      try {
        final file = File(path);
        final meta = readMetadata(file, getImage: true);
        final data = <String, dynamic>{
          'title': meta.title?.trim().isNotEmpty == true
              ? meta.title!.trim()
              : p.basenameWithoutExtension(file.path),
          'artist': meta.artist?.trim() ?? '',
          'album': meta.album?.trim() ?? '',
          'durationMs': (meta.duration ?? Duration.zero).inMilliseconds,
          'coverBytes':
              meta.pictures.isNotEmpty ? meta.pictures.first.bytes : null,
        };
        mainSendPort.send(_WorkerResponse(id: id, data: data));
      } catch (e) {
        mainSendPort.send(_WorkerResponse(id: id, error: '$e'));
      }
    });
  }

  /// Lee tags de un archivo de audio usando el worker persistente.
  Future<RawMetadata?> read(File file) async {
    try {
      await _ensureWorker();
    } catch (e) {
      debugPrint('MetadataReader: worker no disponible, fallback sync: $e');
      // Fallback: lectura síncrona (último recurso).
      return _readSyncSafe(file);
    }

    final sendPort = _workerSendPort;
    if (sendPort == null) return _readSyncSafe(file);

    final id = _nextId++;
    final completer = Completer<RawMetadata?>();
    _pending[id] = completer;

    try {
      sendPort.send({'id': id, 'path': file.path});
      // Timeout generoso por si el worker se atasca con un archivo corrupto.
      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          _pending.remove(id);
          debugPrint('MetadataReader: timeout leyendo ${file.path}');
          return null;
        },
      );
    } catch (e) {
      _pending.remove(id);
      debugPrint('MetadataReader: error enviando a worker: $e');
      return _readSyncSafe(file);
    }
  }

  /// Lectura síncrona de último recurso (sin worker).
  static RawMetadata? _readSyncSafe(File file) {
    try {
      final meta = readMetadata(file, getImage: true);
      return RawMetadata(
        title: meta.title?.trim().isNotEmpty == true
            ? meta.title!.trim()
            : p.basenameWithoutExtension(file.path),
        artist: meta.artist?.trim() ?? '',
        album: meta.album?.trim() ?? '',
        duration: meta.duration ?? Duration.zero,
        coverBytes:
            meta.pictures.isNotEmpty ? meta.pictures.first.bytes : null,
      );
    } catch (_) {
      return null;
    }
  }
}
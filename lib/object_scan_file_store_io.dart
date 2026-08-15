import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class ObjectScanFileStore {
  Future<Directory>? _rootDirectoryFuture;
  final Map<String, Future<Directory>> _scanDirectories = {};

  Future<Directory> _rootDirectory() {
    return _rootDirectoryFuture ??= _createRootDirectory();
  }

  Future<Directory> _createRootDirectory() async {
    final documents = await getApplicationDocumentsDirectory();

    final directory = Directory('${documents.path}/taskproof_object_scans');

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<Directory> _scanDirectory(String id) {
    return _scanDirectories.putIfAbsent(id, () async {
      final root = await _rootDirectory();
      final directory = Directory('${root.path}/$id');

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      return directory;
    });
  }

  Future<String> createScanDirectory(String id) async {
    final directory = await _scanDirectory(id);
    return directory.path;
  }

  Future<String> saveSample({
    required String scanId,
    required int index,
    required Uint8List bytes,
  }) async {
    final directory = await _scanDirectory(scanId);

    final path =
        '${directory.path}/view_${index.toString().padLeft(2, '0')}.jpg';

    final file = File(path);

    // Awaiting the write is sufficient here. Forcing an fsync for every one of
    // the scan's viewpoints stalls the camera loop without improving recovery.
    await file.writeAsBytes(bytes);

    return path;
  }

  Future<Uint8List?> readBytes(String path) async {
    final file = File(path);

    if (!await file.exists()) {
      return null;
    }

    return file.readAsBytes();
  }

  Future<void> deleteScanDirectory(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);

    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
      case FileSystemEntityType.file:
        // Camera captures are temporary files. The scan flow also routes them
        // through this cleanup path after the useful bytes have been persisted.
        await File(path).delete();
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.notFound:
        return;
      default:
        // Named pipes and sockets are never created by the scan workflow.
        return;
    }

    final segments = path.split(Platform.pathSeparator);
    if (segments.isNotEmpty) {
      _scanDirectories.remove(segments.last);
    }
  }
}

import 'dart:typed_data';

class ObjectScanFileStore {
  Future<String> createScanDirectory(String id) {
    throw UnsupportedError(
      'Object scanning is only available on supported mobile devices.',
    );
  }

  Future<String> saveSample({
    required String scanId,
    required int index,
    required Uint8List bytes,
  }) {
    throw UnsupportedError(
      'Object scanning is only available on supported mobile devices.',
    );
  }

  Future<Uint8List?> readBytes(String path) async {
    return null;
  }

  Future<void> deleteScanDirectory(String path) async {}
}

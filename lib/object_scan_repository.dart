import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'object_scan_file_store_stub.dart'
    if (dart.library.io) 'object_scan_file_store_io.dart';

class SavedObjectScan {
  const SavedObjectScan({
    required this.id,
    required this.name,
    required this.scanPath,
    this.thumbnailPath,
    this.samplePaths = const [],
    this.createdAt,
  });

  final String id;
  final String name;

  /// Directory containing this object's scan views.
  final String scanPath;

  final String? thumbnailPath;

  /// Unique automatically sampled viewpoints.
  final List<String> samplePaths;

  final DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'scanPath': scanPath,
      'thumbnailPath': thumbnailPath,
      'samplePaths': samplePaths,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory SavedObjectScan.fromJson(Map<String, dynamic> json) {
    return SavedObjectScan(
      id: json['id'] as String,
      name: json['name'] as String,
      scanPath: json['scanPath'] as String,
      thumbnailPath: json['thumbnailPath'] as String?,
      samplePaths: (json['samplePaths'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }
}

class ObjectScanRepository {
  static const String _storageKey = 'taskproof_saved_object_scans_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  final ObjectScanFileStore _files = ObjectScanFileStore();

  Future<List<SavedObjectScan>> loadAll() async {
    final raw = await _preferences.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;

      final scans = decoded
          .map(
            (item) => SavedObjectScan.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

      scans.sort((a, b) {
        final first = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

        final second = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

        return second.compareTo(first);
      });

      return scans;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(SavedObjectScan scan) async {
    final scans = await loadAll();

    scans.removeWhere((existing) => existing.id == scan.id);

    scans.add(scan);

    await _writeAll(scans);
  }

  Future<void> delete(SavedObjectScan scan) async {
    final scans = await loadAll();

    scans.removeWhere((existing) => existing.id == scan.id);

    await _writeAll(scans);

    await _files.deleteScanDirectory(scan.scanPath);
  }

  Future<SavedObjectScan?> findById(String id) async {
    final scans = await loadAll();

    for (final scan in scans) {
      if (scan.id == id) {
        return scan;
      }
    }

    return null;
  }

  Future<void> _writeAll(List<SavedObjectScan> scans) async {
    final value = jsonEncode(scans.map((scan) => scan.toJson()).toList());

    await _preferences.setString(_storageKey, value);
  }

  String createId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Future<String> createScanDirectory(String scanId) {
    return _files.createScanDirectory(scanId);
  }

  Future<String> saveSample({
    required String scanId,
    required int index,
    required Uint8List bytes,
  }) {
    return _files.saveSample(
      scanId: scanId,
      index: index,
      bytes: bytes,
    );
  }

  Future<Uint8List?> readImage(String path) {
    return _files.readBytes(path);
  }

  Future<void> discardScan(String directory) {
    return _files.deleteScanDirectory(directory);
  }
}
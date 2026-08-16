import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    show DetectionMode, InputImage, ObjectDetector, ObjectDetectorOptions;
import 'package:image/image.dart' as img;

import 'object_scan_repository.dart';

const _taskProofRed = Color(0xFFFF111C);

class _ScanCropRequest {
  const _ScanCropRequest({required this.bytes, required this.bounds});

  final Uint8List bytes;
  final List<List<double>> bounds;
}

Uint8List? _cropScanToPrimaryObject(
  _ScanCropRequest request,
) {
  final decoded =
      img.decodeImage(
    request.bytes,
  );

  if (decoded == null) {
    return null;
  }

  final image =
      img.bakeOrientation(
    decoded,
  );

  // ===========================================================
  // FALLBACK — CENTER CROP
  // ===========================================================
  //
  // The scan UI tells the user to keep the object centered.
  //
  // Small or unusual objects such as mice may not receive an
  // ML Kit bounding box. In that case, DO NOT save the entire
  // camera frame as the object profile.
  //
  // Save the center portion instead.
  // ===========================================================

  if (request.bounds.isEmpty) {
    final shortest =
        math.min(
      image.width,
      image.height,
    );

    final cropSize =
        math.max(
      32,
      (shortest * 0.62).round(),
    );

    final left =
        (image.width - cropSize) ~/
        2;

    final top =
        (image.height - cropSize) ~/
        2;

    final cropped =
        img.copyCrop(
      image,
      x: left,
      y: top,
      width: cropSize,
      height: cropSize,
    );

    return Uint8List.fromList(
      img.encodeJpg(
        cropped,
        quality: 92,
      ),
    );
  }

  // ===========================================================
  // ML KIT OBJECT BOX
  // ===========================================================

  final centerX =
      image.width / 2;

  final centerY =
      image.height / 2;

  List<double>? best;

  var bestScore =
      double.negativeInfinity;

  for (final values
      in request.bounds) {
    if (values.length != 4) {
      continue;
    }

    final left =
        values[0].clamp(
      0.0,
      image.width.toDouble(),
    );

    final top =
        values[1].clamp(
      0.0,
      image.height.toDouble(),
    );

    final right =
        values[2].clamp(
      0.0,
      image.width.toDouble(),
    );

    final bottom =
        values[3].clamp(
      0.0,
      image.height.toDouble(),
    );

    final width =
        right - left;

    final height =
        bottom - top;

    final areaFraction =
        width *
        height /
        (image.width *
            image.height);

    if (width < 12 ||
        height < 12 ||
        areaFraction < 0.008) {
      continue;
    }

    final objectCenterX =
        (left + right) / 2;

    final objectCenterY =
        (top + bottom) / 2;

    final normalizedDistance =
        math.sqrt(
      math.pow(
            (objectCenterX -
                    centerX) /
                image.width,
            2,
          ) +
          math.pow(
            (objectCenterY -
                    centerY) /
                image.height,
            2,
          ),
    );

    final score =
        (1 - normalizedDistance)
                .clamp(
                  0.0,
                  1.0,
                ) *
            2.2 +
        math.sqrt(
          areaFraction.clamp(
            0.0,
            1.0,
          ),
        );

    if (score > bestScore) {
      bestScore = score;

      best = [
        left,
        top,
        right,
        bottom,
      ];
    }
  }

  // ML Kit technically returned objects, but none were
  // usable. Fall back to the centered scan region rather
  // than storing the entire photograph.
  if (best == null) {
    final shortest =
        math.min(
      image.width,
      image.height,
    );

    final cropSize =
        math.max(
      32,
      (shortest * 0.62).round(),
    );

    final left =
        (image.width - cropSize) ~/
        2;

    final top =
        (image.height - cropSize) ~/
        2;

    final cropped =
        img.copyCrop(
      image,
      x: left,
      y: top,
      width: cropSize,
      height: cropSize,
    );

    return Uint8List.fromList(
      img.encodeJpg(
        cropped,
        quality: 92,
      ),
    );
  }

  final objectWidth =
      best[2] - best[0];

  final objectHeight =
      best[3] - best[1];

  final paddingX =
      objectWidth * 0.14;

  final paddingY =
      objectHeight * 0.14;

  final left =
      (best[0] - paddingX)
          .floor()
          .clamp(
            0,
            image.width - 1,
          );

  final top =
      (best[1] - paddingY)
          .floor()
          .clamp(
            0,
            image.height - 1,
          );

  final right =
      (best[2] + paddingX)
          .ceil()
          .clamp(
            left + 1,
            image.width,
          );

  final bottom =
      (best[3] + paddingY)
          .ceil()
          .clamp(
            top + 1,
            image.height,
          );

  final cropped =
      img.copyCrop(
    image,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );

  return Uint8List.fromList(
    img.encodeJpg(
      cropped,
      quality: 92,
    ),
  );
}

int? _createObjectScanHash(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    return null;
  }

  final resized = img.copyResize(decoded, width: 8, height: 8);

  final luminance = <double>[];

  double total = 0;

  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final value = resized.getPixel(x, y).luminanceNormalized.toDouble();

      luminance.add(value);

      total += value;
    }
  }

  final average = total / luminance.length;

  int hash = 0;

  for (var i = 0; i < luminance.length; i++) {
    if (luminance[i] >= average) {
      hash |= 1 << i;
    }
  }

  return hash;
}

class ObjectScanLibraryPage extends StatefulWidget {
  const ObjectScanLibraryPage({
    super.key,
    required this.initialSelectedIds,
    required this.isDarkMode,
  });

  final List<String> initialSelectedIds;
  final bool isDarkMode;

  @override
  State<ObjectScanLibraryPage> createState() => _ObjectScanLibraryPageState();
}

class _ObjectScanLibraryPageState extends State<ObjectScanLibraryPage> {
  final ObjectScanRepository _repository = ObjectScanRepository();

  List<SavedObjectScan> _scans = [];

  late final Set<String> _selectedIds;

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _selectedIds = widget.initialSelectedIds.toSet();

    _load();
  }

  Future<void> _load() async {
    final scans = await _repository.loadAll();

    if (!mounted) {
      return;
    }

    setState(() {
      _scans = scans;

      _selectedIds.removeWhere((id) => !scans.any((scan) => scan.id == id));

      _loading = false;
    });
  }

  Future<void> _scanNewObject() async {
    final scan = await Navigator.push<SavedObjectScan>(
      context,
      MaterialPageRoute(
        builder: (_) => ContinuousObjectScanPage(isDarkMode: widget.isDarkMode),
      ),
    );

    if (scan == null || !mounted) {
      return;
    }

    final scans = await _repository.loadAll();

    if (!mounted) {
      return;
    }

    setState(() {
      _scans = scans;

      if (_selectedIds.length < 3) {
        _selectedIds.add(scan.id);
      }
    });
  }

  void _toggle(SavedObjectScan scan) {
    setState(() {
      if (_selectedIds.contains(scan.id)) {
        _selectedIds.remove(scan.id);
        return;
      }

      if (_selectedIds.length >= 3) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('You can select up to 3 required objects.'),
            ),
          );

        return;
      }

      _selectedIds.add(scan.id);
    });
  }

  void _finish() {
    final selected = _scans
        .where((scan) => _selectedIds.contains(scan.id))
        .toList();

    Navigator.pop(context, selected);
  }

  Future<void> _delete(SavedObjectScan scan) async {
    await _repository.delete(scan);

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedIds.remove(scan.id);
      _scans.removeWhere((item) => item.id == scan.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isDarkMode
        ? const Color(0xFF0B1016)
        : Colors.white;

    final card = widget.isDarkMode
        ? const Color(0xFF10161D)
        : const Color(0xFFF7F7F9);

    final text = widget.isDarkMode ? Colors.white : const Color(0xFF181A20);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: background,
        title: Text(
          'Saved Objects',
          style: TextStyle(color: text, fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text(
              'Done',
              style: TextStyle(
                color: _taskProofRed,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _scanNewObject,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: _taskProofRed,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.view_in_ar_rounded),
                      label: const Text(
                        'Scan New Object',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_selectedIds.length}/3 selected',
                      style: TextStyle(
                        color: widget.isDarkMode
                            ? const Color(0xFF9DA8B8)
                            : const Color(0xFF686C78),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _scans.isEmpty
                      ? Center(
                          child: Text(
                            'No saved objects yet.',
                            style: TextStyle(color: text, fontSize: 16),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                          itemCount: _scans.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final scan = _scans[index];

                            final selected = _selectedIds.contains(scan.id);

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _toggle(scan),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: card,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selected
                                        ? _taskProofRed
                                        : widget.isDarkMode
                                        ? const Color(0xFF252D37)
                                        : const Color(0xFFE1E3E7),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _ScanThumbnail(
                                      key: ValueKey(scan.id),
                                      scan: scan,
                                      repository: _repository,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            scan.name,
                                            style: TextStyle(
                                              color: text,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${scan.samplePaths.length} scan views',
                                            style: TextStyle(
                                              color: widget.isDarkMode
                                                  ? const Color(0xFF9DA8B8)
                                                  : const Color(0xFF777A84),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Checkbox(
                                      value: selected,
                                      activeColor: _taskProofRed,
                                      onChanged: (_) => _toggle(scan),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _delete(scan);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _ScanThumbnail extends StatefulWidget {
  const _ScanThumbnail({
    super.key,
    required this.scan,
    required this.repository,
  });

  final SavedObjectScan scan;
  final ObjectScanRepository repository;

  @override
  State<_ScanThumbnail> createState() => _ScanThumbnailState();
}

class _ScanThumbnailState extends State<_ScanThumbnail> {
  Future<Uint8List?>? _bytes;

  String? get _path =>
      widget.scan.thumbnailPath ??
      (widget.scan.samplePaths.isEmpty ? null : widget.scan.samplePaths.first);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ScanThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPath =
        oldWidget.scan.thumbnailPath ??
        (oldWidget.scan.samplePaths.isEmpty
            ? null
            : oldWidget.scan.samplePaths.first);
    if (oldPath != _path || oldWidget.repository != widget.repository) {
      _load();
    }
  }

  void _load() {
    final path = _path;
    _bytes = path == null ? null : widget.repository.readImage(path);
  }

  @override
  Widget build(BuildContext context) {
    final bytesFuture = _bytes;
    if (bytesFuture == null) {
      return _placeholder();
    }

    return FutureBuilder<Uint8List?>(
      future: bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;

        if (bytes == null) {
          return _placeholder();
        }

        final cacheSize = (66 * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(66, 264)
            .toInt();
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            width: 66,
            height: 66,
            fit: BoxFit.cover,
            cacheWidth: cacheSize,
          ),
        );
      },
    );
  }

  Widget _placeholder() {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEEF1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.inventory_2_outlined),
    );
  }
}

class ContinuousObjectScanPage extends StatefulWidget {
  const ContinuousObjectScanPage({super.key, required this.isDarkMode});

  final bool isDarkMode;

  @override
  State<ContinuousObjectScanPage> createState() =>
      _ContinuousObjectScanPageState();
}

class _ContinuousObjectScanPageState extends State<ContinuousObjectScanPage>
    with WidgetsBindingObserver {
  static const int _targetViews = 12;
  static const int _minimumViews = 6;

  final ObjectScanRepository _repository = ObjectScanRepository();
  final ObjectDetector _objectLocator = ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: false,
      multipleObjects: true,
    ),
  );

  CameraController? _controller;
  Widget? _cameraPreview;
  Future<void>? _scanTask;
  Future<void>? _activeCapture;
  Future<void>? _cameraShutdown;

  bool _initializing = true;
  bool _scanning = false;
  bool _saved = false;
  bool _finishing = false;
  bool _objectLocatorClosed = false;

  String? _error;
  String? _scanId;
  String? _scanDirectory;

  String _status = 'Place the object in the center of the frame.';

  final List<String> _samplePaths = [];
  final List<int> _viewHashes = [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initializeCamera();
  }

  bool get _mobileSupported {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _initializeCamera() async {
    if (!_mobileSupported) {
      setState(() {
        _initializing = false;
        _error = '3D object scanning is available on Android and iPhone.';
      });

      return;
    }

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera was found.');
      }

      CameraDescription camera = cameras.first;

      for (final candidate in cameras) {
        if (candidate.lensDirection == CameraLensDirection.back) {
          camera = candidate;
          break;
        }
      }

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraPreview = RepaintBoundary(child: CameraPreview(controller));

      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
        _error = 'Camera unavailable: ${error.description ?? error.code}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
        _error = 'Could not start camera: $error';
      });
    }
  }

  Future<void> _startScan() async {
    if (_scanning ||
        _finishing ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }

    final id = _repository.createId();

    final directory = await _repository.createScanDirectory(id);

    if (!mounted) {
      return;
    }

    setState(() {
      _scanId = id;
      _scanDirectory = directory;

      _samplePaths.clear();
      _viewHashes.clear();

      _scanning = true;

      _status =
          'Move slowly around the object. TaskProof will capture useful angles automatically.';
    });

    _scanTask = _scanLoop();
  }

  Future<void> _scanLoop() async {
    while (_scanning &&
        !_finishing &&
        mounted &&
        _samplePaths.length < _targetViews) {
      await _captureCandidate();

      if (!_scanning || _finishing || !mounted) {
        break;
      }

      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }

    if (!mounted || _finishing) {
      return;
    }

    if (_samplePaths.length >= _targetViews) {
      setState(() {
        _scanning = false;
        _status = 'Scan coverage complete. You can save this object.';
      });
    }
  }

  Future<void> _captureCandidate() async {
    if (_activeCapture != null || _finishing || !_scanning) {
      return;
    }

    final capture = _performCaptureCandidate();

    _activeCapture = capture;

    try {
      await capture;
    } finally {
      if (identical(_activeCapture, capture)) {
        _activeCapture = null;
      }
    }
  }

  Future<void> _performCaptureCandidate() async {
    final controller = _controller;
    final id = _scanId;

    if (controller == null ||
        id == null ||
        _finishing ||
        !_scanning ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    XFile? picture;

    try {
      picture = await controller.takePicture();

      if (!_scanning || _finishing || !mounted) {
        return;
      }

      final bytes = await picture.readAsBytes();

      if (!_scanning || _finishing || !mounted) {
        return;
      }

      List<List<double>> detectedBounds =
          const [];

      try {
        final objects =
            await _objectLocator.processImage(
          InputImage.fromFilePath(
            picture.path,
          ),
        );

        detectedBounds =
            objects
                .map(
                  (object) =>
                      <double>[
                    object.boundingBox.left,
                    object.boundingBox.top,
                    object.boundingBox.right,
                    object.boundingBox.bottom,
                  ],
                )
                .toList(
                  growable: false,
                );
      } catch (error) {
        debugPrint(
          'Object scan localization fallback: $error',
        );
      }

      // Always create an object-focused profile.
      //
      // When detectedBounds is empty, _cropScanToPrimaryObject()
      // performs the centered fallback crop.
      final localized =
          await compute(
        _cropScanToPrimaryObject,
        _ScanCropRequest(
          bytes: bytes,
          bounds: detectedBounds,
        ),
        debugLabel:
            'TaskProof scan object crop',
      );

      final profileBytes =
          localized != null &&
                  localized.isNotEmpty
              ? localized
              : bytes;

      if (!_scanning || _finishing || !mounted) {
        return;
      }

      final hash = await compute(_createObjectScanHash, profileBytes);

      if (!_scanning || _finishing || !mounted || hash == null) {
        return;
      }

      if (_isNearDuplicate(hash)) {
        if (mounted && _scanning && !_finishing) {
          setState(() {
            _status = 'Similar angle skipped — keep moving around the object.';
          });
        }

        return;
      }

      final path = await _repository.saveSample(
        scanId: id,
        index: _samplePaths.length,
        bytes: profileBytes,
      );

      if (!_scanning || _finishing || !mounted) {
        return;
      }

      setState(() {
        _viewHashes.add(hash);
        _samplePaths.add(path);

        _status =
            '${_samplePaths.length}/$_targetViews useful angles captured — keep moving slowly.';
      });
    } catch (error, stackTrace) {
      debugPrint('Object scan capture error: $error');

      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (picture != null) {
        try {
          await _repository.discardScan(picture.path);
        } catch (error, stackTrace) {
          debugPrint('Object scan temporary capture cleanup error: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }
  }

  bool _isNearDuplicate(int hash) {
    for (final previous in _viewHashes) {
      if (_hammingDistance(hash, previous) < 8) {
        return true;
      }
    }

    return false;
  }

  int _hammingDistance(int first, int second) {
    var difference = first ^ second;

    int distance = 0;

    for (var i = 0; i < 64; i++) {
      distance += difference & 1;

      difference = difference >>> 1;

      if (difference == 0) {
        break;
      }
    }

    return distance;
  }

  void _stopScan() {
    if (_finishing || !mounted) {
      return;
    }

    setState(() {
      _scanning = false;

      if (_samplePaths.length >= _minimumViews) {
        _status = 'Enough angles captured. Tap Finish Scan to save.';
      } else {
        _status =
            'Move around the object and capture at least $_minimumViews unique angles.';
      }
    });
  }

  Future<void> _finishScan() async {
    if (_finishing) {
      return;
    }

    if (_samplePaths.length < _minimumViews) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Capture at least 6 useful angles first.'),
          ),
        );

      return;
    }

    setState(() {
      _finishing = true;
      _scanning = false;
    });

    await _waitForScannerToStop();

    if (!mounted) {
      return;
    }

    final name = await _askForName();

    if (!mounted) {
      return;
    }

    if (name == null || name.trim().isEmpty) {
      setState(() {
        _finishing = false;
      });

      return;
    }

    final id = _scanId;
    final directory = _scanDirectory;

    if (id == null || directory == null) {
      setState(() {
        _finishing = false;
      });

      return;
    }

    final scan = SavedObjectScan(
      id: id,
      name: name.trim(),
      scanPath: directory,
      thumbnailPath: _samplePaths.first,
      samplePaths: List.unmodifiable(_samplePaths),
      createdAt: DateTime.now(),
    );

    try {
      await _repository.save(scan);

      // Set this before camera shutdown so dispose-time cleanup can never
      // remove a scan whose metadata was persisted successfully.
      _saved = true;

      await _shutdownCamera();
    } catch (error, stackTrace) {
      debugPrint('Object scan save error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _finishing = false;
        });

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not save the object. Please try again.'),
            ),
          );
      }

      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.pop(context, scan);
  }

  Future<String?> _askForName() async {
    var name = '';

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Name this object'),
          content: TextField(
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. Bedroom Broom'),
            onChanged: (value) {
              name = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, name);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _waitForScannerToStop() async {
    final scanTask = _scanTask;

    if (scanTask != null) {
      await scanTask;
    }

    final capture = _activeCapture;

    if (capture != null) {
      await capture;
    }
  }

  Future<void> _shutdownCamera() {
    return _cameraShutdown ??= _performCameraShutdown();
  }

  Future<void> _performCameraShutdown() async {
    _scanning = false;

    await _waitForScannerToStop();

    final controller = _controller;

    _controller = null;
    _cameraPreview = null;

    if (controller == null) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      await controller.dispose();
    } on CameraException catch (error, stackTrace) {
      debugPrint('Object scan camera shutdown error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint('Object scan camera shutdown error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _disposeScanner() async {
    await _shutdownCamera();

    if (!_objectLocatorClosed) {
      _objectLocatorClosed = true;
      try {
        await _objectLocator.close();
      } catch (_) {}
    }

    if (!_saved && _scanDirectory != null) {
      try {
        await _repository.discardScan(_scanDirectory!);
      } catch (error, stackTrace) {
        debugPrint('Object scan cleanup error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _scanning = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _scanning = false;

    unawaited(_disposeScanner());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isDarkMode
        ? const Color(0xFF090D12)
        : Colors.black;

    if (_initializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('3D Scan')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final controller = _controller!;

    final progress = (_samplePaths.length / _targetViews).clamp(0.0, 1.0);

    return PopScope(
      canPop: !_finishing,
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 14, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _finishing
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        '3D Scan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child:
                            _cameraPreview ??
                            RepaintBoundary(child: CameraPreview(controller)),
                      ),
                    ),
                    const _ScanFrame(),
                    Positioned(
                      left: 20,
                      right: 20,
                      top: 20,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .56),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: const Color(0xFF101114),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(20),
                            color: _taskProofRed,
                            backgroundColor: const Color(0xFF34363D),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_samplePaths.length}/$_targetViews',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (!_scanning)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _finishing
                              ? null
                              : _samplePaths.isEmpty
                              ? _startScan
                              : _finishScan,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _taskProofRed,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            _finishing
                                ? 'Saving...'
                                : _samplePaths.isEmpty
                                ? 'Start Scan'
                                : 'Finish Scan',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _stopScan,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          child: const Text('Stop Scan'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 270,
          height: 330,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white70, width: 2),
          ),
        ),
      ),
    );
  }
}

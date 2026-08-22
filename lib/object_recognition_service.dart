import 'dart:math' as math;
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'object_scan_repository.dart';

/// The small, UI-safe identity exposed for a loaded visual profile.
class RecognizableObject {
  const RecognizableObject({required this.id, required this.name});

  final String id;
  final String name;
}

/// Result of loading the saved scans needed by one Active session.
class ObjectRecognitionLoadResult {
  ObjectRecognitionLoadResult({
    required List<RecognizableObject> objects,
    required List<String> unavailableIds,
  }) : objects = List.unmodifiable(objects),
       unavailableIds = List.unmodifiable(unavailableIds);

  /// Objects that had at least one readable, usable saved view.
  final List<RecognizableObject> objects;

  /// Requested IDs that were deleted, unreadable, or had no usable image.
  final List<String> unavailableIds;

  List<RecognizableObject> get requiredObjects => objects;
}

/// Recognition state for one available required object.
class ObjectRecognitionMatch {
  const ObjectRecognitionMatch({
    required this.id,
    required this.name,
    required this.confidence,
    required this.isMatch,
    required this.isTemporarilyMissing,
  });

  final String id;
  final String name;

  /// Best local visual-profile similarity, in the range 0...1.
  final double confidence;

  /// True after hit confirmation. By default a failed check clears it; the
  /// page should own the user-facing missing/occlusion grace period.
  final bool isMatch;

  /// True when a previously confirmed object missed the latest analysis but
  /// is still inside [ObjectRecognitionService.missingGrace].
  final bool isTemporarilyMissing;

  bool get matched => isMatch;
}

/// Immutable camera data captured before native object localization starts.
/// Camera plugins may reuse their frame buffers as soon as the stream callback
/// returns, so recognition must never retain a [CameraImage] directly.
class ObjectFrameSnapshot {
  const ObjectFrameSnapshot._({
    required this._bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    required this._format,
    required this.rotationDegrees,
    required this.mirrorHorizontally,
  });

  final TransferableTypedData _bytes;
  final int width;
  final int height;
  final int rowStride;
  final _RawFrameFormat _format;
  final int rotationDegrees;
  final bool mirrorHorizontally;
}

/// Compares raw camera frames with the multi-angle scans already stored by
/// [ObjectScanRepository].
///
/// This is deliberately a local visual-profile matcher, not a semantic object
/// detector. Call [loadRequiredObjects] once at session startup, then call
/// [analyzeFrame] from the image stream. The default interval caps expensive
/// work at about 1.5 checks per second even if the caller submits more often.
/// The interval is a cooldown after a completed match, so slow devices never
/// immediately enqueue another expensive pass.
class ObjectRecognitionService {
  ObjectRecognitionService({
    ObjectScanRepository? repository,
    this.analysisInterval = const Duration(milliseconds: 650),
    this.missingGrace = Duration.zero,
    this.hitConfirmationFrames = 2,
  }) : _repository = repository ?? ObjectScanRepository() {
    if (analysisInterval.isNegative) {
      throw ArgumentError.value(
        analysisInterval,
        'analysisInterval',
        'Must not be negative.',
      );
    }
    if (missingGrace.isNegative) {
      throw ArgumentError.value(
        missingGrace,
        'missingGrace',
        'Must not be negative.',
      );
    }
    if (hitConfirmationFrames < 1) {
      throw ArgumentError.value(
        hitConfirmationFrames,
        'hitConfirmationFrames',
        'Must be at least one.',
      );
    }
  }

  /// Composite score gate applied after all component gates pass.
  static const double minimumMatchConfidence = 0.74;

  /// Minimum normalized-luminance spatial similarity.
  static const double minimumLuminanceSimilarity = 0.62;

  /// Minimum edge-layout similarity.
  static const double minimumEdgeSimilarity = 0.54;

  /// Minimum color-histogram intersection.
  static const double minimumColorSimilarity = 0.46;

  /// Minimum average-hash agreement.
  static const double minimumHashSimilarity = 0.58;

  /// Minimum compatibility between reference/candidate texture strengths.
  static const double minimumTextureCompatibility = 0.30;

  final ObjectScanRepository _repository;
  final Duration analysisInterval;
  final Duration missingGrace;
  final int hitConfirmationFrames;

  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, _TemporalMatchState> _temporalStates = {};

  Future<ObjectRecognitionLoadResult>? _loadFuture;
  ObjectRecognitionLoadResult? _loadResult;
  List<String>? _requestedIds;
  List<_RecognitionProfile> _profiles = const [];
  List<ObjectRecognitionMatch> _lastResults = const [];
  _ObjectMatcherWorker? _matcherWorker;

  bool _disposed = false;
  bool _analysisInFlight = false;
  int? _lastAnalysisCompletedMs;

  bool get isReady => !_disposed && _loadResult != null;

  /// Whether a caller should snapshot and localize the next camera frame.
  /// Checking this before [captureFrame] avoids copying a reusable camera
  /// buffer when the matcher is busy, cooling down, or has no usable profile.
  bool get isAnalysisDue {
    if (!isReady || _profiles.isEmpty || _analysisInFlight) {
      return false;
    }

    final lastCompleted = _lastAnalysisCompletedMs;
    return lastCompleted == null ||
        _clock.elapsedMilliseconds - lastCompleted >=
            analysisInterval.inMilliseconds;
  }

  List<RecognizableObject> get requiredObjects =>
      _loadResult?.objects ?? const [];

  List<String> get unavailableIds => _loadResult?.unavailableIds ?? const [];

  List<ObjectRecognitionMatch> get lastResults => _lastResults;

  /// Loads metadata once, filters it to [ids], and reads/decodes every saved
  /// sample only once. Repeating this with the same IDs returns the first load;
  /// a service instance intentionally cannot be repurposed for another set.
  Future<ObjectRecognitionLoadResult> loadRequiredObjects(List<String> ids) {
    _checkNotDisposed();

    final requested = _uniqueNonEmpty(ids);
    final existing = _loadFuture;

    if (existing != null) {
      if (!_sameIds(requested, _requestedIds!)) {
        throw StateError(
          'This ObjectRecognitionService already loaded a different set of '
          'required objects. Create a new service for a new session.',
        );
      }
      return existing;
    }

    _requestedIds = requested;
    return _loadFuture = _performLoad(requested);
  }

  Future<ObjectRecognitionLoadResult> _performLoad(
    List<String> requestedIds,
  ) async {
    if (requestedIds.isEmpty) {
      final result = ObjectRecognitionLoadResult(
        objects: const [],
        unavailableIds: const [],
      );
      if (_disposed) {
        throw StateError('ObjectRecognitionService has been disposed.');
      }
      _loadResult = result;
      return result;
    }

    // One repository read for the session, followed by an in-memory filter.
    final allScans = await _repository.loadAll();
    final scansById = {for (final scan in allScans) scan.id: scan};
    final encodedScans = <_EncodedScan>[];
    final initiallyUnavailable = <String>[];

    for (final id in requestedIds) {
      final scan = scansById[id];
      if (scan == null) {
        initiallyUnavailable.add(id);
        continue;
      }

      final paths = <String>{
        ...scan.samplePaths.where((path) => path.isNotEmpty),
        if (scan.thumbnailPath case final path? when path.isNotEmpty) path,
      };
      final samples = <Uint8List>[];

      for (final path in paths) {
        try {
          final bytes = await _repository.readImage(path);
          if (bytes != null && bytes.isNotEmpty) {
            samples.add(bytes);
          }
        } catch (_) {
          // One missing/corrupt angle must not make the remaining profile fail.
        }
      }

      if (samples.isEmpty) {
        initiallyUnavailable.add(id);
        continue;
      }

      encodedScans.add(
        _EncodedScan(id: scan.id, name: scan.name, samples: samples),
      );
    }

    final builtProfiles = encodedScans.isEmpty
        ? const <_RecognitionProfile>[]
        : await compute(
            _buildRecognitionProfiles,
            encodedScans,
            debugLabel: 'TaskProof object profile build',
          );

    if (_disposed) {
      throw StateError('ObjectRecognitionService has been disposed.');
    }

    final profilesById = {
      for (final profile in builtProfiles) profile.id: profile,
    };
    final unavailable = initiallyUnavailable.toSet();
    final orderedProfiles = <_RecognitionProfile>[];

    for (final id in requestedIds) {
      final profile = profilesById[id];
      if (profile == null || profile.descriptors.isEmpty) {
        unavailable.add(id);
      } else {
        orderedProfiles.add(profile);
      }
    }

    // Keep matching off the UI isolate without paying the cost of starting a
    // new isolate and serializing every saved descriptor for every frame.
    // Profiles are copied to this worker once and stay there for the session.
    final worker = orderedProfiles.isEmpty
        ? null
        : await _ObjectMatcherWorker.start(orderedProfiles);

    if (_disposed) {
      worker?.dispose();
      throw StateError('ObjectRecognitionService has been disposed.');
    }

    _profiles = List.unmodifiable(orderedProfiles);
    _matcherWorker = worker;
    _temporalStates
      ..clear()
      ..addEntries(
        _profiles.map((profile) => MapEntry(profile.id, _TemporalMatchState())),
      );

    final result = ObjectRecognitionLoadResult(
      objects: _profiles
          .map(
            (profile) => RecognizableObject(id: profile.id, name: profile.name),
          )
          .toList(growable: false),
      unavailableIds: requestedIds
          .where(unavailable.contains)
          .toList(growable: false),
    );

    _loadResult = result;
    _lastResults = _snapshotResults(_clock.elapsedMilliseconds);
    return result;
  }

  /// Analyzes a one-plane Android NV21 or iOS BGRA camera buffer.
  ///
  /// Rotation is derived using the same sensor/device convention used by the
  /// ML Kit camera converter. Front-camera frames are normalized for mirroring,
  /// and descriptor comparison is also mirror-tolerant. This method never
  /// calls `takePicture` and never treats raw plane bytes as JPEG data.
  Future<List<ObjectRecognitionMatch>> analyzeFrame(
    CameraImage image, {
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
    List<Rect> detectedBounds = const [],
  }) async {
    final snapshot = captureFrame(
      image,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );
    return analyzeSnapshot(snapshot, detectedBounds: detectedBounds);
  }

  /// Copies and validates one camera frame synchronously. Call this before an
  /// awaited native detector operation so both recognition stages see the
  /// exact same pixels.
  ObjectFrameSnapshot captureFrame(
    CameraImage image, {
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    _checkNotDisposed();
    if (!isReady) {
      throw StateError('Call loadRequiredObjects before captureFrame.');
    }

    if (image.planes.length != 1) {
      throw ArgumentError.value(
        image.planes.length,
        'image.planes.length',
        'Object recognition requires a one-plane NV21 or BGRA frame.',
      );
    }

    final format = switch (image.format.group) {
      ImageFormatGroup.nv21 => _RawFrameFormat.nv21,
      ImageFormatGroup.bgra8888 => _RawFrameFormat.bgra8888,
      _ => throw ArgumentError.value(
        image.format.group,
        'image.format.group',
        'Only NV21 and BGRA8888 camera frames are supported.',
      ),
    };
    final plane = image.planes.first;
    final rotation = _cameraRotation(
      format: format,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );

    _validateRawPlane(
      format: format,
      bytesLength: plane.bytes.length,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
    );

    return ObjectFrameSnapshot._(
      // Camera plugins may reuse [plane.bytes], so snapshot it synchronously.
      // TransferableTypedData then hands ownership to the matcher isolate
      // without another full-frame serialization copy.
      bytes: TransferableTypedData.fromList([plane.bytes]),
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
      format: format,
      rotationDegrees: rotation,
      mirrorHorizontally: camera.lensDirection == CameraLensDirection.front,
    );
  }

  /// Matches an immutable frame, optionally prioritizing bounding boxes from
  /// an on-device object localizer. Bounds use ML Kit's image coordinates.
  Future<List<ObjectRecognitionMatch>> analyzeSnapshot(
    ObjectFrameSnapshot snapshot, {
    List<Rect> detectedBounds = const [],
  }) async {
    _checkNotDisposed();
    if (!isReady) {
      throw StateError('Call loadRequiredObjects before analyzeSnapshot.');
    }
    if (_profiles.isEmpty) {
      return const [];
    }

    final nowMs = _clock.elapsedMilliseconds;
    final lastCompleted = _lastAnalysisCompletedMs;
    if (_analysisInFlight ||
        (lastCompleted != null &&
            nowMs - lastCompleted < analysisInterval.inMilliseconds)) {
      return _snapshotResults(nowMs);
    }

    final request = _FrameMatchRequest(
      bytes: snapshot._bytes,
      width: snapshot.width,
      height: snapshot.height,
      rowStride: snapshot.rowStride,
      format: snapshot._format,
      rotationDegrees: snapshot.rotationDegrees,
      mirrorHorizontally: snapshot.mirrorHorizontally,
      localizedRegions: _normalizeDetectedBounds(snapshot, detectedBounds),
    );

    _analysisInFlight = true;

    try {
      final worker = _matcherWorker;
      if (worker == null) {
        return const [];
      }
      final rawScores = await worker.match(request);
      if (_disposed) {
        return const [];
      }

      _applyRawScores(rawScores, _clock.elapsedMilliseconds);
      return _lastResults;
    } finally {
      _analysisInFlight = false;
      _lastAnalysisCompletedMs = _clock.elapsedMilliseconds;
    }
  }

  /// Clears hit/miss history, useful after pausing a session or restarting its
  /// camera. Objects must be confirmed again, so stale misses cannot warn.
  void resetTemporalState() {
    if (_disposed) {
      return;
    }
    for (final state in _temporalStates.values) {
      state.reset();
    }
    _lastAnalysisCompletedMs = null;
    _lastResults = _snapshotResults(_clock.elapsedMilliseconds);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _clock.stop();
    _matcherWorker?.dispose();
    _matcherWorker = null;
    _profiles = const [];
    _temporalStates.clear();
    _lastResults = const [];
    _loadResult = null;
    _loadFuture = null;
  }

  void _applyRawScores(List<_RawObjectScore> scores, int nowMs) {
    final scoresById = {for (final score in scores) score.id: score};

    for (final profile in _profiles) {
      final state = _temporalStates[profile.id]!;
      final raw = scoresById[profile.id];
      final passed = raw?.passed ?? false;
      state.latestRawConfidence = raw?.confidence ?? 0;

      if (passed) {
        state.consecutiveHits++;
        state.firstMissMs = null;
        state.lastConfirmedConfidence = math.max(
          state.lastConfirmedConfidence,
          raw!.confidence,
        );
        if (state.visible || state.consecutiveHits >= hitConfirmationFrames) {
          state.visible = true;
          state.lastConfirmedConfidence = raw.confidence;
        }
      } else {
        state.consecutiveHits = 0;
        if (state.visible) {
          state.firstMissMs ??= nowMs;
          if (nowMs - state.firstMissMs! >= missingGrace.inMilliseconds) {
            state.visible = false;
            state.firstMissMs = null;
            state.lastConfirmedConfidence = 0;
          }
        }
      }
    }

    _lastResults = _snapshotResults(nowMs);
  }

  List<ObjectRecognitionMatch> _snapshotResults(int nowMs) {
    return List.unmodifiable(
      _profiles.map((profile) {
        final state = _temporalStates[profile.id] ?? _TemporalMatchState();
        final missStarted = state.firstMissMs;
        var temporarilyMissing = state.visible && missStarted != null;

        if (temporarilyMissing &&
            nowMs - missStarted >= missingGrace.inMilliseconds) {
          state
            ..visible = false
            ..firstMissMs = null
            ..lastConfirmedConfidence = 0;
          temporarilyMissing = false;
        }

        double confidence;
        if (temporarilyMissing) {
          final graceMs = math.max(1, missingGrace.inMilliseconds);
          final progress = ((nowMs - missStarted!) / graceMs).clamp(0.0, 1.0);
          confidence = state.lastConfirmedConfidence * (1 - 0.35 * progress);
        } else if (state.visible) {
          confidence = state.lastConfirmedConfidence;
        } else {
          confidence = state.latestRawConfidence;
        }

        return ObjectRecognitionMatch(
          id: profile.id,
          name: profile.name,
          confidence: confidence.clamp(0.0, 1.0),
          isMatch: state.visible,
          isTemporarilyMissing: temporarilyMissing,
        );
      }),
    );
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('ObjectRecognitionService has been disposed.');
    }
  }
}

class _TemporalMatchState {
  bool visible = false;
  int consecutiveHits = 0;
  int? firstMissMs;
  double lastConfirmedConfidence = 0;
  double latestRawConfidence = 0;

  void reset() {
    visible = false;
    consecutiveHits = 0;
    firstMissMs = null;
    lastConfirmedConfidence = 0;
    latestRawConfidence = 0;
  }
}

enum _RawFrameFormat { nv21, bgra8888 }

class _EncodedScan {
  const _EncodedScan({
    required this.id,
    required this.name,
    required this.samples,
  });

  final String id;
  final String name;
  final List<Uint8List> samples;
}

class _RecognitionProfile {
  const _RecognitionProfile({
    required this.id,
    required this.name,
    required this.descriptors,
  });

  final String id;
  final String name;
  final List<_VisualDescriptor> descriptors;
}

class _FrameMatchRequest {
  const _FrameMatchRequest({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.format,
    required this.rotationDegrees,
    required this.mirrorHorizontally,
    required this.localizedRegions,
  });

  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int rowStride;
  final _RawFrameFormat format;
  final int rotationDegrees;
  final bool mirrorHorizontally;
  final List<_NormalizedRegion> localizedRegions;
}

class _ObjectMatcherWorker {
  _ObjectMatcherWorker._(this._commands);

  final SendPort _commands;
  bool _disposed = false;

  static Future<_ObjectMatcherWorker> start(
    List<_RecognitionProfile> profiles,
  ) async {
    final ready = ReceivePort();
    try {
      await Isolate.spawn(
        _objectMatcherWorkerMain,
        _ObjectMatcherWorkerStart(ready.sendPort, profiles),
        debugName: 'TaskProof object matcher',
      );
      return _ObjectMatcherWorker._(await ready.first as SendPort);
    } finally {
      ready.close();
    }
  }

  Future<List<_RawObjectScore>> match(_FrameMatchRequest request) async {
    if (_disposed) {
      throw StateError('Object matcher worker has been disposed.');
    }

    final responsePort = ReceivePort();
    try {
      _commands.send(_ObjectMatcherWorkerMatch(request, responsePort.sendPort));
      final response = await responsePort.first;
      if (response is _ObjectMatcherWorkerResult) {
        return response.scores;
      }
      if (response is _ObjectMatcherWorkerError) {
        throw StateError(response.message);
      }
      throw StateError('Object matcher returned an invalid response.');
    } finally {
      responsePort.close();
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _commands.send(const _ObjectMatcherWorkerShutdown());
  }
}

class _ObjectMatcherWorkerStart {
  const _ObjectMatcherWorkerStart(this.readyPort, this.profiles);

  final SendPort readyPort;
  final List<_RecognitionProfile> profiles;
}

class _ObjectMatcherWorkerMatch {
  const _ObjectMatcherWorkerMatch(this.request, this.responsePort);

  final _FrameMatchRequest request;
  final SendPort responsePort;
}

class _ObjectMatcherWorkerResult {
  const _ObjectMatcherWorkerResult(this.scores);

  final List<_RawObjectScore> scores;
}

class _ObjectMatcherWorkerError {
  const _ObjectMatcherWorkerError(this.message);

  final String message;
}

class _ObjectMatcherWorkerShutdown {
  const _ObjectMatcherWorkerShutdown();
}

void _objectMatcherWorkerMain(_ObjectMatcherWorkerStart start) async {
  final commands = ReceivePort();
  start.readyPort.send(commands.sendPort);

  await for (final command in commands) {
    if (command is _ObjectMatcherWorkerShutdown) {
      commands.close();
      break;
    }
    if (command is! _ObjectMatcherWorkerMatch) {
      continue;
    }

    try {
      command.responsePort.send(
        _ObjectMatcherWorkerResult(
          _matchRawCameraFrame(command.request, start.profiles),
        ),
      );
    } catch (error) {
      command.responsePort.send(_ObjectMatcherWorkerError(error.toString()));
    }
  }
}

class _RawObjectScore {
  const _RawObjectScore({
    required this.id,
    required this.confidence,
    required this.passed,
  });

  final String id;
  final double confidence;
  final bool passed;
}

class _VisualDescriptor {
  const _VisualDescriptor({
    required this.luminancePattern,
    required this.edgePattern,
    required this.averageHash,
    required this.colorHistogram,
    required this.luminanceStd,
    required this.edgeStrength,
    required this.colorfulness,
  });

  final List<double> luminancePattern;
  final List<double> edgePattern;
  final List<int> averageHash;
  final List<double> colorHistogram;
  final double luminanceStd;
  final double edgeStrength;
  final double colorfulness;

  bool get isUsable => luminanceStd >= 0.012 || edgeStrength >= 0.018;
}

class _RgbRaster {
  const _RgbRaster({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;
}

class _Region {
  const _Region(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

class _NormalizedRegion {
  const _NormalizedRegion(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

const int _descriptorGrid = 10;
const int _profileRasterMaximumDimension = 192;
const int _frameRasterMaximumDimension = 176;

List<_RecognitionProfile> _buildRecognitionProfiles(List<_EncodedScan> scans) {
  final profiles = <_RecognitionProfile>[];

  for (final scan in scans) {
    final descriptors = <_VisualDescriptor>[];

    for (final bytes in scan.samples) {
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded == null || decoded.width < 8 || decoded.height < 8) {
          continue;
        }

        final oriented = img.bakeOrientation(decoded);
        final resized = _resizeImage(oriented, _profileRasterMaximumDimension);
        final raster = _rasterFromImage(resized);
        final shortest = math.min(raster.width, raster.height).toDouble();
        final regions = <_Region>[
          _Region(0, 0, raster.width.toDouble(), raster.height.toDouble()),
          for (final fraction in const [0.90, 0.70])
            _Region(
              (raster.width - shortest * fraction) / 2,
              (raster.height - shortest * fraction) / 2,
              shortest * fraction,
              shortest * fraction,
            ),
        ];

        for (final region in regions) {
          final descriptor = _describeRegion(raster, region);
          if (descriptor.isUsable) {
            descriptors.add(descriptor);
          }
        }
      } catch (_) {
        // Decode failure for one angle does not invalidate other saved views.
      }
    }

    if (descriptors.isNotEmpty) {
      profiles.add(
        _RecognitionProfile(
          id: scan.id,
          name: scan.name,
          descriptors: List.unmodifiable(descriptors),
        ),
      );
    }
  }

  return profiles;
}

List<_RawObjectScore> _matchRawCameraFrame(
  _FrameMatchRequest request,
  List<_RecognitionProfile> profiles,
) {
  final raster = _rasterFromRawFrame(request);
  final localizedRegions = request.localizedRegions;

  if (localizedRegions.isEmpty) {
    // ML Kit did not provide an object box.
    //
    // Search multiple smaller candidate regions instead of
    // comparing the saved object against the ENTIRE scene.
    //
    // This is especially important for small objects such as
    // computer mice, phones, pencils, remotes, etc.
    final regions = _fallbackCandidateRegions(
      raster.width,
      raster.height,
      localizationAvailable: false,
    );

    return _scoreProfiles(profiles, _describeRegions(raster, regions));
  }

  // Try the native detector's tight boxes first. In the usual case where all
  // required profiles are found, this avoids describing and comparing dozens
  // of sliding windows. If even one profile is not found, run the complete
  // legacy fallback and merge its scores, preserving difficult detections.
  final localizedScores = _scoreProfiles(
    profiles,
    _describeRegions(
      raster,
      _localizedCandidateRegions(raster.width, raster.height, localizedRegions),
    ),
  );

  if (localizedScores.every((score) => score.passed)) {
    return localizedScores;
  }

  final fallbackScores = _scoreProfiles(
    profiles,
    _describeRegions(
      raster,
      _fallbackCandidateRegions(
        raster.width,
        raster.height,
        localizationAvailable: true,
      ),
    ),
  );

  return _mergeRawScores(localizedScores, fallbackScores);
}

List<_VisualDescriptor> _describeRegions(
  _RgbRaster raster,
  List<_Region> regions,
) {
  return regions
      .map((region) => _describeRegion(raster, region))
      .where((descriptor) => descriptor.isUsable)
      .toList(growable: false);
}

List<_RawObjectScore> _scoreProfiles(
  List<_RecognitionProfile> profiles,
  List<_VisualDescriptor> candidates,
) {
  final results = <_RawObjectScore>[];

  for (final profile in profiles) {
    var bestConfidence = 0.0;
    var bestPassingConfidence = 0.0;

    for (final candidate in candidates) {
      for (final reference in profile.descriptors) {
        final comparisons = _compareDescriptorOrientations(
          reference,
          candidate,
        );
        final normal = comparisons.normal;
        final mirrored = comparisons.mirrored;
        final comparison = normal.confidence >= mirrored.confidence
            ? normal
            : mirrored;

        if (comparison.confidence > bestConfidence) {
          bestConfidence = comparison.confidence;
        }
        if (normal.passed && normal.confidence > bestPassingConfidence) {
          bestPassingConfidence = normal.confidence;
        }
        if (mirrored.passed && mirrored.confidence > bestPassingConfidence) {
          bestPassingConfidence = mirrored.confidence;
        }
      }
    }

    results.add(
      _RawObjectScore(
        id: profile.id,
        confidence:
            (bestPassingConfidence > 0 ? bestPassingConfidence : bestConfidence)
                .clamp(0.0, 1.0),
        passed: bestPassingConfidence > 0,
      ),
    );
  }

  return results;
}

List<_RawObjectScore> _mergeRawScores(
  List<_RawObjectScore> localized,
  List<_RawObjectScore> fallback,
) {
  final results = <_RawObjectScore>[];

  for (var index = 0; index < localized.length; index++) {
    final first = localized[index];
    final second = fallback[index];
    final passed = first.passed || second.passed;
    final confidence = first.passed && second.passed
        ? math.max(first.confidence, second.confidence)
        : first.passed
        ? first.confidence
        : second.passed
        ? second.confidence
        : math.max(first.confidence, second.confidence);

    results.add(
      _RawObjectScore(id: first.id, confidence: confidence, passed: passed),
    );
  }

  return results;
}

_DescriptorOrientationComparisons _compareDescriptorOrientations(
  _VisualDescriptor reference,
  _VisualDescriptor candidate,
) {
  var referenceLuminanceMagnitude = 0.0;
  var candidateLuminanceMagnitude = 0.0;
  var mirroredCandidateLuminanceMagnitude = 0.0;
  var normalLuminanceDot = 0.0;
  var mirroredLuminanceDot = 0.0;
  var referenceEdgeMagnitude = 0.0;
  var candidateEdgeMagnitude = 0.0;
  var mirroredCandidateEdgeMagnitude = 0.0;
  var normalEdgeDot = 0.0;
  var mirroredEdgeDot = 0.0;
  var normalHashMatches = 0;
  var mirroredHashMatches = 0;

  for (var y = 0; y < _descriptorGrid; y++) {
    for (var x = 0; x < _descriptorGrid; x++) {
      final referenceIndex = y * _descriptorGrid + x;
      final mirroredIndex = y * _descriptorGrid + (_descriptorGrid - 1 - x);

      final referenceLuminance = reference.luminancePattern[referenceIndex];
      final candidateLuminance = candidate.luminancePattern[referenceIndex];
      final mirroredCandidateLuminance =
          candidate.luminancePattern[mirroredIndex];
      normalLuminanceDot += referenceLuminance * candidateLuminance;
      mirroredLuminanceDot += referenceLuminance * mirroredCandidateLuminance;
      referenceLuminanceMagnitude += referenceLuminance * referenceLuminance;
      candidateLuminanceMagnitude += candidateLuminance * candidateLuminance;
      mirroredCandidateLuminanceMagnitude +=
          mirroredCandidateLuminance * mirroredCandidateLuminance;

      final referenceEdge = reference.edgePattern[referenceIndex];
      final candidateEdge = candidate.edgePattern[referenceIndex];
      final mirroredCandidateEdge = candidate.edgePattern[mirroredIndex];
      normalEdgeDot += referenceEdge * candidateEdge;
      mirroredEdgeDot += referenceEdge * mirroredCandidateEdge;
      referenceEdgeMagnitude += referenceEdge * referenceEdge;
      candidateEdgeMagnitude += candidateEdge * candidateEdge;
      mirroredCandidateEdgeMagnitude +=
          mirroredCandidateEdge * mirroredCandidateEdge;

      if (reference.averageHash[referenceIndex] ==
          candidate.averageHash[referenceIndex]) {
        normalHashMatches++;
      }
      if (reference.averageHash[referenceIndex] ==
          candidate.averageHash[mirroredIndex]) {
        mirroredHashMatches++;
      }
    }
  }

  final normalLuminance = _cosineSimilarityFromTotals(
    normalLuminanceDot,
    referenceLuminanceMagnitude,
    candidateLuminanceMagnitude,
  );
  final mirroredLuminance = _cosineSimilarityFromTotals(
    mirroredLuminanceDot,
    referenceLuminanceMagnitude,
    mirroredCandidateLuminanceMagnitude,
  );
  final normalEdge = _cosineSimilarityFromTotals(
    normalEdgeDot,
    referenceEdgeMagnitude,
    candidateEdgeMagnitude,
  );
  final mirroredEdge = _cosineSimilarityFromTotals(
    mirroredEdgeDot,
    referenceEdgeMagnitude,
    mirroredCandidateEdgeMagnitude,
  );
  const descriptorCellCount = _descriptorGrid * _descriptorGrid;
  final normalHash = normalHashMatches / descriptorCellCount;
  final mirroredHash = mirroredHashMatches / descriptorCellCount;
  final color = _colorSimilarity(reference, candidate);
  final texture =
      (_strengthCompatibility(reference.luminanceStd, candidate.luminanceStd) +
          _strengthCompatibility(
            reference.edgeStrength,
            candidate.edgeStrength,
          )) /
      2;

  return _DescriptorOrientationComparisons(
    normal: _buildDescriptorComparison(
      luminance: normalLuminance,
      edge: normalEdge,
      hash: normalHash,
      color: color,
      texture: texture,
    ),
    mirrored: _buildDescriptorComparison(
      luminance: mirroredLuminance,
      edge: mirroredEdge,
      hash: mirroredHash,
      color: color,
      texture: texture,
    ),
  );
}

_DescriptorComparison _buildDescriptorComparison({
  required double luminance,
  required double edge,
  required double hash,
  required double color,
  required double texture,
}) {
  final confidence =
      luminance * 0.32 +
      edge * 0.25 +
      color * 0.22 +
      hash * 0.16 +
      texture * 0.05;
  final passed =
      confidence >= ObjectRecognitionService.minimumMatchConfidence &&
      luminance >= ObjectRecognitionService.minimumLuminanceSimilarity &&
      edge >= ObjectRecognitionService.minimumEdgeSimilarity &&
      color >= ObjectRecognitionService.minimumColorSimilarity &&
      hash >= ObjectRecognitionService.minimumHashSimilarity &&
      texture >= ObjectRecognitionService.minimumTextureCompatibility;

  return _DescriptorComparison(confidence: confidence, passed: passed);
}

double _cosineSimilarityFromTotals(
  double dot,
  double referenceMagnitude,
  double candidateMagnitude,
) {
  if (referenceMagnitude < 0.000001 || candidateMagnitude < 0.000001) {
    return referenceMagnitude < 0.000001 && candidateMagnitude < 0.000001
        ? 1
        : 0;
  }
  final cosine = dot / math.sqrt(referenceMagnitude * candidateMagnitude);
  return ((cosine.clamp(-1.0, 1.0) + 1) / 2).clamp(0.0, 1.0);
}

class _DescriptorOrientationComparisons {
  const _DescriptorOrientationComparisons({
    required this.normal,
    required this.mirrored,
  });

  final _DescriptorComparison normal;
  final _DescriptorComparison mirrored;
}

class _DescriptorComparison {
  const _DescriptorComparison({required this.confidence, required this.passed});

  final double confidence;
  final bool passed;
}

_RgbRaster _rasterFromRawFrame(_FrameMatchRequest request) {
  final sourceBytes = request.bytes.materialize().asUint8List();
  final swapsAxes =
      request.rotationDegrees == 90 || request.rotationDegrees == 270;
  final orientedWidth = swapsAxes ? request.height : request.width;
  final orientedHeight = swapsAxes ? request.width : request.height;
  final scale = math.min(
    1.0,
    _frameRasterMaximumDimension / math.max(orientedWidth, orientedHeight),
  );
  final width = math.max(1, (orientedWidth * scale).round());
  final height = math.max(1, (orientedHeight * scale).round());
  final rgb = Uint8List(width * height * 3);

  final yPlaneLength = request.rowStride * request.height;
  final chromaRows = (request.height + 1) ~/ 2;
  final uvRowStride = request.format == _RawFrameFormat.nv21
      ? (sourceBytes.length - yPlaneLength) ~/ chromaRows
      : 0;

  for (var y = 0; y < height; y++) {
    var orientedY = ((y + 0.5) * orientedHeight / height).floor();
    orientedY = orientedY.clamp(0, orientedHeight - 1);

    for (var x = 0; x < width; x++) {
      var orientedX = ((x + 0.5) * orientedWidth / width).floor();
      orientedX = orientedX.clamp(0, orientedWidth - 1);
      if (request.mirrorHorizontally) {
        orientedX = orientedWidth - 1 - orientedX;
      }

      final (sourceX, sourceY) = _sourceCoordinate(
        orientedX,
        orientedY,
        request.width,
        request.height,
        request.rotationDegrees,
      );
      final outputIndex = (y * width + x) * 3;

      if (request.format == _RawFrameFormat.bgra8888) {
        final inputIndex = sourceY * request.rowStride + sourceX * 4;
        rgb[outputIndex] = sourceBytes[inputIndex + 2];
        rgb[outputIndex + 1] = sourceBytes[inputIndex + 1];
        rgb[outputIndex + 2] = sourceBytes[inputIndex];
      } else {
        final yValue = sourceBytes[sourceY * request.rowStride + sourceX];
        final uvIndex =
            yPlaneLength + (sourceY ~/ 2) * uvRowStride + (sourceX ~/ 2) * 2;
        final v = sourceBytes[uvIndex];
        final u = sourceBytes[uvIndex + 1];
        final (red, green, blue) = _nv21ToRgb(yValue, u, v);
        rgb[outputIndex] = red;
        rgb[outputIndex + 1] = green;
        rgb[outputIndex + 2] = blue;
      }
    }
  }

  return _RgbRaster(width: width, height: height, bytes: rgb);
}

(int, int) _sourceCoordinate(
  int orientedX,
  int orientedY,
  int sourceWidth,
  int sourceHeight,
  int rotationDegrees,
) {
  return switch (rotationDegrees) {
    0 => (orientedX, orientedY),
    90 => (orientedY, sourceHeight - 1 - orientedX),
    180 => (sourceWidth - 1 - orientedX, sourceHeight - 1 - orientedY),
    270 => (sourceWidth - 1 - orientedY, orientedX),
    _ => throw StateError('Unsupported frame rotation: $rotationDegrees'),
  };
}

(int, int, int) _nv21ToRgb(int y, int u, int v) {
  final c = math.max(0, y - 16);
  final d = u - 128;
  final e = v - 128;
  final red = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
  final green = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
  final blue = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
  return (red, green, blue);
}

img.Image _resizeImage(img.Image source, int maximumDimension) {
  if (math.max(source.width, source.height) <= maximumDimension) {
    return source;
  }
  if (source.width >= source.height) {
    return img.copyResize(
      source,
      width: maximumDimension,
      interpolation: img.Interpolation.average,
    );
  }
  return img.copyResize(
    source,
    height: maximumDimension,
    interpolation: img.Interpolation.average,
  );
}

_RgbRaster _rasterFromImage(img.Image image) {
  final bytes = Uint8List(image.width * image.height * 3);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final index = (y * image.width + x) * 3;
      bytes[index] = (pixel.rNormalized * 255).round().clamp(0, 255);
      bytes[index + 1] = (pixel.gNormalized * 255).round().clamp(0, 255);
      bytes[index + 2] = (pixel.bNormalized * 255).round().clamp(0, 255);
    }
  }
  return _RgbRaster(width: image.width, height: image.height, bytes: bytes);
}

List<_Region> _localizedCandidateRegions(
  int width,
  int height,
  List<_NormalizedRegion> localizedRegions,
) {
  final regions = <_Region>[_Region(0, 0, width.toDouble(), height.toDouble())];

  // Native ML Kit localization supplies tight object-shaped regions. Compare
  // each box with a little surrounding context because saved views can contain
  // shadows, handles, and a narrow background border.
  for (final normalized in localizedRegions.take(5)) {
    final base = _Region(
      normalized.x * width,
      normalized.y * height,
      normalized.width * width,
      normalized.height * height,
    );
    for (final padding in const [0.0, 0.10, 0.22]) {
      regions.add(_expandRegion(base, padding, width, height));
    }

    final squareSize = math.max(base.width, base.height);
    final square = _Region(
      base.x + (base.width - squareSize) / 2,
      base.y + (base.height - squareSize) / 2,
      squareSize,
      squareSize,
    );
    regions.add(_expandRegion(square, 0.12, width, height));
  }

  return regions;
}

List<_Region> _fallbackCandidateRegions(
  int width,
  int height, {
  required bool localizationAvailable,
}) {
  final regions = <_Region>[];
  final shortest = math.min(width, height).toDouble();

  // Keep a multiscale fallback because a generic detector can occasionally
  // miss a small or unusual object. The old matcher started at 38% of the
  // frame, which made hand-held objects effectively invisible.
  final squareScales = !localizationAvailable
      ? const [0.16, 0.24, 0.36, 0.52, 0.72, 0.90]
      : const [0.20, 0.34, 0.52, 0.72];
  for (final scale in squareScales) {
    final size = shortest * scale;
    _appendSlidingRegions(regions, width, height, size, size);
  }

  // Frame-aspect windows retain long objects (for example a broom) and match
  // the uncropped descriptor saved from each scan angle.
  for (final scale in const [0.34, 0.52, 0.72]) {
    _appendSlidingRegions(
      regions,
      width,
      height,
      width * scale,
      height * scale,
    );
  }

  return regions;
}

_Region _expandRegion(
  _Region region,
  double fraction,
  int imageWidth,
  int imageHeight,
) {
  final horizontal = region.width * fraction;
  final vertical = region.height * fraction;
  final left = (region.x - horizontal).clamp(0.0, imageWidth.toDouble());
  final top = (region.y - vertical).clamp(0.0, imageHeight.toDouble());
  final right = (region.x + region.width + horizontal).clamp(
    0.0,
    imageWidth.toDouble(),
  );
  final bottom = (region.y + region.height + vertical).clamp(
    0.0,
    imageHeight.toDouble(),
  );
  return _Region(left, top, right - left, bottom - top);
}

void _appendSlidingRegions(
  List<_Region> output,
  int imageWidth,
  int imageHeight,
  double regionWidth,
  double regionHeight,
) {
  final xCount = _regionPositionCount(imageWidth.toDouble(), regionWidth);
  final yCount = _regionPositionCount(imageHeight.toDouble(), regionHeight);

  for (var yi = 0; yi < yCount; yi++) {
    final y = yCount == 1
        ? (imageHeight - regionHeight) / 2
        : yi * (imageHeight - regionHeight) / (yCount - 1);
    for (var xi = 0; xi < xCount; xi++) {
      final x = xCount == 1
          ? (imageWidth - regionWidth) / 2
          : xi * (imageWidth - regionWidth) / (xCount - 1);
      output.add(_Region(x, y, regionWidth, regionHeight));
    }
  }
}

int _regionPositionCount(double extent, double regionExtent) {
  if (regionExtent >= extent * 0.94) {
    return 1;
  }
  final count = ((extent - regionExtent) / (regionExtent * 0.62)).ceil() + 1;
  return count.clamp(2, 4);
}

_VisualDescriptor _describeRegion(_RgbRaster raster, _Region region) {
  const cellCount = _descriptorGrid * _descriptorGrid;
  final red = List<double>.filled(cellCount, 0);
  final green = List<double>.filled(cellCount, 0);
  final blue = List<double>.filled(cellCount, 0);
  final luminance = List<double>.filled(cellCount, 0);

  for (var gridY = 0; gridY < _descriptorGrid; gridY++) {
    for (var gridX = 0; gridX < _descriptorGrid; gridX++) {
      var redTotal = 0.0;
      var greenTotal = 0.0;
      var blueTotal = 0.0;

      // Four samples per cell reduce aliasing without constructing crop images.
      for (final yOffset in const [0.3, 0.7]) {
        final sampleY =
            (region.y + (gridY + yOffset) * region.height / _descriptorGrid)
                .floor()
                .clamp(0, raster.height - 1);
        for (final xOffset in const [0.3, 0.7]) {
          final sampleX =
              (region.x + (gridX + xOffset) * region.width / _descriptorGrid)
                  .floor()
                  .clamp(0, raster.width - 1);
          final index = (sampleY * raster.width + sampleX) * 3;
          redTotal += raster.bytes[index] / 255;
          greenTotal += raster.bytes[index + 1] / 255;
          blueTotal += raster.bytes[index + 2] / 255;
        }
      }

      final index = gridY * _descriptorGrid + gridX;
      red[index] = redTotal / 4;
      green[index] = greenTotal / 4;
      blue[index] = blueTotal / 4;
      luminance[index] =
          red[index] * 0.299 + green[index] * 0.587 + blue[index] * 0.114;
    }
  }

  final luminanceStats = _normalizeValues(luminance);
  final edgeMagnitudes = List<double>.filled(cellCount, 0);
  var edgeTotal = 0.0;

  for (var y = 0; y < _descriptorGrid; y++) {
    final up = math.max(0, y - 1);
    final down = math.min(_descriptorGrid - 1, y + 1);
    for (var x = 0; x < _descriptorGrid; x++) {
      final left = math.max(0, x - 1);
      final right = math.min(_descriptorGrid - 1, x + 1);
      final dx =
          luminance[y * _descriptorGrid + right] -
          luminance[y * _descriptorGrid + left];
      final dy =
          luminance[down * _descriptorGrid + x] -
          luminance[up * _descriptorGrid + x];
      final magnitude = math.sqrt(dx * dx + dy * dy) / math.sqrt2;
      final index = y * _descriptorGrid + x;
      edgeMagnitudes[index] = magnitude;
      edgeTotal += magnitude;
    }
  }

  final edgeStats = _normalizeValues(edgeMagnitudes);
  final histogram = List<double>.filled(16, 0);
  var hueWeight = 0.0;
  var saturationTotal = 0.0;

  for (var i = 0; i < cellCount; i++) {
    final r = red[i];
    final g = green[i];
    final b = blue[i];
    final maximum = math.max(r, math.max(g, b));
    final minimum = math.min(r, math.min(g, b));
    final delta = maximum - minimum;
    final saturation = maximum <= 0.0001 ? 0.0 : delta / maximum;
    saturationTotal += saturation;

    if (saturation >= 0.08 && delta > 0.0001) {
      double hue;
      if (maximum == r) {
        hue = ((g - b) / delta) % 6;
      } else if (maximum == g) {
        hue = (b - r) / delta + 2;
      } else {
        hue = (r - g) / delta + 4;
      }
      hue = (hue * 60) % 360;
      if (hue < 0) {
        hue += 360;
      }
      final hueBin = (hue / 45).floor().clamp(0, 7);
      histogram[hueBin] += saturation;
      hueWeight += saturation;
    }

    final saturationBin = (saturation * 4).floor().clamp(0, 3);
    histogram[8 + saturationBin]++;
    final luminanceBin = (luminance[i] * 4).floor().clamp(0, 3);
    histogram[12 + luminanceBin]++;
  }

  if (hueWeight > 0) {
    for (var i = 0; i < 8; i++) {
      histogram[i] /= hueWeight;
    }
  }
  for (var i = 8; i < 16; i++) {
    histogram[i] /= cellCount;
  }

  return _VisualDescriptor(
    luminancePattern: luminanceStats.normalized,
    edgePattern: edgeStats.normalized,
    averageHash: luminance
        .map((value) => value >= luminanceStats.mean ? 1 : 0)
        .toList(growable: false),
    colorHistogram: histogram,
    luminanceStd: luminanceStats.standardDeviation,
    edgeStrength: edgeTotal / cellCount,
    colorfulness: saturationTotal / cellCount,
  );
}

class _NormalizedValues {
  const _NormalizedValues({
    required this.normalized,
    required this.mean,
    required this.standardDeviation,
  });

  final List<double> normalized;
  final double mean;
  final double standardDeviation;
}

_NormalizedValues _normalizeValues(List<double> values) {
  final mean = values.reduce((first, second) => first + second) / values.length;
  var variance = 0.0;
  for (final value in values) {
    final difference = value - mean;
    variance += difference * difference;
  }
  final standardDeviation = math.sqrt(variance / values.length);
  final denominator = math.max(standardDeviation, 0.0001);
  return _NormalizedValues(
    normalized: values
        .map((value) => ((value - mean) / denominator).clamp(-3.0, 3.0))
        .toList(growable: false),
    mean: mean,
    standardDeviation: standardDeviation,
  );
}

double _colorSimilarity(
  _VisualDescriptor reference,
  _VisualDescriptor candidate,
) {
  double intersection(int start, int end) {
    var total = 0.0;
    for (var i = start; i < end; i++) {
      total += math.min(
        reference.colorHistogram[i],
        candidate.colorHistogram[i],
      );
    }
    return total.clamp(0.0, 1.0);
  }

  final hue = reference.colorfulness < 0.08 && candidate.colorfulness < 0.08
      ? 1.0
      : reference.colorfulness < 0.08 || candidate.colorfulness < 0.08
      ? 0.25
      : intersection(0, 8);
  final saturation = intersection(8, 12);
  final luminance = intersection(12, 16);
  return (hue * 0.55 + saturation * 0.30 + luminance * 0.15).clamp(0.0, 1.0);
}

double _strengthCompatibility(double first, double second) {
  final strongest = math.max(first, second);
  if (strongest < 0.008) {
    return 1;
  }
  return (math.min(first, second) / strongest).clamp(0.0, 1.0);
}

int _cameraRotation({
  required _RawFrameFormat format,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  final sensorOrientation = camera.sensorOrientation;
  int rotation;

  if (format == _RawFrameFormat.bgra8888) {
    // Camera/ML Kit convention on iOS: sensor orientation describes BGRA data.
    rotation = sensorOrientation;
  } else {
    final deviceDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    rotation = camera.lensDirection == CameraLensDirection.front
        ? sensorOrientation + deviceDegrees
        : sensorOrientation - deviceDegrees;
  }

  rotation = ((rotation % 360) + 360) % 360;
  if (rotation % 90 != 0) {
    throw ArgumentError.value(
      sensorOrientation,
      'camera.sensorOrientation',
      'Expected an orthogonal sensor orientation.',
    );
  }
  return rotation;
}

void _validateRawPlane({
  required _RawFrameFormat format,
  required int bytesLength,
  required int width,
  required int height,
  required int rowStride,
}) {
  if (width <= 0 || height <= 0 || rowStride <= 0) {
    throw ArgumentError(
      'Camera frame dimensions and row stride must be positive.',
    );
  }

  if (format == _RawFrameFormat.bgra8888) {
    if (rowStride < width * 4 || bytesLength < rowStride * height) {
      throw ArgumentError(
        'The BGRA plane is shorter than its declared layout.',
      );
    }
    return;
  }

  final yPlaneLength = rowStride * height;
  final chromaRows = (height + 1) ~/ 2;
  final chromaLength = bytesLength - yPlaneLength;
  if (rowStride < width ||
      chromaLength < width * chromaRows ||
      chromaLength ~/ chromaRows < width) {
    throw ArgumentError('The NV21 plane is shorter than its declared layout.');
  }
}

List<_NormalizedRegion> _normalizeDetectedBounds(
  ObjectFrameSnapshot snapshot,
  List<Rect> bounds,
) {
  if (bounds.isEmpty) {
    return const [];
  }

  final swapsAxes =
      snapshot.rotationDegrees == 90 || snapshot.rotationDegrees == 270;
  final orientedWidth = (swapsAxes ? snapshot.height : snapshot.width)
      .toDouble();
  final orientedHeight = (swapsAxes ? snapshot.width : snapshot.height)
      .toDouble();
  final regions = <_NormalizedRegion>[];

  void add(Rect rect, double coordinateWidth, double coordinateHeight) {
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.right.isFinite ||
        !rect.bottom.isFinite ||
        coordinateWidth <= 0 ||
        coordinateHeight <= 0) {
      return;
    }

    final left = (rect.left / coordinateWidth).clamp(0.0, 1.0);
    final top = (rect.top / coordinateHeight).clamp(0.0, 1.0);
    final right = (rect.right / coordinateWidth).clamp(0.0, 1.0);
    final bottom = (rect.bottom / coordinateHeight).clamp(0.0, 1.0);
    final width = right - left;
    final height = bottom - top;

    if (width < 0.025 || height < 0.025 || width * height < 0.002) {
      return;
    }

    final normalizedLeft = snapshot.mirrorHorizontally ? 1.0 - right : left;
    final candidate = _NormalizedRegion(normalizedLeft, top, width, height);

    final duplicate = regions.any(
      (existing) =>
          (existing.x - candidate.x).abs() < 0.025 &&
          (existing.y - candidate.y).abs() < 0.025 &&
          (existing.width - candidate.width).abs() < 0.025 &&
          (existing.height - candidate.height).abs() < 0.025,
    );
    if (!duplicate) {
      regions.add(candidate);
    }
  }

  for (final rect in bounds) {
    // ML Kit normally reports coordinates after applying input rotation.
    add(rect, orientedWidth, orientedHeight);

    // Some native camera/plugin combinations report source-buffer
    // coordinates instead. Including the transformed interpretation makes the
    // localizer robust across both Android and iOS camera conventions.
    if (snapshot.rotationDegrees != 0 &&
        rect.right <= snapshot.width * 1.05 &&
        rect.bottom <= snapshot.height * 1.05) {
      add(
        _rotateSourceRect(
          rect,
          snapshot.width.toDouble(),
          snapshot.height.toDouble(),
          snapshot.rotationDegrees,
        ),
        orientedWidth,
        orientedHeight,
      );
    }
  }

  return List.unmodifiable(regions);
}

Rect _rotateSourceRect(
  Rect rect,
  double sourceWidth,
  double sourceHeight,
  int rotationDegrees,
) {
  return switch (rotationDegrees) {
    0 => rect,
    90 => Rect.fromLTRB(
      sourceHeight - rect.bottom,
      rect.left,
      sourceHeight - rect.top,
      rect.right,
    ),
    180 => Rect.fromLTRB(
      sourceWidth - rect.right,
      sourceHeight - rect.bottom,
      sourceWidth - rect.left,
      sourceHeight - rect.top,
    ),
    270 => Rect.fromLTRB(
      rect.top,
      sourceWidth - rect.right,
      rect.bottom,
      sourceWidth - rect.left,
    ),
    _ => throw StateError('Unsupported frame rotation: $rotationDegrees'),
  };
}

List<String> _uniqueNonEmpty(List<String> ids) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in ids) {
    final id = value.trim();
    if (id.isNotEmpty && seen.add(id)) {
      result.add(id);
    }
  }
  return List.unmodifiable(result);
}

bool _sameIds(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) {
      return false;
    }
  }
  return true;
}

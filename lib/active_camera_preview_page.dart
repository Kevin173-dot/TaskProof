import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'new_task_page.dart' show MlKitCameraFrame, MlKitCameraImageConverter;

/// A camera-only setup screen for Active tasks.
///
/// This page intentionally has no task or timer dependency. It only helps the
/// user position the front-facing camera before starting a session.
class ActiveCameraPreviewPage extends StatefulWidget {
  const ActiveCameraPreviewPage({super.key, required this.isDarkMode});

  final bool isDarkMode;

  @override
  State<ActiveCameraPreviewPage> createState() =>
      _ActiveCameraPreviewPageState();
}

class _ActiveCameraPreviewPageState extends State<ActiveCameraPreviewPage>
    with WidgetsBindingObserver {
  static const _analysisInterval = Duration(milliseconds: 165);
  static const _landmarkLikelihood = 0.45;

  static const _usefulBodyLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  };

  static const _lowerBodyLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  };

  CameraController? _controller;
  PoseDetector? _poseDetector;

  Future<void>? _cameraInitialization;
  Future<void>? _cameraShutdown;
  Future<void>? _activeAnalysis;

  bool _wantCamera = true;
  bool _acceptFrames = false;
  bool _processing = false;
  bool _disposing = false;
  bool _lifecycleSuspended = false;
  bool _exitRequested = false;
  bool _allowPop = false;
  int _cameraEpoch = 0;

  Future<void>? _exitPreparation;

  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);

  _PreviewFeedback _feedback = const _PreviewFeedback.preparing();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_lifecycleSuspended || _disposing) {
        return;
      }

      _lifecycleSuspended = false;
      _wantCamera = true;
      _cameraEpoch++;
      _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);
      _setFeedback(const _PreviewFeedback.preparing());
      unawaited(_startCamera());
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_lifecycleSuspended || _disposing) {
        return;
      }

      _lifecycleSuspended = true;
      _wantCamera = false;
      _acceptFrames = false;
      _cameraEpoch++;
      unawaited(_stopCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposing = true;
    _wantCamera = false;
    _acceptFrames = false;
    _cameraEpoch++;
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _prepareToExit() async {
    final existing = _exitPreparation;
    if (existing != null) {
      await existing;
      return;
    }

    _wantCamera = false;
    _acceptFrames = false;
    _cameraEpoch++;

    final preparation = _disposeResources();
    _exitPreparation = preparation;

    try {
      await preparation;
    } finally {
      if (identical(_exitPreparation, preparation)) {
        _exitPreparation = null;
      }
    }
  }

  Future<void> _requestExit() async {
    if (_exitRequested) {
      return;
    }

    _exitRequested = true;
    await _prepareToExit();

    if (!mounted) {
      return;
    }

    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.maybePop(context);
      }
    });
  }

  Future<void> _startCamera() {
    if (_disposing || !_wantCamera || _controller != null) {
      return Future<void>.value();
    }

    final existing = _cameraInitialization;
    if (existing != null) {
      return existing;
    }

    final epoch = _cameraEpoch;
    final initialization = _runCameraInitialization(epoch);
    _cameraInitialization = initialization;
    return initialization;
  }

  Future<void> _runCameraInitialization(int epoch) async {
    CameraController? initializingController;

    try {
      final shutdown = _cameraShutdown;
      if (shutdown != null) {
        await shutdown;
      }

      if (!_canUseCamera(epoch)) {
        return;
      }

      if (!MlKitCameraImageConverter.supported) {
        _setFeedback(
          const _PreviewFeedback.error(
            'Camera preview requires an Android phone or iPhone.',
          ),
        );
        return;
      }

      _poseDetector ??= PoseDetector(
        options: PoseDetectorOptions(
          model: PoseDetectionModel.base,
          mode: PoseDetectionMode.stream,
        ),
      );

      final cameras = await availableCameras();
      if (!_canUseCamera(epoch)) {
        return;
      }

      CameraDescription? frontCamera;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      if (frontCamera == null) {
        _setFeedback(
          const _PreviewFeedback.error('No front camera was found.'),
        );
        return;
      }

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: MlKitCameraImageConverter.cameraFormat,
      );
      initializingController = controller;

      await controller.initialize();

      if (!_canUseCamera(epoch)) {
        await _disposeUnownedController(controller);
        initializingController = null;
        return;
      }

      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Some camera implementations do not support orientation locking.
      }

      if (!_canUseCamera(epoch)) {
        await _disposeUnownedController(controller);
        initializingController = null;
        return;
      }

      _acceptFrames = true;
      await controller.startImageStream((image) {
        _handleCameraImage(
          image: image,
          controller: controller,
          camera: frontCamera!,
          epoch: epoch,
        );
      });

      if (!_canUseCamera(epoch)) {
        _acceptFrames = false;
        await _disposeUnownedController(controller);
        initializingController = null;
        return;
      }

      _controller = controller;
      initializingController = null;
      _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);
      _setFeedback(const _PreviewFeedback.findingPerson(cameraReady: true));
    } on CameraException catch (error, stackTrace) {
      debugPrint('Active camera preview error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_canUseCamera(epoch)) {
        _setFeedback(
          _PreviewFeedback.error(
            'Camera unavailable: ${error.description ?? error.code}',
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Active camera preview initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_canUseCamera(epoch)) {
        _setFeedback(
          const _PreviewFeedback.error(
            'Could not start the camera. Check camera permission and try again.',
          ),
        );
      }
    } finally {
      if (initializingController != null) {
        await _disposeUnownedController(initializingController);
      }

      _cameraInitialization = null;

      // A resume can arrive while an older initialization is cancelling.
      // Start the desired camera once that older operation has fully exited.
      if (!_disposing &&
          _wantCamera &&
          _controller == null &&
          epoch != _cameraEpoch) {
        unawaited(_startCamera());
      }
    }
  }

  bool _canUseCamera(int epoch) {
    return !_disposing && _wantCamera && epoch == _cameraEpoch;
  }

  Future<void> _stopCamera() {
    final existing = _cameraShutdown;
    if (existing != null) {
      return existing;
    }

    final shutdown = _runCameraShutdown();
    _cameraShutdown = shutdown;
    return shutdown;
  }

  Future<void> _runCameraShutdown() async {
    try {
      _acceptFrames = false;

      final initialization = _cameraInitialization;
      if (initialization != null) {
        await initialization;
      }

      final controller = _controller;
      _controller = null;

      if (!_disposing && !_wantCamera) {
        _setFeedback(const _PreviewFeedback.paused());
      }

      if (controller == null) {
        await _waitForAnalysis();
        return;
      }

      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } on CameraException catch (error, stackTrace) {
        debugPrint('Active camera preview stream shutdown error: $error');
        debugPrintStack(stackTrace: stackTrace);
      } catch (error, stackTrace) {
        debugPrint('Active camera preview stream shutdown error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      // ML Kit may still be reading bytes from the final camera image.
      // Never dispose its controller until that analysis has completed.
      await _waitForAnalysis();

      try {
        await controller.dispose();
      } on CameraException catch (error, stackTrace) {
        debugPrint('Active camera preview disposal error: $error');
        debugPrintStack(stackTrace: stackTrace);
      } catch (error, stackTrace) {
        debugPrint('Active camera preview disposal error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _cameraShutdown = null;
    }
  }

  Future<void> _disposeUnownedController(CameraController controller) async {
    _acceptFrames = false;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException catch (error, stackTrace) {
      debugPrint('Active camera preview cancelled stream error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint('Active camera preview cancelled stream error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    await _waitForAnalysis();

    try {
      await controller.dispose();
    } on CameraException catch (error, stackTrace) {
      debugPrint('Active camera preview cancelled camera error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint('Active camera preview cancelled camera error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _waitForAnalysis() async {
    final analysis = _activeAnalysis;
    if (analysis == null) {
      return;
    }

    try {
      await analysis;
    } catch (_) {
      // Analysis errors are already reported by _runPoseAnalysis.
    }
  }

  Future<void> _disposeResources() async {
    await _stopCamera();
    await _waitForAnalysis();

    final detector = _poseDetector;
    _poseDetector = null;

    if (detector != null) {
      try {
        await detector.close();
      } catch (error, stackTrace) {
        debugPrint('Active camera preview detector disposal error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  void _handleCameraImage({
    required CameraImage image,
    required CameraController controller,
    required CameraDescription camera,
    required int epoch,
  }) {
    if (_processing ||
        !_acceptFrames ||
        !_canUseCamera(epoch) ||
        _poseDetector == null) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastAnalysisAt) < _analysisInterval) {
      return;
    }

    final frame = MlKitCameraImageConverter.convert(
      image: image,
      camera: camera,
      deviceOrientation: controller.value.deviceOrientation,
    );
    if (frame == null) {
      return;
    }

    _processing = true;

    final detector = _poseDetector!;
    late final Future<void> analysis;
    analysis = _runPoseAnalysis(detector: detector, frame: frame, epoch: epoch)
        .whenComplete(() {
          if (identical(_activeAnalysis, analysis)) {
            _activeAnalysis = null;
          }
          // Measure the cadence from completion, not from start. On a slower
          // phone this leaves a small idle window instead of keeping ML Kit at
          // a continuous 100% duty cycle.
          _lastAnalysisAt = DateTime.now();
          _processing = false;
        });
    _activeAnalysis = analysis;
  }

  Future<void> _runPoseAnalysis({
    required PoseDetector detector,
    required MlKitCameraFrame frame,
    required int epoch,
  }) async {
    try {
      final poses = await detector.processImage(frame.inputImage);
      if (!_acceptFrames || !_canUseCamera(epoch)) {
        return;
      }

      _setFeedback(_evaluatePlacement(poses, frame.imageSize));
    } catch (error, stackTrace) {
      debugPrint('Active camera preview pose analysis error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  _PreviewFeedback _evaluatePlacement(List<Pose> poses, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0 || poses.isEmpty) {
      return const _PreviewFeedback.findingPerson(cameraReady: true);
    }

    Pose? bestPose;
    var bestBodyCount = 0;
    var bestOverallCount = 0;

    for (final pose in poses) {
      var bodyCount = 0;
      var overallCount = 0;

      for (final entry in pose.landmarks.entries) {
        if (entry.value.likelihood < _landmarkLikelihood) {
          continue;
        }

        overallCount++;
        if (_usefulBodyLandmarks.contains(entry.key)) {
          bodyCount++;
        }
      }

      if (bodyCount > bestBodyCount ||
          (bodyCount == bestBodyCount && overallCount > bestOverallCount)) {
        bestPose = pose;
        bestBodyCount = bodyCount;
        bestOverallCount = overallCount;
      }
    }

    if (bestPose == null || bestOverallCount < 4 || bestBodyCount < 2) {
      return const _PreviewFeedback.findingPerson(cameraReady: true);
    }

    final visiblePoints = <Offset>[];
    var lowerBodyCount = 0;

    for (final type in _usefulBodyLandmarks) {
      final landmark = bestPose.landmarks[type];
      if (landmark == null || landmark.likelihood < _landmarkLikelihood) {
        continue;
      }

      final normalized = Offset(
        landmark.x / imageSize.width,
        landmark.y / imageSize.height,
      );

      if (normalized.dx < 0 ||
          normalized.dx > 1 ||
          normalized.dy < 0 ||
          normalized.dy > 1) {
        continue;
      }

      visiblePoints.add(normalized);
      if (_lowerBodyLandmarks.contains(type)) {
        lowerBodyCount++;
      }
    }

    final visibleCount = visiblePoints.length;
    final quality = _qualityFor(visibleCount);

    if (visiblePoints.length < 2) {
      return _PreviewFeedback.moreBody(quality);
    }

    var minX = visiblePoints.first.dx;
    var maxX = visiblePoints.first.dx;
    var minY = visiblePoints.first.dy;
    var maxY = visiblePoints.first.dy;

    for (final point in visiblePoints.skip(1)) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    final horizontalSpan = maxX - minX;
    final verticalSpan = maxY - minY;
    final largestSpan = horizontalSpan > verticalSpan
        ? horizontalSpan
        : verticalSpan;
    final touchesFrameEdge =
        minX < 0.035 || maxX > 0.965 || minY < 0.035 || maxY > 0.965;

    if (touchesFrameEdge || largestSpan > 0.86) {
      return _PreviewFeedback.moveFarther(quality);
    }

    // Eight reliable points, including some lower-body coverage, gives Active
    // verification enough signal without demanding a perfect full-body pose.
    if (visibleCount < 8 || lowerBodyCount < 2) {
      return _PreviewFeedback.moreBody(quality);
    }

    if (largestSpan < 0.28) {
      return _PreviewFeedback.moveCloser(quality);
    }

    return _PreviewFeedback.ready(quality);
  }

  _LandmarkQuality _qualityFor(int visibleCount) {
    if (visibleCount >= 10) {
      return _LandmarkQuality.good;
    }
    if (visibleCount >= 7) {
      return _LandmarkQuality.fair;
    }
    return _LandmarkQuality.limited;
  }

  void _setFeedback(_PreviewFeedback feedback) {
    if (_disposing || !mounted || feedback == _feedback) {
      return;
    }

    setState(() {
      _feedback = feedback;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final background = isDark
        ? const Color(0xFF07090D)
        : const Color(0xFFF4F5F7);
    final foreground = isDark ? Colors.white : const Color(0xFF17191D);
    final muted = isDark ? const Color(0xFFAEB4BE) : const Color(0xFF60646D);

    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestExit());
        }
      },
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 16, 5),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => unawaited(_requestExit()),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: foreground,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Active Camera Preview',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 21,
                          fontFamily: 'Nunito Sans',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(child: _buildCameraView()),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _ActivePreviewBracketPainter(
                              color: _feedback.accentColor,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: _PersonBadge(feedback: _feedback),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: _PlacementOverlay(feedback: _feedback),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.accessibility_new_rounded,
                          size: 20,
                          color: _feedback.accentColor,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'Body landmark quality: ${_feedback.qualityLabel}',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontFamily: 'Nunito Sans',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Prop the phone securely with your work area in view. '
                      'This preview does not start or change your task.',
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => unawaited(_requestExit()),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE31B36),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'Nunito Sans',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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

  Widget _buildCameraView() {
    final controller = _controller;

    if (_feedback.cameraReady &&
        controller != null &&
        controller.value.isInitialized) {
      return CameraPreview(controller);
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _feedback.placement == _CameraPlacement.error
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: Colors.white70,
                      size: 42,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _feedback.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ],
                )
              : const CircularProgressIndicator(color: Color(0xFFE31B36)),
        ),
      ),
    );
  }
}

enum _CameraPlacement {
  preparing,
  paused,
  findingPerson,
  moveFarther,
  moveCloser,
  moreBody,
  ready,
  error,
}

enum _LandmarkQuality { unavailable, limited, fair, good }

class _PreviewFeedback {
  const _PreviewFeedback._({
    required this.placement,
    required this.cameraReady,
    required this.personPresent,
    required this.landmarkQuality,
    this.errorMessage,
  });

  const _PreviewFeedback.preparing()
    : this._(
        placement: _CameraPlacement.preparing,
        cameraReady: false,
        personPresent: false,
        landmarkQuality: _LandmarkQuality.unavailable,
      );

  const _PreviewFeedback.paused()
    : this._(
        placement: _CameraPlacement.paused,
        cameraReady: false,
        personPresent: false,
        landmarkQuality: _LandmarkQuality.unavailable,
      );

  const _PreviewFeedback.findingPerson({required bool cameraReady})
    : this._(
        placement: _CameraPlacement.findingPerson,
        cameraReady: cameraReady,
        personPresent: false,
        landmarkQuality: _LandmarkQuality.unavailable,
      );

  const _PreviewFeedback.moveFarther(_LandmarkQuality quality)
    : this._(
        placement: _CameraPlacement.moveFarther,
        cameraReady: true,
        personPresent: true,
        landmarkQuality: quality,
      );

  const _PreviewFeedback.moveCloser(_LandmarkQuality quality)
    : this._(
        placement: _CameraPlacement.moveCloser,
        cameraReady: true,
        personPresent: true,
        landmarkQuality: quality,
      );

  const _PreviewFeedback.moreBody(_LandmarkQuality quality)
    : this._(
        placement: _CameraPlacement.moreBody,
        cameraReady: true,
        personPresent: true,
        landmarkQuality: quality,
      );

  const _PreviewFeedback.ready(_LandmarkQuality quality)
    : this._(
        placement: _CameraPlacement.ready,
        cameraReady: true,
        personPresent: true,
        landmarkQuality: quality,
      );

  const _PreviewFeedback.error(String message)
    : this._(
        placement: _CameraPlacement.error,
        cameraReady: false,
        personPresent: false,
        landmarkQuality: _LandmarkQuality.unavailable,
        errorMessage: message,
      );

  final _CameraPlacement placement;
  final bool cameraReady;
  final bool personPresent;
  final _LandmarkQuality landmarkQuality;
  final String? errorMessage;

  String get title {
    return switch (placement) {
      _CameraPlacement.preparing => 'Preparing camera',
      _CameraPlacement.paused => 'Camera paused',
      _CameraPlacement.findingPerson => 'Step into view',
      _CameraPlacement.moveFarther => 'Move farther back',
      _CameraPlacement.moveCloser => 'Move closer',
      _CameraPlacement.moreBody => 'Make more of your body visible',
      _CameraPlacement.ready => 'Ready',
      _CameraPlacement.error => 'Camera unavailable',
    };
  }

  String get guidance {
    return switch (placement) {
      _CameraPlacement.preparing => 'Starting the front camera…',
      _CameraPlacement.paused => 'The preview will restart when you return.',
      _CameraPlacement.findingPerson =>
        'Stand where you will perform the task so TaskProof can see you.',
      _CameraPlacement.moveFarther =>
        'Leave enough room around your body for movement.',
      _CameraPlacement.moveCloser =>
        'You are a little too small in the frame for reliable tracking.',
      _CameraPlacement.moreBody =>
        'Adjust the phone so your torso, arms, and legs are easier to see.',
      _CameraPlacement.ready =>
        'Person detected with enough useful body landmarks.',
      _CameraPlacement.error => errorMessage ?? 'Could not use the camera.',
    };
  }

  String get qualityLabel {
    return switch (landmarkQuality) {
      _LandmarkQuality.unavailable => 'Waiting',
      _LandmarkQuality.limited => 'Limited',
      _LandmarkQuality.fair => 'Fair',
      _LandmarkQuality.good => 'Good',
    };
  }

  Color get accentColor {
    return switch (placement) {
      _CameraPlacement.ready => const Color(0xFF22C55E),
      _CameraPlacement.moveFarther ||
      _CameraPlacement.moveCloser ||
      _CameraPlacement.moreBody => const Color(0xFFF59E0B),
      _CameraPlacement.error => const Color(0xFFE31B36),
      _ => Colors.white,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is _PreviewFeedback &&
        other.placement == placement &&
        other.cameraReady == cameraReady &&
        other.personPresent == personPresent &&
        other.landmarkQuality == landmarkQuality &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
    placement,
    cameraReady,
    personPresent,
    landmarkQuality,
    errorMessage,
  );
}

class _PersonBadge extends StatelessWidget {
  const _PersonBadge({required this.feedback});

  final _PreviewFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final detected = feedback.personPresent;
    final color = detected ? const Color(0xFF22C55E) : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD914171C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x4DFFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              detected ? 'Person detected' : 'Finding person…',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'Nunito Sans',
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlacementOverlay extends StatelessWidget {
  const _PlacementOverlay({required this.feedback});

  final _PreviewFeedback feedback;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xDD101318),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x38FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              feedback.title,
              style: TextStyle(
                color: feedback.accentColor,
                fontSize: 16,
                fontFamily: 'Nunito Sans',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              feedback.guidance,
              style: const TextStyle(
                color: Color(0xFFE1E4E8),
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivePreviewBracketPainter extends CustomPainter {
  const _ActivePreviewBracketPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 24.0;
    const length = 38.0;
    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;

    canvas.drawLine(Offset(left, top), Offset(left + length, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left, top + length), paint);
    canvas.drawLine(Offset(right, top), Offset(right - length, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + length), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + length, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - length), paint);
    canvas.drawLine(
      Offset(right, bottom),
      Offset(right - length, bottom),
      paint,
    );
    canvas.drawLine(
      Offset(right, bottom),
      Offset(right, bottom - length),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ActivePreviewBracketPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

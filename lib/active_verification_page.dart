import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    show DetectionMode, ObjectDetector, ObjectDetectorOptions;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'active_movement_analyzer.dart';
import 'new_task_page.dart';
import 'object_recognition_service.dart';

enum ActiveVerificationState {
  preparing,
  active,
  lowActivity,
  briefExit,
  warning,
  recovering,
  paused,
  completed,
}

enum _ActiveWarningCause { inactivity, personMissing, objectMissing }

class ActiveVerificationPage extends StatefulWidget {
  const ActiveVerificationPage({
    super.key,
    required this.task,
    required this.isDarkMode,
  });

  final TaskData task;
  final bool isDarkMode;

  @override
  State<ActiveVerificationPage> createState() => _ActiveVerificationPageState();
}

class _ActiveVerificationPageState extends State<ActiveVerificationPage>
    with WidgetsBindingObserver {
  static const _taskProofRed = Color(0xFFFF101C);
  static const _verifiedGreen = Color(0xFF22C55E);
  static const _detectorLossGrace = Duration(milliseconds: 1000);
  static const _resumeWarmup = Duration(milliseconds: 1800);
  static const _recoveryStabilization = Duration(milliseconds: 1400);
  static const _objectInitialGrace = Duration(seconds: 6);
  static const _objectMissingGrace = Duration(seconds: 4);
  static const _personObservationFreshness = Duration(milliseconds: 650);
  static const _objectVisibleFreshness = Duration(milliseconds: 1700);
  static const _poseAnalysisCooldown = Duration(milliseconds: 150);

  late final ActiveTaskConfig _config;

  final ActiveMovementAnalyzer _movementAnalyzer = ActiveMovementAnalyzer();
  final ObjectRecognitionService _objectRecognition =
      ObjectRecognitionService();

  PoseDetector? _poseDetector;
  ObjectDetector? _objectLocator;
  CameraController? _controller;
  CameraDescription? _camera;

  Timer? _sessionTimer;

  Future<bool>? _cameraStartFuture;
  Future<void>? _cameraStopFuture;
  Future<void>? _activePoseAnalysis;
  Future<void>? _activeObjectAnalysis;
  Future<void>? _resourceShutdown;

  bool _cameraWanted = false;
  bool _cameraInitializing = true;
  bool _processing = false;
  bool _objectProcessing = false;
  bool _objectLocalizationProcessing = false;
  bool _closing = false;
  bool _finishing = false;
  bool _confirmingEnd = false;
  bool _monitoringReady = false;
  bool _objectProfilesReady = false;

  bool _userPaused = false;
  bool _lifecyclePaused = false;
  bool _cameraFailurePaused = false;
  bool _pauseTransitionRunning = false;

  int _cameraGeneration = 0;

  Widget? _cameraPreview;

  ActiveVerificationState _verificationState =
      ActiveVerificationState.preparing;
  _ActiveWarningCause? _warningCause;
  bool _warningLatched = false;

  String _status = 'Preparing active verification';
  String? _warningReason;
  String? _cameraError;
  String? _configurationError;
  String _lastRenderSignature = '';

  ActiveMovementObservation? _movementObservation;

  final List<_RequiredObjectState> _requiredObjects = [];

  DateTime _lastPoseAnalysisCompletedAt = DateTime.fromMillisecondsSinceEpoch(
    0,
  );
  DateTime? _lastPersonObservationAt;
  DateTime? _lastPersonSeenAt;
  DateTime? _monitoringStartedAt;
  DateTime? _warmupUntil;
  DateTime? _lastTickAt;
  DateTime? _recoveryStartedAt;
  DateTime? _suspensionStartedAt;

  Duration _inactivityElapsed = Duration.zero;
  Duration? _pausedRemaining;

  bool get _isSuspended =>
      _userPaused || _lifecyclePaused || _cameraFailurePaused;

  double get _expectedMovementThreshold =>
      ActiveMovementAnalyzer.thresholdFor(_config.activityLevel);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    final config = widget.task.activeConfig;

    _config =
        config ??
        const ActiveTaskConfig(
          activityLevel: ActivityLevel.moderate,
          inactivityWarning: Duration(minutes: 2),
          briefExitAllowance: Duration.zero,
        );

    if (config == null) {
      _configurationError =
          'This task does not contain an Active verification setup.';
      _cameraInitializing = false;
      _status = _configurationError!;
      return;
    }

    widget.task.startedAt ??= DateTime.now();

    _sessionTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _sessionTick(),
    );

    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closing = true;
    _sessionTimer?.cancel();
    unawaited(_shutdownResources());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing || _finishing || _configurationError != null) {
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_lifecyclePaused) {
        _lifecyclePaused = true;
        _beginSuspension();
        _prepareAnalysisForPause();
        _verificationState = ActiveVerificationState.paused;
        _status = 'Session paused while TaskProof is inactive';
        _refreshUi();
        unawaited(_stopCamera());
      }
      return;
    }

    if (state == AppLifecycleState.resumed && _lifecyclePaused) {
      _lifecyclePaused = false;

      if (!_userPaused) {
        unawaited(_resumeAfterSuspension());
      }
    }
  }

  Future<void> _initialize() async {
    if (!MlKitCameraImageConverter.supported) {
      _cameraInitializing = false;
      _cameraError = 'Active verification requires Android or iPhone.';
      _status = _cameraError!;
      _cameraFailurePaused = true;
      _beginSuspension();
      _verificationState = ActiveVerificationState.paused;
      _refreshUi();
      return;
    }

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );

    if (_config.requiredObjectIds.isNotEmpty) {
      _objectLocator = ObjectDetector(
        options: ObjectDetectorOptions(
          // Frames are sampled independently and tracking IDs are not used.
          // Single-image mode avoids the stream tracker's reset/restart work.
          mode: DetectionMode.single,
          classifyObjects: false,
          multipleObjects: true,
        ),
      );
    }

    final cameraFuture = _initializeCamera();
    await _loadRequiredObjects();
    final cameraReady = await cameraFuture;

    if (_closing || !mounted || _isSuspended || !cameraReady) {
      return;
    }

    _monitoringReady = true;
    _beginWarmup();
  }

  Future<void> _loadRequiredObjects() async {
    final ids = _config.requiredObjectIds;

    if (ids.isEmpty) {
      _objectProfilesReady = true;
      return;
    }

    try {
      final result = await _objectRecognition.loadRequiredObjects(ids);

      if (_closing) {
        return;
      }

      final objectsById = {
        for (final object in result.objects) object.id: object,
      };

      _requiredObjects.clear();

      for (final id in ids) {
        final object = objectsById[id];

        _requiredObjects.add(
          _RequiredObjectState(
            id: id,
            name: object?.name ?? 'Saved object unavailable',
            available: object != null,
          ),
        );
      }

      _objectProfilesReady = true;
      _refreshUi();
    } catch (error, stackTrace) {
      debugPrint('Active object profile load error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (_closing) {
        return;
      }

      _requiredObjects
        ..clear()
        ..addAll(
          ids.map(
            (id) => _RequiredObjectState(
              id: id,
              name: 'Saved object unavailable',
              available: false,
            ),
          ),
        );

      _objectProfilesReady = true;
      _refreshUi();
    }
  }

  Future<bool> _initializeCamera() async {
    final stopping = _cameraStopFuture;

    if (stopping != null) {
      await stopping;
    }

    if (_closing || _controller != null) {
      return _controller?.value.isInitialized ?? false;
    }

    final existing = _cameraStartFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<bool> future;
    future = _performCameraInitialization();
    _cameraStartFuture = future;

    try {
      return await future;
    } finally {
      if (identical(_cameraStartFuture, future)) {
        _cameraStartFuture = null;
      }
    }
  }

  Future<bool> _performCameraInitialization() async {
    _cameraWanted = true;
    _cameraInitializing = true;
    _cameraError = null;
    final generation = ++_cameraGeneration;
    CameraController? localController;

    _refreshUi();

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw StateError('No camera was found.');
      }

      final camera = cameras.firstWhere(
        (candidate) => candidate.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      localController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: MlKitCameraImageConverter.cameraFormat,
      );

      await localController.initialize();

      if (!_cameraStartIsCurrent(generation)) {
        await _disposeLocalController(localController);
        return false;
      }

      try {
        await localController.lockCaptureOrientation(
          DeviceOrientation.portraitUp,
        );
      } catch (_) {}

      if (!_cameraStartIsCurrent(generation)) {
        await _disposeLocalController(localController);
        return false;
      }

      _camera = camera;
      _controller = localController;

      await localController.startImageStream(_onCameraImage);

      if (!_cameraStartIsCurrent(generation)) {
        if (identical(_controller, localController)) {
          _controller = null;
          _cameraPreview = null;
        }
        await _disposeLocalController(localController);
        return false;
      }

      _cameraPreview = _ActiveCameraPreview(controller: localController);
      _cameraInitializing = false;
      _cameraError = null;
      _status = 'Position yourself so your body and task area are visible';
      _refreshUi();
      return true;
    } on CameraException catch (error, stackTrace) {
      debugPrint('Active camera initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (localController != null) {
        if (identical(_controller, localController)) {
          _controller = null;
          _cameraPreview = null;
        }
        await _disposeLocalController(localController);
      }

      _handleCameraFailure(
        'Camera unavailable: ${error.description ?? error.code}',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint('Active camera initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (localController != null) {
        if (identical(_controller, localController)) {
          _controller = null;
          _cameraPreview = null;
        }
        await _disposeLocalController(localController);
      }

      _handleCameraFailure(
        error is StateError ? error.message : 'Could not start the camera.',
      );
      return false;
    }
  }

  bool _cameraStartIsCurrent(int generation) {
    return mounted &&
        !_closing &&
        _cameraWanted &&
        generation == _cameraGeneration;
  }

  void _handleCameraFailure(String message) {
    if (_closing) {
      return;
    }

    _cameraInitializing = false;
    _cameraError = message;
    _cameraFailurePaused = true;
    _beginSuspension();
    _prepareAnalysisForPause();
    _verificationState = ActiveVerificationState.paused;
    _status = message;
    _refreshUi();
  }

  Future<void> _disposeLocalController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    try {
      await controller.dispose();
    } catch (_) {}
  }

  Future<void> _stopCamera() {
    final existing = _cameraStopFuture;

    if (existing != null) {
      return existing;
    }

    late final Future<void> future;
    future = _performCameraStop();
    _cameraStopFuture = future;

    unawaited(
      future.whenComplete(() {
        if (identical(_cameraStopFuture, future)) {
          _cameraStopFuture = null;
        }
      }),
    );

    return future;
  }

  Future<void> _performCameraStop() async {
    _cameraWanted = false;
    _cameraGeneration++;

    final starting = _cameraStartFuture;

    if (starting != null) {
      try {
        await starting;
      } catch (_) {}
    }

    final controller = _controller;
    _controller = null;
    _cameraPreview = null;

    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
    }

    final poseAnalysis = _activePoseAnalysis;
    final objectAnalysis = _activeObjectAnalysis;

    if (poseAnalysis != null) {
      try {
        await poseAnalysis;
      } catch (_) {}
    }

    if (objectAnalysis != null) {
      try {
        await objectAnalysis;
      } catch (_) {}
    }

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _shutdownResources() {
    return _resourceShutdown ??= _performResourceShutdown();
  }

  Future<void> _performResourceShutdown() async {
    _closing = true;
    _sessionTimer?.cancel();
    await _stopCamera();

    final detector = _poseDetector;
    _poseDetector = null;

    if (detector != null) {
      try {
        await detector.close();
      } catch (_) {}
    }

    final objectLocator = _objectLocator;
    _objectLocator = null;

    if (objectLocator != null) {
      try {
        await objectLocator.close();
      } catch (_) {}
    }

    _objectRecognition.dispose();
  }

  void _onCameraImage(CameraImage image) {
    if (_closing || _isSuspended || !_cameraWanted) {
      return;
    }

    final controller = _controller;
    final camera = _camera;

    if (controller == null ||
        camera == null ||
        !controller.value.isInitialized) {
      return;
    }

    final now = DateTime.now();
    final orientation = controller.value.deviceOrientation;

    if (!_processing &&
        !_objectLocalizationProcessing &&
        now.difference(_lastPoseAnalysisCompletedAt) >= _poseAnalysisCooldown) {
      late final Future<void> analysis;
      analysis = _analyzePoseFrame(image, camera, orientation, now);
      _activePoseAnalysis = analysis;

      unawaited(
        analysis.whenComplete(() {
          if (identical(_activePoseAnalysis, analysis)) {
            _activePoseAnalysis = null;
          }
        }),
      );
    }

    if (_config.requiredObjectIds.isNotEmpty &&
        _objectProfilesReady &&
        _objectRecognition.isAnalysisDue &&
        !_objectProcessing &&
        !_processing) {
      late final Future<void> analysis;
      analysis = _analyzeObjectFrame(image, camera, orientation, now);
      _activeObjectAnalysis = analysis;

      unawaited(
        analysis.whenComplete(() {
          if (identical(_activeObjectAnalysis, analysis)) {
            _activeObjectAnalysis = null;
          }
        }),
      );
    }
  }

  Future<void> _analyzePoseFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
    DateTime timestamp,
  ) async {
    final detector = _poseDetector;
    if (detector == null) {
      return;
    }

    _processing = true;

    try {
      final frame = MlKitCameraImageConverter.convert(
        image: image,
        camera: camera,
        deviceOrientation: orientation,
      );

      if (frame == null || _closing || _isSuspended) {
        return;
      }

      final poses = await detector.processImage(frame.inputImage);

      if (_closing || _isSuspended) {
        return;
      }

      final observation = _movementAnalyzer.analyze(
        poses: poses,
        imageSize: frame.imageSize,
        timestamp: timestamp,
        sensitivity: widget.task.sensitivity,
      );

      final observedAt = DateTime.now();

      _movementObservation = observation;
      _lastPersonObservationAt = observedAt;

      if (observation.personPresent) {
        _lastPersonSeenAt = observedAt;
      }
    } catch (error, stackTrace) {
      debugPrint('Active pose processing error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _processing = false;
      _lastPoseAnalysisCompletedAt = DateTime.now();
    }
  }

  Future<void> _analyzeObjectFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
    DateTime timestamp,
  ) async {
    _objectProcessing = true;

    try {
      // Capture before awaiting ML Kit. Camera stream buffers are reusable,
      // so localization and matching must operate on the same pixels.
      final snapshot = _objectRecognition.captureFrame(
        image,
        camera: camera,
        deviceOrientation: orientation,
      );
      final detectedBounds = <Rect>[];
      final locator = _objectLocator;

      if (locator != null) {
        final frame = MlKitCameraImageConverter.convert(
          image: image,
          camera: camera,
          deviceOrientation: orientation,
        );

        if (frame != null) {
          _objectLocalizationProcessing = true;
          try {
            final objects = await locator.processImage(frame.inputImage);
            detectedBounds.addAll(objects.map((object) => object.boundingBox));
          } catch (error) {
            // Matching still has a multiscale fallback if the native detector
            // is warming up or temporarily unavailable.
            debugPrint('Active object localization error: $error');
          } finally {
            _objectLocalizationProcessing = false;
          }
        }
      }

      // Pausing or closing while native localization is running invalidates
      // this result. Avoid starting the much more expensive visual match.
      if (_closing || _isSuspended) {
        return;
      }

      final matches = await _objectRecognition.analyzeSnapshot(
        snapshot,
        detectedBounds: detectedBounds,
      );

      if (_closing || _isSuspended) {
        return;
      }

      final matchesById = {for (final match in matches) match.id: match};
      final checkedAt = DateTime.now();

      for (final object in _requiredObjects) {
        final match = matchesById[object.id];

        if (match == null) {
          continue;
        }

        object.currentlyMatched = match.isMatch && !match.isTemporarilyMissing;
        object.confidence = match.confidence;
        object.lastCheckedAt = checkedAt;

        if (object.currentlyMatched) {
          object.lastMatchedAt = checkedAt;
          object.hasEverMatched = true;
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Active object recognition error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _objectLocalizationProcessing = false;
      _objectProcessing = false;
    }
  }

  void _sessionTick() {
    if (!mounted || _closing || _finishing || _configurationError != null) {
      return;
    }

    if (widget.task.status != TaskStatus.live) {
      return;
    }

    final now = DateTime.now();

    if (_isSuspended) {
      _lastTickAt = now;
      _refreshUi();
      return;
    }

    final remaining = _remainingTime(now);

    if (remaining <= Duration.zero) {
      unawaited(_completeSession());
      return;
    }

    final previousTick = _lastTickAt;
    _lastTickAt = now;
    final delta = previousTick == null
        ? Duration.zero
        : now.difference(previousTick);

    if (!_monitoringReady ||
        !_objectProfilesReady ||
        _controller == null ||
        _cameraInitializing) {
      _verificationState = ActiveVerificationState.preparing;
      _status = 'Preparing active verification';
      _refreshUi();
      return;
    }

    final warmupUntil = _warmupUntil;

    if (warmupUntil != null && now.isBefore(warmupUntil)) {
      _verificationState = ActiveVerificationState.preparing;
      _status = 'Warming up verification...';
      _refreshUi();
      return;
    }

    _evaluateVerification(now, delta);
    _refreshUi();
  }

  void _evaluateVerification(DateTime now, Duration delta) {
    final personFresh = _personIsFresh(now);
    final observation = _movementObservation;
    final movementPassing =
        personFresh &&
        observation != null &&
        observation.smoothedMovementScore >= _expectedMovementThreshold;

    if (personFresh) {
      if (movementPassing) {
        _inactivityElapsed = Duration.zero;
      } else {
        _inactivityElapsed += delta;
      }
    }

    final personMissingDuration = _personMissingDuration(now);
    final confirmedPersonMissing = personMissingDuration >= _detectorLossGrace;
    final exitElapsed = confirmedPersonMissing
        ? personMissingDuration - _detectorLossGrace
        : Duration.zero;

    final missingObjects = _missingObjects(now);
    final pendingObjects = _objectsTemporarilyUnverified(now);

    _ActiveWarningCause? currentViolation;
    String? violationReason;

    if (confirmedPersonMissing && exitElapsed >= _config.briefExitAllowance) {
      currentViolation = _ActiveWarningCause.personMissing;
      violationReason = 'Return to the camera view to continue verification.';
    } else if (missingObjects.isNotEmpty) {
      currentViolation = _ActiveWarningCause.objectMissing;
      violationReason = missingObjects.length == 1
          ? '${missingObjects.first.name} is not detected.'
          : '${missingObjects.length} required objects are not detected.';
    } else if (personFresh && _inactivityElapsed >= _config.inactivityWarning) {
      currentViolation = _ActiveWarningCause.inactivity;
      violationReason =
          'Movement has stayed below the ${_activityLevelName(_config.activityLevel)} level.';
    }

    if (currentViolation != null) {
      _recoveryStartedAt = null;

      if (!_warningLatched) {
        _enterWarning(currentViolation, violationReason!);
      } else {
        _warningCause = currentViolation;
        _warningReason = violationReason;
        _verificationState = ActiveVerificationState.warning;
        _status = 'Active verification warning';
      }
      return;
    }

    if (_warningLatched) {
      if (!_canRecoverFromWarning(
        now: now,
        personFresh: personFresh,
        movementPassing: movementPassing,
        missingObjects: missingObjects,
      )) {
        _recoveryStartedAt = null;
        _verificationState = ActiveVerificationState.warning;
        _status = 'Active verification warning';
        return;
      }

      _recoveryStartedAt ??= now;

      if (now.difference(_recoveryStartedAt!) < _recoveryStabilization) {
        _verificationState = ActiveVerificationState.recovering;
        _status = 'Verifying recovery...';
        return;
      }

      _warningLatched = false;
      _warningCause = null;
      _warningReason = null;
      _recoveryStartedAt = null;
      _inactivityElapsed = Duration.zero;
    }

    if (!personFresh && !confirmedPersonMissing) {
      _verificationState = ActiveVerificationState.preparing;
      _status = 'Confirming person presence...';
      return;
    }

    if (confirmedPersonMissing) {
      _verificationState = ActiveVerificationState.briefExit;
      final allowanceRemaining = _config.briefExitAllowance - exitElapsed;
      _status = 'Brief exit — ${_shortDuration(allowanceRemaining)} remaining';
      return;
    }

    if (pendingObjects.isNotEmpty) {
      _verificationState = ActiveVerificationState.preparing;
      _status = pendingObjects.any((object) => !object.hasEverMatched)
          ? 'Looking for required objects...'
          : 'Required object temporarily hidden';
      return;
    }

    if (!movementPassing) {
      _verificationState = ActiveVerificationState.lowActivity;
      final inactivityRemaining =
          _config.inactivityWarning - _inactivityElapsed;
      _status =
          'Activity below expected — ${_shortDuration(inactivityRemaining)} until warning';
      return;
    }

    _verificationState = ActiveVerificationState.active;
    _status = 'Actively verifying';
  }

  bool _canRecoverFromWarning({
    required DateTime now,
    required bool personFresh,
    required bool movementPassing,
    required List<_RequiredObjectState> missingObjects,
  }) {
    if (!personFresh || missingObjects.isNotEmpty) {
      return false;
    }

    switch (_warningCause) {
      case _ActiveWarningCause.inactivity:
        return movementPassing;
      case _ActiveWarningCause.personMissing:
        return true;
      case _ActiveWarningCause.objectMissing:
        return _requiredObjects.every(
          (object) =>
              object.available &&
              object.currentlyMatched &&
              object.lastCheckedAt != null &&
              now.difference(object.lastCheckedAt!) <= _objectVisibleFreshness,
        );
      case null:
        return false;
    }
  }

  void _enterWarning(_ActiveWarningCause cause, String reason) {
    _warningLatched = true;
    _warningCause = cause;
    _warningReason = reason;
    _recoveryStartedAt = null;
    _verificationState = ActiveVerificationState.warning;
    _status = 'Active verification warning';
    _refreshUi();
    unawaited(_triggerWarningFeedback());
  }

  Future<void> _triggerWarningFeedback() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  bool _personIsFresh(DateTime now) {
    final observationAt = _lastPersonObservationAt;
    final observation = _movementObservation;

    return observationAt != null &&
        observation != null &&
        observation.personPresent &&
        now.difference(observationAt) <= _personObservationFreshness;
  }

  Duration _personMissingDuration(DateTime now) {
    final baseline = _lastPersonSeenAt ?? _monitoringStartedAt ?? now;
    final missing = now.difference(baseline);
    return missing.isNegative ? Duration.zero : missing;
  }

  List<_RequiredObjectState> _missingObjects(DateTime now) {
    if (_requiredObjects.isEmpty) {
      return const [];
    }

    final monitoringStarted = _monitoringStartedAt ?? now;

    return _requiredObjects.where((object) {
      if (!object.available) {
        return now.difference(monitoringStarted) >= _objectInitialGrace;
      }

      final lastMatched = object.lastMatchedAt;

      if (lastMatched == null) {
        return now.difference(monitoringStarted) >= _objectInitialGrace;
      }

      return now.difference(lastMatched) >= _objectMissingGrace;
    }).toList();
  }

  List<_RequiredObjectState> _objectsTemporarilyUnverified(DateTime now) {
    if (_requiredObjects.isEmpty) {
      return const [];
    }

    final missingIds = _missingObjects(now).map((object) => object.id).toSet();

    return _requiredObjects.where((object) {
      if (missingIds.contains(object.id)) {
        return false;
      }

      if (!object.currentlyMatched || object.lastCheckedAt == null) {
        return true;
      }

      return now.difference(object.lastCheckedAt!) > _objectVisibleFreshness;
    }).toList();
  }

  void _beginWarmup({bool preserveVerification = false}) {
    final now = DateTime.now();
    _movementAnalyzer.reset();
    _objectRecognition.resetTemporalState();
    _movementObservation = null;
    _lastPersonObservationAt = null;
    _recoveryStartedAt = null;
    _warmupUntil = now.add(_resumeWarmup);
    _lastTickAt = now;

    if (preserveVerification) {
      for (final object in _requiredObjects) {
        object.currentlyMatched = false;
        object.lastCheckedAt = null;
      }
    } else {
      _lastPersonSeenAt = null;
      _inactivityElapsed = Duration.zero;
      _warningLatched = false;
      _warningCause = null;
      _warningReason = null;
      _monitoringStartedAt = _warmupUntil;

      for (final object in _requiredObjects) {
        object.resetForWarmup();
      }
    }

    _verificationState = ActiveVerificationState.preparing;
    _status = 'Warming up verification...';
    _refreshUi();
  }

  void _beginSuspension() {
    if (_suspensionStartedAt != null) {
      return;
    }

    final now = DateTime.now();
    _pausedRemaining = _remainingTime(now);
    _suspensionStartedAt = now;
    _lastTickAt = now;
  }

  void _endSuspension() {
    if (_isSuspended) {
      return;
    }

    final suspendedAt = _suspensionStartedAt;
    final now = DateTime.now();
    final preserveVerification = _monitoringStartedAt != null;
    final suspendedFor = suspendedAt == null
        ? Duration.zero
        : now.difference(suspendedAt);

    if (suspendedAt != null && widget.task.startedAt != null) {
      widget.task.startedAt = widget.task.startedAt!.add(suspendedFor);
    }

    // Monitoring clocks exclude both the suspension and the short resume
    // warm-up, while the session countdown excludes only the suspension.
    final verificationShift = suspendedFor + _resumeWarmup;
    _lastPersonSeenAt = _shiftTimestamp(_lastPersonSeenAt, verificationShift);
    _monitoringStartedAt = _shiftTimestamp(
      _monitoringStartedAt,
      verificationShift,
    );

    for (final object in _requiredObjects) {
      object.lastCheckedAt = _shiftTimestamp(
        object.lastCheckedAt,
        verificationShift,
      );
      object.lastMatchedAt = _shiftTimestamp(
        object.lastMatchedAt,
        verificationShift,
      );
    }

    _suspensionStartedAt = null;
    _pausedRemaining = null;
    _monitoringReady = true;
    _beginWarmup(preserveVerification: preserveVerification);
  }

  void _prepareAnalysisForPause() {
    _movementAnalyzer.reset();
    _objectRecognition.resetTemporalState();
    _movementObservation = null;
    _lastPersonObservationAt = null;
    _recoveryStartedAt = null;

    for (final object in _requiredObjects) {
      object.currentlyMatched = false;
      object.lastCheckedAt = null;
    }
  }

  Future<void> _togglePause() async {
    if (_pauseTransitionRunning || _finishing || _closing) {
      return;
    }

    if (_userPaused || _cameraFailurePaused) {
      await _resumeAfterSuspension();
      return;
    }

    _pauseTransitionRunning = true;
    _userPaused = true;
    _beginSuspension();
    _prepareAnalysisForPause();
    _verificationState = ActiveVerificationState.paused;
    _status = 'Session paused';
    _refreshUi();

    try {
      await _stopCamera();
    } finally {
      _pauseTransitionRunning = false;
      _refreshUi();
    }
  }

  Future<void> _resumeAfterSuspension() async {
    if (_pauseTransitionRunning || _finishing || _closing) {
      return;
    }

    if (_lifecyclePaused) {
      return;
    }

    _pauseTransitionRunning = true;
    _userPaused = false;
    _cameraFailurePaused = true;
    _verificationState = ActiveVerificationState.preparing;
    _status = 'Restarting camera...';
    _refreshUi();

    try {
      final cameraReady = await _initializeCamera();

      if (!cameraReady || _closing || _lifecyclePaused) {
        return;
      }

      _cameraFailurePaused = false;
      _endSuspension();
    } finally {
      _pauseTransitionRunning = false;
      _refreshUi();
    }
  }

  Duration _remainingTime([DateTime? at]) {
    if (_isSuspended && _pausedRemaining != null) {
      return _pausedRemaining!;
    }

    final startedAt = widget.task.startedAt;

    if (startedAt == null) {
      return widget.task.duration;
    }

    final remaining =
        widget.task.duration - (at ?? DateTime.now()).difference(startedAt);

    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _completeSession() async {
    if (_finishing || widget.task.status == TaskStatus.completed) {
      return;
    }

    _finishing = true;
    _verificationState = ActiveVerificationState.completed;
    _status = 'Task completed';
    _warningLatched = false;
    widget.task.status = TaskStatus.completed;
    widget.task.completedAt = DateTime.now();
    widget.task.startedAt = null;
    _sessionTimer?.cancel();
    _refreshUi();

    await _shutdownResources();

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Task Completed'),
        content: Text('${widget.task.name} has been completed.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _taskProofRed),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _confirmEndEarly() async {
    if (_confirmingEnd || _finishing || !mounted) {
      return;
    }

    _confirmingEnd = true;

    final end = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 34),
          child: Container(
            width: 360,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE8EA),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: _taskProofRed,
                      size: 30,
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'End session?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF17181C),
                    fontSize: 22,
                    fontFamily: 'Nunito Sans',
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),

                const SizedBox(height: 9),

                const Text(
                  'The task will not be marked as completed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF737782),
                    fontSize: 14,
                    fontFamily: 'Nunito Sans',
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 24),

                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFECEDEF),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext, false);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF17181C),
                            side: const BorderSide(
                              color: Color(0xFFDADCE1),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Nunito Sans',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(dialogContext, true);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _taskProofRed,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'End Session',
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'Nunito Sans',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    _confirmingEnd = false;

    if (end != true || !mounted || _finishing) {
      return;
    }

    _finishing = true;
    _sessionTimer?.cancel();
    _warningLatched = false;

    widget.task.status = TaskStatus.ready;
    widget.task.startedAt = null;
    widget.task.completedAt = null;

    await _shutdownResources();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _refreshUi() {
    if (!mounted || _closing && !_finishing) {
      return;
    }

    final signature = _renderSignature();

    if (signature == _lastRenderSignature) {
      return;
    }

    _lastRenderSignature = signature;
    setState(() {});
  }

  String _renderSignature() {
    final now = DateTime.now();
    final remainingSeconds = (_remainingTime(now).inMilliseconds + 999) ~/ 1000;
    final movementBand = _movementStatus(now);
    final personBand = _personStatus(now);
    final objectBands = _requiredObjects
        .map((object) => '${object.id}:${_objectStatus(object, now).name}')
        .join(',');

    return '${_verificationState.name}|$_status|$_warningReason|'
        '$_cameraInitializing|$_cameraError|$remainingSeconds|'
        '$movementBand|$personBand|$objectBands|$_pauseTransitionRunning';
  }

  Color get _verificationColor {
    switch (_verificationState) {
      case ActiveVerificationState.active:
        return _verifiedGreen;
      case ActiveVerificationState.warning:
        return _taskProofRed;
      case ActiveVerificationState.preparing:
      case ActiveVerificationState.lowActivity:
      case ActiveVerificationState.briefExit:
      case ActiveVerificationState.recovering:
      case ActiveVerificationState.paused:
      case ActiveVerificationState.completed:
        return const Color(0xFFD5D8DE);
    }
  }

  String get _stateLabel {
    switch (_verificationState) {
      case ActiveVerificationState.active:
        return 'Actively verifying';
      case ActiveVerificationState.lowActivity:
        return 'Activity check';
      case ActiveVerificationState.briefExit:
        return 'Brief exit';
      case ActiveVerificationState.warning:
        return 'Warning';
      case ActiveVerificationState.recovering:
        return 'Recovering';
      case ActiveVerificationState.paused:
        return 'Paused';
      case ActiveVerificationState.completed:
        return 'Completed';
      case ActiveVerificationState.preparing:
        return 'Preparing';
    }
  }

  String _personStatus(DateTime now) {
    if (_isSuspended) {
      return 'Presence paused';
    }

    if (_personIsFresh(now)) {
      return 'Person detected';
    }

    final missing = _personMissingDuration(now);

    if (missing < _detectorLossGrace) {
      return 'Confirming presence';
    }

    if (missing - _detectorLossGrace < _config.briefExitAllowance) {
      return 'Briefly out of frame';
    }

    return 'Person not detected';
  }

  String _movementStatus(DateTime now) {
    if (_isSuspended) {
      return 'Movement paused';
    }

    if (!_personIsFresh(now) || _movementObservation == null) {
      return 'Waiting for movement data';
    }

    return _movementObservation!.smoothedMovementScore >=
            _expectedMovementThreshold
        ? '${_activityLevelName(_config.activityLevel)} activity detected'
        : 'Below ${_activityLevelName(_config.activityLevel)} activity';
  }

  _ObjectDisplayStatus _objectStatus(
    _RequiredObjectState object,
    DateTime now,
  ) {
    if (!object.available) {
      final monitoringStarted = _monitoringStartedAt ?? now;
      return now.difference(monitoringStarted) >= _objectInitialGrace
          ? _ObjectDisplayStatus.missing
          : _ObjectDisplayStatus.checking;
    }

    if (object.currentlyMatched &&
        object.lastCheckedAt != null &&
        now.difference(object.lastCheckedAt!) <= _objectVisibleFreshness) {
      return _ObjectDisplayStatus.visible;
    }

    final lastMatched = object.lastMatchedAt;

    if (lastMatched == null) {
      final monitoringStarted = _monitoringStartedAt ?? now;
      return now.difference(monitoringStarted) >= _objectInitialGrace
          ? _ObjectDisplayStatus.missing
          : _ObjectDisplayStatus.checking;
    }

    return now.difference(lastMatched) >= _objectMissingGrace
        ? _ObjectDisplayStatus.missing
        : _ObjectDisplayStatus.checking;
  }

  Color _statusColor(String status) {
    if (status.contains('detected') && !status.contains('not')) {
      return _verifiedGreen;
    }

    if (_verificationState == ActiveVerificationState.warning &&
        (status.contains('not detected') || status.contains('Below'))) {
      return _taskProofRed;
    }

    return widget.isDarkMode
        ? const Color(0xFFB9C0CA)
        : const Color(0xFF686D77);
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isDarkMode
        ? const Color(0xFF07090D)
        : const Color(0xFFF8F8F9);
    final foreground = widget.isDarkMode
        ? Colors.white
        : const Color(0xFF17191E);
    final now = DateTime.now();
    final movementStatus = _movementStatus(now);
    final personStatus = _personStatus(now);
    final remainingTime = _remainingTime(now);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmEndEarly());
        }
      },
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    const SizedBox(width: 42),
                    Expanded(
                      child: Text(
                        widget.task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 22,
                          fontFamily: 'Nunito Sans',
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 42),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _cameraBody(),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _ActiveCameraFramePainter(
                              color: _verificationColor,
                            ),
                          ),
                        ),
                        if (_verificationState ==
                            ActiveVerificationState.warning)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: _taskProofRed.withValues(alpha: .13),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC0D1014),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _verificationColor.withValues(
                                  alpha: .75,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: _verificationColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _stateLabel,
                                  style: TextStyle(
                                    color: _verificationColor,
                                    fontSize: 11,
                                    fontFamily: 'Nunito Sans',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_requiredObjects.isNotEmpty)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: _buildRequiredObjectOverlay(now),
                          ),
                        if (_verificationState ==
                            ActiveVerificationState.warning)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.all(28),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xEB160B0D),
                                border: Border.all(
                                  color: _taskProofRed,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: _taskProofRed,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Verification Warning',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontFamily: 'Nunito Sans',
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _warningReason ??
                                        'Return to the task area.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFE3E5E8),
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                child: Column(
                  children: [
                    _StatusLine(
                      icon: Icons.directions_run_rounded,
                      label: movementStatus,
                      color: _statusColor(movementStatus),
                      foreground: foreground,
                    ),
                    const SizedBox(height: 5),
                    _StatusLine(
                      icon: Icons.person_outline_rounded,
                      label: personStatus,
                      color: _statusColor(personStatus),
                      foreground: foreground,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isDarkMode
                        ? const Color(0xFF0E1116)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: widget.isDarkMode
                          ? const Color(0xFF252A31)
                          : const Color(0xFFE1E3E7),
                    ),
                  ),
                  child: Row(
                    children: [
                      _SessionControl(
                        icon: _userPaused || _cameraFailurePaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        label: _cameraFailurePaused
                            ? 'Retry'
                            : _userPaused
                            ? 'Resume'
                            : 'Pause',
                        color: foreground,
                        disabled:
                            _pauseTransitionRunning ||
                            _lifecyclePaused ||
                            _configurationError != null,
                        onTap: _togglePause,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: widget.isDarkMode
                                    ? const Color(0xFFB8BEC7)
                                    : const Color(0xFF626771),
                                fontSize: 11,
                                fontFamily: 'Nunito Sans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _formatCountdown(remainingTime),
                              style: TextStyle(
                                color: widget.isDarkMode
                                    ? const Color(0xFFF2F3F5)
                                    : const Color(0xFF25272D),
                                fontSize: 34,
                                fontFamily: 'Nunito Sans',
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _SessionControl(
                        icon: Icons.stop_rounded,
                        label: 'End Session',
                        color: _taskProofRed,
                        onTap: _confirmEndEarly,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraBody() {
    if (_configurationError != null) {
      return _cameraMessage(
        icon: Icons.error_outline_rounded,
        message: _configurationError!,
      );
    }

    if (_userPaused || _lifecyclePaused) {
      return _cameraMessage(
        icon: Icons.pause_circle_outline_rounded,
        message: 'Camera verification is paused.',
      );
    }

    if (_cameraInitializing) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: _taskProofRed)),
      );
    }

    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return _cameraMessage(
        icon: Icons.videocam_off_outlined,
        message: _cameraError ?? 'Camera is unavailable.',
      );
    }

    return _cameraPreview ?? _ActiveCameraPreview(controller: controller);
  }

  Widget _cameraMessage({required IconData icon, required String message}) {
    return ColoredBox(
      color: const Color(0xFF11151A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 54),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequiredObjectOverlay(DateTime now) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xC90C0F13),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Required Objects',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'Nunito Sans',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          ..._requiredObjects.map((object) {
            final status = _objectStatus(object, now);
            final color = switch (status) {
              _ObjectDisplayStatus.visible => _verifiedGreen,
              _ObjectDisplayStatus.checking => const Color(0xFFD5D8DE),
              _ObjectDisplayStatus.missing => _taskProofRed,
            };
            final icon = switch (status) {
              _ObjectDisplayStatus.visible => Icons.check_circle_rounded,
              _ObjectDisplayStatus.checking => Icons.schedule_rounded,
              _ObjectDisplayStatus.missing => Icons.error_outline_rounded,
            };
            final label = switch (status) {
              _ObjectDisplayStatus.visible => object.name,
              _ObjectDisplayStatus.checking => '${object.name} — checking',
              _ObjectDisplayStatus.missing => '${object.name} not detected',
            };

            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'Nunito Sans',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ActiveCameraPreview extends StatelessWidget {
  const _ActiveCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return const ColoredBox(color: Colors.black);
    }

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.height,
                height: previewSize.width,
                child: CameraPreview(controller),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RequiredObjectState {
  _RequiredObjectState({
    required this.id,
    required this.name,
    required this.available,
  });

  final String id;
  final String name;
  final bool available;

  bool currentlyMatched = false;
  bool hasEverMatched = false;
  double confidence = 0;
  DateTime? lastCheckedAt;
  DateTime? lastMatchedAt;

  void resetForWarmup() {
    currentlyMatched = false;
    hasEverMatched = false;
    confidence = 0;
    lastCheckedAt = null;
    lastMatchedAt = null;
  }
}

enum _ObjectDisplayStatus { visible, checking, missing }

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontFamily: 'Nunito Sans',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionControl extends StatelessWidget {
  const _SessionControl({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = disabled ? color.withValues(alpha: .35) : color;

    return InkWell(
      onTap: disabled ? null : () => unawaited(onTap()),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: effectiveColor),
              ),
              child: Icon(icon, color: effectiveColor),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: effectiveColor,
                fontSize: 10,
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

class _ActiveCameraFramePainter extends CustomPainter {
  const _ActiveCameraFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 24.0;
    const length = 36.0;
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
  bool shouldRepaint(covariant _ActiveCameraFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

String _activityLevelName(ActivityLevel level) {
  return switch (level) {
    ActivityLevel.light => 'light',
    ActivityLevel.moderate => 'moderate',
    ActivityLevel.high => 'high',
  };
}

DateTime? _shiftTimestamp(DateTime? timestamp, Duration amount) {
  return timestamp?.add(amount);
}

String _shortDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final seconds = (safe.inMilliseconds + 999) ~/ 1000;

  if (seconds >= 60) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
  }

  return '${seconds}s';
}

String _formatCountdown(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final totalSeconds = (safe.inMilliseconds + 999) ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

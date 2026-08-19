import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'new_task_page.dart';
import 'workout_pose_analyzer.dart';


enum WorkoutSessionState {
  preparing,
  countdown,
  exercising,
  resting,
  warning,
  paused,
  completed,
}

enum _WorkoutWarning { personMissing, coverage, restLimit }

class WorkoutVerificationPage extends StatefulWidget {
  const WorkoutVerificationPage({
    super.key,
    required this.task,
    required this.isDarkMode,
  });

  final TaskData task;
  final bool isDarkMode;

  @override
  State<WorkoutVerificationPage> createState() =>
      _WorkoutVerificationPageState();
}

class _WorkoutVerificationPageState extends State<WorkoutVerificationPage>
    with WidgetsBindingObserver {
  static const _red = Color(0xFFFF101C);
  static const _green = Color(0xFF22C55E);
  static const _analysisInterval = Duration(milliseconds: 100);
  static const _personLossGrace = Duration(milliseconds: 1000);
  static const _exerciseLossGrace = Duration(milliseconds: 1100);
  static const _initialReadyDuration =
      Duration(milliseconds: 400);
  static const _pushUpReadyDuration =
      Duration(milliseconds: 850);
  static const _pushUpCountdownGrace =
      Duration(milliseconds: 900);
  static const _jumpingJackReadinessGrace =
      Duration(milliseconds: 950);
  static const bool _showWorkoutDebug = false;

  late final WorkoutTaskConfig _config;
  late final WorkoutPoseAnalyzer _analyzer;

  PoseDetector? _poseDetector;
  CameraController? _controller;
  CameraDescription? _camera;
  Widget? _cameraPreview;

  Timer? _sessionTimer;
  Future<bool>? _cameraStartFuture;
  Future<void>? _cameraStopFuture;
  Future<void>? _activeAnalysis;
  Future<void>? _shutdownFuture;

  bool _cameraWanted = false;
  bool _cameraInitializing = true;
  bool _processing = false;
  bool _closing = false;
  bool _finishing = false;
  bool _userPaused = false;
  bool _lifecyclePaused = false;
  bool _resumeWarmup = false;
  int _cameraGeneration = 0;

  WorkoutSessionState _state = WorkoutSessionState.preparing;
  _WorkoutWarning? _warning;
  WorkoutPoseObservation? _observation;

  String _status = 'Step back so TaskProof can see you';
  String? _cameraError;
  String _renderSignature = '';
  String? _formCandidate;
  String? _formFeedback;

  int _repetitions = 0;
  Duration _validExerciseTime = Duration.zero;
  Duration _restElapsed = Duration.zero;

  DateTime _lastAnalysisStarted = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastPersonSeen;
  DateTime? _lastJumpingJackSignalsSeen;
  DateTime? _readySince;
  DateTime? _countdownStarted;
  DateTime? _pushUpCountdownUnreadySince;
  DateTime? _exerciseInvalidSince;
  DateTime? _restStarted;
  DateTime? _coverageLostSince;
  DateTime? _formCandidateSince;
  DateTime? _lastTick;
  bool _exerciseValid = false;
  bool _restHapticSent = false;
  bool _jumpingJackBaselineLatched = false;
  int _countdownSeconds = 3;

  bool get _suspended => _userPaused || _lifecyclePaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final config = widget.task.workoutConfig;
    if (config == null) {
      throw StateError('Workout task is missing WorkoutTaskConfig.');
    }
    _config = config;
      unawaited(_applySavedOrientation());
    _analyzer = WorkoutPoseAnalyzer(
      exercise: config.exercise,
      movementType: config.movementType,
      sensitivity: widget.task.sensitivity,
      formChecking: config.formChecking,
    );
    _sessionTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _sessionTick(),
    );
    unawaited(_initialize());
  }

  Future<void> _applySavedOrientation() async {
  if (_config.cameraOrientation ==
      WorkoutCameraOrientation.landscape) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }
}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closing = true;
    _sessionTimer?.cancel();
    unawaited(_shutdown());
    unawaited(_restorePortraitOrientation());
    super.dispose();
  }

Future<void> _restorePortraitOrientation() async {
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing || _finishing) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_lifecyclePaused) {
        _lifecyclePaused = true;
        _pauseVerification();
        unawaited(_stopCamera());
      }
      return;
    }
    if (state == AppLifecycleState.resumed && _lifecyclePaused) {
      _lifecyclePaused = false;
      if (!_userPaused) unawaited(_resumeVerification());
    }
  }

  Future<void> _initialize() async {
    if (!MlKitCameraImageConverter.supported) {
      _cameraInitializing = false;
      _cameraError = 'Workout verification requires Android or iPhone.';
      _status = _cameraError!;
      _refresh();
      return;
    }
  _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      // Push-ups use the higher-precision landmark model.
      // Other workouts keep the existing base model.
      model:
          _config.exercise == WorkoutExercise.pushUps
          ? PoseDetectionModel.accurate
          : PoseDetectionModel.base,
      mode: PoseDetectionMode.stream,
    ),
  );

  await _startCamera();
  }

  Future<bool> _startCamera() {
    final existing = _cameraStartFuture;
    if (existing != null) return existing;
    late final Future<bool> future;
    future = _performCameraStart();
    _cameraStartFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_cameraStartFuture, future)) _cameraStartFuture = null;
      }),
    );
    return future;
  }

  Future<bool> _performCameraStart() async {
    final stopping = _cameraStopFuture;
    if (stopping != null) await stopping;
    if (_closing || _suspended) return false;
    if (_controller?.value.isInitialized ?? false) return true;

    _cameraWanted = true;
    _cameraInitializing = true;
    _cameraError = null;
    final generation = ++_cameraGeneration;
    CameraController? local;
    _refresh();

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera was found.');
      final camera = cameras.firstWhere(
        (candidate) => candidate.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      local = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: MlKitCameraImageConverter.cameraFormat,
      );
      await local.initialize();
      if (!_cameraStartCurrent(generation)) {
        await _disposeLocal(local);
        return false;
      }
      try {
        await local.lockCaptureOrientation(
          _config.cameraOrientation == WorkoutCameraOrientation.landscape
              ? DeviceOrientation.landscapeLeft
              : DeviceOrientation.portraitUp,
        );
      } catch (_) {}
      if (!_cameraStartCurrent(generation)) {
        await _disposeLocal(local);
        return false;
      }
      _camera = camera;
      _controller = local;
      await local.startImageStream(_onCameraImage);
      if (!_cameraStartCurrent(generation)) {
        if (identical(_controller, local)) _controller = null;
        await _disposeLocal(local);
        return false;
      }
      _cameraPreview = _WorkoutCameraView(controller: local);
      _cameraInitializing = false;
      _status = 'Step back so TaskProof can see you';
      _lastAnalysisStarted = DateTime.fromMillisecondsSinceEpoch(0);
      _refresh();
      return true;
    } catch (error, stackTrace) {
      debugPrint('Workout camera initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (local != null) {
        if (identical(_controller, local)) _controller = null;
        await _disposeLocal(local);
      }
      _cameraInitializing = false;
      _cameraError = error is CameraException
          ? 'Camera unavailable: ${error.description ?? error.code}'
          : 'Could not start the camera.';
      _status = _cameraError!;
      _refresh();
      return false;
    }
  }

  bool _cameraStartCurrent(int generation) =>
      mounted &&
      !_closing &&
      !_suspended &&
      _cameraWanted &&
      generation == _cameraGeneration;

  Future<void> _disposeLocal(CameraController controller) async {
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
    if (existing != null) return existing;
    late final Future<void> future;
    future = _performCameraStop();
    _cameraStopFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_cameraStopFuture, future)) _cameraStopFuture = null;
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
    final analysis = _activeAnalysis;
    if (analysis != null) {
      try {
        await analysis;
      } catch (_) {}
    }
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _shutdown() {
    return _shutdownFuture ??= _performShutdown();
  }

  Future<void> _performShutdown() async {
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
  }

  void _onCameraImage(CameraImage image) {
    if (_processing || _closing || _suspended || !_cameraWanted) return;
    final controller = _controller;
    final camera = _camera;
    final detector = _poseDetector;
    if (controller == null ||
        camera == null ||
        detector == null ||
        !controller.value.isInitialized) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastAnalysisStarted) < _analysisInterval) return;
    final frame = MlKitCameraImageConverter.convert(
      image: image,
      camera: camera,
      deviceOrientation: controller.value.deviceOrientation,
    );
    if (frame == null) return;
    _lastAnalysisStarted = now;
    _processing = true;
    late final Future<void> analysis;
    analysis = _analyzeFrame(detector, frame, now).whenComplete(() {
      if (identical(_activeAnalysis, analysis)) _activeAnalysis = null;
      _processing = false;
    });
    _activeAnalysis = analysis;
  }

  Future<void> _analyzeFrame(
    PoseDetector detector,
    MlKitCameraFrame frame,
    DateTime timestamp,
  ) async {
    try {
      final poses = await detector.processImage(frame.inputImage);
      if (_closing || _suspended) return;
      final observation = _analyzer.analyzePoses(
        poses: poses,
        imageSize: frame.imageSize,
        timestamp: timestamp,
      );
      _applyObservation(observation, DateTime.now());
    } catch (error, stackTrace) {
      debugPrint('Workout pose analysis error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _applyObservation(WorkoutPoseObservation observation, DateTime now) {
    _observation = observation;

    if (observation.personPresent) {
      _lastPersonSeen = now;
    }

    final jumpingJackDebug = observation.jumpingJackDebug;

    if (jumpingJackDebug?.signalsAvailable == true) {
      _lastJumpingJackSignalsSeen = now;
    }

    if (jumpingJackDebug?.baselineReady == true) {
      _jumpingJackBaselineLatched = true;
    }

    if (_state == WorkoutSessionState.preparing) {
      if (_config.exercise == WorkoutExercise.jumpingJacks) {
        final signalsSeen = _lastJumpingJackSignalsSeen;
        final signalsRecentlyAvailable =
            signalsSeen != null &&
            now.difference(signalsSeen) <= _jumpingJackReadinessGrace;
        final ready = _jumpingJackBaselineLatched && signalsRecentlyAvailable;

        if (ready) {
          _readySince ??= now;
          _status = 'Camera position looks good';
          final readyDuration = _resumeWarmup
              ? const Duration(milliseconds: 400)
              : _initialReadyDuration;
          if (now.difference(_readySince!) >= readyDuration) {
            _beginCountdown(resume: _resumeWarmup);
          }
        } else {
          _readySince = null;
          _status = workoutCameraGuidance(_config.exercise, observation);
        }
        _refresh();
        return;
      }

      _status = workoutCameraGuidance(_config.exercise, observation);
      if (observation.cameraReady) {
        _readySince ??= now;
        final readyDuration = _resumeWarmup
          ? const Duration(milliseconds: 400)
          : _config.exercise == WorkoutExercise.pushUps
          ? _pushUpReadyDuration
          : _initialReadyDuration;
        if (now.difference(_readySince!) >= readyDuration) {
          _beginCountdown(resume: _resumeWarmup);
        }
      } else {
        _readySince = null;
      }
      _refresh();
      return;
    }

    if (_state == WorkoutSessionState.countdown) {
      if (_config.exercise ==
          WorkoutExercise.pushUps) {
        final debug =
            observation.pushUpDebug;

        final coreSignalsHealthy =
            observation.personPresent &&
            debug != null &&
            debug.signalsAvailable &&
            debug.torsoHorizontal;

        if (coreSignalsHealthy) {
          _pushUpCountdownUnreadySince = null;
        } else {
          _pushUpCountdownUnreadySince ??= now;

          if (now.difference(
                _pushUpCountdownUnreadySince!,
              ) >=
              _pushUpCountdownGrace) {
            _cancelCountdown();
          }
        }

        _refresh();
        return;
      }

      final signalsSeen =
          _lastJumpingJackSignalsSeen;

      final jumpingJackSignalsRecentlyAvailable =
          _config.exercise ==
                  WorkoutExercise.jumpingJacks &&
              _jumpingJackBaselineLatched &&
              signalsSeen != null &&
              now.difference(signalsSeen) <=
                  _jumpingJackReadinessGrace;

      if (!observation.cameraReady &&
          !jumpingJackSignalsRecentlyAvailable) {
        _cancelCountdown();
      }

      _refresh();
      return;
    }

    if (_state == WorkoutSessionState.paused ||
        _state == WorkoutSessionState.completed) {
      return;
    }

    if (!observation.personPresent) {
      _exerciseValid = false;
      _refresh();
      return;
    }
    if (_config.exercise != WorkoutExercise.jumpingJacks &&
        (observation.tooClose ||
            observation.coverage == WorkoutBodyCoverage.insufficient)) {
      _exerciseValid = false;
      _status = workoutCameraGuidance(_config.exercise, observation);
      _coverageLostSince ??= now;
      if (now.difference(_coverageLostSince!) >=
          const Duration(milliseconds: 900)) {
        _warning = _WorkoutWarning.coverage;
        _state = WorkoutSessionState.warning;
      }
      _refresh();
      return;
    }
    _coverageLostSince = null;

    if (_warning == _WorkoutWarning.personMissing ||
        _warning == _WorkoutWarning.coverage) {
      _warning = null;
      _state = WorkoutSessionState.exercising;
      _status = 'Ready';
    }

    _updateFormFeedback(observation.formFeedback, now);
    _exerciseValid = switch (_config.movementType) {
      WorkoutMovementType.hold => observation.exercisePoseValid,
      WorkoutMovementType.continuous => observation.exerciseActive,
      WorkoutMovementType.repetitions => observation.exerciseActive,
    };

    final resumedExercise = switch (_config.movementType) {
      WorkoutMovementType.hold => observation.exercisePoseValid,
      WorkoutMovementType.continuous => observation.exerciseActive,
      WorkoutMovementType.repetitions =>
        _config.exercise == WorkoutExercise.jumpingJacks
            ? observation.exerciseActive
            : observation.exerciseActive || observation.meaningfulMovement,
    };
    if (resumedExercise) {
      _exerciseInvalidSince = null;
      _restStarted = null;
      _restElapsed = Duration.zero;
      _restHapticSent = false;
      if (_state == WorkoutSessionState.resting ||
          _warning == _WorkoutWarning.restLimit ||
          _warning == _WorkoutWarning.coverage ||
          _warning == _WorkoutWarning.personMissing) {
        _state = WorkoutSessionState.exercising;
        _warning = null;
      }
    }

    if (_config.movementType == WorkoutMovementType.repetitions &&
        observation.repCounted) {
      _repetitions++;
      _status = 'Rep counted';
      unawaited(HapticFeedback.selectionClick());
      if (_repetitions >= _config.repGoal) {
        unawaited(_completeWorkout());
      }
    } else if (_formFeedback != null) {
      _status = _formFeedback!;
    } else if (_exerciseValid) {
      _status = _config.movementType == WorkoutMovementType.hold
          ? 'Hold steady'
          : 'Keep going';
    }
    _refresh();
  }

  void _updateFormFeedback(String? feedback, DateTime now) {
    if (feedback != _formCandidate) {
      _formCandidate = feedback;
      _formCandidateSince = now;
      if (feedback == null) _formFeedback = null;
      return;
    }
    if (feedback != null &&
        _formCandidateSince != null &&
        now.difference(_formCandidateSince!) >=
            const Duration(milliseconds: 700)) {
      _formFeedback = feedback;
    }
  }

  void _beginCountdown({required bool resume}) {
    _countdownSeconds = resume ? 1 : 3;
    _countdownStarted = DateTime.now();
    _pushUpCountdownUnreadySince = null;
    _state = WorkoutSessionState.countdown;
    _status = 'Ready';
    _resumeWarmup = false;
    _refresh();
  }

  void _cancelCountdown() {
    _state = WorkoutSessionState.preparing;
    _countdownStarted = null;
    _pushUpCountdownUnreadySince = null;
    _readySince = null;
    _status =
        workoutCameraGuidance(
          _config.exercise,
          _observation,
        );
  }

  void _startExercise(DateTime now) {
    // Clear any in-progress cycle while retaining the closed Jumping Jack
    // stance learned during preparation/countdown.
    _analyzer.resetRepPhase();
   _state = WorkoutSessionState.exercising;
    _warning = null;
    _countdownStarted = null;
    _pushUpCountdownUnreadySince = null;
    _lastTick = now;
    _lastPersonSeen = now;
    _exerciseValid = false;
    widget.task.startedAt ??= now;
    _status = 'Begin ${workoutExerciseLabel(_config.exercise)}';
    _refresh();
  }

  void _sessionTick() {
    if (!mounted || _closing || _finishing) return;
    final now = DateTime.now();
    final previous = _lastTick;
    _lastTick = now;
    final delta = previous == null
        ? Duration.zero
        : _capDuration(
            now.difference(previous),
            const Duration(milliseconds: 250),
          );

    if (_state == WorkoutSessionState.countdown) {
      final started = _countdownStarted;
      if (started != null) {
        final elapsed = now.difference(started);
        if (elapsed >= Duration(seconds: _countdownSeconds)) {
          _startExercise(now);
          return;
        }
      }
      _refresh();
      return;
    }

    if (_state == WorkoutSessionState.preparing ||
        _state == WorkoutSessionState.paused ||
        _state == WorkoutSessionState.completed) {
      _refresh();
      return;
    }

    final personSeen = _lastPersonSeen;
    if (personSeen == null || now.difference(personSeen) > _personLossGrace) {
      _exerciseValid = false;
      _state = WorkoutSessionState.warning;
      _warning = _WorkoutWarning.personMissing;
      _status = 'Return to camera';
      if (_config.exercise == WorkoutExercise.jumpingJacks) {
        _analyzer.resetRepPhase();
      } else {
        _analyzer.reset();
      }
      _refresh();
      return;
    }

    // One dropped detector frame is not a rest and must not turn the workout
    // red. The person-loss branch above takes over only after its grace period.
    if (!(_observation?.personPresent ?? false)) {
      _refresh();
      return;
    }

    final coverageLost = _coverageLostSince;
    if (coverageLost != null &&
        now.difference(coverageLost) < const Duration(milliseconds: 900)) {
      _refresh();
      return;
    }

    if (_warning == _WorkoutWarning.coverage) {
      _refresh();
      return;
    }

    if (_config.movementType == WorkoutMovementType.hold ||
        _config.movementType == WorkoutMovementType.continuous) {
      if (_exerciseValid) {
        _exerciseInvalidSince = null;
        _validExerciseTime += delta;
        _state = WorkoutSessionState.exercising;
        _warning = null;
        _restStarted = null;
        _restElapsed = Duration.zero;
        if (_validExerciseTime >= _config.targetDuration) {
          _validExerciseTime = _config.targetDuration;
          unawaited(_completeWorkout());
          return;
        }
      } else {
        _exerciseInvalidSince ??= now;
        if (now.difference(_exerciseInvalidSince!) >= _exerciseLossGrace) {
          _beginOrAdvanceRest(now);
        }
      }
    } else {
      // Repetition workouts are goal-driven, not time-driven. Pausing between
      // reps never starts a rest timer or inactivity warning.
      _state = WorkoutSessionState.exercising;
      _warning = null;
      _restStarted = null;
      _restElapsed = Duration.zero;
      _restHapticSent = false;
    }
    _refresh();
  }

  void _beginOrAdvanceRest(DateTime now) {
    _restStarted ??= now;
    _restElapsed = now.difference(_restStarted!);
    if (_restElapsed >= _config.restLimit) {
      _state = WorkoutSessionState.warning;
      _warning = _WorkoutWarning.restLimit;
      _status = 'Rest limit exceeded';
      if (!_restHapticSent) {
        _restHapticSent = true;
        unawaited(HapticFeedback.heavyImpact());
      }
    } else {
      _state = WorkoutSessionState.resting;
      _warning = null;
      _status = 'Resting';
    }
  }

  void _pauseVerification() {
    _analyzer.reset();
    _jumpingJackBaselineLatched = false;
    _lastJumpingJackSignalsSeen = null;
    _exerciseValid = false;
    _state = WorkoutSessionState.paused;
    _pushUpCountdownUnreadySince = null;
    _status = 'Workout paused';
    _lastTick = null;
    _restStarted = null;
    _exerciseInvalidSince = null;
    _refresh();
  }

  Future<void> _togglePause() async {
    if (_userPaused) {
      _userPaused = false;
      await _resumeVerification();
    } else {
      _userPaused = true;
      _pauseVerification();
      await _stopCamera();
    }
  }

  Future<void> _resumeVerification() async {
    if (_closing || _lifecyclePaused || _userPaused) return;
    _resumeWarmup = true;
     _state = WorkoutSessionState.preparing;
    _status = 'Restarting camera';
    _readySince = null;
    _pushUpCountdownUnreadySince = null;
    _lastPersonSeen = null;
    _lastJumpingJackSignalsSeen = null;
    _analyzer.reset();
    _jumpingJackBaselineLatched = false;
    _lastTick = DateTime.now();
    _refresh();
    await _startCamera();
  }

  Future<void> _completeWorkout() async {
    if (_finishing || _closing || _state == WorkoutSessionState.completed) {
      return;
    }
    _finishing = true;
    _state = WorkoutSessionState.completed;
    _status = 'Workout complete';
    widget.task.status = TaskStatus.completed;
    widget.task.completedAt = DateTime.now();
    _sessionTimer?.cancel();
    _refresh();
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _shutdown();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmEnd() async {
    if (_finishing || _closing) return;
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End workout?'),
        content: const Text(
          'Your current workout progress will not be completed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    if (end != true || !mounted) return;
    _finishing = true;
    widget.task.status = TaskStatus.ready;
    widget.task.startedAt = null;
    widget.task.completedAt = null;
    await _shutdown();
    if (mounted) Navigator.pop(context);
  }

  void _refresh() {
    if (!mounted || (_closing && !_finishing)) return;
    final debug = _observation?.jumpingJackDebug;

    final signature =
        '${_state.name}|$_status|$_cameraInitializing|'
        '$_cameraError|$_repetitions|${_validExerciseTime.inSeconds}|'
        '${_restElapsed.inSeconds}|${_countdownValue()}|${_observation?.coverage.name}|'
        '${_observation?.tooClose}|$_userPaused|'
        '${debug?.signalsAvailable}|${debug?.baselineReady}|'
        '${debug?.armsOpen}|${debug?.armsClosed}|'
        '${debug?.kneesOpen}|${debug?.kneesClosed}|'
        '${debug?.kneeSpreadRatio}|${debug?.phase.name}|'
        '${_observation?.overlayLandmarks}';
    if (signature == _renderSignature) return;
    _renderSignature = signature;
    setState(() {});
  }

  int _countdownValue() {
    final started = _countdownStarted;
    if (_state != WorkoutSessionState.countdown || started == null) return 0;
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    return (_countdownSeconds - elapsed / 1000).ceil().clamp(
      1,
      _countdownSeconds,
    );
  }

  Color get _accentColor {
    if (_state == WorkoutSessionState.warning) return _red;
    if (_state == WorkoutSessionState.exercising && _exerciseValid) {
      return _green;
    }
    if (_state == WorkoutSessionState.completed) return _green;
    return Colors.white;
  }

  Color get _trackerColor {
    final observation = _observation;

    if (_config.exercise == WorkoutExercise.jumpingJacks) {
      final debug = observation?.jumpingJackDebug;
      final readyToCount =
          debug != null && debug.baselineReady && debug.signalsAvailable;

      return readyToCount ? _green : Colors.white;
    }

    return observation?.cameraReady == true ? _green : Colors.white;
  }

  String get _goalText {
    if (_config.movementType == WorkoutMovementType.repetitions) {
      return '$_repetitions / ${_config.repGoal}';
    }
    return '${_formatDuration(_validExerciseTime)} / '
        '${_formatDuration(_config.targetDuration)}';
  }

  String get _goalLabel => switch (_config.movementType) {
    WorkoutMovementType.repetitions => 'REPS',
    WorkoutMovementType.hold => 'HOLD TIME',
    WorkoutMovementType.continuous => 'ACTIVE TIME',
  };

  @override
  Widget build(BuildContext context) {
    final background = widget.isDarkMode
        ? const Color(0xFF090B0E)
        : const Color(0xFFF3F4F6);

    final foreground = widget.isDarkMode
        ? Colors.white
        : const Color(0xFF111318);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmEnd());
      },
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Column(
                  children: [
                    Text(
                      widget.task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      workoutExerciseLabel(_config.exercise),
                      style: const TextStyle(
                        color: Color(0xFF777A84),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _cameraBody(),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _WorkoutSkeletonPainter(
                              landmarks:
                                  _observation?.overlayLandmarks ?? const {},
                              color: _trackerColor,
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _WorkoutFramePainter(color: _accentColor),
                          ),
                        ),
                        Positioned(
                          top: 14,
                          left: 14,
                          right: 14,
                          child: Center(child: _statusPill()),
                        ),
                        if (_showWorkoutDebug &&
                            _config.exercise == WorkoutExercise.jumpingJacks)
                          Positioned(
                            top: 60,
                            left: 14,
                            child: _jumpingJackDebugPanel(),
                          ),
                        if (_state == WorkoutSessionState.countdown)
                          Center(
                            child: Text(
                              '${_countdownValue()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 92,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(blurRadius: 18, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                        if (_state == WorkoutSessionState.paused)
                          const ColoredBox(
                            color: Color(0x99000000),
                            child: Center(
                              child: Text(
                                'PAUSED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                child: Column(
                  children: [
                    Text(
                      _goalText,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _goalLabel,
                      style: const TextStyle(
                        color: Color(0xFF777A84),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    if (_config.movementType !=
                            WorkoutMovementType.repetitions &&
                        (_state == WorkoutSessionState.resting ||
                            _warning == _WorkoutWarning.restLimit)) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Rest ${_formatDuration(_restElapsed)} / '
                        '${_formatDuration(_config.restLimit)}',
                        style: TextStyle(
                          color: _warning == _WorkoutWarning.restLimit
                              ? _red
                              : foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _finishing || _lifecyclePaused
                            ? null
                            : () => unawaited(_togglePause()),
                        icon: Icon(
                          _userPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        label: Text(_userPaused ? 'Resume' : 'Pause'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: foreground,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _finishing ? null : _confirmEnd,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('End Session'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _red,
                          minimumSize: const Size.fromHeight(48),
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

  Widget _cameraBody() {
    final preview = _cameraPreview;
    if (preview != null) return preview;
    return ColoredBox(
      color: const Color(0xFF111318),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_cameraInitializing)
                const CircularProgressIndicator(color: Colors.white)
              else
                const Icon(
                  Icons.videocam_off_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              const SizedBox(height: 14),
              Text(
                _cameraError ?? 'Starting camera…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              if (_cameraError != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => unawaited(_startCamera()),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xD914171B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accentColor.withValues(alpha: .75)),
      ),
      child: Text(
        _status,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _accentColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _jumpingJackDebugPanel() {
    final debug = _observation?.jumpingJackDebug;
    String posture(bool open, bool closed) => open
        ? 'OPEN'
        : closed
        ? 'CLOSED'
        : '—';
    return Container(
      width: 205,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xDD000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Jumping Jack Debug\n'
        'Pose: ${debug?.poseDetected == true ? 'detected' : 'missing'}\n'
        'Signals: ${debug?.signalsAvailable == true ? 'YES' : 'NO'}\n'
        'Baseline: ${debug?.baselineReady == true ? 'READY' : 'NOT READY'}\n'
        'Arms: ${posture(debug?.armsOpen == true, debug?.armsClosed == true)}\n'
        'Knees: ${posture(debug?.kneesOpen == true, debug?.kneesClosed == true)}\n'
        'Knee spread ratio: '
        '${debug?.kneeSpreadRatio.toStringAsFixed(2) ?? '—'}\n'
        'Vertical motion: ${debug?.verticalMotion == true ? 'yes' : 'no'}\n'
        'Phase: ${debug?.phase.name ?? '—'}\n'
        'Reps: $_repetitions',
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 10,
          height: 1.25,
        ),
      ),
    );
  }
}

class _WorkoutCameraView extends StatelessWidget {
  const _WorkoutCameraView({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const ColoredBox(color: Colors.black);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Portrait-locked camera dimensions are the sensor dimensions with
          // their axes swapped. FittedBox covers without stretching.
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

class _WorkoutSkeletonPainter extends CustomPainter {
  const _WorkoutSkeletonPainter({required this.landmarks, required this.color});

  final Map<PoseLandmarkType, Offset> landmarks;
  final Color color;

  Offset? _point(PoseLandmarkType type, Size size) {
    final point = landmarks[type];
    if (point == null) return null;
    return Offset(point.dx * size.width, point.dy * size.height);
  }

  void _drawConnection(
    Canvas canvas,
    Paint paint,
    Size size,
    PoseLandmarkType a,
    PoseLandmarkType b,
  ) {
    final first = _point(a, size);
    final second = _point(b, size);
    if (first == null || second == null) return;
    canvas.drawLine(first, second, paint);
  }

  void _drawDot(Canvas canvas, Paint paint, Size size, PoseLandmarkType type) {
    final point = _point(type, size);
    if (point == null) return;
    canvas.drawCircle(point, 4.2, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final linePaint = Paint()
      ..color = color.withValues(alpha: .92)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const connections = [
      (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
      (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
      (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
      (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
      (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
      (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
      (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
      (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
      (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
      (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
      (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
    ];
    for (final connection in connections) {
      _drawConnection(canvas, linePaint, size, connection.$1, connection.$2);
    }

    const joints = [
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
    ];
    for (final joint in joints) {
      _drawDot(canvas, dotPaint, size, joint);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkoutSkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks || oldDelegate.color != color;
  }
}

class _WorkoutFramePainter extends CustomPainter {
  const _WorkoutFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const inset = 18.0;
    final length = mathMin(48.0, mathMin(size.width, size.height) * .12);
    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;
    canvas
      ..drawLine(Offset(left, top + length), Offset(left, top), paint)
      ..drawLine(Offset(left, top), Offset(left + length, top), paint)
      ..drawLine(Offset(right - length, top), Offset(right, top), paint)
      ..drawLine(Offset(right, top), Offset(right, top + length), paint)
      ..drawLine(Offset(left, bottom - length), Offset(left, bottom), paint)
      ..drawLine(Offset(left, bottom), Offset(left + length, bottom), paint)
      ..drawLine(Offset(right - length, bottom), Offset(right, bottom), paint)
      ..drawLine(Offset(right, bottom), Offset(right, bottom - length), paint);
  }

  @override
  bool shouldRepaint(covariant _WorkoutFramePainter oldDelegate) =>
      oldDelegate.color != color;
}

double mathMin(double first, double second) => first < second ? first : second;

Duration _capDuration(Duration value, Duration maximum) {
  if (value.isNegative) return Duration.zero;
  return value > maximum ? maximum : value;
}

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 5999);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

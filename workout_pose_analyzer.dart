// ignore_for_file: unused_element

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'new_task_page.dart' show WorkoutExercise, WorkoutMovementType;

enum WorkoutBodyCoverage { insufficient, good, excellent }

enum JumpingJackPhase { waitingForClosed, closed, opening, open, closing }

enum _PrecisionRepPhase {
  waitingForStart,
  start,
  movingToTarget,
  target,
  returning,
}

class JumpingJackDebugData {
  const JumpingJackDebugData({
    required this.poseDetected,
    required this.signalsAvailable,
    required this.baselineReady,
    required this.armsClosed,
    required this.armsOpen,
    required this.kneesClosed,
    required this.kneesOpen,
    required this.kneeSpreadRatio,
    required this.verticalMotion,
    required this.phase,
  });

  final bool poseDetected;
  final bool signalsAvailable;
  final bool baselineReady;
  final bool armsClosed;
  final bool armsOpen;
  final bool kneesClosed;
  final bool kneesOpen;
  final double kneeSpreadRatio;
  final bool verticalMotion;
  final JumpingJackPhase phase;
}

String workoutExerciseLabel(WorkoutExercise exercise) {
  return switch (exercise) {
    WorkoutExercise.pushUps => 'Push-ups',
    WorkoutExercise.squats => 'Squats',
    WorkoutExercise.jumpingJacks => 'Jumping Jacks',
    WorkoutExercise.lunges => 'Lunges',
    WorkoutExercise.sitUps => 'Sit-ups',
    WorkoutExercise.burpees => 'Burpees',
    WorkoutExercise.mountainClimbers => 'Mountain Climbers',
    WorkoutExercise.highKnees => 'High Knees',
    WorkoutExercise.plank => 'Plank',
    WorkoutExercise.wallSit => 'Wall Sit',
    WorkoutExercise.runningInPlace => 'Running in Place',
    WorkoutExercise.jumpRope => 'Jump Rope',
  };
}

String workoutCameraGuidance(
  WorkoutExercise exercise,
  WorkoutPoseObservation? observation,
) {
  if (observation == null || !observation.personPresent) {
    return switch (exercise) {
      WorkoutExercise.pushUps => 'Keep your full side profile in frame',
      WorkoutExercise.squats =>
        'Keep your shoulders, hips, knees, and ankles in frame',
      WorkoutExercise.sitUps => 'Keep your shoulder, hip, and knee in frame',
      WorkoutExercise.jumpingJacks =>
        'Keep your shoulders, hands, hips, and knees in frame',
      WorkoutExercise.lunges => 'Keep both legs and your torso in frame',
      _ => 'Step back so TaskProof can see you',
    };
  }
  if (observation.tooClose && exercise != WorkoutExercise.jumpingJacks) {
    return 'Move farther from the camera';
  }

  if (observation.repetitionTrackingEnabled) {
    if (!observation.repetitionSignalsAvailable) {
      return switch (exercise) {
        WorkoutExercise.pushUps =>
          'Keep one shoulder, elbow, wrist, hip, and knee in frame',
        WorkoutExercise.squats =>
          'Keep both hips, knees, ankles, and your torso in frame',
        WorkoutExercise.sitUps => 'Keep one shoulder, hip, and knee in frame',
        WorkoutExercise.lunges => 'Keep both legs and your torso in frame',
        _ => 'Show more of your body',
      };
    }

    if (!observation.repetitionReady) {
      return switch (exercise) {
        WorkoutExercise.pushUps => 'Hold the top push-up position',
        WorkoutExercise.squats => 'Stand tall with both legs straight',
        WorkoutExercise.sitUps => 'Lie back in the starting sit-up position',
        WorkoutExercise.lunges => 'Stand tall before beginning the lunge',
        _ => 'Get into the starting position',
      };
    }

    return 'Camera position looks good';
  }

  if (observation.coverage == WorkoutBodyCoverage.insufficient) {
    return switch (exercise) {
      WorkoutExercise.jumpingJacks =>
        'Keep your shoulders, hands, hips, and knees in frame',
      _ => 'Show more of your body',
    };
  }
  return 'Camera position looks good';
}

class WorkoutLandmark {
  const WorkoutLandmark(this.position, {this.confidence = 1});

  final Offset position;
  final double confidence;
}

class WorkoutPoseObservation {
  const WorkoutPoseObservation({
    required this.personPresent,
    required this.coverage,
    required this.tooClose,
    required this.cameraStable,
    required this.exercisePoseValid,
    required this.exerciseActive,
    required this.meaningfulMovement,
    required this.repCounted,
    required this.formFeedback,
    this.jumpingJackDebug,
    this.repetitionTrackingEnabled = false,
    this.repetitionSignalsAvailable = false,
    this.repetitionReady = false,
    this.overlayLandmarks = const {},
  });

  final bool personPresent;
  final WorkoutBodyCoverage coverage;
  final bool tooClose;
  final bool cameraStable;
  final bool exercisePoseValid;
  final bool exerciseActive;
  final bool meaningfulMovement;
  final bool repCounted;
  final String? formFeedback;
  final JumpingJackDebugData? jumpingJackDebug;
  final bool repetitionTrackingEnabled;
  final bool repetitionSignalsAvailable;
  final bool repetitionReady;
  final Map<PoseLandmarkType, Offset> overlayLandmarks;

  bool get cameraReady {
    final jumpingJack = jumpingJackDebug;

    if (jumpingJack != null) {
      return personPresent && jumpingJack.baselineReady;
    }

    if (repetitionTrackingEnabled) {
      return personPresent && !tooClose && repetitionReady;
    }

    return personPresent &&
        !tooClose &&
        coverage != WorkoutBodyCoverage.insufficient;
  }
}

/// Stateful, scale-independent exercise detector used by Workout mode.
///
/// The analyzer deliberately separates basic recognition from optional form
/// feedback. A valid movement cycle can count even when form feedback suggests
/// a small improvement.
class WorkoutPoseAnalyzer {
  WorkoutPoseAnalyzer({
    required this.exercise,
    required this.movementType,
    this.sensitivity = 0.5,
    this.formChecking = false,
  });

  static const double landmarkConfidenceThreshold = 0.45;
  static const double jumpingJackLandmarkConfidenceThreshold = 0.30;
  static const double _minimumJumpingJackHipWidth = 0.010;
  static const int _jumpingJackBaselineSampleTarget = 5;

  final WorkoutExercise exercise;
  final WorkoutMovementType movementType;
  final double sensitivity;
  final bool formChecking;

  double get _landmarkConfidenceThreshold =>
      exercise == WorkoutExercise.jumpingJacks
      ? jumpingJackLandmarkConfidenceThreshold
      : landmarkConfidenceThreshold;

  _PoseSample? _previous;
  bool _cycleStarted = false;
  bool _cycleTargetReached = false;
  int _burpeeStage = 0;
  final Map<bool, bool> _kneeReset = {false: true, true: true};
  bool? _lastDrivenRight;
  DateTime? _lastExerciseEvent;
  int _stableFrames = 0;

  _PrecisionRepPhase _precisionRepPhase = _PrecisionRepPhase.waitingForStart;
  int _precisionRepConfirmationFrames = 0;
  DateTime? _lastPrecisionRepSignalsAt;

  JumpingJackPhase _jumpingJackPhase = JumpingJackPhase.waitingForClosed;
  int _jumpingJackConfirmationFrames = 0;
  bool _jumpingJackArmsOpened = false;
  bool _jumpingJackKneesOpened = false;
  DateTime? _lastJumpingJackSignalsAt;
  final List<double> _jumpingJackKneeBaselines = [];
  final List<double> _jumpingJackHipYBaselines = [];

  bool get _jumpingJackBaselineReady =>
      _jumpingJackKneeBaselines.length >= _jumpingJackBaselineSampleTarget;

  bool get _usesPrecisionRepTracker =>
      movementType == WorkoutMovementType.repetitions &&
      (exercise == WorkoutExercise.pushUps ||
          exercise == WorkoutExercise.squats ||
          exercise == WorkoutExercise.sitUps ||
          exercise == WorkoutExercise.lunges);

  void reset() {
    _jumpingJackKneeBaselines.clear();
    _jumpingJackHipYBaselines.clear();

    _precisionRepPhase = _PrecisionRepPhase.waitingForStart;
    _precisionRepConfirmationFrames = 0;
    _lastPrecisionRepSignalsAt = null;

    resetRepPhase();
  }

  /// Clears an in-progress repetition while preserving a confirmed starting
  /// position through the preparation -> countdown transition.
  void resetRepPhase() {
    final jumpingJackWasCalibratedClosed =
        _jumpingJackPhase == JumpingJackPhase.closed &&
        _jumpingJackBaselineReady;
    final precisionWasReady =
        _usesPrecisionRepTracker &&
        _precisionRepPhase == _PrecisionRepPhase.start;
    final precisionSignalsAt = _lastPrecisionRepSignalsAt;

    _previous = null;
    _cycleStarted = false;
    _cycleTargetReached = false;
    _burpeeStage = 0;
    _kneeReset
      ..[false] = true
      ..[true] = true;
    _lastDrivenRight = null;
    _lastExerciseEvent = null;
    _stableFrames = 0;

    _precisionRepPhase = precisionWasReady
        ? _PrecisionRepPhase.start
        : _PrecisionRepPhase.waitingForStart;
    _precisionRepConfirmationFrames = 0;
    _lastPrecisionRepSignalsAt = precisionWasReady ? precisionSignalsAt : null;

    _jumpingJackPhase = jumpingJackWasCalibratedClosed
        ? JumpingJackPhase.closed
        : JumpingJackPhase.waitingForClosed;
    _jumpingJackConfirmationFrames = 0;
    _jumpingJackArmsOpened = false;
    _jumpingJackKneesOpened = false;
    _lastJumpingJackSignalsAt = null;
  }

  WorkoutPoseObservation analyzePoses({
    required List<Pose> poses,
    required Size imageSize,
    required DateTime timestamp,
  }) {
    if (imageSize.width <= 0 || imageSize.height <= 0 || poses.isEmpty) {
      return _absent();
    }

    Map<PoseLandmarkType, WorkoutLandmark>? best;
    var bestScore = -1.0;
    for (final pose in poses) {
      final landmarks = <PoseLandmarkType, WorkoutLandmark>{};
      var confidence = 0.0;
      for (final entry in pose.landmarks.entries) {
        final landmark = entry.value;
        if (landmark.likelihood < _landmarkConfidenceThreshold) {
          continue;
        }
        final point = Offset(
          landmark.x / imageSize.width,
          landmark.y / imageSize.height,
        );
        if (point.dx < -0.08 ||
            point.dx > 1.08 ||
            point.dy < -0.08 ||
            point.dy > 1.08) {
          continue;
        }
        landmarks[entry.key] = WorkoutLandmark(
          point,
          confidence: landmark.likelihood,
        );
        confidence += landmark.likelihood;
      }
      final score = landmarks.length * 10 + confidence;
      if (landmarks.length >= 4 && score > bestScore) {
        best = landmarks;
        bestScore = score;
      }
    }

    if (best == null) {
      return _absent();
    }
    return analyzeLandmarks(best, timestamp: timestamp);
  }

  /// Public synthetic-landmark entry point used by deterministic unit tests.
  /// Positions are normalized to the camera image (0..1).
  WorkoutPoseObservation analyzeLandmarks(
    Map<PoseLandmarkType, WorkoutLandmark> landmarks, {
    required DateTime timestamp,
  }) {
    final confident = <PoseLandmarkType, Offset>{};
    for (final entry in landmarks.entries) {
      if (entry.value.confidence >= _landmarkConfidenceThreshold) {
        confident[entry.key] = entry.value.position;
      }
    }
    if (confident.length < 4) {
      return _absent();
    }

    final sample = _PoseSample.from(confident, timestamp);
    final coverage = _coverage(sample.landmarks);
    final tooClose =
        exercise != WorkoutExercise.jumpingJacks &&
        (sample.bounds.width > 0.88 || sample.bounds.height > 0.94);
    final previous = _previous;
    final movement = previous == null
        ? 0.0
        : _movementBetween(previous, sample);
    final stable =
        previous != null &&
        timestamp.difference(previous.timestamp) <=
            const Duration(milliseconds: 700) &&
        (sample.center - previous.center).distance /
                math.max(sample.bodyScale, 0.05) <
            0.045;
    _stableFrames = stable ? _stableFrames + 1 : 0;

    var repCounted = false;
    var poseValid = false;
    var jumpingJackActivity = false;
    var precisionRepActivity = false;
    var repetitionSignalsAvailable = false;
    var repetitionReady = false;
    JumpingJackDebugData? jumpingJackDebug;

    if (exercise == WorkoutExercise.jumpingJacks ||
        _usesPrecisionRepTracker ||
        (coverage != WorkoutBodyCoverage.insufficient && !tooClose)) {
      switch (exercise) {
        case WorkoutExercise.pushUps:
          final update = _updatePushUp(sample);
          repCounted = update.repCounted;
          poseValid = update.poseValid;
          precisionRepActivity = update.exerciseActive;
          repetitionSignalsAvailable = update.signalsAvailable;
          repetitionReady = update.ready;
        case WorkoutExercise.squats:
          final update = _updateSquat(sample);
          repCounted = update.repCounted;
          poseValid = update.poseValid;
          precisionRepActivity = update.exerciseActive;
          repetitionSignalsAvailable = update.signalsAvailable;
          repetitionReady = update.ready;
        case WorkoutExercise.sitUps:
          final update = _updateSitUp(sample);
          repCounted = update.repCounted;
          poseValid = update.poseValid;
          precisionRepActivity = update.exerciseActive;
          repetitionSignalsAvailable = update.signalsAvailable;
          repetitionReady = update.ready;
        case WorkoutExercise.jumpingJacks:
          final update = _updateJumpingJack(sample);
          repCounted = update.repCounted;
          poseValid = update.poseValid;
          jumpingJackActivity = update.exerciseActive;
          jumpingJackDebug = update.debug;
        case WorkoutExercise.lunges:
          final update = _updateLunge(sample);
          repCounted = update.repCounted;
          poseValid = update.poseValid;
          precisionRepActivity = update.exerciseActive;
          repetitionSignalsAvailable = update.signalsAvailable;
          repetitionReady = update.ready;
        case WorkoutExercise.burpees:
          repCounted = _burpee(sample.landmarks);
          poseValid = _burpeeStage > 0;
        case WorkoutExercise.mountainClimbers:
          poseValid = _isHorizontal(sample.landmarks);
          repCounted = poseValid
              ? _kneeDrive(sample.landmarks, mountainClimber: true)
              : false;
        case WorkoutExercise.highKnees:
          repCounted = _kneeDrive(sample.landmarks, mountainClimber: false);
          poseValid = true;
        case WorkoutExercise.plank:
          poseValid = _plankValid(sample.landmarks);
        case WorkoutExercise.wallSit:
          poseValid = _wallSitValid(sample.landmarks);
        case WorkoutExercise.runningInPlace:
          repCounted = _kneeDrive(
            sample.landmarks,
            mountainClimber: false,
            running: true,
          );
          poseValid = true;
        case WorkoutExercise.jumpRope:
          poseValid = _jumpRopeMovement(sample, previous);
      }
    } else {
      _stableFrames = 0;
    }

    if (repCounted) {
      _lastExerciseEvent = timestamp;
    }

    final movementFloor = _lerp(0.052, 0.026, sensitivity.clamp(0.0, 1.0));
    final meaningfulMovement = movement >= movementFloor;
    final recentEvent =
        _lastExerciseEvent != null &&
        timestamp.difference(_lastExerciseEvent!) <=
            const Duration(milliseconds: 950);
    final exerciseActive = switch (movementType) {
      WorkoutMovementType.hold => poseValid,
      WorkoutMovementType.continuous =>
        exercise == WorkoutExercise.jumpingJacks
            ? jumpingJackActivity
            : poseValid && (recentEvent || meaningfulMovement),
      WorkoutMovementType.repetitions =>
        exercise == WorkoutExercise.jumpingJacks
            ? jumpingJackActivity
            : _usesPrecisionRepTracker
            ? precisionRepActivity
            : repCounted || (_cycleStarted && meaningfulMovement),
    };

    _previous = sample;
    return WorkoutPoseObservation(
      personPresent: true,
      coverage: coverage,
      tooClose: tooClose,
      cameraStable: _stableFrames >= 4,
      exercisePoseValid: poseValid,
      exerciseActive: exerciseActive,
      meaningfulMovement: meaningfulMovement,
      repCounted: repCounted,
      formFeedback: formChecking ? _formFeedback(sample.landmarks) : null,
      jumpingJackDebug: jumpingJackDebug,
      repetitionTrackingEnabled: _usesPrecisionRepTracker,
      repetitionSignalsAvailable: repetitionSignalsAvailable,
      repetitionReady: repetitionReady,
      overlayLandmarks: {
        for (final entry in sample.landmarks.entries) entry.key: entry.value,
      },
    );
  }

  WorkoutPoseObservation _absent() {
    _stableFrames = 0;
    return const WorkoutPoseObservation(
      personPresent: false,
      coverage: WorkoutBodyCoverage.insufficient,
      tooClose: false,
      cameraStable: false,
      exercisePoseValid: false,
      exerciseActive: false,
      meaningfulMovement: false,
      repCounted: false,
      formFeedback: null,
      overlayLandmarks: {},
    );
  }

  // ignore: duplicate_ignore
  // ignore: unused_element
  double get _extendedThreshold => _lerp(158, 150, sensitivity);
  // ignore: duplicate_ignore
  // ignore: unused_element
  double get _deepKneeThreshold => _lerp(100, 112, sensitivity);
  double get _flexedElbowThreshold => _lerp(92, 105, sensitivity);
  double get _lungeThreshold => _lerp(105, 118, sensitivity);

  _PrecisionRepUpdate _updatePushUp(_PoseSample sample) {
    final points = sample.landmarks;
    final topThreshold = _lerp(156, 150, sensitivity);
    final bottomThreshold = _lerp(105, 115, sensitivity);

    var signalsAvailable = false;
    var validPushUpShape = false;
    var top = false;
    var bottom = false;

    for (final right in const [false, true]) {
      final shoulder =
          points[right
              ? PoseLandmarkType.rightShoulder
              : PoseLandmarkType.leftShoulder];
      final elbow =
          points[right
              ? PoseLandmarkType.rightElbow
              : PoseLandmarkType.leftElbow];
      final wrist =
          points[right
              ? PoseLandmarkType.rightWrist
              : PoseLandmarkType.leftWrist];
      final hip =
          points[right ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip];
      final knee =
          points[right
              ? PoseLandmarkType.rightKnee
              : PoseLandmarkType.leftKnee];

      if (shoulder == null ||
          elbow == null ||
          wrist == null ||
          hip == null ||
          knee == null) {
        continue;
      }

      signalsAvailable = true;
      final elbowAngle = _angle(shoulder, elbow, wrist);
      final bodyAlignment = _angle(shoulder, hip, knee);
      final torsoVector = shoulder - hip;
      final horizontal = torsoVector.dx.abs() > torsoVector.dy.abs() * 0.75;
      final straightBody = bodyAlignment >= 145;

      if (horizontal && straightBody) {
        validPushUpShape = true;
        if (elbowAngle >= topThreshold) top = true;
        if (elbowAngle <= bottomThreshold) bottom = true;
      }
    }

    return _updatePrecisionRepCycle(
      timestamp: sample.timestamp,
      signalsAvailable: signalsAvailable,
      startCandidate: top,
      targetCandidate: bottom,
      poseValid: signalsAvailable && validPushUpShape,
    );
  }

  _PrecisionRepUpdate _updateSquat(_PoseSample sample) {
    final points = sample.landmarks;
    final leftHip = points[PoseLandmarkType.leftHip];
    final rightHip = points[PoseLandmarkType.rightHip];
    final leftKnee = points[PoseLandmarkType.leftKnee];
    final rightKnee = points[PoseLandmarkType.rightKnee];
    final leftAnkle = points[PoseLandmarkType.leftAnkle];
    final rightAnkle = points[PoseLandmarkType.rightAnkle];
    final shoulderCenter = _center(points, const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    ]);
    final hipCenter = _center(points, const [
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]);
    final signalsAvailable =
        leftHip != null &&
        rightHip != null &&
        leftKnee != null &&
        rightKnee != null &&
        leftAnkle != null &&
        rightAnkle != null &&
        shoulderCenter != null &&
        hipCenter != null;

    if (!signalsAvailable) {
      return _updatePrecisionRepCycle(
        timestamp: sample.timestamp,
        signalsAvailable: false,
        startCandidate: false,
        targetCandidate: false,
        poseValid: false,
      );
    }

    final leftAngle = _angle(leftHip, leftKnee, leftAnkle);
    final rightAngle = _angle(rightHip, rightKnee, rightAnkle);
    final torsoVector = shoulderCenter - hipCenter;
    final upright = torsoVector.dy.abs() > torsoVector.dx.abs() * 0.75;
    final angleDifference = (leftAngle - rightAngle).abs();
    final leftThighX = (leftKnee.dx - leftHip.dx).abs();
    final rightThighX = (rightKnee.dx - rightHip.dx).abs();
    final leftThighY = (leftKnee.dy - leftHip.dy).abs();
    final rightThighY = (rightKnee.dy - rightHip.dy).abs();
    final geometryAsymmetry =
        ((leftThighX - rightThighX).abs() + (leftThighY - rightThighY).abs()) /
        sample.bodyScale;
    final standingThreshold = _lerp(154, 148, sensitivity);
    final squatDepthThreshold = _lerp(112, 126, sensitivity);
    final standing =
        upright &&
        leftAngle >= standingThreshold &&
        rightAngle >= standingThreshold;
    final bottom =
        upright &&
        leftAngle <= squatDepthThreshold &&
        rightAngle <= squatDepthThreshold &&
        angleDifference <= 24 &&
        geometryAsymmetry <= 0.20;

    return _updatePrecisionRepCycle(
      timestamp: sample.timestamp,
      signalsAvailable: true,
      startCandidate: standing,
      targetCandidate: bottom,
      poseValid: upright,
    );
  }

  _PrecisionRepUpdate _updateLunge(_PoseSample sample) {
    final points = sample.landmarks;
    final leftHip = points[PoseLandmarkType.leftHip];
    final rightHip = points[PoseLandmarkType.rightHip];
    final leftKnee = points[PoseLandmarkType.leftKnee];
    final rightKnee = points[PoseLandmarkType.rightKnee];
    final leftAnkle = points[PoseLandmarkType.leftAnkle];
    final rightAnkle = points[PoseLandmarkType.rightAnkle];
    final shoulderCenter = _center(points, const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    ]);
    final hipCenter = _center(points, const [
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]);
    final signalsAvailable =
        leftHip != null &&
        rightHip != null &&
        leftKnee != null &&
        rightKnee != null &&
        leftAnkle != null &&
        rightAnkle != null &&
        shoulderCenter != null &&
        hipCenter != null;

    if (!signalsAvailable) {
      return _updatePrecisionRepCycle(
        timestamp: sample.timestamp,
        signalsAvailable: false,
        startCandidate: false,
        targetCandidate: false,
        poseValid: false,
      );
    }

    final leftAngle = _angle(leftHip, leftKnee, leftAnkle);
    final rightAngle = _angle(rightHip, rightKnee, rightAnkle);
    final torsoVector = shoulderCenter - hipCenter;
    final upright = torsoVector.dy.abs() > torsoVector.dx.abs() * 0.70;
    final angleDifference = (leftAngle - rightAngle).abs();
    final leftThighX = (leftKnee.dx - leftHip.dx).abs();
    final rightThighX = (rightKnee.dx - rightHip.dx).abs();
    final leftThighY = (leftKnee.dy - leftHip.dy).abs();
    final rightThighY = (rightKnee.dy - rightHip.dy).abs();
    final geometryAsymmetry =
        ((leftThighX - rightThighX).abs() + (leftThighY - rightThighY).abs()) /
        sample.bodyScale;
    final standingThreshold = _lerp(152, 146, sensitivity);
    final lungeDepthThreshold = _lerp(108, 122, sensitivity);
    final standing =
        upright &&
        leftAngle >= standingThreshold &&
        rightAngle >= standingThreshold;
    final deepestKnee = math.min(leftAngle, rightAngle);
    final asymmetricLunge = angleDifference >= 18 || geometryAsymmetry >= 0.11;
    final bottom =
        upright && deepestKnee <= lungeDepthThreshold && asymmetricLunge;

    return _updatePrecisionRepCycle(
      timestamp: sample.timestamp,
      signalsAvailable: true,
      startCandidate: standing,
      targetCandidate: bottom,
      poseValid: upright,
    );
  }

  _PrecisionRepUpdate _updateSitUp(_PoseSample sample) {
    final points = sample.landmarks;
    final reclinedThreshold = _lerp(140, 132, sensitivity);
    final uprightThreshold = _lerp(92, 106, sensitivity);

    var signalsAvailable = false;
    var reclined = false;
    var upright = false;

    for (final right in const [false, true]) {
      final shoulder =
          points[right
              ? PoseLandmarkType.rightShoulder
              : PoseLandmarkType.leftShoulder];
      final hip =
          points[right ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip];
      final knee =
          points[right
              ? PoseLandmarkType.rightKnee
              : PoseLandmarkType.leftKnee];

      if (shoulder == null || hip == null || knee == null) continue;

      signalsAvailable = true;
      final hipAngle = _angle(shoulder, hip, knee);
      final torsoVector = shoulder - hip;
      final torsoLength = math.max(torsoVector.distance, 0.05);
      final torsoReclined = torsoVector.dx.abs() > torsoVector.dy.abs() * 0.55;
      final torsoRaised = hip.dy - shoulder.dy > torsoLength * 0.30;

      if (hipAngle >= reclinedThreshold && torsoReclined) reclined = true;
      if (hipAngle <= uprightThreshold && torsoRaised) upright = true;
    }

    return _updatePrecisionRepCycle(
      timestamp: sample.timestamp,
      signalsAvailable: signalsAvailable,
      startCandidate: reclined,
      targetCandidate: upright,
      poseValid: signalsAvailable,
    );
  }

  _PrecisionRepUpdate _updatePrecisionRepCycle({
    required DateTime timestamp,
    required bool signalsAvailable,
    required bool startCandidate,
    required bool targetCandidate,
    required bool poseValid,
  }) {
    const signalLossTolerance = Duration(milliseconds: 850);
    const confirmationFrames = 2;
    final previousSignalsAt = _lastPrecisionRepSignalsAt;

    if (!signalsAvailable) {
      if (previousSignalsAt != null &&
          timestamp.difference(previousSignalsAt) > signalLossTolerance) {
        _resetPrecisionRepPhase();
      }

      return _PrecisionRepUpdate(
        repCounted: false,
        poseValid: false,
        exerciseActive: false,
        signalsAvailable: false,
        ready: _precisionRepPhase == _PrecisionRepPhase.start,
      );
    }

    _lastPrecisionRepSignalsAt = timestamp;
    final previousPhase = _precisionRepPhase;
    var repCounted = false;

    switch (_precisionRepPhase) {
      case _PrecisionRepPhase.waitingForStart:
        if (startCandidate) {
          _precisionRepConfirmationFrames++;
          if (_precisionRepConfirmationFrames >= confirmationFrames) {
            _precisionRepPhase = _PrecisionRepPhase.start;
            _precisionRepConfirmationFrames = 0;
            _cycleTargetReached = false;
          }
        } else {
          _precisionRepConfirmationFrames = 0;
        }
      case _PrecisionRepPhase.start:
        if (targetCandidate) {
          _precisionRepPhase = _PrecisionRepPhase.target;
          _precisionRepConfirmationFrames = 0;
          _cycleTargetReached = true;
        } else if (!startCandidate) {
          _precisionRepPhase = _PrecisionRepPhase.movingToTarget;
          _precisionRepConfirmationFrames = 0;
        }
      case _PrecisionRepPhase.movingToTarget:
        if (targetCandidate) {
          _precisionRepPhase = _PrecisionRepPhase.target;
          _precisionRepConfirmationFrames = 0;
          _cycleTargetReached = true;
        } else if (startCandidate) {
          _precisionRepPhase = _PrecisionRepPhase.start;
          _precisionRepConfirmationFrames = 0;
          _cycleTargetReached = false;
        }
      case _PrecisionRepPhase.target:
        if (startCandidate) {
          _precisionRepPhase = _PrecisionRepPhase.returning;
          _precisionRepConfirmationFrames = 1;
        }
      case _PrecisionRepPhase.returning:
        if (startCandidate) {
          _precisionRepConfirmationFrames++;
          if (_precisionRepConfirmationFrames >= confirmationFrames) {
            _precisionRepPhase = _PrecisionRepPhase.start;
            _precisionRepConfirmationFrames = 0;
            _cycleTargetReached = false;
            repCounted = true;
          }
        } else if (targetCandidate) {
          _precisionRepPhase = _PrecisionRepPhase.target;
          _precisionRepConfirmationFrames = 0;
        } else {
          _precisionRepConfirmationFrames = 0;
        }
    }

    final exerciseActive =
        repCounted ||
        previousPhase != _precisionRepPhase ||
        _precisionRepPhase == _PrecisionRepPhase.movingToTarget ||
        _precisionRepPhase == _PrecisionRepPhase.target ||
        _precisionRepPhase == _PrecisionRepPhase.returning;

    return _PrecisionRepUpdate(
      repCounted: repCounted,
      poseValid: poseValid,
      exerciseActive: exerciseActive,
      signalsAvailable: true,
      ready: _precisionRepPhase == _PrecisionRepPhase.start,
    );
  }

  void _resetPrecisionRepPhase() {
    _precisionRepPhase = _PrecisionRepPhase.waitingForStart;
    _precisionRepConfirmationFrames = 0;
    _cycleTargetReached = false;
  }

  bool _twoPhaseCycle({required bool start, required bool target}) {
    if (start) {
      final counted = _cycleStarted && _cycleTargetReached;
      _cycleStarted = true;
      _cycleTargetReached = false;
      return counted;
    }
    if (target && _cycleStarted) {
      _cycleTargetReached = true;
    }
    return false;
  }

  bool _burpee(Map<PoseLandmarkType, Offset> points) {
    final knees = _kneeAngles(points);
    final standing =
        knees.isNotEmpty &&
        knees.every((angle) => angle > 145) &&
        !_isHorizontal(points);
    final crouched = knees.any((angle) => angle < 112);
    final plank = _plankValid(points);

    switch (_burpeeStage) {
      case 0:
        if (standing) _burpeeStage = 1;
      case 1:
        if (crouched) _burpeeStage = 2;
      case 2:
        if (plank) _burpeeStage = 3;
      case 3:
        if (crouched) _burpeeStage = 4;
      case 4:
        if (standing) {
          _burpeeStage = 1;
          return true;
        }
    }
    return false;
  }

  bool _kneeDrive(
    Map<PoseLandmarkType, Offset> points, {
    required bool mountainClimber,
    bool running = false,
  }) {
    var counted = false;
    for (final right in const [false, true]) {
      final hip =
          points[right ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip];
      final knee =
          points[right
              ? PoseLandmarkType.rightKnee
              : PoseLandmarkType.leftKnee];
      final shoulder =
          points[right
              ? PoseLandmarkType.rightShoulder
              : PoseLandmarkType.leftShoulder];
      if (hip == null || knee == null) continue;

      final torso = shoulder == null
          ? 0.18
          : math.max((shoulder - hip).distance, 0.08);
      final driven = mountainClimber
          ? shoulder != null && (knee - shoulder).distance < torso * 1.12
          : knee.dy < hip.dy + torso * (running ? 0.42 : 0.24);
      final lowered = mountainClimber
          ? shoulder != null && (knee - shoulder).distance > torso * 1.42
          : knee.dy > hip.dy + torso * 0.72;

      if (lowered) _kneeReset[right] = true;
      if (driven && (_kneeReset[right] ?? true) && _lastDrivenRight != right) {
        _kneeReset[right] = false;
        _lastDrivenRight = right;
        counted = true;
      }
    }
    return counted;
  }

  bool _jumpRopeMovement(_PoseSample sample, _PoseSample? previous) {
    if (previous == null) return false;
    final hasLowerBody =
        _hasAny(sample.landmarks, const [
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.rightKnee,
        ]) &&
        _hasAny(sample.landmarks, const [
          PoseLandmarkType.leftAnkle,
          PoseLandmarkType.rightAnkle,
        ]);
    final verticalChange =
        (sample.center.dy - previous.center.dy).abs() / sample.bodyScale;
    final active = hasLowerBody && verticalChange > 0.018;
    if (active) _lastExerciseEvent = sample.timestamp;
    return active;
  }

  static bool _hasJumpingJackSignals(Map<PoseLandmarkType, Offset> points) {
    return _requiredLandmarks(
      WorkoutExercise.jumpingJacks,
    ).every(points.containsKey);
  }

  WorkoutBodyCoverage _coverage(Map<PoseLandmarkType, Offset> points) {
    final required = _requiredLandmarks(exercise);
    final visible = required.where(points.containsKey).length;
    final ratio = visible / required.length;
    final semanticReady = switch (exercise) {
      WorkoutExercise.pushUps =>
        _completeSide(points, const [
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftElbow,
              PoseLandmarkType.leftWrist,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftKnee,
            ]) ||
            _completeSide(points, const [
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightElbow,
              PoseLandmarkType.rightWrist,
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightKnee,
            ]),
      WorkoutExercise.squats || WorkoutExercise.lunges =>
        _completeSide(points, const [
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftKnee,
              PoseLandmarkType.leftAnkle,
            ]) &&
            _completeSide(points, const [
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightKnee,
              PoseLandmarkType.rightAnkle,
            ]) &&
            _hasAny(points, const [
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.rightShoulder,
            ]),
      WorkoutExercise.sitUps =>
        _completeSide(points, const [
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftKnee,
            ]) ||
            _completeSide(points, const [
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightKnee,
            ]),
      WorkoutExercise.wallSit => _kneeAngles(points).isNotEmpty,
      WorkoutExercise.plank => _bodyAlignmentAngles(points).isNotEmpty,
      WorkoutExercise.jumpingJacks => _hasJumpingJackSignals(points),
      _ => visible >= math.min(4, required.length),
    };
    // One complete, high-confidence body side is enough for side-on exercises
    // such as push-ups; requiring both sides rejects otherwise excellent views.
    if (!semanticReady || ratio < 0.48) {
      return WorkoutBodyCoverage.insufficient;
    }
    return ratio >= 0.82
        ? WorkoutBodyCoverage.excellent
        : WorkoutBodyCoverage.good;
  }

  String? _formFeedback(Map<PoseLandmarkType, Offset> points) {
    switch (exercise) {
      case WorkoutExercise.squats:
        final angle = _averageKneeAngle(points);
        if (_cycleTargetReached && angle != null && angle > 98) {
          return 'Go slightly lower';
        }
      case WorkoutExercise.pushUps:
        final angle = _averageElbowAngle(points);
        if (_cycleTargetReached && angle != null && angle > 92) {
          return 'Bend your elbows a little more';
        }
        if (_bodyAlignmentAngles(points).any((angle) => angle < 145)) {
          return 'Straighten your body';
        }
      case WorkoutExercise.plank:
        if (!_plankValid(points)) return 'Straighten your body';
      case WorkoutExercise.lunges:
        final angles = _kneeAngles(points);
        if (_cycleTargetReached && angles.every((angle) => angle > 108)) {
          return 'Lower into the lunge';
        }
      default:
        return null;
    }
    return null;
  }

  bool _plankValid(Map<PoseLandmarkType, Offset> points) {
    final alignments = _bodyAlignmentAngles(points);
    return alignments.any((angle) => angle >= 145) && _isHorizontal(points);
  }

  bool _wallSitValid(Map<PoseLandmarkType, Offset> points) {
    final knees = _kneeAngles(points);
    if (!knees.any((angle) => angle >= 68 && angle <= 125)) return false;
    final shoulder = _center(points, const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    ]);
    final hip = _center(points, const [
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]);
    if (shoulder == null || hip == null) return false;
    final delta = shoulder - hip;
    return delta.dy.abs() > delta.dx.abs() * 1.1;
  }

  bool _isHorizontal(Map<PoseLandmarkType, Offset> points) {
    final shoulder = _center(points, const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    ]);
    final hip = _center(points, const [
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]);
    if (shoulder == null || hip == null) return false;
    final delta = shoulder - hip;
    return delta.dx.abs() > delta.dy.abs() * 1.15;
  }

  _JumpingJackUpdate _updateJumpingJack(_PoseSample sample) {
    const signalLossTolerance = Duration(milliseconds: 850);
    const openSpreadRatio = 1.06;
    const closedSpreadRatio = 1.03;

    final points = sample.landmarks;
    final shoulderCenter = _center(points, const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    ]);
    final hipCenter = _center(points, const [
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]);
    final hipWidth = _pairDistance(
      points,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    );
    final kneeSpread = _pairDistance(
      points,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
    );
    final leftWrist = points[PoseLandmarkType.leftWrist];
    final rightWrist = points[PoseLandmarkType.rightWrist];

    final signalsAvailable =
        shoulderCenter != null &&
        hipCenter != null &&
        hipWidth != null &&
        kneeSpread != null &&
        leftWrist != null &&
        rightWrist != null &&
        // Reject ratios that would amplify small landmark errors at distance.
        hipWidth > _minimumJumpingJackHipWidth;

    final previousSignalsAt = _lastJumpingJackSignalsAt;
    if (!signalsAvailable) {
      if (previousSignalsAt != null &&
          sample.timestamp.difference(previousSignalsAt) >
              signalLossTolerance) {
        _resetJumpingJackPhase();
      }

      return _JumpingJackUpdate(
        repCounted: false,
        poseValid: false,
        exerciseActive: false,
        debug: JumpingJackDebugData(
          poseDetected: true,
          signalsAvailable: false,
          baselineReady: _jumpingJackBaselineReady,
          armsClosed: false,
          armsOpen: false,
          kneesClosed: false,
          kneesOpen: false,
          kneeSpreadRatio: 0,
          verticalMotion: false,
          phase: _jumpingJackPhase,
        ),
      );
    }

    _lastJumpingJackSignalsAt = sample.timestamp;
    final torsoLength = math.max((shoulderCenter - hipCenter).distance, 0.08);
    final armsClosed =
        leftWrist.dy > shoulderCenter.dy + torsoLength * 0.30 &&
        rightWrist.dy > shoulderCenter.dy + torsoLength * 0.30;
    final armsOpen =
        leftWrist.dy < shoulderCenter.dy - torsoLength * 0.01 &&
        rightWrist.dy < shoulderCenter.dy - torsoLength * 0.01;
    final normalizedKneeSpread = kneeSpread / hipWidth;

    // Learn the user's closed stance from several valid down-arm samples, then
    // freeze it for the rest of the workout. This avoids a noisy early sample
    // permanently pulling the baseline downward.
    if (armsClosed && !_jumpingJackBaselineReady) {
      _recordJumpingJackBaseline(normalizedKneeSpread, hipCenter.dy);
    }

    final baselineSpread = _jumpingJackBaselineSpread;
    final baselineHipY = _jumpingJackBaselineHipY;
    final spreadRatio = baselineSpread == null || baselineSpread <= 0.001
        ? 1.0
        : normalizedKneeSpread / baselineSpread;
    final verticalMotion =
        baselineHipY != null &&
        (hipCenter.dy - baselineHipY).abs() / sample.bodyScale >= 0.010;
    final kneesOpen =
        baselineSpread != null &&
        (spreadRatio >= openSpreadRatio ||
            (verticalMotion && spreadRatio >= 1.05));
    final kneesClosed =
        baselineSpread != null && spreadRatio <= closedSpreadRatio;
    final closedCandidate = armsClosed && kneesClosed;
    final openCandidate = armsOpen && kneesOpen;

    final previousPhase = _jumpingJackPhase;
    var repCounted = false;
    switch (_jumpingJackPhase) {
      case JumpingJackPhase.waitingForClosed:
        if (closedCandidate) {
          _jumpingJackConfirmationFrames++;
          if (_jumpingJackConfirmationFrames >= 2) {
            _jumpingJackPhase = JumpingJackPhase.closed;
            _jumpingJackConfirmationFrames = 0;
          }
        } else {
          _jumpingJackConfirmationFrames = 0;
        }
      case JumpingJackPhase.closed:
        if (openCandidate) {
          _jumpingJackPhase = JumpingJackPhase.open;
          _jumpingJackArmsOpened = true;
          _jumpingJackKneesOpened = true;
        } else if (armsOpen || kneesOpen) {
          _jumpingJackPhase = JumpingJackPhase.opening;
          _jumpingJackArmsOpened = armsOpen;
          _jumpingJackKneesOpened = kneesOpen;
        }
      case JumpingJackPhase.opening:
        _jumpingJackArmsOpened |= armsOpen;
        _jumpingJackKneesOpened |= kneesOpen;
        if (_jumpingJackArmsOpened && _jumpingJackKneesOpened) {
          _jumpingJackPhase = JumpingJackPhase.open;
          _jumpingJackConfirmationFrames = 0;
        } else if (closedCandidate) {
          _jumpingJackPhase = JumpingJackPhase.closed;
          _jumpingJackConfirmationFrames = 0;
          _jumpingJackArmsOpened = false;
          _jumpingJackKneesOpened = false;
        }
      case JumpingJackPhase.open:
        if (closedCandidate) {
          _jumpingJackPhase = JumpingJackPhase.closing;
          _jumpingJackConfirmationFrames = 1;
        }
      case JumpingJackPhase.closing:
        if (closedCandidate) {
          _jumpingJackConfirmationFrames++;
          if (_jumpingJackConfirmationFrames >= 2) {
            _jumpingJackPhase = JumpingJackPhase.closed;
            _jumpingJackConfirmationFrames = 0;
            _jumpingJackArmsOpened = false;
            _jumpingJackKneesOpened = false;
            repCounted = true;
          }
        } else if (openCandidate) {
          _jumpingJackPhase = JumpingJackPhase.open;
          _jumpingJackConfirmationFrames = 0;
        } else {
          // Closed confirmation must be consecutive.
          _jumpingJackConfirmationFrames = 0;
        }
    }

    return _JumpingJackUpdate(
      repCounted: repCounted,
      poseValid: closedCandidate || openCandidate,
      exerciseActive:
          previousPhase != _jumpingJackPhase ||
          _jumpingJackPhase == JumpingJackPhase.opening ||
          _jumpingJackPhase == JumpingJackPhase.open ||
          _jumpingJackPhase == JumpingJackPhase.closing,
      debug: JumpingJackDebugData(
        poseDetected: true,
        signalsAvailable: true,
        baselineReady: _jumpingJackBaselineReady,
        armsClosed: armsClosed,
        armsOpen: armsOpen,
        kneesClosed: kneesClosed,
        kneesOpen: kneesOpen,
        kneeSpreadRatio: spreadRatio,
        verticalMotion: verticalMotion,
        phase: _jumpingJackPhase,
      ),
    );
  }

  void _resetJumpingJackPhase() {
    _jumpingJackPhase = JumpingJackPhase.waitingForClosed;
    _jumpingJackConfirmationFrames = 0;
    _jumpingJackArmsOpened = false;
    _jumpingJackKneesOpened = false;
  }

  void _recordJumpingJackBaseline(double spread, double hipY) {
    if (_jumpingJackBaselineReady) return;

    _jumpingJackKneeBaselines.add(spread);
    _jumpingJackHipYBaselines.add(hipY);
  }

  double? get _jumpingJackBaselineSpread => _jumpingJackKneeBaselines.isEmpty
      ? null
      : _median(_jumpingJackKneeBaselines);

  double? get _jumpingJackBaselineHipY => _jumpingJackHipYBaselines.isEmpty
      ? null
      : _median(_jumpingJackHipYBaselines);

  List<double> _kneeAngles(Map<PoseLandmarkType, Offset> points) {
    return _bilateralAngles(
      points,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.rightAnkle,
    );
  }

  double? _averageKneeAngle(Map<PoseLandmarkType, Offset> points) =>
      _average(_kneeAngles(points));

  double? _averageElbowAngle(Map<PoseLandmarkType, Offset> points) => _average(
    _bilateralAngles(
      points,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.rightWrist,
    ),
  );

  double? _averageHipAngle(Map<PoseLandmarkType, Offset> points) => _average(
    _bilateralAngles(
      points,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
    ),
  );

  List<double> _bodyAlignmentAngles(Map<PoseLandmarkType, Offset> points) =>
      _bilateralAngles(
        points,
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
      );

  static List<double> _bilateralAngles(
    Map<PoseLandmarkType, Offset> points,
    PoseLandmarkType leftA,
    PoseLandmarkType leftB,
    PoseLandmarkType leftC,
    PoseLandmarkType rightA,
    PoseLandmarkType rightB,
    PoseLandmarkType rightC,
  ) {
    final results = <double>[];
    void add(PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType c) {
      final first = points[a];
      final vertex = points[b];
      final last = points[c];
      if (first != null && vertex != null && last != null) {
        results.add(_angle(first, vertex, last));
      }
    }

    add(leftA, leftB, leftC);
    add(rightA, rightB, rightC);
    return results;
  }

  static double _angle(Offset first, Offset vertex, Offset last) {
    final a = first - vertex;
    final b = last - vertex;
    final denominator = a.distance * b.distance;
    if (denominator <= 0.000001) return 0;
    final cosine = ((a.dx * b.dx + a.dy * b.dy) / denominator).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }

  static double? _average(List<double> values) => values.isEmpty
      ? null
      : values.reduce((first, second) => first + second) / values.length;

  static bool _completeSide(
    Map<PoseLandmarkType, Offset> points,
    List<PoseLandmarkType> types,
  ) => types.every(points.containsKey);

  static bool _hasAny(
    Map<PoseLandmarkType, Offset> points,
    List<PoseLandmarkType> types,
  ) => types.any(points.containsKey);

  static Offset? _center(
    Map<PoseLandmarkType, Offset> points,
    List<PoseLandmarkType> types,
  ) {
    final found = types
        .map((type) => points[type])
        .whereType<Offset>()
        .toList();
    if (found.isEmpty) return null;
    return Offset(
      found.map((point) => point.dx).reduce((a, b) => a + b) / found.length,
      found.map((point) => point.dy).reduce((a, b) => a + b) / found.length,
    );
  }

  static double? _pairDistance(
    Map<PoseLandmarkType, Offset> points,
    PoseLandmarkType first,
    PoseLandmarkType second,
  ) {
    final a = points[first];
    final b = points[second];
    return a == null || b == null ? null : (a - b).distance;
  }

  static List<PoseLandmarkType> _requiredLandmarks(WorkoutExercise exercise) {
    return switch (exercise) {
      WorkoutExercise.pushUps => const [
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
      ],
      WorkoutExercise.jumpingJacks => const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
      ],
      WorkoutExercise.plank => const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ],
      WorkoutExercise.sitUps => const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
      ],
      _ => const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ],
    };
  }

  static double _movementBetween(_PoseSample previous, _PoseSample current) {
    if (current.timestamp.difference(previous.timestamp) >
        const Duration(milliseconds: 750)) {
      return 0;
    }
    final shared = previous.landmarks.keys
        .where(current.landmarks.containsKey)
        .toList(growable: false);
    if (shared.length < 4) return 0;
    final scale = math.max((previous.bodyScale + current.bodyScale) / 2, 0.05);
    final translation = current.center - previous.center;
    final distances = <double>[];
    for (final type in shared) {
      final delta = current.landmarks[type]! - previous.landmarks[type]!;
      distances.add((delta - translation).distance / scale);
    }
    distances.sort();
    if (distances.length > 5) distances.removeLast();
    return distances.reduce((a, b) => a + b) / distances.length;
  }

  static double _lerp(double start, double end, double amount) =>
      start + (end - start) * amount.clamp(0.0, 1.0);

  static double _median(Iterable<double> input) {
    final values = input.toList()..sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }
}

class _PrecisionRepUpdate {
  const _PrecisionRepUpdate({
    required this.repCounted,
    required this.poseValid,
    required this.exerciseActive,
    required this.signalsAvailable,
    required this.ready,
  });

  final bool repCounted;
  final bool poseValid;
  final bool exerciseActive;
  final bool signalsAvailable;
  final bool ready;
}

class _JumpingJackUpdate {
  const _JumpingJackUpdate({
    required this.repCounted,
    required this.poseValid,
    required this.exerciseActive,
    required this.debug,
  });

  final bool repCounted;
  final bool poseValid;
  final bool exerciseActive;
  final JumpingJackDebugData debug;
}

class _PoseSample {
  const _PoseSample({
    required this.landmarks,
    required this.timestamp,
    required this.center,
    required this.bounds,
    required this.bodyScale,
  });

  factory _PoseSample.from(
    Map<PoseLandmarkType, Offset> landmarks,
    DateTime timestamp,
  ) {
    final torso = <Offset>[];
    for (final type in const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]) {
      final point = landmarks[type];
      if (point != null) torso.add(point);
    }
    final centerPoints = torso.length >= 2 ? torso : landmarks.values.toList();
    final center = Offset(
      _median(centerPoints.map((point) => point.dx)),
      _median(centerPoints.map((point) => point.dy)),
    );
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final point in landmarks.values) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    final bounds = Rect.fromLTRB(left, top, right, bottom);
    final shoulderCenter = WorkoutPoseAnalyzer._center(landmarks, const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    ]);
    final hipCenter = WorkoutPoseAnalyzer._center(landmarks, const [
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]);
    final torsoScale = shoulderCenter == null || hipCenter == null
        ? 0.0
        : (shoulderCenter - hipCenter).distance * 2.2;
    final bodyScale = math.max(
      torsoScale,
      math.max(bounds.width, bounds.height) * 0.7,
    );
    return _PoseSample(
      landmarks: landmarks,
      timestamp: timestamp,
      center: center,
      bounds: bounds,
      bodyScale: math.max(bodyScale, 0.05),
    );
  }

  final Map<PoseLandmarkType, Offset> landmarks;
  final DateTime timestamp;
  final Offset center;
  final Rect bounds;
  final double bodyScale;

  static double _median(Iterable<double> input) {
    final values = input.toList()..sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }
}

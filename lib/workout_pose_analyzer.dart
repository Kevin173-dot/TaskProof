// ignore_for_file: unused_element

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'new_task_page.dart' show WorkoutExercise, WorkoutMovementType;

enum WorkoutBodyCoverage { insufficient, good, excellent }

enum JumpingJackPhase { waitingForClosed, closed, opening, open, closing }

enum PushUpPhase { waitingForTop, top, descending, bottom, ascending }

enum PushUpTrackedSide { none, left, right }

class PushUpDebugData {
  const PushUpDebugData({
    required this.poseDetected,
    required this.signalsAvailable,
    required this.trackedSide,
    required this.torsoHorizontal,
    required this.topCandidate,
    required this.bottomCandidate,
    required this.phase,
    required this.signalMissingMilliseconds,
    required this.repCounted,
    required this.topThreshold,
    required this.bottomThreshold,

    this.shoulderConfidence,
    this.elbowConfidence,
    this.wristConfidence,

    this.elbowAngle,
    this.leftElbowAngle,
    this.rightElbowAngle,

    this.bodyAlignmentAngle,

    this.wristSupportEvidence,
    this.nonWristSupportEvidence,

    this.elbowPerpendicularity,
    this.elbowSupportScore,

    this.anchorTravel,
    this.maxAnchorTravel,

    this.anchorElbowBend,
    this.anchorUpperArmDelta,
    this.maxAnchorArmBend,

    this.torsoOnlyTrackable,
  });

  final bool poseDetected;
  final bool signalsAvailable;

  final PushUpTrackedSide trackedSide;

  final double? shoulderConfidence;
  final double? elbowConfidence;
  final double? wristConfidence;

  final double? elbowAngle;
  final double? leftElbowAngle;
  final double? rightElbowAngle;

  final bool torsoHorizontal;

  final double? bodyAlignmentAngle;

  final bool topCandidate;
  final bool bottomCandidate;

  final PushUpPhase phase;

  final int signalMissingMilliseconds;

  final bool repCounted;

  final double topThreshold;
  final double bottomThreshold;

  // Support debugging.
  final bool? wristSupportEvidence;
  final bool? nonWristSupportEvidence;

  final double? elbowPerpendicularity;
  final double? elbowSupportScore;

  // Anchor debugging.
  final double? anchorTravel;
  final double? maxAnchorTravel;

  final double? anchorElbowBend;
  final double? anchorUpperArmDelta;
  final double? maxAnchorArmBend;

  // Occlusion debugging.
  final bool? torsoOnlyTrackable;
}



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
    WorkoutExercise.pushUps =>
      'Get into your natural push-up starting position',
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
            'Keep one shoulder, elbow, and hip visible',
        WorkoutExercise.squats =>
          'Keep both hips, knees, ankles, and your torso in frame',
        WorkoutExercise.sitUps =>  'Keep one shoulder, hip, and knee visible',
        WorkoutExercise.lunges => 'Keep both legs and your torso in frame',
        _ => 'Show more of your body',
      };
    }

    if (!observation.repetitionReady) {
      return switch (exercise) {
        WorkoutExercise.pushUps =>
  'Hold your natural starting push-up position briefly',
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
    this.pushUpDebug,
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
  final PushUpDebugData? pushUpDebug;
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
  static const double pushUpLandmarkConfidenceThreshold = 0.30;
  static const double jumpingJackLandmarkConfidenceThreshold = 0.30;
  static const double _minimumJumpingJackHipWidth = 0.010;
  static const int _jumpingJackBaselineSampleTarget = 5;

  final WorkoutExercise exercise;
  final WorkoutMovementType movementType;
  final double sensitivity;
  final bool formChecking;

 

  double get _landmarkConfidenceThreshold => switch (exercise) {
    WorkoutExercise.pushUps => pushUpLandmarkConfidenceThreshold,
    WorkoutExercise.jumpingJacks => jumpingJackLandmarkConfidenceThreshold,
    _ => landmarkConfidenceThreshold,
  };

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

  PushUpPhase _pushUpPhase = PushUpPhase.waitingForTop;
  int _pushUpConfirmationFrames = 0;
  DateTime? _lastPushUpUsableSignalAt;
  DateTime? _pushUpCycleStartedAt;
  bool? _pushUpTrackedRight;
  bool? _pushUpSwitchCandidateRight;
  int _pushUpSwitchCandidateFrames = 0;

  // ============================================================
  // ADAPTIVE PUSH-UP TOP BASELINES
  // ============================================================
  //
  // These follow the user's natural top position gradually.

  final Map<bool, double> _pushUpTopElbowBaselines = {};
  final Map<bool, double> _pushUpUpperArmTopBaselines = {};
  final Map<bool, int> _pushUpUpperArmBaselineSamples = {};

  final Map<bool, Offset> _pushUpTopTorsoCenters = {};
  final Map<bool, Offset> _pushUpTopTorsoNormals = {};
  final Map<bool, double> _pushUpTopTorsoLengths = {};

  // ============================================================
  // SLOW SESSION ANCHORS
  // ============================================================
//
// Adaptive baselines above follow normal body drift.
//
// These anchors move MUCH more slowly and only while a supported
// top pose is stable.
//
// They act as anti-drift sanity checks rather than forcing the user
// to remain in one exact screen position.

final Map<bool, Offset>
    _pushUpAnchorTorsoCenters = {};

final Map<bool, Offset>
    _pushUpAnchorTorsoNormals = {};

final Map<bool, double>
    _pushUpAnchorTorsoLengths = {};

final Map<bool, double>
    _pushUpAnchorElbowBaselines = {};

final Map<bool, double>
    _pushUpAnchorUpperArmBaselines = {};

final Map<bool, bool>
    _pushUpAnchorLocked = {};

final Map<bool, int>
    _pushUpAnchorDisagreementFrames = {};

double? _pushUpMaxAnchorTravel;
double? _pushUpMaxAnchorArmBend;

double? _pushUpSmoothedElbowAngle;
Offset? _pushUpSmoothedTorsoCenter;

double _pushUpMaxTravel = 0;
double _pushUpMaxArmBend = 0;

  JumpingJackPhase _jumpingJackPhase =
    JumpingJackPhase.waitingForClosed;

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

    _pushUpPhase = PushUpPhase.waitingForTop;
    _pushUpConfirmationFrames = 0;
    _lastPushUpUsableSignalAt = null;
    _pushUpCycleStartedAt = null;
    _pushUpTrackedRight = null;
    _pushUpSwitchCandidateRight = null;
    _pushUpSwitchCandidateFrames = 0;
    _pushUpTopElbowBaselines.clear();
    _pushUpUpperArmTopBaselines.clear();
    _pushUpUpperArmBaselineSamples.clear();
    _pushUpTopTorsoCenters.clear();
    _pushUpTopTorsoNormals.clear();
    _pushUpTopTorsoLengths.clear();

    _pushUpAnchorTorsoCenters.clear();
    _pushUpAnchorTorsoNormals.clear();
    _pushUpAnchorTorsoLengths.clear();
    _pushUpAnchorElbowBaselines.clear();
    _pushUpAnchorUpperArmBaselines.clear();
    _pushUpAnchorLocked.clear();
    _pushUpAnchorDisagreementFrames.clear();

    _pushUpSmoothedElbowAngle = null;
    _pushUpSmoothedTorsoCenter = null;

    _pushUpMaxTravel = 0;
    _pushUpMaxArmBend = 0;

    _pushUpMaxAnchorTravel = null;
    _pushUpMaxAnchorArmBend = null;

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
        final pushUpWasReady =
            exercise == WorkoutExercise.pushUps &&
            _pushUpPhase == PushUpPhase.top;
        final pushUpSignalsAt = _lastPushUpUsableSignalAt;

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

      _pushUpPhase = pushUpWasReady
        ? PushUpPhase.top
        : PushUpPhase.waitingForTop;
    _pushUpConfirmationFrames = 0;
    _lastPushUpUsableSignalAt = pushUpWasReady ? pushUpSignalsAt : null;
    _pushUpCycleStartedAt = null;
    _pushUpMaxTravel = 0;
    _pushUpMaxArmBend = 0;
    _pushUpMaxAnchorTravel = null;
_pushUpMaxAnchorArmBend = null;
    _pushUpSmoothedElbowAngle = null;
    _pushUpSmoothedTorsoCenter = null;
    _pushUpSwitchCandidateRight = null;
    _pushUpSwitchCandidateFrames = 0;

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
      return _absent(timestamp: timestamp);
    }

    final minimumLandmarks =
        exercise == WorkoutExercise.pushUps ? 3 : 4;

    Map<PoseLandmarkType, WorkoutLandmark>? best;
    Pose? bestPose;
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
      if (landmarks.length >= minimumLandmarks && score > bestScore) {
        best = landmarks;
        bestPose = pose;
        bestScore = score;
      }
    }

    if (best == null || bestPose == null) {
      return _absent(timestamp: timestamp);
    }

    return _analyzeLandmarks(
      best,
      timestamp: timestamp,
    );
  }

  /// Public synthetic-landmark entry point used by deterministic tests.
///
/// Real camera poses and synthetic landmark tests both feed the same
/// exercise-specific tracking logic after landmark normalization.

  WorkoutPoseObservation analyzeLandmarks(
    Map<PoseLandmarkType, WorkoutLandmark> landmarks, {
    required DateTime timestamp,
  }) {
    return _analyzeLandmarks(landmarks, timestamp: timestamp);
  }

WorkoutPoseObservation _analyzeLandmarks(
  Map<PoseLandmarkType, WorkoutLandmark> landmarks, {
  required DateTime timestamp,
}) {
       final confident = <PoseLandmarkType, Offset>{};
        final confidences = <PoseLandmarkType, double>{};

        for (final entry in landmarks.entries) {
          if (entry.value.confidence >= _landmarkConfidenceThreshold) {
            confident[entry.key] = entry.value.position;
            confidences[entry.key] = entry.value.confidence;
          }
        }

        final minimumLandmarks =
        exercise == WorkoutExercise.pushUps ? 3 : 4;

        if (confident.length < minimumLandmarks) {
          return _absent(timestamp: timestamp);
        }

        final sample = _PoseSample.from(
          confident,
          timestamp,
          confidences: confidences,
        );

        final coverage = _coverage(sample.landmarks);

          final tooClose = switch (exercise) {
          // Push-ups are horizontal and often fill a phone frame. If the
          // useful landmarks remain visible, edge-to-edge framing is fine.
          WorkoutExercise.pushUps => false,
          WorkoutExercise.jumpingJacks => false,
          _ => sample.bounds.width > 0.88 || sample.bounds.height > 0.94,
        };
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
    PushUpDebugData? pushUpDebug;
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
          pushUpDebug = update.debug;
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
      pushUpDebug: pushUpDebug,
      repetitionTrackingEnabled: _usesPrecisionRepTracker,
      repetitionSignalsAvailable: repetitionSignalsAvailable,
      repetitionReady: repetitionReady,
      overlayLandmarks: {
        for (final entry in sample.landmarks.entries) entry.key: entry.value,
      },
    );
  }

    WorkoutPoseObservation _absent({DateTime? timestamp}) {
      _stableFrames = 0;

      final pushUpMissingFor =
          timestamp == null || _lastPushUpUsableSignalAt == null
          ? Duration.zero
          : timestamp.difference(_lastPushUpUsableSignalAt!);

      final pushUpDebug = exercise == WorkoutExercise.pushUps
          ? PushUpDebugData(
              poseDetected: false,
              signalsAvailable: false,
              trackedSide: _pushUpTrackedSide,
              torsoHorizontal: false,
              topCandidate: false,
              bottomCandidate: false,
              phase: _pushUpPhase,
              signalMissingMilliseconds:
                  math.max(0, pushUpMissingFor.inMilliseconds),
              repCounted: false,
              topThreshold: _pushUpTopThreshold,
              bottomThreshold: _pushUpBottomThreshold,
            )
          : null;

      return WorkoutPoseObservation(
        personPresent: false,
        coverage: WorkoutBodyCoverage.insufficient,
        tooClose: false,
        cameraStable: false,
        exercisePoseValid: false,
        exerciseActive: false,
        meaningfulMovement: false,
        repCounted: false,
        formFeedback: null,
        pushUpDebug: pushUpDebug,
        overlayLandmarks: const {},
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

  // Push-up thresholds are deliberately relative to the user's learned top
  // pose. Sensitivity only changes tolerance; a rep still needs BOTH real
  // arm flexion and real torso travel, which prevents stationary floor poses
  // and landmark jitter from manufacturing repetitions.
  double get _pushUpTopThreshold => _lerp(142, 134, sensitivity);
  double get _pushUpBottomThreshold => _lerp(122, 132, sensitivity);
  double get _pushUpTopReturnTolerance => _lerp(10, 16, sensitivity);
  double get _pushUpMinArmBend => _lerp(18, 10, sensitivity);
  double get _pushUpMinTorsoTravel => _lerp(0.11, 0.06, sensitivity);
  double get _pushUpReturnTravelTolerance => _lerp(0.055, 0.09, sensitivity);
  double get _pushUpFallbackTopTolerance => _lerp(9, 15, sensitivity);
  double get _pushUpFallbackMinArmDelta => _lerp(22, 14, sensitivity);
  double get _pushUpSupportPerpendicularMin =>
      _lerp(0.58, 0.42, sensitivity);

  double get _pushUpSupportReachMin =>
      _lerp(0.46, 0.32, sensitivity);

  double get _pushUpSupportHeightMin =>
      _lerp(0.24, 0.17, sensitivity);

  // Shoulder -> elbow fallback.
  //
  // These are smaller than the wrist thresholds because
  // shoulder -> elbow is a shorter limb segment.
  double get _pushUpElbowPerpendicularMin =>
      _lerp(0.50, 0.36, sensitivity);

  double get _pushUpElbowReachMin =>
      _lerp(0.20, 0.14, sensitivity);

  double get _pushUpElbowSupportHeightMin =>
      _lerp(0.11, 0.07, sensitivity);

  double get _pushUpElbowMinimumReach =>
      _lerp(0.24, 0.18, sensitivity);

  PushUpTrackedSide get _pushUpTrackedSide => switch (_pushUpTrackedRight) {
    true => PushUpTrackedSide.right,
    false => PushUpTrackedSide.left,
    null => PushUpTrackedSide.none,
  };

 
  _PushUpUpdate _updatePushUp(_PoseSample sample) {
const signalLossTolerance =
    Duration(milliseconds: 1000);

// Prevent impossible jitter-reps without punishing
// genuinely fast users.
const minimumRepDuration =
    Duration(milliseconds: 250);

// Allow deliberately slow push-ups and paused reps.
const maximumRepDuration =
    Duration(seconds: 25);
  const topConfirmationFrames = 3;
  const bottomConfirmationFrames = 2;
  const returnConfirmationFrames = 2;

  final points = sample.landmarks;
  final confidences = sample.confidences;

  final leftArm = _pushUpArm(points, confidences, right: false);
  final rightArm = _pushUpArm(points, confidences, right: true);

  final trackedBeforeSelection = _pushUpTrackedRight;
  final selectedArm = _selectPushUpArm(leftArm, rightArm);

  if (selectedArm != null && trackedBeforeSelection != selectedArm.right) {
    // A side change can move the measured shoulder several pixels even when
    // the user did not move. Never feed that discontinuity into smoothing.
    _pushUpSmoothedElbowAngle = null;
    _pushUpSmoothedTorsoCenter = null;
  }

  final hipCenter = _center(points, const [
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
  ]);

  final selectedHip = selectedArm == null
      ? null
      : points[selectedArm.right
                ? PoseLandmarkType.rightHip
                : PoseLandmarkType.leftHip] ??
            hipCenter;

var torsoHorizontal = false;
var torsoLengthVisible = false;

if (selectedArm != null && selectedHip != null) {
  final visibleTorsoVector =
      selectedArm.shoulder - selectedHip;

  torsoLengthVisible =
      visibleTorsoVector.distance > 0.035;

  // Keep this only for debugging.
  //
  // It is NOT a hard requirement for push-up tracking anymore.
  torsoHorizontal =
      torsoLengthVisible &&
      visibleTorsoVector.dx.abs() >
          visibleTorsoVector.dy.abs() * 0.55;
}

final signalsAvailable =
    selectedArm != null &&
    selectedHip != null;

final usableSignal =
    signalsAvailable &&
    torsoLengthVisible;


// ============================================================
// TORSO-ONLY PRESENCE DURING OCCLUSION
// ============================================================
//
// THIS DOES NOT COUNT OR ADVANCE REPS.
//
// It only prevents a real in-progress rep from immediately being
// thrown away when both elbows briefly disappear.

final shoulderCenter =
    _center(
  points,
  const [
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
  ],
);

final torsoOnlyTrackable =
    shoulderCenter != null &&
    hipCenter != null &&
    (shoulderCenter - hipCenter)
            .distance >
        0.035;
  final previousUsableSignalAt = _lastPushUpUsableSignalAt;

  if (usableSignal) {
    _lastPushUpUsableSignalAt = sample.timestamp;
  }

  final missingFor = usableSignal
      ? Duration.zero
      : previousUsableSignalAt == null
      ? Duration.zero
      : sample.timestamp.difference(previousUsableSignalAt);

if (!usableSignal) {
  final effectiveTolerance =
      _pushUpCycleStartedAt != null &&
              torsoOnlyTrackable
          ? signalLossTolerance * 2
          : signalLossTolerance;

  if (previousUsableSignalAt != null &&
      missingFor >
          effectiveTolerance) {
    _resetPushUpPhase();
  }

  return _PushUpUpdate(
    repCounted: false,
    poseValid: false,
    exerciseActive:
        _pushUpPhase !=
        PushUpPhase.waitingForTop,
    signalsAvailable: signalsAvailable,
    ready: false,

    debug: PushUpDebugData(
      poseDetected: true,
      signalsAvailable: signalsAvailable,
      trackedSide: _pushUpTrackedSide,

      shoulderConfidence:
          selectedArm?.shoulderConfidence,

      elbowConfidence:
          selectedArm?.elbowConfidence,

      wristConfidence:
          selectedArm?.wristConfidence,

      elbowAngle:
          selectedArm?.angle,

      leftElbowAngle:
          leftArm?.angle,

      rightElbowAngle:
          rightArm?.angle,

      torsoHorizontal:
          torsoHorizontal,

      bodyAlignmentAngle:
          _pushUpBodyAlignment(
        points,
        selectedArm,
      ),

      topCandidate: false,
      bottomCandidate: false,

      phase: _pushUpPhase,

      signalMissingMilliseconds:
          math.max(
        0,
        missingFor.inMilliseconds,
      ),

      repCounted: false,

      topThreshold:
          _pushUpTopThreshold,

      bottomThreshold:
          _pushUpBottomThreshold,

      torsoOnlyTrackable:
          torsoOnlyTrackable,
    ),
  );
}

  final activeArm = selectedArm;
  final activeHip = selectedHip;

  final torsoVector = activeArm.shoulder - activeHip;
  final torsoLength = math.max(torsoVector.distance, 0.035);

  final torsoAxis = Offset(
    torsoVector.dx / torsoLength,
    torsoVector.dy / torsoLength,
  );

  final torsoNormal = Offset(
    -torsoAxis.dy,
    torsoAxis.dx,
  );

  final rawTorsoCenter = Offset(
    (activeArm.shoulder.dx + activeHip.dx) / 2,
    (activeArm.shoulder.dy + activeHip.dy) / 2,
  );

  final previousTorsoCenter = _pushUpSmoothedTorsoCenter;

  _pushUpSmoothedTorsoCenter = previousTorsoCenter == null
      ? rawTorsoCenter
      : Offset(
          previousTorsoCenter.dx * 0.60 +
              rawTorsoCenter.dx * 0.40,
          previousTorsoCenter.dy * 0.60 +
              rawTorsoCenter.dy * 0.40,
        );

  final torsoCenter = _pushUpSmoothedTorsoCenter!;

  final rawElbowAngle = activeArm.angle;

  double? elbowAngle;

  if (rawElbowAngle != null) {
    final previousElbow = _pushUpSmoothedElbowAngle;

    _pushUpSmoothedElbowAngle = previousElbow == null
        ? rawElbowAngle
        : previousElbow * 0.55 + rawElbowAngle * 0.45;

    elbowAngle = _pushUpSmoothedElbowAngle;
  }

  final upperArmAngle = _angle(
    activeHip,
    activeArm.shoulder,
    activeArm.elbow,
  );

// ============================================================
// PUSH-UP SUPPORT EVIDENCE
// ============================================================
//
// Wrist is optional.
// Evidence that the body is actually supported is NOT optional.

// ------------------------------------------------------------
// ELBOW / NON-WRIST SUPPORT
// ------------------------------------------------------------

final shoulderToElbow =
    activeArm.elbow - activeArm.shoulder;

final elbowReachDistance =
    shoulderToElbow.distance;

final shoulderElbowReach =
    elbowReachDistance / torsoLength;

double? elbowPerpendicularity;
double? elbowSupportScore;

if (elbowReachDistance > 0.01) {
  final elbowUnit = Offset(
    shoulderToElbow.dx / elbowReachDistance,
    shoulderToElbow.dy / elbowReachDistance,
  );

  // Measure relative to the torso instead of raw screen direction.
  //
  // Hand rotation does not affect this.
  // Portrait/landscape does not inherently affect this.
  elbowPerpendicularity =
      (elbowUnit.dx * torsoNormal.dx +
              elbowUnit.dy * torsoNormal.dy)
          .abs();

  elbowSupportScore =
      elbowPerpendicularity *
      shoulderElbowReach;
}

final elbowGeometrySupported =
    elbowPerpendicularity != null &&
    elbowPerpendicularity >=
        _pushUpElbowPerpendicularMin &&
    shoulderElbowReach >=
        _pushUpElbowReachMin &&
    elbowSupportScore != null &&
    elbowSupportScore >=
        _pushUpElbowSupportHeightMin;

final elbowHasReach =
    shoulderElbowReach >=
        _pushUpElbowMinimumReach;

final bodyAlignment =
    _pushUpBodyAlignment(
  points,
  activeArm,
);

// Alignment is a veto, NOT proof.
//
// A straight body may still be lying flat,
// so alignment alone must never establish support.
final plausibleBodyAlignment =
    bodyAlignment == null ||
    bodyAlignment >= 120.0;

final nonWristSupportEvidence =
    plausibleBodyAlignment &&
    elbowGeometrySupported &&
    elbowHasReach;


// ------------------------------------------------------------
// WRIST SUPPORT
// ------------------------------------------------------------

var wristSupportEvidence = false;

final wrist = activeArm.wrist;

if (wrist != null) {
  final shoulderToWrist =
      wrist - activeArm.shoulder;

  final reach =
      shoulderToWrist.distance;

  if (reach > 0.01) {
    final armUnit = Offset(
      shoulderToWrist.dx / reach,
      shoulderToWrist.dy / reach,
    );

    final supportPerpendicularity =
        (armUnit.dx * torsoNormal.dx +
                armUnit.dy * torsoNormal.dy)
            .abs();

    final supportReachRatio =
        reach / torsoLength;

    wristSupportEvidence =
        supportPerpendicularity >=
                _pushUpSupportPerpendicularMin &&
            supportReachRatio >=
                _pushUpSupportReachMin &&
            supportPerpendicularity *
                    supportReachRatio >=
                _pushUpSupportHeightMin;
  }
}


// ------------------------------------------------------------
// FINAL SUPPORT DECISION
// ------------------------------------------------------------
//
// Either route can establish support.
//
// Therefore:
//
// wrist visible + good geometry -> yes
// wrist absent + good elbow geometry -> yes
// weird hand rotation + good elbow geometry -> yes
// neither arm geometry looks supported -> no

final supportEvidence =
    wristSupportEvidence ||
    nonWristSupportEvidence;

  final side = activeArm.right;

  final topElbowBaseline =
      _pushUpTopElbowBaselines[side];

  final upperArmTopBaseline =
      _pushUpUpperArmTopBaselines[side];

  final topTorsoCenter =
      _pushUpTopTorsoCenters[side];

  final topTorsoNormal =
      _pushUpTopTorsoNormals[side];

  final topTorsoLength =
      _pushUpTopTorsoLengths[side];

  double? torsoTravel;

  if (topTorsoCenter != null &&
      topTorsoNormal != null &&
      topTorsoLength != null &&
      topTorsoLength > 0.02) {
    final delta = torsoCenter - topTorsoCenter;

    final perpendicularTravel =
        (delta.dx * topTorsoNormal.dx +
                delta.dy * topTorsoNormal.dy)
            .abs();

    torsoTravel =
        perpendicularTravel / topTorsoLength;
  }

  final fullArmBend =
      elbowAngle == null || topElbowBaseline == null
      ? null
      : math.max(
          0.0,
          topElbowBaseline - elbowAngle,
        );

  final fallbackArmDelta =
      upperArmTopBaseline == null
      ? null
      : (upperArmAngle - upperArmTopBaseline).abs();

// ============================================================
// SLOW-ANCHOR TORSO TRAVEL
// ============================================================

double? anchorTravel;

final anchorTorsoCenter =
    _pushUpAnchorTorsoCenters[side];

final anchorTorsoNormal =
    _pushUpAnchorTorsoNormals[side];

final anchorTorsoLength =
    _pushUpAnchorTorsoLengths[side];

if (anchorTorsoCenter != null &&
    anchorTorsoNormal != null &&
    anchorTorsoLength != null &&
    anchorTorsoLength > 0.02) {
  final anchorDelta =
      torsoCenter -
      anchorTorsoCenter;

  final anchorPerpendicularTravel =
      (anchorDelta.dx *
                  anchorTorsoNormal.dx +
              anchorDelta.dy *
                  anchorTorsoNormal.dy)
          .abs();

  anchorTravel =
      anchorPerpendicularTravel /
      anchorTorsoLength;
}

final anchorElbowBaseline =
    _pushUpAnchorElbowBaselines[side];

final anchorUpperArmBaseline =
    _pushUpAnchorUpperArmBaselines[side];

final double? anchorElbowBend =
    elbowAngle != null &&
            anchorElbowBaseline != null
        ? math.max(
            0.0,
            anchorElbowBaseline -
                elbowAngle,
          )
        : null;

final double? anchorUpperArmDelta =
    anchorUpperArmBaseline != null
        ? (upperArmAngle -
                anchorUpperArmBaseline)
            .abs()
        : null;
  // The user's natural top position may have a slightly bent elbow,
  // unusual arm angle, hidden wrist, rotated hand, etc.
  //
  // What remains mandatory is evidence that the body is actually
  // supported rather than merely horizontal.

final naturalTopPose =
    usableSignal &&
    supportEvidence;
// Wrist-derived elbow angle is useful but optional.
//
// Upper-arm + torso information is enough for the normal
// wristless tracking path.
final baselineReady =
    upperArmTopBaseline != null &&
    topTorsoCenter != null &&
    topTorsoNormal != null &&
    topTorsoLength != null;

final returnArmReady = baselineReady
    ? (
        elbowAngle != null &&
                topElbowBaseline != null
            ? elbowAngle >=
                topElbowBaseline -
                    _pushUpTopReturnTolerance
            : fallbackArmDelta != null &&
                fallbackArmDelta <=
                    _pushUpFallbackTopTolerance
      )
    : naturalTopPose;

final returnTravelReady =
    baselineReady &&
            torsoTravel != null
        ? torsoTravel <=
            _pushUpReturnTravelTolerance
        : naturalTopPose;

final topCandidate =
    _pushUpPhase ==
            PushUpPhase.waitingForTop
        ? naturalTopPose
        : returnArmReady &&
            returnTravelReady &&
            (
              supportEvidence ||
              _pushUpCycleStartedAt != null
            );

  final fullBottomCandidate =
      torsoTravel != null &&
      fullArmBend != null &&
      torsoTravel >= _pushUpMinTorsoTravel &&
      fullArmBend >= _pushUpMinArmBend;

// Weak wristless tracking may CONTINUE an already-established
// repetition, but this weakest evidence path cannot independently
// create one.
//
// Wristless reps can still begin through the stronger calibrated
// torso + upper-arm descent logic.
final fallbackBottomCandidate =
    _pushUpCycleStartedAt != null &&
    elbowAngle == null &&
    torsoTravel != null &&
    fallbackArmDelta != null &&
    torsoTravel >=
        _pushUpMinTorsoTravel &&
    fallbackArmDelta >=
        _pushUpFallbackMinArmDelta;

  final bottomCandidate =
      fullBottomCandidate ||
      fallbackBottomCandidate;

  final armBendEvidence =
      fullArmBend ??
      fallbackArmDelta ??
      0.0;

  final travelEvidence =
      torsoTravel ?? 0.0;

final descentStarted =
    baselineReady &&
    ((travelEvidence >=
                _pushUpMinTorsoTravel * 0.30 &&
            armBendEvidence >= 4.0) ||
        (armBendEvidence >=
                _pushUpMinArmBend * 0.35 &&
            travelEvidence >= 0.018));


// ============================================================
// ADAPTIVE TOP BASELINE
// ============================================================

if (naturalTopPose &&
    (_pushUpPhase ==
            PushUpPhase.waitingForTop ||
        _pushUpPhase ==
            PushUpPhase.top) &&
    _pushUpCycleStartedAt == null) {
  _recordPushUpTopBaseline(
    right: side,
    elbowAngle: elbowAngle,
    upperArmAngle: upperArmAngle,
    torsoCenter: torsoCenter,
    torsoNormal: torsoNormal,
    torsoLength: torsoLength,
  );
  
}


// ============================================================
// SLOW SESSION ANCHOR
// ============================================================

if (naturalTopPose &&
    supportEvidence &&
    _pushUpPhase ==
        PushUpPhase.top &&
    _pushUpCycleStartedAt == null) {
  _slowlyAdaptPushUpAnchor(
    right: side,
    torsoCenter: torsoCenter,
    torsoNormal: torsoNormal,
    torsoLength: torsoLength,
    upperArmAngle: upperArmAngle,
    elbowAngle: elbowAngle,
    
  );
}


  final previousPhase = _pushUpPhase;

  var repCounted = false;

void trackAnchorEvidence() {
  if (anchorTravel != null) {
    _pushUpMaxAnchorTravel =
        math.max(
      _pushUpMaxAnchorTravel ?? 0,
      anchorTravel,
    );
  }

  if (anchorElbowBend != null) {
    _pushUpMaxAnchorArmBend =
        math.max(
      _pushUpMaxAnchorArmBend ?? 0,
      anchorElbowBend,
    );
  } else if (anchorUpperArmDelta != null) {
    _pushUpMaxAnchorArmBend =
        math.max(
      _pushUpMaxAnchorArmBend ?? 0,
      anchorUpperArmDelta,
    );
  }
}

void beginCycle() {
  _pushUpCycleStartedAt ??=
      sample.timestamp;

  _pushUpMaxTravel =
      math.max(
    _pushUpMaxTravel,
    travelEvidence,
  );

  _pushUpMaxArmBend =
      math.max(
    _pushUpMaxArmBend,
    armBendEvidence,
  );

  trackAnchorEvidence();
}

void updateCycleEvidence() {
  if (_pushUpCycleStartedAt == null) {
    return;
  }

  _pushUpMaxTravel =
      math.max(
    _pushUpMaxTravel,
    travelEvidence,
  );

  _pushUpMaxArmBend =
      math.max(
    _pushUpMaxArmBend,
    armBendEvidence,
  );

  trackAnchorEvidence();
}

bool cycleCanCount() {
  final started =
      _pushUpCycleStartedAt;

  if (started == null) {
    return false;
  }

  final duration =
      sample.timestamp.difference(
    started,
  );

  // ==========================================================
  // ADAPTIVE PER-REP EVIDENCE
  // ==========================================================

  final adaptiveTravelReached =
      _pushUpMaxTravel >=
          _pushUpMinTorsoTravel;

  final adaptiveArmReached =
      _pushUpMaxArmBend >=
          _pushUpMinArmBend;

  // ==========================================================
  // SLOW ANCHOR — TORSO
  // ==========================================================

  final anchorTravelReached =
      _pushUpMaxAnchorTravel == null ||
      _pushUpMaxAnchorTravel! >=
          _pushUpMinTorsoTravel *
              0.55;

  // ==========================================================
  // SLOW ANCHOR — ARM
  // ==========================================================

  final hasRealElbowAnchor =
      anchorElbowBaseline != null;

  final anchorArmReached =
      _pushUpMaxAnchorArmBend == null ||
      (
        hasRealElbowAnchor
            ? _pushUpMaxAnchorArmBend! >=
                _pushUpMinArmBend *
                    0.50
            : _pushUpMaxAnchorArmBend! >=
                _pushUpFallbackMinArmDelta *
                    0.50
      );

  // Rep must have actually reached the target/bottom state.
  final sequenceCompleted =
      _cycleTargetReached;

  return duration >=
          minimumRepDuration &&
      duration <=
          maximumRepDuration &&
      adaptiveTravelReached &&
      adaptiveArmReached &&
      anchorTravelReached &&
      anchorArmReached &&
      sequenceCompleted;
}

  void finishAtTop({
    required bool count,
  }) {
    repCounted = count;

    _pushUpPhase =
        PushUpPhase.top;

    _pushUpConfirmationFrames = 0;
    _pushUpCycleStartedAt = null;
    _pushUpMaxTravel = 0;
    _pushUpMaxArmBend = 0;

    _pushUpMaxAnchorTravel = null;
    _pushUpMaxAnchorArmBend = null;

    _cycleTargetReached = false;
  }

  switch (_pushUpPhase) {
    case PushUpPhase.waitingForTop:
      if (naturalTopPose) {
        _pushUpConfirmationFrames++;

        if (_pushUpConfirmationFrames >=
            topConfirmationFrames) {
          _pushUpPhase =
              PushUpPhase.top;

          _pushUpConfirmationFrames = 0;
          _pushUpCycleStartedAt = null;
          _pushUpMaxTravel = 0;
          _pushUpMaxArmBend = 0;
          _pushUpMaxAnchorTravel = null;
          _pushUpMaxAnchorArmBend = null;
          
          _cycleTargetReached = false;
        }
        } else {
    _pushUpConfirmationFrames =
        math.max(
      0,
      _pushUpConfirmationFrames - 1,
    );
  }

    case PushUpPhase.top:
      if (bottomCandidate) {
        beginCycle();

        _pushUpPhase =
            PushUpPhase.bottom;

        _pushUpConfirmationFrames = 0;
        _cycleTargetReached = true;
      } else if (descentStarted) {
        beginCycle();

        _pushUpPhase =
            PushUpPhase.descending;

        _pushUpConfirmationFrames = 0;
      }

    case PushUpPhase.descending:
      updateCycleEvidence();

      final started =
          _pushUpCycleStartedAt;

      if (started != null &&
          sample.timestamp.difference(started) >
              maximumRepDuration) {
        _resetPushUpPhase();
      } else if (bottomCandidate) {
        final strongBottom =
            travelEvidence >=
                    _pushUpMinTorsoTravel *
                        1.30 &&
                armBendEvidence >=
                    _pushUpMinArmBend *
                        1.20;

        _pushUpConfirmationFrames++;

        if (strongBottom ||
            _pushUpConfirmationFrames >=
                bottomConfirmationFrames) {
          _pushUpPhase =
              PushUpPhase.bottom;

          _pushUpConfirmationFrames = 0;
          _cycleTargetReached = true;
        }
      } else if (topCandidate) {
        // A shallow dip that returns to the top is not a rep.
        finishAtTop(count: false);
      } else {
        _pushUpConfirmationFrames = 0;
      }

    case PushUpPhase.bottom:
      updateCycleEvidence();

      if (topCandidate) {
        _pushUpConfirmationFrames++;

        if (_pushUpConfirmationFrames >=
            returnConfirmationFrames) {
          finishAtTop(
            count: cycleCanCount(),
          );
        }
      } else if (!bottomCandidate) {
        _pushUpPhase =
            PushUpPhase.ascending;

        _pushUpConfirmationFrames = 0;
      } else {
        _pushUpConfirmationFrames = 0;
      }

    case PushUpPhase.ascending:
      updateCycleEvidence();

      final started =
          _pushUpCycleStartedAt;

      if (started != null &&
          sample.timestamp.difference(started) >
              maximumRepDuration) {
        _resetPushUpPhase();
      } else if (bottomCandidate) {
        _pushUpPhase =
            PushUpPhase.bottom;

        _pushUpConfirmationFrames = 0;
      } else if (topCandidate) {
        _pushUpConfirmationFrames++;

        if (_pushUpConfirmationFrames >=
            returnConfirmationFrames) {
          finishAtTop(
            count: cycleCanCount(),
          );
        }
      } else {
        _pushUpConfirmationFrames = 0;
      }
  }




final exerciseActive =
    repCounted ||
      previousPhase != _pushUpPhase ||
      _pushUpCycleStartedAt != null ||
      _pushUpPhase ==
          PushUpPhase.descending ||
      _pushUpPhase ==
          PushUpPhase.bottom ||
      _pushUpPhase ==
          PushUpPhase.ascending;

final ready =
    _pushUpPhase ==
        PushUpPhase.top &&
    baselineReady &&
    usableSignal;

  return _PushUpUpdate(
    repCounted: repCounted,

    // Torso does not have to look perfectly horizontal on screen.
    //
    // Support evidence is orientation-relative.
    poseValid:
        signalsAvailable &&
        (
          supportEvidence ||
          _pushUpCycleStartedAt != null
        ),

    exerciseActive:
        exerciseActive,

    signalsAvailable:
        true,

    ready:
        ready,
    debug: PushUpDebugData(
      poseDetected: true,
      signalsAvailable: true,
      trackedSide: _pushUpTrackedSide,
      shoulderConfidence:
          activeArm.shoulderConfidence,
      elbowConfidence:
          activeArm.elbowConfidence,
      wristConfidence:
          activeArm.wristConfidence,
      elbowAngle: elbowAngle,
      leftElbowAngle:
          leftArm?.angle,
      rightElbowAngle:
          rightArm?.angle,
      torsoHorizontal:
          torsoHorizontal,
      bodyAlignmentAngle:
          bodyAlignment,
      topCandidate:
          topCandidate,
      bottomCandidate:
          bottomCandidate,
      phase:
          _pushUpPhase,
      signalMissingMilliseconds: 0,
      repCounted:
          repCounted,
      topThreshold:
          _pushUpTopThreshold,
      bottomThreshold:
    _pushUpBottomThreshold,

    wristSupportEvidence:
        wristSupportEvidence,

    nonWristSupportEvidence:
        nonWristSupportEvidence,

    elbowPerpendicularity:
        elbowPerpendicularity,

    elbowSupportScore:
        elbowSupportScore,

    anchorTravel:
        anchorTravel,

    maxAnchorTravel:
        _pushUpMaxAnchorTravel,

    anchorElbowBend:
        anchorElbowBend,

    anchorUpperArmDelta:
        anchorUpperArmDelta,

    maxAnchorArmBend:
        _pushUpMaxAnchorArmBend,

    torsoOnlyTrackable:
        torsoOnlyTrackable,
    ),
  );
}

    _PushUpArmSample? _pushUpArm(
    Map<PoseLandmarkType, Offset> points,
    Map<PoseLandmarkType, double> confidences, {
    required bool right,
  }) {
    final shoulderType = right
        ? PoseLandmarkType.rightShoulder
        : PoseLandmarkType.leftShoulder;

    final elbowType = right
        ? PoseLandmarkType.rightElbow
        : PoseLandmarkType.leftElbow;

    final wristType = right
        ? PoseLandmarkType.rightWrist
        : PoseLandmarkType.leftWrist;

    final shoulder = points[shoulderType];
    final elbow = points[elbowType];
    final wrist = points[wristType];

    // Wrist is optional. Shoulder + elbow are enough to keep the arm alive
    // so the upper-arm fallback can continue the repetition.
    if (shoulder == null || elbow == null) {
      return null;
    }

    final shoulderConfidence = confidences[shoulderType] ?? 1;
    final elbowConfidence = confidences[elbowType] ?? 1;

    final wristConfidence =
        wrist == null ? null : (confidences[wristType] ?? 1);

    final weakestCoreConfidence =
        math.min(shoulderConfidence, elbowConfidence);

    final averageCoreConfidence =
        (shoulderConfidence + elbowConfidence) / 2;

    // Shoulder + elbow determine tracking quality.
    //
    // Wrist is additional measurement data, not a requirement.
    final score =
        weakestCoreConfidence * 0.70 +
        averageCoreConfidence * 0.30;

    return _PushUpArmSample(
      right: right,
      shoulder: shoulder,
      elbow: elbow,
      wrist: wrist,
      shoulderConfidence: shoulderConfidence,
      elbowConfidence: elbowConfidence,
      wristConfidence: wristConfidence,
      angle: wrist == null
          ? null
          : _angle(shoulder, elbow, wrist),
      score: score,
    );
  }

  _PushUpArmSample? _selectPushUpArm(
    _PushUpArmSample? left,
    _PushUpArmSample? right,
  ) {
    _PushUpArmSample? tracked = switch (_pushUpTrackedRight) {
      true => right,
      false => left,
      null => null,
    };

      if (tracked == null) {
  _PushUpArmSample? replacement;

  // Wrist visibility does not determine whether an arm is useful.
  //
  // Use whichever shoulder/elbow side currently has the better
  // tracking quality.
  if (left == null) {
    replacement = right;
  } else if (right == null) {
    replacement = left;
  } else {
    replacement =
        right.score > left.score
            ? right
            : left;
  }

      if (replacement != null) {
        _pushUpTrackedRight = replacement.right;
      }

      _pushUpSwitchCandidateRight = null;
      _pushUpSwitchCandidateFrames = 0;

      return replacement;
    }

    final alternate = tracked.right ? left : right;

    final safeToImproveSelection =
        _pushUpPhase == PushUpPhase.waitingForTop ||
        _pushUpPhase == PushUpPhase.top;

    if (safeToImproveSelection &&
        alternate != null &&
        alternate.score >= tracked.score + 0.16) {
      if (_pushUpSwitchCandidateRight == alternate.right) {
        _pushUpSwitchCandidateFrames++;
      } else {
        _pushUpSwitchCandidateRight = alternate.right;
        _pushUpSwitchCandidateFrames = 1;
      }

      if (_pushUpSwitchCandidateFrames >= 3) {
        _pushUpTrackedRight = alternate.right;
        _pushUpSwitchCandidateRight = null;
        _pushUpSwitchCandidateFrames = 0;
        tracked = alternate;
      }
    } else {
      _pushUpSwitchCandidateRight = null;
      _pushUpSwitchCandidateFrames = 0;
    }

    return tracked;
  }


void _slowlyAdaptPushUpAnchor({
  required bool right,
  required Offset torsoCenter,
  required Offset torsoNormal,
  required double torsoLength,
  required double upperArmAngle,
  required double? elbowAngle,
}) {
  if (_pushUpAnchorLocked[right] != true) {
    return;
  }

  // Much slower than the adaptive top baseline.
  const alpha = 0.02;

  final oldCenter =
      _pushUpAnchorTorsoCenters[right];

  if (oldCenter != null) {
    _pushUpAnchorTorsoCenters[right] =
        Offset(
      oldCenter.dx * (1 - alpha) +
          torsoCenter.dx * alpha,
      oldCenter.dy * (1 - alpha) +
          torsoCenter.dy * alpha,
    );
  }

  final oldLength =
      _pushUpAnchorTorsoLengths[right];

  if (oldLength != null) {
    _pushUpAnchorTorsoLengths[right] =
        oldLength * (1 - alpha) +
        torsoLength * alpha;
  }

  final oldUpperArm =
      _pushUpAnchorUpperArmBaselines[right];

  if (oldUpperArm != null) {
    _pushUpAnchorUpperArmBaselines[right] =
        oldUpperArm * (1 - alpha) +
        upperArmAngle * alpha;
  }

  if (elbowAngle != null) {
    final oldElbow =
        _pushUpAnchorElbowBaselines[right];

    if (oldElbow != null) {
      _pushUpAnchorElbowBaselines[right] =
          oldElbow * (1 - alpha) +
          elbowAngle * alpha;
    }
  }

  final oldNormal =
      _pushUpAnchorTorsoNormals[right];

  if (oldNormal != null) {
    final blended = Offset(
      oldNormal.dx * (1 - alpha) +
          torsoNormal.dx * alpha,
      oldNormal.dy * (1 - alpha) +
          torsoNormal.dy * alpha,
    );

    final normalLength =
        blended.distance;

    if (normalLength > 0.0001) {
      _pushUpAnchorTorsoNormals[right] =
          Offset(
        blended.dx / normalLength,
        blended.dy / normalLength,
      );
    }
  }
}

void _recordPushUpTopBaseline({
  required bool right,
  required double? elbowAngle,
  required double upperArmAngle,
  required Offset torsoCenter,
  required Offset torsoNormal,
  required double torsoLength,
}) {

  final samples =
      _pushUpUpperArmBaselineSamples[right] ?? 0;

  final alpha =
      samples < 3 ? 0.45 : 0.12;

  double blend(
    double? previous,
    double current,
  ) =>
      previous == null
      ? current
      : previous * (1 - alpha) +
          current * alpha;

  Offset blendOffset(
    Offset? previous,
    Offset current,
  ) =>
      previous == null
      ? current
      : Offset(
          previous.dx * (1 - alpha) +
              current.dx * alpha,
          previous.dy * (1 - alpha) +
              current.dy * alpha,
        );

// Only maintain an elbow-angle baseline when the wrist exists
// strongly enough to calculate one.
//
// Missing wrist must not stop torso/upper-arm calibration.
if (elbowAngle != null) {
  _pushUpTopElbowBaselines[right] =
      blend(
    _pushUpTopElbowBaselines[right],
    elbowAngle,
  );
}

  _pushUpUpperArmTopBaselines[right] =
      blend(
    _pushUpUpperArmTopBaselines[right],
    upperArmAngle,
  );

  _pushUpTopTorsoCenters[right] =
      blendOffset(
    _pushUpTopTorsoCenters[right],
    torsoCenter,
  );

  _pushUpTopTorsoLengths[right] =
      blend(
    _pushUpTopTorsoLengths[right],
    torsoLength,
  );

  final blendedNormal =
      blendOffset(
    _pushUpTopTorsoNormals[right],
    torsoNormal,
  );

  final normalLength =
      blendedNormal.distance;

  _pushUpTopTorsoNormals[right] =
      normalLength <= 0.0001
      ? torsoNormal
      : Offset(
          blendedNormal.dx /
              normalLength,
          blendedNormal.dy /
              normalLength,
        );

final updatedSamples =
    math.min(samples + 1, 30);

_pushUpUpperArmBaselineSamples[right] =
    updatedSamples;


// ============================================================
// INITIAL ANCHOR
// ============================================================
//
// Do not trust the first frame.
// Let the adaptive top baseline settle first.

if (_pushUpAnchorLocked[right] != true &&
    updatedSamples >= 3) {
  final adaptiveCenter =
      _pushUpTopTorsoCenters[right];

  final adaptiveNormal =
      _pushUpTopTorsoNormals[right];

  final adaptiveLength =
      _pushUpTopTorsoLengths[right];

  final adaptiveUpperArm =
      _pushUpUpperArmTopBaselines[right];

  if (adaptiveCenter != null &&
      adaptiveNormal != null &&
      adaptiveLength != null &&
      adaptiveUpperArm != null) {
    _pushUpAnchorTorsoCenters[right] =
        adaptiveCenter;

    _pushUpAnchorTorsoNormals[right] =
        adaptiveNormal;

    _pushUpAnchorTorsoLengths[right] =
        adaptiveLength;

    _pushUpAnchorUpperArmBaselines[right] =
        adaptiveUpperArm;

    final adaptiveElbow =
        _pushUpTopElbowBaselines[right];

    if (adaptiveElbow != null) {
      _pushUpAnchorElbowBaselines[right] =
          adaptiveElbow;
    }

    _pushUpAnchorLocked[right] = true;

    _pushUpAnchorDisagreementFrames[right] =
        0;
  }
}


// ============================================================
// EARLY BAD-ANCHOR RECOVERY
// ============================================================
//
// If the first anchor was based on a bad/noisy calibration,
// allow it to reopen only after several consecutive top samples
// disagree with it.

if (_pushUpAnchorLocked[right] == true &&
    updatedSamples <= 8) {
  final adaptiveLength =
      _pushUpTopTorsoLengths[right];

  final anchorLength =
      _pushUpAnchorTorsoLengths[right];

  if (adaptiveLength != null &&
      anchorLength != null &&
      anchorLength > 0.02) {
    final disagreement =
        (adaptiveLength - anchorLength)
                .abs() /
            anchorLength;

    if (disagreement > 0.25) {
      _pushUpAnchorDisagreementFrames[right] =
          (_pushUpAnchorDisagreementFrames[right] ?? 0) + 1;
    } else {
      _pushUpAnchorDisagreementFrames[right] = 0;
    }

    if ((_pushUpAnchorDisagreementFrames[right] ?? 0) >= 3) {
      _pushUpAnchorLocked[right] = false;

      _pushUpAnchorTorsoCenters.remove(right);
      _pushUpAnchorTorsoNormals.remove(right);
      _pushUpAnchorTorsoLengths.remove(right);

      _pushUpAnchorElbowBaselines.remove(right);
      _pushUpAnchorUpperArmBaselines.remove(right);

      _pushUpAnchorDisagreementFrames[right] = 0;
    }
  }
}

// closes _recordPushUpTopBaseline()
}





  double? _pushUpBodyAlignment(
    Map<PoseLandmarkType, Offset> points,
    _PushUpArmSample? selectedArm,
  ) {
    if (selectedArm != null) {
      final hip = points[selectedArm.right
          ? PoseLandmarkType.rightHip
          : PoseLandmarkType.leftHip];

      final knee = points[selectedArm.right
          ? PoseLandmarkType.rightKnee
          : PoseLandmarkType.leftKnee];

      if (hip != null && knee != null) {
        return _angle(selectedArm.shoulder, hip, knee);
      }
    }

    return _average(_bodyAlignmentAngles(points));
  }

  void _resetPushUpPhase() {
    _pushUpPhase = PushUpPhase.waitingForTop;
    _pushUpConfirmationFrames = 0;
    _lastPushUpUsableSignalAt = null;
    _pushUpCycleStartedAt = null;
    _pushUpMaxTravel = 0;
    _pushUpMaxArmBend = 0;
    _pushUpMaxAnchorTravel = null;
    _pushUpMaxAnchorArmBend = null;
  
    _pushUpSmoothedElbowAngle = null;
    _pushUpSmoothedTorsoCenter = null;
    _cycleTargetReached = false;
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
        (_completeSide(points, const [
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftElbow,
            ]) ||
            _completeSide(points, const [
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightElbow,
            ])) &&
        _hasAny(points, const [
          PoseLandmarkType.leftHip,
          PoseLandmarkType.rightHip,
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
      // Push-ups are side-on, so the far side of the body may be hidden.
      if (exercise == WorkoutExercise.pushUps) {
        if (!semanticReady) {
          return WorkoutBodyCoverage.insufficient;
        }

            return visible >= 5
          ? WorkoutBodyCoverage.excellent
          : WorkoutBodyCoverage.good;
      }

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
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
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

class _PushUpUpdate {
  const _PushUpUpdate({
    required this.repCounted,
    required this.poseValid,
    required this.exerciseActive,
    required this.signalsAvailable,
    required this.ready,
    required this.debug,
  });

  final bool repCounted;
  final bool poseValid;
  final bool exerciseActive;
  final bool signalsAvailable;
  final bool ready;
  final PushUpDebugData debug;
}

class _PushUpArmSample {
  const _PushUpArmSample({
    required this.right,
    required this.shoulder,
    required this.elbow,
    required this.wrist,
    required this.shoulderConfidence,
    required this.elbowConfidence,
    required this.wristConfidence,
    required this.angle,
    required this.score,
  });

  final bool right;
  final Offset shoulder;
  final Offset elbow;
  final Offset? wrist;

  final double shoulderConfidence;
  final double elbowConfidence;
  final double? wristConfidence;

  final double? angle;
  final double score;

  bool get hasWrist => wrist != null && angle != null;
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
    required this.confidences,
    required this.timestamp,
    required this.center,
    required this.bounds,
    required this.bodyScale,
  });

  factory _PoseSample.from(
    Map<PoseLandmarkType, Offset> landmarks,
    DateTime timestamp, {
    Map<PoseLandmarkType, double> confidences = const {},
  }) {
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
      confidences: confidences,
      timestamp: timestamp,
      center: center,
      bounds: bounds,
      bodyScale: math.max(bodyScale, 0.05),
    );
  }

  final Map<PoseLandmarkType, Offset> landmarks;
  final Map<PoseLandmarkType, double> confidences;
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

import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    hide InputImage, InputImageMetadata, InputImageFormat, InputImageRotation;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    hide InputImage, InputImageMetadata, InputImageFormat, InputImageRotation;

import 'active_camera_preview_page.dart';
import 'object_scan_page.dart';
import 'object_scan_repository.dart';
import 'workout_camera_preview_page.dart';

// =============================================================
// TASK ICON TYPES
// =============================================================

enum TaskIconType {
  generic,
  study,
  cleaning,
  workout,
  running,
  computer,
  cooking,
  laundry,
  meditation,
  garden,
  sleep,
  shopping,
  hydration,
  health,
  music,
  phone,
  pet,
  selfCare,
}

// =============================================================
// TASK STATUS
// =============================================================

enum TaskStatus {
  ready,
  scheduled,
  live,
  completed,
}

enum TaskMode { focus, active, workout }

enum FocusActivity {
  general,
  reading,
  writingNotes,
  computerWork,
}

enum ActivityLevel { light, moderate, high }

enum WorkoutMovementType { repetitions, hold, continuous }

enum WorkoutExercise {
  pushUps,
  squats,
  jumpingJacks,
  lunges,
  sitUps,
  burpees,
  mountainClimbers,
  highKnees,
  plank,
  wallSit,
  runningInPlace,
  jumpRope,
}

enum WorkoutCameraOrientation {
  portrait,
  landscape,
}
WorkoutCameraOrientation workoutCameraOrientation =
    WorkoutCameraOrientation.portrait;

// =============================================================
// REFERENCE POSE
// =============================================================

class PoseReference {
  const PoseReference({
    required this.landmarks,
    required this.centerX,
    required this.centerY,
    required this.poseScale,
    this.headYaw,
    this.headPitch,
    this.headRoll,
    this.faceDetected = false,
    this.faceTrackingEnabled = false,
    this.bodyAxisAngle,
  });

  final Map<PoseLandmarkType, Offset> landmarks;

  final double centerX;
  final double centerY;
  final double poseScale;

  final double? headYaw;
  final double? headPitch;
  final double? headRoll;

  final bool faceDetected;
  final bool faceTrackingEnabled;

  final double? bodyAxisAngle;
}

class FocusPoseMetrics {
  const FocusPoseMetrics({
    required this.commonLandmarkCount,
    required this.requiredLandmarkCount,
    required this.centerMovement,
    required this.scaleDifference,
    this.structuralDeviation,
    this.bodyAxisDifference,
  });

  final int commonLandmarkCount;
  final int requiredLandmarkCount;

  final double centerMovement;
  final double scaleDifference;

  final double? structuralDeviation;
  final double? bodyAxisDifference;

  bool get hasEnoughCoverage =>
      commonLandmarkCount >= requiredLandmarkCount;
}

// =============================================================
// TASK DATA
// =============================================================
// =============================================================
// TASK DATA
// =============================================================
class ActiveTaskConfig {
  const ActiveTaskConfig({
    required this.activityLevel,
    required this.inactivityWarning,
    required this.briefExitAllowance,
    this.requiredObjectIds = const [],
  });

  final ActivityLevel activityLevel;
  final Duration inactivityWarning;
  final Duration briefExitAllowance;

  final List<String> requiredObjectIds;
}

class WorkoutTaskConfig {
  const WorkoutTaskConfig({
    required this.movementType,
    required this.exercise,
    required this.repGoal,
    required this.targetDuration,
    required this.restLimit,
    required this.formChecking,
    this.cameraOrientation = WorkoutCameraOrientation.portrait,
  });

  final WorkoutMovementType movementType;
  final WorkoutExercise exercise;

  final int repGoal;

  final Duration targetDuration;

  final Duration restLimit;

  final bool formChecking;

  final WorkoutCameraOrientation cameraOrientation;
}

class TaskData {
  TaskData({
    required this.id,
    required this.name,
    required this.icon,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.mode,
    required this.stayInPosition,
    required this.objectInFrame,
    required this.alarm,
    required this.sensitivity,
    this.focusActivity = FocusActivity.general,
    this.poseReference,
    this.requiredObjectIds = const [],
    this.activeConfig,
    this.workoutConfig,
    this.status = TaskStatus.ready,
    this.scheduledFor,
    this.startedAt,
    this.completedAt,
    this.scheduleAlertShown = false,
  });
  final TaskMode mode;

  final ActiveTaskConfig? activeConfig;

  final WorkoutTaskConfig? workoutConfig;

  final String id;
  final String name;

  final TaskIconType icon;

  final int hours;
  final int minutes;
  final int seconds;

  final bool stayInPosition;
  final bool objectInFrame;

  final String alarm;
  final double sensitivity;

  final FocusActivity focusActivity;

  // Mutable because a task can calibrate when
  // the live session starts.
  PoseReference? poseReference;

  // Saved 3D objects required for Focus verification.
  final List<String> requiredObjectIds;

  TaskStatus status;

  DateTime? scheduledFor;
  DateTime? startedAt;
  DateTime? completedAt;

  bool scheduleAlertShown;

  Duration get duration {
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }
}

// =============================================================
// CAMERA FRAME FOR ML KIT
// =============================================================

class MlKitCameraFrame {
  const MlKitCameraFrame({required this.inputImage, required this.imageSize});

  final InputImage inputImage;

  final Size imageSize;
}

// =============================================================
// CAMERA IMAGE -> ML KIT IMAGE
// =============================================================

class MlKitCameraImageConverter {
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // ===========================================================
  // MOBILE SUPPORT
  // ===========================================================

  static bool get supported {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ===========================================================
  // CAMERA FORMAT
  // ===========================================================

  static ImageFormatGroup get cameraFormat {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ImageFormatGroup.bgra8888;
    }

    return ImageFormatGroup.nv21;
  }

  // ===========================================================
  // CONVERT
  // ===========================================================

  static MlKitCameraFrame? convert({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    if (!supported) {
      return null;
    }

    // =========================================================
    // ROTATION
    // =========================================================

    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      var rotationCompensation = _orientations[deviceOrientation];

      if (rotationCompensation == null) {
        return null;
      }

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }

      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) {
      return null;
    }

    // =========================================================
    // IMAGE FORMAT
    // =========================================================

    final rawFormat = image.format.raw;

    if (rawFormat is! int) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(rawFormat);

    if (format == null) {
      return null;
    }

    if (defaultTargetPlatform == TargetPlatform.android &&
        format != InputImageFormat.nv21) {
      return null;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS &&
        format != InputImageFormat.bgra8888) {
      return null;
    }

    if (image.planes.length != 1) {
      return null;
    }

    final plane = image.planes.first;

    // =========================================================
    // BUILD INPUT IMAGE
    // =========================================================

    final rawSize = Size(image.width.toDouble(), image.height.toDouble());

    final inputImage = InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: rawSize,
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );

    final coordinateSize =
        defaultTargetPlatform == TargetPlatform.android &&
            (rotation == InputImageRotation.rotation90deg ||
                rotation == InputImageRotation.rotation270deg)
        ? Size(rawSize.height, rawSize.width)
        : rawSize;

    return MlKitCameraFrame(inputImage: inputImage, imageSize: coordinateSize);
  }
}

// =============================================================
// POSE ANALYZER
// =============================================================

class TaskPoseAnalyzer {
  static const double _landmarkLikelihood = 0.35;

  // Landmarks useful for comparing major posture changes.
  // Hands/wrists are intentionally excluded because normal
  // writing/reaching should not drastically affect posture.
  static const Set<PoseLandmarkType> _structuralTypes = {
    PoseLandmarkType.nose,
    PoseLandmarkType.leftEar,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  };

  // Prefer these landmarks for determining whether the person
  // moved out of their focus area. Elbows/wrists are excluded
  // because they move naturally while studying.
  static const Set<PoseLandmarkType> _positionAnchorTypes = {
    PoseLandmarkType.nose,
    PoseLandmarkType.leftEye,
    PoseLandmarkType.rightEye,
    PoseLandmarkType.leftEar,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  };

  // Used only when the normal shoulder/hip body axis
  // cannot be calculated.
  static const Set<PoseLandmarkType> _orientationFallbackTypes = {
    PoseLandmarkType.nose,
    PoseLandmarkType.leftEar,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  };

  // ===========================================================
  // CREATE ONE LIVE SNAPSHOT
  // ===========================================================

  static PoseReference? createSnapshot({
    required List<Pose> poses,
    required List<Face> faces,
    required Size imageSize,
  }) {
    if (poses.isEmpty ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return null;
    }

    Pose? bestPose;
    var bestVisibleCount = 0;

    // Select the pose that has the most confidently
    // visible landmarks.
    for (final pose in poses) {
      var visibleCount = 0;

      for (final landmark in pose.landmarks.values) {
        if (landmark.likelihood >= _landmarkLikelihood) {
          visibleCount++;
        }
      }

      if (visibleCount > bestVisibleCount) {
        bestVisibleCount = visibleCount;
        bestPose = pose;
      }
    }

    if (bestPose == null || bestVisibleCount < 4) {
      return null;
    }

    final visibleLandmarks =
        <PoseLandmarkType, Offset>{};

    for (final entry in bestPose.landmarks.entries) {
      final landmark = entry.value;

      if (landmark.likelihood < _landmarkLikelihood) {
        continue;
      }

      visibleLandmarks[entry.key] = Offset(
        landmark.x / imageSize.width,
        landmark.y / imageSize.height,
      );
    }

    if (visibleLandmarks.length < 4) {
      return null;
    }

    final geometry =
        _geometryFor(visibleLandmarks);

    // Associate the face with the selected body instead of
    // blindly choosing the largest face in the frame.
    final face = _selectFaceForPose(
      pose: bestPose,
      faces: faces,
      imageSize: imageSize,
    );

    final hasFaceOrientation =
        face != null &&
        (
          face.headEulerAngleY != null ||
          face.headEulerAngleX != null
        );

    return PoseReference(
      landmarks: visibleLandmarks,
      centerX: geometry.center.dx,
      centerY: geometry.center.dy,
      poseScale: geometry.scale,
      headYaw: face?.headEulerAngleY,
      headPitch: face?.headEulerAngleX,
      headRoll: face?.headEulerAngleZ,
      faceDetected: face != null,
      faceTrackingEnabled: hasFaceOrientation,
      bodyAxisAngle:
          _bodyAxisAngleFor(visibleLandmarks),
    );
  }

  // ===========================================================
  // BUILD ADAPTIVE REFERENCE
  // ===========================================================

  static PoseReference? buildAdaptiveReference(
    List<PoseReference> samples,
  ) {
    final validSamples = samples
        .where(
          (sample) => sample.landmarks.length >= 3,
        )
        .toList(growable: false);

    // Don't calibrate from one accidental frame.
    if (validSamples.length < 4) {
      return null;
    }

    // A landmark must be present in at least 65% of
    // calibration frames to become part of the reference.
    final requiredAppearances =
        (validSamples.length * 0.65).ceil();

    final counts =
        <PoseLandmarkType, int>{};

    for (final sample in validSamples) {
      for (final type in sample.landmarks.keys) {
        counts.update(
          type,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final stableTypes = counts.entries
        .where(
          (entry) =>
              entry.value >= requiredAppearances,
        )
        .map((entry) => entry.key)
        .toList(growable: false);

    if (stableTypes.length < 3) {
      return null;
    }

    final averagedLandmarks =
        <PoseLandmarkType, Offset>{};

    for (final type in stableTypes) {
      var totalX = 0.0;
      var totalY = 0.0;
      var count = 0;

      for (final sample in validSamples) {
        final point = sample.landmarks[type];

        if (point == null) {
          continue;
        }

        totalX += point.dx;
        totalY += point.dy;
        count++;
      }

      if (count > 0) {
        averagedLandmarks[type] = Offset(
          totalX / count,
          totalY / count,
        );
      }
    }

    if (averagedLandmarks.length < 3) {
      return null;
    }

    final geometry =
        _geometryFor(averagedLandmarks);

    // Face tracking is enabled ONLY if the face was
    // consistently usable during calibration.
    final faceSamples = validSamples
        .where(
          (sample) =>
              sample.faceDetected &&
              (
                sample.headYaw != null ||
                sample.headPitch != null
              ),
        )
        .toList(growable: false);

    final requiredFaceSamples = math.max(
      3,
      (validSamples.length * 0.55).ceil(),
    );

    final faceTrackingEnabled =
        faceSamples.length >= requiredFaceSamples;

    return PoseReference(
      landmarks: averagedLandmarks,
      centerX: geometry.center.dx,
      centerY: geometry.center.dy,
      poseScale: geometry.scale,

      headYaw: faceTrackingEnabled
          ? _averageNullable(
              faceSamples.map(
                (sample) => sample.headYaw,
              ),
            )
          : null,

      headPitch: faceTrackingEnabled
          ? _averageNullable(
              faceSamples.map(
                (sample) => sample.headPitch,
              ),
            )
          : null,

      headRoll: faceTrackingEnabled
          ? _averageNullable(
              faceSamples.map(
                (sample) => sample.headRoll,
              ),
            )
          : null,

      faceDetected: faceTrackingEnabled,
      faceTrackingEnabled: faceTrackingEnabled,

      bodyAxisAngle:
          _bodyAxisAngleFor(averagedLandmarks),
    );
  }

  // ===========================================================
  // COMPARE LIVE POSITION TO REFERENCE
  // ===========================================================

  static FocusPoseMetrics compareToReference({
    required PoseReference reference,
    required PoseReference current,
  }) {
    // Only compare landmarks that belonged to the
    // calibrated reference AND still exist now.
    final commonTypes = reference.landmarks.keys
        .where(current.landmarks.containsKey)
        .toList(growable: false);

    final requiredCount = math.max(
      3,
      (reference.landmarks.length * 0.50).ceil(),
    );

    if (commonTypes.length < 3) {
      return FocusPoseMetrics(
        commonLandmarkCount:
            commonTypes.length,
        requiredLandmarkCount:
            requiredCount,
        centerMovement:
            double.infinity,
        scaleDifference:
            double.infinity,
      );
    }

    final referenceCommon =
        <PoseLandmarkType, Offset>{
      for (final type in commonTypes)
        type: reference.landmarks[type]!,
    };

    final currentCommon =
        <PoseLandmarkType, Offset>{
      for (final type in commonTypes)
        type: current.landmarks[type]!,
    };

    // Prefer stable head/torso/leg anchors for location.
    // Hands and elbows should not move the person's
    // calculated focus area while writing.
    final preferredPositionTypes = commonTypes
        .where(_positionAnchorTypes.contains)
        .toList(growable: false);

    final positionTypes =
        preferredPositionTypes.length >= 2
        ? preferredPositionTypes
        : commonTypes;

    final referencePosition =
        <PoseLandmarkType, Offset>{
      for (final type in positionTypes)
        type: reference.landmarks[type]!,
    };

    final currentPosition =
        <PoseLandmarkType, Offset>{
      for (final type in positionTypes)
        type: current.landmarks[type]!,
    };

    final referenceGeometry =
        _geometryFor(referencePosition);

    final currentGeometry =
        _geometryFor(currentPosition);

    final centerMovement =
        (
          currentGeometry.center -
          referenceGeometry.center
        ).distance;

    final scaleDifference =
        referenceGeometry.scale <= 0.001
        ? 0.0
        : (
            (
              currentGeometry.scale -
              referenceGeometry.scale
            ).abs() /
            referenceGeometry.scale
          );

    // =========================================================
    // MAJOR POSTURE CHANGE
    // =========================================================

    final structuralTypes = commonTypes
        .where(_structuralTypes.contains)
        .toList(growable: false);

    double? structuralDeviation;

    if (structuralTypes.length >= 3) {
      final refStructural =
          <PoseLandmarkType, Offset>{
        for (final type in structuralTypes)
          type: reference.landmarks[type]!,
      };

      final curStructural =
          <PoseLandmarkType, Offset>{
        for (final type in structuralTypes)
          type: current.landmarks[type]!,
      };

      final refGeometry =
          _geometryFor(refStructural);

      final curGeometry =
          _geometryFor(curStructural);

      if (refGeometry.scale > 0.001 &&
          curGeometry.scale > 0.001) {
        var totalDeviation = 0.0;

        for (final type in structuralTypes) {
          final refPoint =
              (
                refStructural[type]! -
                refGeometry.center
              ) /
              refGeometry.scale;

          final curPoint =
              (
                curStructural[type]! -
                curGeometry.center
              ) /
              curGeometry.scale;

          totalDeviation +=
              (curPoint - refPoint).distance;
        }

        structuralDeviation =
            totalDeviation /
            structuralTypes.length;
      }
    }

    // =========================================================
    // BODY ORIENTATION
    // =========================================================

    final referenceAxis =
        _bodyAxisAngleFor(referenceCommon);

    final currentAxis =
        _bodyAxisAngleFor(currentCommon);

    final bodyAxisDifference =
        referenceAxis != null &&
        currentAxis != null
        ? _axisAngleDifference(
            referenceAxis,
            currentAxis,
          )
        : null;

    return FocusPoseMetrics(
      commonLandmarkCount:
          commonTypes.length,
      requiredLandmarkCount:
          requiredCount,
      centerMovement:
          centerMovement,
      scaleDifference:
          scaleDifference,
      structuralDeviation:
          structuralDeviation,
      bodyAxisDifference:
          bodyAxisDifference,
    );
  }

  // ===========================================================
  // HAND/FIDGET MOVEMENT
  // ===========================================================

  static double handMotion({
    required PoseReference reference,
    required PoseReference current,
    PoseReference? previous,
  }) {
    if (previous == null) {
      return 0.0;
    }

    const wristTypes = {
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
    };

    var total = 0.0;
    var count = 0;

    for (final type in wristTypes) {
      // Only use a wrist if it belonged to the
      // original calibrated view.
      if (!reference.landmarks.containsKey(type)) {
        continue;
      }

      final currentPoint =
          current.landmarks[type];

      final previousPoint =
          previous.landmarks[type];

      if (currentPoint == null ||
          previousPoint == null) {
        continue;
      }

      total +=
          (currentPoint - previousPoint).distance;

      count++;
    }

    if (count == 0) {
      return 0.0;
    }

    // Normalize movement based on apparent body size,
    // so moving closer to the camera doesn't drastically
    // change fidget sensitivity.
    final normalizer =
        math.max(reference.poseScale, 0.03);

    return (total / count) / normalizer;
  }

  // ===========================================================
  // MATCH FACE TO SELECTED PERSON
  // ===========================================================

  static Face? _selectFaceForPose({
    required Pose pose,
    required List<Face> faces,
    required Size imageSize,
  }) {
    if (faces.isEmpty) {
      return null;
    }

    final nose =
        pose.landmarks[PoseLandmarkType.nose];

    // If there is no reliable nose, don't risk attaching
    // someone else's face to this body.
    if (nose == null ||
        nose.likelihood < _landmarkLikelihood) {
      return null;
    }

    final headPoint =
        Offset(nose.x, nose.y);

    Face? bestFace;
    var bestDistance = double.infinity;

    for (final face in faces) {
      final distance =
          (
            face.boundingBox.center -
            headPoint
          ).distance;

      if (distance < bestDistance) {
        bestDistance = distance;
        bestFace = face;
      }
    }

    if (bestFace == null) {
      return null;
    }

    final shortSide = math.min(
      imageSize.width,
      imageSize.height,
    );

    // Only accept the face if it is actually close
    // to the selected pose's head.
    if (
      bestFace.boundingBox
              .inflate(shortSide * 0.04)
              .contains(headPoint) ||
      bestDistance <= shortSide * 0.22
    ) {
      return bestFace;
    }

    return null;
  }

  // ===========================================================
  // BODY ORIENTATION
  // ===========================================================

  static double? _bodyAxisAngleFor(
    Map<PoseLandmarkType, Offset> landmarks,
  ) {
    final shoulderMid = _midpoint(
      landmarks[
          PoseLandmarkType.leftShoulder],
      landmarks[
          PoseLandmarkType.rightShoulder],
    );

    final hipMid = _midpoint(
      landmarks[
          PoseLandmarkType.leftHip],
      landmarks[
          PoseLandmarkType.rightHip],
    );

    Offset? upper;
    Offset? lower;

    // Best case: shoulders -> hips.
    if (shoulderMid != null &&
        hipMid != null) {
      upper = shoulderMid;
      lower = hipMid;
    } else {
      final nose =
          landmarks[PoseLandmarkType.nose];

      // Good for upper-body-only camera views.
      if (nose != null &&
          shoulderMid != null) {
        upper = nose;
        lower = shoulderMid;
      } else {
        final leftShoulder =
            landmarks[
                PoseLandmarkType.leftShoulder];

        final leftHip =
            landmarks[
                PoseLandmarkType.leftHip];

        final rightShoulder =
            landmarks[
                PoseLandmarkType.rightShoulder];

        final rightHip =
            landmarks[
                PoseLandmarkType.rightHip];

        if (leftShoulder != null &&
            leftHip != null) {
          upper = leftShoulder;
          lower = leftHip;
        } else if (
          rightShoulder != null &&
          rightHip != null
        ) {
          upper = rightShoulder;
          lower = rightHip;
        }
      }
    }

    if (upper != null &&
        lower != null) {
      final delta = lower - upper;

      if (delta.distance >= 0.01) {
        return math.atan2(
              delta.dy,
              delta.dx,
            ) *
            180 /
            math.pi;
      }
    }

    // Fallback for unusual framing, for example
    // shoulders + elbows but no hips/head.
    final fallbackPoints = landmarks.entries
        .where(
          (entry) =>
              _orientationFallbackTypes
                  .contains(entry.key),
        )
        .map((entry) => entry.value)
        .toList(growable: false);

    if (fallbackPoints.length < 4) {
      return null;
    }

    var meanX = 0.0;
    var meanY = 0.0;

    for (final point in fallbackPoints) {
      meanX += point.dx;
      meanY += point.dy;
    }

    meanX /= fallbackPoints.length;
    meanY /= fallbackPoints.length;

    var covarianceXX = 0.0;
    var covarianceYY = 0.0;
    var covarianceXY = 0.0;

    for (final point in fallbackPoints) {
      final dx = point.dx - meanX;
      final dy = point.dy - meanY;

      covarianceXX += dx * dx;
      covarianceYY += dy * dy;
      covarianceXY += dx * dy;
    }

    if (
      (covarianceXX + covarianceYY) <
      0.0001
    ) {
      return null;
    }

    return 0.5 *
        math.atan2(
          2 * covarianceXY,
          covarianceXX - covarianceYY,
        ) *
        180 /
        math.pi;
  }

  static double _axisAngleDifference(
    double first,
    double second,
  ) {
    final difference =
        angleDifference(first, second);

    // A body axis has no arrow direction:
    // 0° and 180° represent the same line.
    return difference > 90
        ? 180 - difference
        : difference;
  }

  static Offset? _midpoint(
    Offset? first,
    Offset? second,
  ) {
    if (first == null ||
        second == null) {
      return null;
    }

    return Offset(
      (first.dx + second.dx) / 2,
      (first.dy + second.dy) / 2,
    );
  }

  // ===========================================================
  // GEOMETRY
  // ===========================================================

  static _PoseGeometry _geometryFor(
    Map<PoseLandmarkType, Offset> landmarks,
  ) {
    var totalX = 0.0;
    var totalY = 0.0;

    for (final point in landmarks.values) {
      totalX += point.dx;
      totalY += point.dy;
    }

    final center = Offset(
      totalX / landmarks.length,
      totalY / landmarks.length,
    );

    var totalDistanceSquared = 0.0;

    for (final point in landmarks.values) {
      final delta = point - center;

      totalDistanceSquared +=
          (delta.dx * delta.dx) +
          (delta.dy * delta.dy);
    }

    final scale = math.sqrt(
      totalDistanceSquared /
      landmarks.length,
    );

    return _PoseGeometry(
      center: center,
      scale: scale,
    );
  }

  static double? _averageNullable(
    Iterable<double?> values,
  ) {
    var total = 0.0;
    var count = 0;

    for (final value in values) {
      if (value == null) {
        continue;
      }

      total += value;
      count++;
    }

    return count == 0
        ? null
        : total / count;
  }

  // ===========================================================
  // ANGLE DIFFERENCE
  // ===========================================================

  static double angleDifference(
    double first,
    double second,
  ) {
    var difference =
        (first - second).abs();

    while (difference > 360) {
      difference -= 360;
    }

    if (difference > 180) {
      difference =
          360 - difference;
    }

    return difference.abs();
  }
}

class _PoseGeometry {
  const _PoseGeometry({
    required this.center,
    required this.scale,
  });

  final Offset center;
  final double scale;
}

// =============================================================
// NEW TASK PAGE
// =============================================================

class NewTaskPage extends StatefulWidget {
  const NewTaskPage({super.key, this.isDarkMode = false});

  final bool isDarkMode;

  @override
  State<NewTaskPage> createState() => _NewTaskPageState();
}

class _NewTaskPageState extends State<NewTaskPage> {
  // ===========================================================
  // TASK NAME
  // ===========================================================

  final TextEditingController taskNameController = TextEditingController();

  // ===========================================================
  // DURATION
  // ===========================================================

  late final FixedExtentScrollController _hoursController;

  late final FixedExtentScrollController _minutesController;

  late final FixedExtentScrollController _secondsController;

  late final FixedExtentScrollController _repGoalController;

  int hours = 0;
  int minutes = 0;
  int seconds = 0;

  late final ValueNotifier<int> _hoursValue;
  late final ValueNotifier<int> _minutesValue;
  late final ValueNotifier<int> _secondsValue;

  late final ValueNotifier<int> _repGoalValue;

  // ===========================================================
  // SCHEDULE
  // ===========================================================

  bool scheduleEnabled = false;

  DateTime? selectedScheduleDate;

  TimeOfDay? selectedScheduleTime;

  // ===========================================================
  // VERIFICATION
  // ===========================================================

  bool stayInPosition = true;

  bool objectInFrame = false;

  TaskMode selectedMode = TaskMode.focus;

FocusActivity focusActivity = FocusActivity.general;

// ACTIVE
ActivityLevel activityLevel = ActivityLevel.moderate;

Duration inactivityWarning = const Duration(minutes: 2);
Duration briefExitAllowance = const Duration(seconds: 30);

// WORKOUT
WorkoutMovementType workoutMovementType = WorkoutMovementType.repetitions;
  WorkoutExercise selectedExercise = WorkoutExercise.pushUps;

  int workoutRepGoal = 20;

  Duration workoutTargetDuration = const Duration(minutes: 1);

  Duration workoutRestLimit = const Duration(seconds: 30);

  bool workoutFormChecking = false;
  // ===========================================================
  // REFERENCE
  // ===========================================================

  PoseReference? referencePose;

  final List<SavedObjectScan> selectedObjectScans = [];

  // ===========================================================
  // SETTINGS
  // ===========================================================

  double sensitivity = .5;

  late final ValueNotifier<double> _sensitivityValue;

  String selectedAlarm = 'Default Alarm';

  // ===========================================================
  // ICON
  // ===========================================================

  TaskIconType selectedTaskIcon = TaskIconType.generic;

  bool taskIconManuallySelected = false;

  // Change when subscriptions are connected.
  // ===========================================================
// TEMPORARY PRO TESTING
// ===========================================================

// Set to true to test as a Pro user.
// Set to false to test as a Free user.
// IMPORTANT: Turn this off before production release.
  static const bool _forceProForTesting = true;

  bool get isPro => _forceProForTesting;
  // ===========================================================
  // INIT
  // ===========================================================

  @override
  void initState() {
    super.initState();

    _hoursController = FixedExtentScrollController(initialItem: hours);

    _minutesController = FixedExtentScrollController(initialItem: minutes);

    _secondsController = FixedExtentScrollController(initialItem: seconds);

    _repGoalController = FixedExtentScrollController(
      initialItem: workoutRepGoal - 1,
    );

    _hoursValue = ValueNotifier(hours);

    _minutesValue = ValueNotifier(minutes);

    _secondsValue = ValueNotifier(seconds);

    _repGoalValue = ValueNotifier(workoutRepGoal);

    _sensitivityValue = ValueNotifier(sensitivity);
  }

  @override
  void dispose() {
    taskNameController.dispose();

    _hoursController.dispose();

    _minutesController.dispose();

    _secondsController.dispose();

    _repGoalController.dispose();

    _hoursValue.dispose();

    _minutesValue.dispose();

    _secondsValue.dispose();

    _repGoalValue.dispose();

    _sensitivityValue.dispose();

    super.dispose();
  }

  // ===========================================================
  // BUILD
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;

    final theme = Theme.of(context).copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: dark ? _T.background : const Color(0xFFF4F4F6),
      canvasColor: dark ? _T.surface : Colors.white,
      cardColor: dark ? _T.surface : Colors.white,
      dividerColor: dark ? _T.border : const Color(0xFFE2E3E7),
      colorScheme: dark
          ? const ColorScheme.dark(
              primary: _C.red,
              surface: _T.surface,
              onSurface: _T.text,
            )
          : const ColorScheme.light(
              primary: _C.red,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: dark ? _T.background : const Color(0xFFF4F4F6),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ColoredBox(
              color: dark ? _T.background : Colors.white,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // =========================================
                      // HEADER
                      // =========================================
                      _buildHeader(),

                      const SizedBox(height: 24),

                      // =========================================
                      // TASK NAME
                      // =========================================
                      const _SectionTitle('Task Name'),

                      const SizedBox(height: 9),

                      _buildTaskNameField(),

                      const SizedBox(height: 22),

                      // =========================================
                      // DURATION
                      // =========================================
                      const _SectionTitle('Duration'),

                      const SizedBox(height: 10),

                      _buildDurationPicker(),

                      const SizedBox(height: 8),

                      Center(
                        child: Text(
                          'Max duration is 24 hours.',
                          style: TextStyle(
                            color: dark ? _T.muted : const Color(0xFF676A74),
                            fontSize: 13,
                          ),
                        ),
                      ),

                      const _SectionDivider(),

                      // =========================================
                      // SCHEDULE
                      // =========================================
                      _buildScheduleSection(),

                      const _SectionDivider(),

                      // =========================================
                      // TASK MODE
                      // =========================================
                      const _SectionTitle('Task Mode'),

                      const SizedBox(height: 10),

                      _buildTaskModeSelector(),

                      const SizedBox(height: 18),

                      _buildModeSetup(),

                      const _SectionDivider(),

                      // =========================================
                      // ALARM
                      // =========================================
                      const _SectionTitle('Alarm Sound'),

                      const SizedBox(height: 9),

                      _buildAlarmSound(),

                      const SizedBox(height: 21),

                      // =========================================
                      // SENSITIVITY
                      // =========================================
                      const _SectionTitle('Sensitivity'),

                      const SizedBox(height: 7),

                      _buildSensitivity(),

                      const SizedBox(height: 24),

                      // =========================================
                      // SAVE
                      // =========================================
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton(
                          onPressed: _saveTask,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _C.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Save Task',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // TASK MODE
  // ===========================================================

  Widget _buildModeSetup() {
    switch (selectedMode) {
      case TaskMode.focus:
        return _buildFocusSetup();

      case TaskMode.active:
        return _buildActiveSetup();

      case TaskMode.workout:
        return _buildWorkoutSetup();
    }
  }

  Widget _buildTaskModeSelector() {
    return Row(
      children: [
        Expanded(
          child: _TaskModeButton(
            title: 'Focus',
            subtitle: 'Stay in one area',
            imagePath: 'assets/images/icons/focus_mode.png',
            selected: selectedMode == TaskMode.focus,
            onTap: () {
              setState(() {
                selectedMode = TaskMode.focus;
              });
            },
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _TaskModeButton(
            title: 'Active',
            subtitle: 'Move around',
            imagePath: 'assets/images/icons/active_mode.png',
            selected: selectedMode == TaskMode.active,
            onTap: () {
              setState(() {
                selectedMode = TaskMode.active;
              });
            },
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _TaskModeButton(
            title: 'Workout',
            subtitle: 'Exercise / reps',
            imagePath: 'assets/images/icons/workout_mode.png',
            selected: selectedMode == TaskMode.workout,
            onTap: () {
              setState(() {
                selectedMode = TaskMode.workout;
              });
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // FOCUS SETUP
  // ===========================================================

Widget _buildFocusSetup() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Verification Rules'),

      const SizedBox(height: 10),

      _buildVerificationRules(),

      const SizedBox(height: 18),

      const _SectionTitle('Expected Activity'),

      const SizedBox(height: 8),

      _buildFocusExpectedActivity(),

      const SizedBox(height: 18),

      const _SectionTitle('Reference Setup'),

      const SizedBox(height: 4),

      Text(
        _referenceDescription,
        style: TextStyle(
          color: widget.isDarkMode
              ? _T.muted
              : const Color(0xFF555861),
          fontSize: 13,
          height: 1.35,
        ),
      ),

      const SizedBox(height: 10),

      _buildReferenceSetup(),
    ],
  );
}

  Widget _buildFocusExpectedActivity() {
    return _ModeSettingRow(
      icon: Icons.center_focus_strong_rounded,
      title: 'Focus behavior',
      subtitle: _focusActivityDescription,
      trailing: DropdownButton<FocusActivity>(
        value: focusActivity,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(
            value: FocusActivity.general,
            child: Text('General'),
          ),
          DropdownMenuItem(
            value: FocusActivity.reading,
            child: Text('Reading'),
          ),
          DropdownMenuItem(
            value: FocusActivity.writingNotes,
            child: Text('Writing / Notes'),
          ),
          DropdownMenuItem(
            value: FocusActivity.computerWork,
            child: Text('Computer Work'),
          ),
        ],
        onChanged: (value) {
          if (value == null) {
            return;
          }

          setState(() {
            focusActivity = value;

            // Different activities can have completely different
            // natural head/body positions.
            referencePose = null;
          });
        },
      ),
    );
  }

  String get _focusActivityDescription {
    return switch (focusActivity) {
      FocusActivity.general =>
        'Balanced attention checks with normal movement allowed.',

      FocusActivity.reading =>
        'Allows normal page turns and looking down at reading material.',

      FocusActivity.writingNotes =>
        'Allows sustained hand movement and looking down while writing.',

      FocusActivity.computerWork =>
        'Allows keyboard/mouse movement while watching for disengagement.',
    };
  }
  // ===========================================================
  // ACTIVE SETUP
  // ===========================================================

  Widget _buildActiveSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Active Task Setup'),

        const SizedBox(height: 6),

        Text(
          'Active mode monitors movement, inactivity, presence, and leaving the task area.',
          style: TextStyle(
            color: widget.isDarkMode ? _T.muted : const Color(0xFF676A74),
            fontSize: 12,
            height: 1.35,
          ),
        ),

        const SizedBox(height: 14),

        _buildExpectedActivity(),

        const Divider(),

        _buildInactivityWarning(),

        const Divider(),

        _buildBriefExitAllowance(),

        const Divider(),

        _buildRequiredObjectScan(),

        const SizedBox(height: 18),

        _buildCameraSetup(),
      ],
    );
  }

  // ===========================================================
  // WORKOUT SETUP
  // ===========================================================

  Widget _buildWorkoutSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Workout Setup'),

        const SizedBox(height: 12),

        _buildExerciseAndGoal(),

        const SizedBox(height: 18),

        const _SectionTitle('Optional Settings'),

        const SizedBox(height: 10),

        _buildWorkoutOptions(),

        const SizedBox(height: 18),

        _buildCameraSetup(),
      ],
    );
  }

  // ===========================================================
  // HEADER
  // ===========================================================

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 25,
            color: widget.isDarkMode ? _T.text : Colors.black,
          ),
        ),

        const SizedBox(width: 4),

        Text(
          'New Task',
          style: TextStyle(
            color: widget.isDarkMode ? _T.text : Colors.black,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // TASK NAME FIELD
  // ===========================================================

  Widget _buildTaskNameField() {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: widget.isDarkMode ? _T.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isDarkMode ? _T.border : const Color(0xFFCDD0D7),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _showTaskIconPicker,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 6, 7),
              child: Row(
                children: [
                  _TaskIconTile(type: selectedTaskIcon, size: 50),

                  const SizedBox(width: 3),

                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: widget.isDarkMode
                        ? _T.muted
                        : const Color(0xFF30323A),
                    size: 21,
                  ),
                ],
              ),
            ),
          ),

          Container(
            width: 1,
            height: 40,
            color: widget.isDarkMode ? _T.border : const Color(0xFFE1E2E6),
          ),

          Expanded(
            child: TextField(
              controller: taskNameController,
              onChanged: _onTaskNameChanged,
              style: TextStyle(
                color: widget.isDarkMode ? _T.text : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Study Session.',
                hintStyle: TextStyle(
                  color: widget.isDarkMode ? _T.muted : const Color(0xFF8D9099),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // SMART ICON
  // ===========================================================

  void _onTaskNameChanged(String value) {
    if (taskIconManuallySelected) {
      return;
    }

    final suggestion = _getSuggestedTaskIcon(value);

    if (suggestion == selectedTaskIcon) {
      return;
    }

    setState(() {
      selectedTaskIcon = suggestion;
    });
  }

  TaskIconType _getSuggestedTaskIcon(String taskName) {
    final text = taskName.toLowerCase();

    if (_containsAny(text, [
      'study',
      'read',
      'school',
      'homework',
      'exam',
      'research',
      'assignment',
    ])) {
      return TaskIconType.study;
    }

    if (_containsAny(text, [
      'clean',
      'sweep',
      'mop',
      'vacuum',
      'dust',
      'dishes',
    ])) {
      return TaskIconType.cleaning;
    }

    if (_containsAny(text, ['gym', 'workout', 'exercise', 'lift', 'fitness'])) {
      return TaskIconType.workout;
    }

    if (_containsAny(text, ['run', 'jog', 'walk', 'cardio'])) {
      return TaskIconType.running;
    }

    if (_containsAny(text, [
      'code',
      'coding',
      'computer',
      'laptop',
      'project',
      'work',
      'app',
      'website',
    ])) {
      return TaskIconType.computer;
    }

    if (_containsAny(text, [
      'cook',
      'food',
      'dinner',
      'lunch',
      'breakfast',
      'bake',
    ])) {
      return TaskIconType.cooking;
    }

    if (_containsAny(text, ['laundry', 'wash clothes', 'fold clothes'])) {
      return TaskIconType.laundry;
    }

    if (_containsAny(text, ['meditate', 'meditation', 'yoga', 'pray'])) {
      return TaskIconType.meditation;
    }

    if (_containsAny(text, ['garden', 'plant', 'yard', 'mow'])) {
      return TaskIconType.garden;
    }

    if (_containsAny(text, ['sleep', 'nap', 'bedtime'])) {
      return TaskIconType.sleep;
    }

    if (_containsAny(text, ['shop', 'shopping', 'grocery', 'groceries'])) {
      return TaskIconType.shopping;
    }

    if (_containsAny(text, ['water', 'hydrate'])) {
      return TaskIconType.hydration;
    }

    if (_containsAny(text, ['medicine', 'doctor', 'health'])) {
      return TaskIconType.health;
    }

    if (_containsAny(text, ['music', 'guitar', 'piano', 'sing'])) {
      return TaskIconType.music;
    }

    if (_containsAny(text, ['call', 'phone', 'facetime'])) {
      return TaskIconType.phone;
    }

    if (_containsAny(text, ['dog', 'cat', 'pet'])) {
      return TaskIconType.pet;
    }

    if (_containsAny(text, ['shower', 'bath', 'skincare', 'brush teeth'])) {
      return TaskIconType.selfCare;
    }

    return TaskIconType.generic;
  }

  bool _containsAny(String text, List<String> values) {
    for (final value in values) {
      if (text.contains(value)) {
        return true;
      }
    }

    return false;
  }

  // ===========================================================
  // ICON PICKER
  // ===========================================================

  void _showTaskIconPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDarkMode ? _T.surface : Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: .68,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose Task Icon',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                  ),

                  const SizedBox(height: 12),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.auto_awesome_rounded,
                      color: _C.red,
                    ),
                    title: const Text('Automatic'),
                    subtitle: const Text(
                      'Choose automatically from the task name.',
                    ),
                    trailing: !taskIconManuallySelected
                        ? const Icon(Icons.check_rounded, color: _C.red)
                        : null,
                    onTap: () {
                      setState(() {
                        taskIconManuallySelected = false;

                        selectedTaskIcon = _getSuggestedTaskIcon(
                          taskNameController.text,
                        );
                      });

                      Navigator.pop(context);
                    },
                  ),

                  const Divider(),

                  const SizedBox(height: 8),

                  Expanded(
                    child: GridView.builder(
                      itemCount: TaskIconType.values.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: .88,
                          ),
                      itemBuilder: (context, index) {
                        final type = TaskIconType.values[index];

                        final selected =
                            taskIconManuallySelected &&
                            selectedTaskIcon == type;

                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() {
                              selectedTaskIcon = type;

                              taskIconManuallySelected = true;
                            });

                            Navigator.pop(context);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFFFECEE)
                                  : widget.isDarkMode
                                  ? _T.selected
                                  : const Color(0xFFF7F7F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? _C.red
                                    : widget.isDarkMode
                                    ? _T.border
                                    : const Color(0xFFE5E6EA),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(taskIconData(type), size: 29),

                                const SizedBox(height: 6),

                                Text(
                                  taskIconLabel(type),
                                  style: const TextStyle(fontSize: 10),
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
            ),
          ),
        );
      },
    );
  }

  // ===========================================================
  // DURATION
  // ===========================================================

  void _changeHours(int value) {
    hours = value;
    _hoursValue.value = value;

    if (hours == 24) {
      minutes = 0;
      seconds = 0;
      _minutesValue.value = 0;
      _secondsValue.value = 0;

      if (_minutesController.hasClients) {
        _minutesController.jumpToItem(0);
      }

      if (_secondsController.hasClients) {
        _secondsController.jumpToItem(0);
      }
    }
  }

  void _changeMinutes(int value) {
    if (hours == 24) {
      if (_minutesController.hasClients) {
        _minutesController.jumpToItem(0);
      }

      return;
    }

    minutes = value;
    _minutesValue.value = value;
  }

  void _changeSeconds(int value) {
    if (hours == 24) {
      if (_secondsController.hasClients) {
        _secondsController.jumpToItem(0);
      }

      return;
    }

    seconds = value;
    _secondsValue.value = value;
  }

  Widget _buildDurationPicker() {
    return Center(
      child: Container(
        width: 255,
        height: 170,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isDarkMode ? _T.surface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: _hoursValue,
              builder: (context, value, child) => _DurationWheel(
                controller: _hoursController,
                selectedValue: value,
                itemCount: 25,
                label: 'HOURS',
                onChanged: _changeHours,
              ),
            ),

            const _DurationColon(),

            ValueListenableBuilder<int>(
              valueListenable: _minutesValue,
              builder: (context, value, child) => _DurationWheel(
                controller: _minutesController,
                selectedValue: value,
                itemCount: 60,
                label: 'MINUTES',
                onChanged: _changeMinutes,
              ),
            ),

            const _DurationColon(),

            ValueListenableBuilder<int>(
              valueListenable: _secondsValue,
              builder: (context, value, child) => _DurationWheel(
                controller: _secondsController,
                selectedValue: value,
                itemCount: 60,
                label: 'SECONDS',
                onChanged: _changeSeconds,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // SCHEDULE
  // ===========================================================

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Schedule',
              style: TextStyle(
                color: widget.isDarkMode ? _T.text : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(width: 5),

            Text(
              '(Optional)',
              style: TextStyle(
                color: widget.isDarkMode ? _T.muted : const Color(0xFF777A84),
                fontSize: 14,
              ),
            ),

            const Spacer(),

            if (scheduleEnabled)
              Switch(
                value: true,
                onChanged: _setScheduleEnabled,
                activeTrackColor: _C.red,
                activeThumbColor: Colors.white,
              ),
          ],
        ),

        const SizedBox(height: 10),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: scheduleEnabled
              ? _buildScheduleEnabled()
              : _buildScheduleDisabled(),
        ),
      ],
    );
  }

  Widget _buildScheduleDisabled() {
    return Column(
      key: const ValueKey('schedule-off'),
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            _setScheduleEnabled(true);
          },
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: widget.isDarkMode ? _T.surface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
              ),
            ),
            child: Row(
              children: [
                _PinkIcon(
                  icon: Icons.calendar_month_outlined,
                  dark: widget.isDarkMode,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    'Schedule for later',
                    style: TextStyle(
                      color: widget.isDarkMode ? _T.text : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                Switch(value: false, onChanged: _setScheduleEnabled),
              ],
            ),
          ),
        ),

        const SizedBox(height: 9),

        Text(
          'Turn on to choose a date and time.',
          style: TextStyle(
            color: widget.isDarkMode ? _T.muted : const Color(0xFF777A84),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleEnabled() {
    return Column(
      key: const ValueKey('schedule-on'),
      children: [
        Container(
          decoration: BoxDecoration(
            color: widget.isDarkMode ? _T.surface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
            ),
          ),
          child: Column(
            children: [
              _ScheduleRow(
                icon: Icons.calendar_today_outlined,
                title: 'Date',
                subtitle: 'Choose a date',
                value: _formattedScheduleDate,
                dark: widget.isDarkMode,
                onTap: _chooseScheduleDate,
              ),

              const Divider(height: 1),

              _ScheduleRow(
                icon: Icons.schedule_rounded,
                title: 'Time',
                subtitle: 'Choose a time',
                value: _formattedScheduleTime,
                dark: widget.isDarkMode,
                onTap: _chooseScheduleTime,
              ),
            ],
          ),
        ),

        const SizedBox(height: 9),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.notifications_none_rounded,
              color: _C.red,
              size: 17,
            ),

            const SizedBox(width: 5),

            Flexible(
              child: Text(
                "You'll be reminded when it's time to start.",
                style: TextStyle(
                  color: widget.isDarkMode ? _T.muted : const Color(0xFF676A74),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setScheduleEnabled(bool enabled) {
    setState(() {
      scheduleEnabled = enabled;

      if (enabled) {
        final next = DateTime.now().add(const Duration(hours: 1));

        selectedScheduleDate ??= DateTime(next.year, next.month, next.day);

        selectedScheduleTime ??= TimeOfDay.fromDateTime(next);
      }
    });
  }

  Future<void> _chooseScheduleDate() async {
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final result = await showDatePicker(
      context: context,
      initialDate: selectedScheduleDate ?? today,
      firstDate: today,
      lastDate: DateTime(now.year + 3, 12, 31),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      selectedScheduleDate = result;
    });
  }

  Future<void> _chooseScheduleTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime:
          selectedScheduleTime ??
          TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      selectedScheduleTime = result;
    });
  }

  DateTime? get _scheduledDateTime {
    if (!scheduleEnabled ||
        selectedScheduleDate == null ||
        selectedScheduleTime == null) {
      return null;
    }

    final date = selectedScheduleDate!;

    final time = selectedScheduleTime!;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String get _formattedScheduleDate {
    final date = selectedScheduleDate;

    if (date == null) {
      return 'Choose date';
    }

    final now = DateTime.now();

    if (DateUtils.isSameDay(date, now)) {
      return 'Today, ${_monthName(date.month)} ${date.day}';
    }

    final tomorrow = now.add(const Duration(days: 1));

    if (DateUtils.isSameDay(date, tomorrow)) {
      return 'Tomorrow, ${_monthName(date.month)} ${date.day}';
    }

    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  String get _formattedScheduleTime {
    final time = selectedScheduleTime;

    if (time == null) {
      return 'Choose time';
    }

    var hour = time.hour;

    final suffix = hour >= 12 ? 'PM' : 'AM';

    hour %= 12;

    if (hour == 0) {
      hour = 12;
    }

    return '$hour:${time.minute.toString().padLeft(2, '0')} $suffix';
  }

  // ===========================================================
  // VERIFICATION RULES
  // ===========================================================

  // ===========================================================
  // ACTIVE MODE UI
  // ===========================================================

  Widget _buildExpectedActivity() {
    return _ModeSettingRow(
      icon: Icons.bar_chart_rounded,
      title: 'Expected Activity',
      subtitle: 'How much movement is expected for this task.',
      trailing: DropdownButton<ActivityLevel>(
        value: activityLevel,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: ActivityLevel.light, child: Text('Light')),
          DropdownMenuItem(
            value: ActivityLevel.moderate,
            child: Text('Moderate'),
          ),
          DropdownMenuItem(value: ActivityLevel.high, child: Text('High')),
        ],
        onChanged: (value) {
          if (value == null) {
            return;
          }

          setState(() {
            activityLevel = value;
          });
        },
      ),
    );
  }

  Widget _buildInactivityWarning() {
    const options = [
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ];

    return _ModeSettingRow(
      icon: Icons.schedule_rounded,
      title: 'Inactivity Warning',
      subtitle:
          'Warn me if activity stays below the expected level for this long.',
      trailing: DropdownButton<Duration>(
        value: inactivityWarning,
        underline: const SizedBox.shrink(),
        items: options.map((duration) {
          return DropdownMenuItem(
            value: duration,
            child: Text(_durationOptionLabel(duration)),
          );
        }).toList(),
        onChanged: (value) {
          if (value == null) {
            return;
          }

          setState(() {
            inactivityWarning = value;
          });
        },
      ),
    );
  }

  Widget _buildBriefExitAllowance() {
    const options = [
      Duration.zero,
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
    ];

    return _ModeSettingRow(
      icon: Icons.exit_to_app_rounded,
      title: 'Brief Exit Allowance',
      subtitle: 'Allow a short exit without immediately triggering a warning.',
      trailing: DropdownButton<Duration>(
        value: briefExitAllowance,
        underline: const SizedBox.shrink(),
        items: options.map((duration) {
          return DropdownMenuItem(
            value: duration,
            child: Text(
              duration == Duration.zero
                  ? 'None'
                  : _durationOptionLabel(duration),
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value == null) {
            return;
          }

          setState(() {
            briefExitAllowance = value;
          });
        },
      ),
    );
  }

  Future<void> _openObjectScanner() async {
    if (!MlKitCameraImageConverter.supported) {
      _showMessage('3D object scanning must be used on Android or iPhone.');

      return;
    }

    final result = await Navigator.push<List<SavedObjectScan>>(
      context,
      MaterialPageRoute(
        builder: (_) => ObjectScanLibraryPage(
          isDarkMode: widget.isDarkMode,
          initialSelectedIds: selectedObjectScans
              .map((scan) => scan.id)
              .toList(),
        ),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      selectedObjectScans
        ..clear()
        ..addAll(result.take(3));
    });
  }

  Widget _buildRequiredObjectScan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeSettingRow(
          icon: Icons.view_in_ar_rounded,
          title: 'Required Object / Tool',
          subtitle: selectedObjectScans.isEmpty
              ? 'Optional — scan an object or tool that must appear.'
              : '${selectedObjectScans.length}/3 saved objects selected.',
          trailing: OutlinedButton.icon(
            onPressed: _openObjectScanner,
            icon: const Icon(Icons.view_in_ar_rounded, size: 18),
            label: const Text('3D Scan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.red,
              side: const BorderSide(color: _C.red),
            ),
          ),
        ),

        if (selectedObjectScans.isNotEmpty) ...[
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedObjectScans
                .map(
                  (scan) => Chip(
                    label: Text(scan.name),
                    deleteIcon: const Icon(Icons.close_rounded, size: 17),
                    onDeleted: () {
                      setState(() {
                        selectedObjectScans.removeWhere(
                          (item) => item.id == scan.id,
                        );
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  String _durationOptionLabel(Duration duration) {
    if (duration.inMinutes >= 1 && duration.inSeconds % 60 == 0) {
      final minutes = duration.inMinutes;

      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    }

    return '${duration.inSeconds} seconds';
  }

  // ===========================================================
  // VERIFICATION RULES
  // ===========================================================

  void _toggleStayInPosition() {
    if (stayInPosition) {
      setState(() {
        stayInPosition = false;
      });

      return;
    }

    if (objectInFrame && !isPro) {
      _showUpgradeDialog();
      return;
    }

    setState(() {
      stayInPosition = true;
    });
  }

  void _toggleObjectInFrame() {
    if (objectInFrame) {
      setState(() {
        objectInFrame = false;
      });

      return;
    }

    if (stayInPosition && !isPro) {
      _showUpgradeDialog();
      return;
    }

    setState(() {
      objectInFrame = true;
    });
  }

  Widget _buildVerificationRules() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: widget.isDarkMode ? _T.surface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
            ),
          ),
          child: Column(
            children: [
              _VerificationRow(
                imagePath: 'assets/images/icons/stay_in_position.png',
                title: 'Stay in Position',
                subtitle:
                    'Warn for major posture changes, looking away, or leaving frame.',
                checked: stayInPosition,
                dark: widget.isDarkMode,
                onTap: _toggleStayInPosition,
              ),

              const Divider(height: 1),

              _VerificationRow(
                imagePath: 'assets/images/icons/object_in_frame.png',
                title: 'Object Must Be in Frame',
                subtitle: 'Keep the selected object visible in the camera.',
                checked: objectInFrame,
                dark: widget.isDarkMode,
                onTap: _toggleObjectInFrame,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        InkWell(
          onTap: _showUpgradeDialog,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isDarkMode ? _T.surface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
              ),
            ),
            child: Row(
              children: [
                _AssetIconBox(
                  imagePath:
                      'assets/images/icons/dual_verification.png',
                  dark: widget.isDarkMode,
                ),

                const SizedBox(width: 12),

                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Dual Verification',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),

                          SizedBox(width: 7),

                          _ProBadge(),
                        ],
                      ),

                      SizedBox(height: 3),

                      Text(
                        'Use position and object verification together.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777A84),
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF777A84),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // REFERENCE
  // ===========================================================

  String get _referenceDescription {
  if (stayInPosition) {
    if (referencePose != null) {
      return 'Your focus position has been calibrated. Tap it to recalibrate.';
    }

    return 'Choose a calibration delay, return to your task, and TaskProof will learn your natural working position.';
  }

  if (objectInFrame) {
    return 'Scan or select the objects that must remain visible.';
  }

  return 'Select a verification rule first.';
}

Widget _buildReferenceSetup() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? _T.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
        ),
      ),
      child: Column(
        children: [
          if (stayInPosition)
            _ReferenceRow(
              imagePath:
                  'assets/images/icons/reference_position.png',
              title: 'Reference Position',
              subtitle: referencePose != null
              ? 'Calibrated — tap to recalibrate'
              : 'Set a delay and let TaskProof learn your natural position.',
              complete: referencePose != null,
              dark: widget.isDarkMode,
              onTap: _captureReferencePosition,
            ),

          if (stayInPosition && objectInFrame)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 11),
              child: Divider(height: 1),
            ),

          if (objectInFrame)
      _ReferenceRow(
        icon: Icons.view_in_ar_rounded,
        title: 'Required Objects',
        subtitle: selectedObjectScans.isEmpty
            ? 'Scan or select a required object'
            : '${selectedObjectScans.length}/3 objects selected',
        complete: selectedObjectScans.isNotEmpty,
        dark: widget.isDarkMode,
        onTap: _openObjectScanner,
      ),

          if (!stayInPosition && !objectInFrame)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Text('Choose a verification rule above.'),
            ),
        ],
      ),
    );
  }

  // ===========================================================
  // CAPTURE REFERENCE POSITION
  // ===========================================================

  Future<void> _captureReferencePosition() async {
  if (!MlKitCameraImageConverter.supported) {
    _showMessage(
      'Position verification must be tested on an Android or iPhone device, not Chrome.',
    );

    return;
  }

  final result = await Navigator.push<PoseReference>(
    context,
    MaterialPageRoute(
      builder: (context) => ReferencePositionPage(
        isDarkMode: widget.isDarkMode,
        focusActivity: focusActivity,
      ),
    ),
  );

  if (result == null || !mounted) {
    return;
  }

  setState(() {
    referencePose = result;
  });

  _showMessage(
    'Reference position calibrated.',
  );
}

  // ===========================================================
  // ALARM
  // ===========================================================

  // ===========================================================
  // WORKOUT MODE UI
  // ===========================================================

  void _selectWorkoutMovementType(WorkoutMovementType type) {
    setState(() {
      workoutMovementType = type;

      switch (type) {
        case WorkoutMovementType.repetitions:
          selectedExercise = WorkoutExercise.pushUps;
          break;

        case WorkoutMovementType.hold:
          selectedExercise = WorkoutExercise.plank;
          break;

        case WorkoutMovementType.continuous:
          selectedExercise = WorkoutExercise.runningInPlace;
          break;
      }
    });
  }

  // ignore: unused_element
  Widget _buildWorkoutMovementType() {
    return Row(
      children: [
        Expanded(
          child: _WorkoutTypeButton(
            title: 'Repetitions',
            subtitle: 'Count reps',
            icon: Icons.sync_rounded,
            selected: workoutMovementType == WorkoutMovementType.repetitions,
            onTap: () {
              _selectWorkoutMovementType(WorkoutMovementType.repetitions);
            },
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _WorkoutTypeButton(
            title: 'Hold',
            subtitle: 'Hold a position',
            icon: Icons.timer_outlined,
            selected: workoutMovementType == WorkoutMovementType.hold,
            onTap: () {
              _selectWorkoutMovementType(WorkoutMovementType.hold);
            },
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _WorkoutTypeButton(
            title: 'Continuous',
            subtitle: 'Stay active',
            icon: Icons.directions_run_rounded,
            selected: workoutMovementType == WorkoutMovementType.continuous,
            onTap: () {
              _selectWorkoutMovementType(WorkoutMovementType.continuous);
            },
          ),
        ),
      ],
    );
  }

  List<WorkoutExercise> get _availableWorkoutExercises => const [
    WorkoutExercise.pushUps,
    WorkoutExercise.squats,
    WorkoutExercise.sitUps,
    WorkoutExercise.jumpingJacks,
    WorkoutExercise.lunges,
  ];

  String _workoutExerciseLabel(WorkoutExercise exercise) {
    switch (exercise) {
      case WorkoutExercise.pushUps:
        return 'Push-ups';

      case WorkoutExercise.squats:
        return 'Squats';

      case WorkoutExercise.jumpingJacks:
        return 'Jumping Jacks';

      case WorkoutExercise.lunges:
        return 'Lunges';

      case WorkoutExercise.sitUps:
        return 'Sit-ups';

      case WorkoutExercise.burpees:
        return 'Burpees';

      case WorkoutExercise.mountainClimbers:
        return 'Mountain Climbers';

      case WorkoutExercise.highKnees:
        return 'High Knees';

      case WorkoutExercise.plank:
        return 'Plank';

      case WorkoutExercise.wallSit:
        return 'Wall Sit';

      case WorkoutExercise.runningInPlace:
        return 'Running in Place';

      case WorkoutExercise.jumpRope:
        return 'Jump Rope';
    }
  }

  IconData _workoutExerciseIcon(WorkoutExercise exercise) {
    switch (exercise) {
      case WorkoutExercise.runningInPlace:
      case WorkoutExercise.highKnees:
        return Icons.directions_run_rounded;

      case WorkoutExercise.jumpRope:
      case WorkoutExercise.jumpingJacks:
        return Icons.accessibility_new_rounded;

      default:
        return Icons.fitness_center_rounded;
    }
  }

  Widget _buildExerciseAndGoal() {
    final exercises = _availableWorkoutExercises;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Exercise',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 8),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<WorkoutExercise>(
              value: selectedExercise,
              isExpanded: true,
              items: exercises.map((exercise) {
                return DropdownMenuItem(
                  value: exercise,
                  child: Row(
                    children: [
                      Icon(
                        _workoutExerciseIcon(exercise),
                        size: 23,
                        color: _C.red,
                      ),

                      const SizedBox(width: 10),

                      Text(_workoutExerciseLabel(exercise)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  selectedExercise = value;
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 18),

        const Text(
          'Goal (Repetitions)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 8),

        Center(
          child: Container(
            width: 120,
            height: 154,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isDarkMode ? _T.surface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
                width: 1.2,
              ),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: _repGoalValue,
              builder: (context, value, child) {
                return _RepGoalWheel(
                  controller: _repGoalController,
                  selectedValue: value,
                  onChanged: (newValue) {
                    workoutRepGoal = newValue;
                    _repGoalValue.value = newValue;
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutOptions() {
    const restOptions = [
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
    ];

    return Container(
      decoration: BoxDecoration(
        color: widget.isDarkMode ? _T.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: workoutFormChecking,
            onChanged: isPro
                ? (value) {
                    setState(() {
                      workoutFormChecking = value;
                    });
                  }
                : (_) {
                    _showMessage('Form Checking is a TaskProof Pro feature.');
                  },
            secondary: const Icon(Icons.person_search_rounded, color: _C.red),
            title: const Row(
              children: [
                Text(
                  'Form Checking',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(width: 7),
                _ProBadge(),
              ],
            ),
            subtitle: const Text('Get extra feedback on your form.'),
          ),

          if (workoutMovementType != WorkoutMovementType.repetitions) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 24),

                  const SizedBox(width: 14),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rest Limit',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Maximum rest time between exercise activity.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF777A84),
                          ),
                        ),
                      ],
                    ),
                  ),

                  DropdownButton<Duration>(
                    value: workoutRestLimit,
                    underline: const SizedBox.shrink(),
                    items: restOptions.map((duration) {
                      return DropdownMenuItem(
                        value: duration,
                        child: Text(_durationOptionLabel(duration)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        workoutRestLimit = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Camera Setup'),

        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: widget.isDarkMode ? _T.surface : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
            ),
          ),
          child: Row(
            children: [
              _PinkIcon(
                icon: Icons.photo_camera_outlined,
                dark: widget.isDarkMode,
              ),

              const SizedBox(width: 12),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Position Camera',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    SizedBox(height: 2),

                    Text(
                      'Place the camera so the required area is visible.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF777A84)),
                    ),
                  ],
                ),
              ),

              OutlinedButton.icon(
                onPressed: _openCameraPreview,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Preview'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _C.red,
                  side: const BorderSide(color: _C.red),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openCameraPreview() async {
    switch (selectedMode) {
      case TaskMode.active:
        if (!MlKitCameraImageConverter.supported) {
          _showMessage('Active camera preview requires Android or iPhone.');
          return;
        }

        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ActiveCameraPreviewPage(isDarkMode: widget.isDarkMode),
          ),
        );
        return;

      case TaskMode.workout:
        if (!MlKitCameraImageConverter.supported) {
          _showMessage('Workout camera preview requires Android or iPhone.');
          return;
        }
        final selectedOrientation =
        await Navigator.push<WorkoutCameraOrientation>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutCameraPreviewPage(
          isDarkMode: widget.isDarkMode,
          exercise: selectedExercise,
          movementType: workoutMovementType,
          sensitivity: sensitivity,
          initialOrientation: workoutCameraOrientation,
        ),
      ),
    );

    if (selectedOrientation != null && mounted) {
      setState(() {
        workoutCameraOrientation = selectedOrientation;
      });
    }

    return;

      case TaskMode.focus:
        await _captureReferencePosition();
        return;
    }
  }

  // ===========================================================
  // ALARM
  // ===========================================================

  Widget _buildAlarmSound() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _selectAlarm,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: widget.isDarkMode ? _T.surface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isDarkMode ? _T.border : const Color(0xFFCACDD5),
          ),
        ),
        child: Row(
          children: [
            _AssetIconBox(
              imagePath: 'assets/images/icons/default_alarm.png',
              dark: widget.isDarkMode,
            ),

            const SizedBox(width: 13),

            Expanded(
              child: Text(selectedAlarm, style: const TextStyle(fontSize: 16)),
            ),

            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  void _selectAlarm() {
    const alarms = ['Default Alarm', 'Pulse', 'Bell', 'Alert'];

    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDarkMode ? _T.surface : Colors.white,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: alarms.map((alarm) {
                final selected = selectedAlarm == alarm;

                return ListTile(
                  title: Text(alarm),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: _C.red)
                      : null,
                  onTap: () {
                    setState(() {
                      selectedAlarm = alarm;
                    });

                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================
  // SENSITIVITY
  // ===========================================================

  Widget _buildSensitivity() {
  const sensitivityRed = Color(0xFFFF111C);
  const sensitivityOrange = Color(0xFFFF8A00);

  return ValueListenableBuilder<double>(
    valueListenable: _sensitivityValue,
    builder: (context, value, child) {
      final thumbColor =
          Color.lerp(
            sensitivityRed,
            sensitivityOrange,
            value,
          ) ??
          sensitivityRed;

      return Column(
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 24,
                  right: 24,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          sensitivityRed,
                          sensitivityOrange,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.isDarkMode
                              ? Colors.black.withValues(
                                  alpha: .24,
                                )
                              : Colors.black.withValues(
                                  alpha: .08,
                                ),
                          blurRadius: 5,
                          offset: const Offset(
                            0,
                            1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliderTheme(
                  data: SliderTheme.of(
                    context,
                  ).copyWith(
                    trackHeight: 5,

                    activeTrackColor:
                        Colors.transparent,

                    inactiveTrackColor:
                        Colors.transparent,

                    thumbColor: thumbColor,

                    overlayColor:
                        thumbColor.withValues(
                      alpha: .14,
                    ),

                    thumbShape:
                        const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                    ),

                    overlayShape:
                        const RoundSliderOverlayShape(
                      overlayRadius: 18,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: 1,
                    onChanged: (
                      nextValue,
                    ) {
                      sensitivity =
                          nextValue;

                      _sensitivityValue.value =
                          nextValue;
                    },
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 3,
            ),
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Low',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Medium',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
                Text(
                  'High',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 6,
          ),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _sensitivityDescription,
              style: TextStyle(
                color: widget.isDarkMode
                    ? _T.muted
                    : const Color(
                        0xFF676A74,
                      ),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      );
    },
  );
}

  String get _sensitivityDescription {
  if (selectedMode == TaskMode.active) {
    if (sensitivity < .34) {
      return 'Low: allows more inactivity and movement variation.';
    }

    if (sensitivity < .67) {
      return 'Medium: balanced movement and inactivity detection.';
    }

    return 'High: notices smaller activity changes more quickly.';
  }

  if (selectedMode == TaskMode.workout) {
    if (sensitivity < .34) {
      return 'Low: more forgiving workout movement detection.';
    }

    if (sensitivity < .67) {
      return 'Medium: balanced exercise movement detection.';
    }

    return 'High: detects smaller exercise movement differences more strictly.';
  }

    // Focus mode
   // Focus mode
  if (sensitivity < .34) {
    return 'Low: larger focus area, more movement tolerance, and a longer grace period.';
  }

  if (sensitivity < .67) {
    return 'Medium: balanced area, attention, and sustained behavior-change detection.';
  }

  return 'High: tighter focus area and faster attention/behavior checks while still allowing normal task movement.';
  }
  // ===========================================================
  // PRO DIALOG
  // ===========================================================

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dual Verification'),
        content: const Text(
          'Using Stay in Position and Object Must Be in Frame together is a TaskProof Pro feature.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Not now'),
          ),

          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _C.red),
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('View Pro'),
          ),
        ],
      ),
    );
  }

  // ===========================================================
  // SAVE TASK
  // ===========================================================

  void _saveTask() {
    final name = taskNameController.text.trim();

    if (name.isEmpty) {
      _showMessage('Enter a task name first.');

      return;
    }

    if (hours == 0 && minutes == 0 && seconds == 0) {
      _showMessage('Task duration must be longer than 0 seconds.');

      return;
    }

    if (selectedMode == TaskMode.focus && !stayInPosition && !objectInFrame) {
      _showMessage('Choose at least one verification rule.');

      return;
    }

    if (selectedMode == TaskMode.focus &&
        objectInFrame &&
        selectedObjectScans.isEmpty) {
      _showMessage('Scan or select at least one required object.');

      return;
    }

    DateTime? scheduledFor;

    if (scheduleEnabled) {
      scheduledFor = _scheduledDateTime;

      if (scheduledFor == null) {
        _showMessage('Choose a schedule date and time.');

        return;
      }

      if (!scheduledFor.isAfter(DateTime.now())) {
        _showMessage('Choose a scheduled time in the future.');

        return;
      }
    }

    final task = TaskData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),

      name: name,

      icon: selectedTaskIcon,

      mode: selectedMode,

      hours: hours,
      minutes: minutes,
      seconds: seconds,

      stayInPosition: selectedMode == TaskMode.focus ? stayInPosition : false,

      objectInFrame: selectedMode == TaskMode.focus ? objectInFrame : false,

      alarm: selectedAlarm,

      sensitivity: sensitivity,

      focusActivity: selectedMode == TaskMode.focus
          ? focusActivity
          : FocusActivity.general,

      poseReference: selectedMode == TaskMode.focus ? referencePose : null,

      requiredObjectIds:
          selectedMode == TaskMode.focus && objectInFrame
              ? selectedObjectScans.map((scan) => scan.id).toList()
              : const [],

      activeConfig: selectedMode == TaskMode.active
          ? ActiveTaskConfig(
              activityLevel: activityLevel,
              inactivityWarning: inactivityWarning,
              briefExitAllowance: briefExitAllowance,
              requiredObjectIds: selectedObjectScans
                  .map((scan) => scan.id)
                  .toList(),
            )
          : null,

        workoutConfig: selectedMode == TaskMode.workout
      ? WorkoutTaskConfig(
          movementType: workoutMovementType,
          exercise: selectedExercise,
          repGoal: workoutRepGoal,
          targetDuration: workoutTargetDuration,
          restLimit: workoutRestLimit,
          formChecking: workoutFormChecking,
          cameraOrientation: workoutCameraOrientation,
        )
      : null,

      status: scheduleEnabled ? TaskStatus.scheduled : TaskStatus.ready,

      scheduledFor: scheduledFor,
    );

    Navigator.pop(context, task);
  }

  // ===========================================================
  // HELPERS
  // ============================================================================================

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }
}

  // =============================================================
  // REFERENCE POSITION CAMERA PAGE
  // =============================================================

  enum _ReferenceCalibrationMode {
    quick,
    countdown,
  }

class ReferencePositionPage extends StatefulWidget {
  const ReferencePositionPage({
    super.key,
    required this.isDarkMode,
    required this.focusActivity,
  });

  final bool isDarkMode;

  final FocusActivity focusActivity;

  @override
  State<ReferencePositionPage> createState() =>
      _ReferencePositionPageState();
}

class _ReferencePositionPageState extends State<ReferencePositionPage>
    with WidgetsBindingObserver {
  CameraController? _controller;

  Widget? _cameraPreview;

  CameraDescription? _camera;

  PoseDetector? _poseDetector;

  FaceDetector? _faceDetector;

  bool _initializing = true;

  bool _startingCamera = false;

  bool _processing = false;

  bool _acceptFrames = false;

  bool _lifecycleActive = true;

  bool _disposed = false;

  Future<void>? _activeAnalysis;

  Future<void>? _cameraDisposal;

  Future<void>? _shutdownTask;

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastFaceProcessed = DateTime.fromMillisecondsSinceEpoch(0);

 List<Face> _cachedFaces = const [];


final List<PoseReference> _recentCalibrationSamples =
    <PoseReference>[];

final ValueNotifier<bool> _positionDetected =
    ValueNotifier(false);

// ===========================================================
// CALIBRATION TIMING
// ===========================================================

  _ReferenceCalibrationMode _calibrationMode =
      _ReferenceCalibrationMode.quick;

  // Used when Countdown is selected.
  int _customCountdownSeconds = 10;

  Timer? _calibrationCountdownTimer;

  // Example: 3 → 2 → 1.
  // Null means no countdown is currently running.
  int? _countdownRemaining;

  // We ONLY collect reference samples after the countdown.
  bool _collectingCalibration = false;

  bool get _calibrationInProgress =>
      _countdownRemaining != null ||
      _collectingCalibration;

  String _status = 'Preparing camera...';

  // ===========================================================
  // INIT
  // ===========================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _disposed = true;
    _lifecycleActive = false;
    _acceptFrames = false;

    _calibrationCountdownTimer?.cancel();
    _calibrationCountdownTimer = null;

    unawaited(_shutdown());

    _positionDetected.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
    state == AppLifecycleState.inactive) {
    _lifecycleActive = false;
    _acceptFrames = false;

    _cancelCalibration(silent: true);

    _setCurrentPose(null);

    unawaited(_disposeCamera());

    return;
  }

    if (state == AppLifecycleState.resumed) {
      _lifecycleActive = true;
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initialize() async {
    if (!MlKitCameraImageConverter.supported) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;

        _status = 'This feature requires Android or iPhone.';
      });

      return;
    }

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: true,
      ),
    );

    await _initializeCamera();
  }

  // ===========================================================
  // CAMERA
  // ===========================================================

  Future<void> _initializeCamera() async {
    if (_startingCamera ||
        _controller != null ||
        _disposed ||
        !_lifecycleActive) {
      return;
    }

    _startingCamera = true;
    CameraController? pendingController;

    try {
      final disposal = _cameraDisposal;
      if (disposal != null) {
        await disposal;
      }

      if (_disposed || !_lifecycleActive || _controller != null) {
        return;
      }

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initializing = false;

            _status = 'No camera was found.';
          });
        }

        return;
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: MlKitCameraImageConverter.cameraFormat,
      );
      pendingController = controller;

      await controller.initialize();

      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}

      if (!mounted || _disposed || !_lifecycleActive) {
        return;
      }

      _camera = camera;
      _controller = controller;
      _cameraPreview = RepaintBoundary(child: CameraPreview(controller));
      _acceptFrames = true;
      pendingController = null;

      await controller.startImageStream(_handleFrame);

      if (!mounted || _disposed || !_lifecycleActive) {
        await _disposeCamera();
        return;
      }

      setState(() {
        _initializing = false;

        _status =
        'Position the phone, then choose how long you need before calibration begins.';
      });
    } on CameraException catch (error) {
      await _disposeCamera();

      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _initializing = false;

        _status = 'Camera error: ${error.description ?? error.code}';
      });
    } finally {
      final abandonedController = pendingController;
      if (abandonedController != null) {
        try {
          await abandonedController.dispose();
        } catch (_) {}
      }

      _startingCamera = false;
    }
  }

  Future<void> _disposeCamera() async {
    final existing = _cameraDisposal;
    if (existing != null) {
      return existing;
    }

    final disposal = _performCameraDisposal();
    _cameraDisposal = disposal;

    try {
      await disposal;
    } finally {
      if (identical(_cameraDisposal, disposal)) {
        _cameraDisposal = null;
      }
    }
  }

  Future<void> _performCameraDisposal() async {
    _acceptFrames = false;

    final controller = _controller;

    _controller = null;
    _camera = null;
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
    return _shutdownTask ??= _performShutdown();
  }

  Future<void> _performShutdown() async {
    await _disposeCamera();

    final poseDetector = _poseDetector;
    final faceDetector = _faceDetector;
    _poseDetector = null;
    _faceDetector = null;

    await Future.wait<void>([
      if (poseDetector != null) poseDetector.close(),
      if (faceDetector != null) faceDetector.close(),
    ]);
  }

  // ===========================================================
  // ML FRAME PROCESSING
  // ===========================================================

  void _handleFrame(CameraImage image) {
    if (_processing || !_acceptFrames || _disposed) {
      return;
    }

    final analysis = _processFrame(image);
    _activeAnalysis = analysis;

    unawaited(
      analysis
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('Reference pose processing error: $error');
            debugPrintStack(stackTrace: stackTrace);
          })
          .whenComplete(() {
            if (identical(_activeAnalysis, analysis)) {
              _activeAnalysis = null;
            }
          }),
    );
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing ||
        !_acceptFrames ||
        _disposed ||
        _controller == null ||
        _camera == null ||
        _poseDetector == null ||
        _faceDetector == null) {
      return;
    }

    final now = DateTime.now();

    // Four pose updates per second are responsive for alignment while leaving
    // enough time for the camera texture and controls to render smoothly.
    if (now.difference(_lastProcessed) < const Duration(milliseconds: 250)) {
      return;
    }

    _lastProcessed = now;

    final frame = MlKitCameraImageConverter.convert(
      image: image,
      camera: _camera!,
      deviceOrientation: _controller!.value.deviceOrientation,
    );

    if (frame == null) {
      return;
    }

    _processing = true;

    try {
      final poses = await _poseDetector!.processImage(frame.inputImage);

      var faces = _cachedFaces;
      if (poses.isEmpty) {
        faces = const [];
        _cachedFaces = const [];
        _lastFaceProcessed = DateTime.fromMillisecondsSinceEpoch(0);
      } else if (now.difference(_lastFaceProcessed) >=
          const Duration(milliseconds: 500)) {
        faces = await _faceDetector!.processImage(frame.inputImage);
        _cachedFaces = faces;
        _lastFaceProcessed = now;
      }

      final snapshot = TaskPoseAnalyzer.createSnapshot(
        poses: poses,
        faces: faces,
        imageSize: frame.imageSize,
      );

      if (!mounted || _disposed || !_acceptFrames) {
        return;
      }

      _setCurrentPose(snapshot);
    } catch (error) {
      debugPrint('Reference pose processing error: $error');
    } finally {
      _processing = false;
    }
  }

String get _calibrationActivityInstruction {
  return switch (widget.focusActivity) {
    FocusActivity.general =>
      'Use your normal focus position and continue naturally.',

    FocusActivity.reading =>
      'Look naturally at your book or reading material.',

    FocusActivity.writingNotes =>
      'Return to your normal writing position and look at your notes.',

    FocusActivity.computerWork =>
      'Look naturally at your computer and continue as if you were working.',
  };
}

String get _countdownInstruction {
  return switch (widget.focusActivity) {
    FocusActivity.general =>
      'Return to your normal focus position.',

    FocusActivity.reading =>
      'Return to your reading position and look at your reading material.',

    FocusActivity.writingNotes =>
      'Return to your writing position and look at your notes.',

    FocusActivity.computerWork =>
      'Return to your computer and look at the screen naturally.',
  };
}

void _startCalibration() {
  final controller = _controller;

  if (_disposed ||
      _initializing ||
      controller == null ||
      !controller.value.isInitialized ||
      _calibrationInProgress) {
    return;
  }

  _calibrationCountdownTimer?.cancel();

  _recentCalibrationSamples.clear();

  final delaySeconds =
      _calibrationMode == _ReferenceCalibrationMode.quick
          ? 3
          : _customCountdownSeconds;

  setState(() {
    _collectingCalibration = false;
    _countdownRemaining = delaySeconds;

    _status =
        '$_countdownInstruction Calibration begins in $delaySeconds seconds.';
  });

  _calibrationCountdownTimer =
      Timer.periodic(
    const Duration(seconds: 1),
    (timer) {
      if (!mounted || _disposed) {
        timer.cancel();
        return;
      }

      final current =
          _countdownRemaining;

      if (current == null) {
        timer.cancel();
        return;
      }

      final next = current - 1;

      if (next <= 0) {
        timer.cancel();

        _calibrationCountdownTimer = null;

        // Anything detected while the user was tapping
        // or returning to their task is intentionally discarded.
        _recentCalibrationSamples.clear();

        setState(() {
          _countdownRemaining = null;
          _collectingCalibration = true;

          _status =
              'Calibrating... $_calibrationActivityInstruction';
        });

        return;
      }

      setState(() {
        _countdownRemaining = next;

        _status =
            '$_countdownInstruction Calibration begins in $next seconds.';
      });
    },
  );
}

void _cancelCalibration({
  bool silent = false,
}) {
  _calibrationCountdownTimer?.cancel();
  _calibrationCountdownTimer = null;

  _countdownRemaining = null;
  _collectingCalibration = false;

  _recentCalibrationSamples.clear();

  if (!silent &&
      mounted &&
      !_disposed) {
    setState(() {
      _status =
          'Calibration cancelled. Choose when you are ready.';
    });
  }
}

void _finishCalibration(
  PoseReference reference,
) {
  if (!mounted ||
      _disposed ||
      !_collectingCalibration) {
    return;
  }

  // Prevent another camera frame from completing it twice.
  _collectingCalibration = false;

  _calibrationCountdownTimer?.cancel();
  _calibrationCountdownTimer = null;


  Navigator.pop(context, reference);
}

void _setCurrentPose(
  PoseReference? snapshot,
) {
  final personVisible =
      snapshot != null;

  if (_positionDetected.value !=
      personVisible) {
    _positionDetected.value =
        personVisible;
  }

  // =========================================================
  // NOT CALIBRATING
  // =========================================================

  if (!_collectingCalibration) {
    // During the countdown, keep the countdown
    // instruction on screen instead of replacing it
    // with "Position visible".
    if (_countdownRemaining != null) {
      return;
    }

    _status = personVisible
        ? 'Position visible. Choose a calibration option below.'
        : 'Move into view so TaskProof can see your position.';

    return;
  }

  // =========================================================
  // CALIBRATION IS ACTIVE
  // =========================================================

  if (snapshot == null) {
    // Calibration should use one continuous period
    // where the person's pose can be reliably seen.
    //
    // If they disappear, throw away the incomplete
    // samples and automatically begin again once
    // they are visible.
    _recentCalibrationSamples.clear();


    _status =
        'Position lost. Move back into view — calibration will restart automatically.';

    return;
  }

  _recentCalibrationSamples.add(
    snapshot,
  );

  // Camera pose analysis is currently approximately
  // once every 250 ms.
  //
  // 8 samples therefore represents roughly
  // 2 seconds of natural working position.
  if (_recentCalibrationSamples.length >
      8) {
    _recentCalibrationSamples.removeAt(
      0,
    );
  }

  // Do not create the final reference until
  // we have the full calibration window.
  if (_recentCalibrationSamples.length <
      8) {
    return;
  }

  final reference =
      TaskPoseAnalyzer
          .buildAdaptiveReference(
    _recentCalibrationSamples,
  );

  if (reference == null) {
    // The reference was not stable enough yet.
    // Keep receiving new frames until TaskProof
    // gets a usable 8-frame window.
    return;
  }


  _finishCalibration(
    reference,
  );
}


  // ===========================================================
  // BUILD
  // ===========================================================

  @override
Widget build(BuildContext context) {
  return ValueListenableBuilder<bool>(
    valueListenable: _positionDetected,
    builder: (
      context,
      positionDetected,
      child,
    ) {
      return Scaffold(
        backgroundColor:
            const Color(0xFF07090D),

        body: SafeArea(
          child: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  8,
                  5,
                  16,
                  4,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                        );
                      },
                      icon: const Icon(
                        Icons
                            .arrow_back_ios_new_rounded,
                        color: Colors.white,
                      ),
                    ),

                    const Text(
                      'Calibrate Position',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // CAMERA
              // =================================================

              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    14,
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(
                      22,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // =========================================
                        // CAMERA PREVIEW
                        // =========================================

                        _cameraView(),

                        // =========================================
                        // VIEWFINDER BRACKETS
                        // =========================================

                        IgnorePointer(
                          child: CustomPaint(
                            painter:
                                _ReferenceCameraPainter(
                              detected:
                                  positionDetected,
                            ),
                          ),
                        ),

                        // =========================================
                        // POSITION STATUS
                        // =========================================

                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 16,
                              vertical: 9,
                            ),
                            decoration:
                                BoxDecoration(
                              color:
                                  widget.isDarkMode
                                      ? const Color(
                                          0xFF0E1116,
                                        )
                                      : const Color(
                                          0xFFF8F9FA,
                                        ),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                18,
                              ),
                              border:
                                  Border.all(
                                color:
                                    widget.isDarkMode
                                        ? const Color(
                                            0xFF2A2F37,
                                          )
                                        : const Color(
                                            0xFFE0E3E8,
                                          ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize:
                                  MainAxisSize
                                      .min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        positionDetected
                                            ? const Color(
                                                0xFF22C55E,
                                              )
                                            : _C.red,
                                    shape:
                                        BoxShape
                                            .circle,
                                  ),
                                ),

                                const SizedBox(
                                  width: 9,
                                ),

                                Text(
                                  positionDetected
                                      ? 'Position Detected'
                                      : 'Finding Position...',
                                  style:
                                      TextStyle(
                                    color:
                                        positionDetected
                                            ? const Color(
                                                0xFF22C55E,
                                              )
                                            : _C.red,
                                    fontSize: 14,
                                    fontWeight:
                                        FontWeight
                                            .w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // =========================================
                        // COUNTDOWN OVERLAY
                        // =========================================

                        if (_countdownRemaining !=
                            null)
                          Center(
                            child: Container(
                              width: 116,
                              height: 116,
                              alignment:
                                  Alignment.center,
                              decoration:
                                  BoxDecoration(
                                color: Colors.black
                                    .withValues(
                                  alpha: .70,
                                ),
                                shape:
                                    BoxShape.circle,
                                border:
                                    Border.all(
                                  color:
                                      Colors.white
                                          .withValues(
                                    alpha: .20,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${_countdownRemaining!}',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize: 58,
                                  height: 1,
                                  fontWeight:
                                      FontWeight
                                          .w900,
                                ),
                              ),
                            ),
                          ),

                        // =========================================
                        // CALIBRATION OVERLAY
                        // =========================================

                        if (_collectingCalibration)
                          Center(
                            child: Container(
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              decoration:
                                  BoxDecoration(
                                color: Colors.black
                                    .withValues(
                                  alpha: .70,
                                ),
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  999,
                                ),
                              ),
                              child:
                                  const Row(
                                mainAxisSize:
                                    MainAxisSize
                                        .min,
                                children: [
                                  SizedBox(
                                    width: 17,
                                    height: 17,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth:
                                          2,
                                      color:
                                          Color(
                                        0xFF22C55E,
                                      ),
                                    ),
                                  ),

                                  SizedBox(
                                    width: 9,
                                  ),

                                  Text(
                                    'CALIBRATING',
                                    style:
                                        TextStyle(
                                      color:
                                          Colors.white,
                                      fontSize:
                                          13,
                                      fontWeight:
                                          FontWeight
                                              .w800,
                                      letterSpacing:
                                          .5,
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

              // =================================================
              // STATUS + CALIBRATION CONTROLS
              // =================================================

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  7,
                  20,
                  23,
                ),
                child: Column(
                  children: [
                    Text(
                      _status,
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        color: Color(
                          0xFFD6D9DE,
                        ),
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    // =============================================
                    // WAITING FOR USER
                    // =============================================

                    if (!_calibrationInProgress) ...[
                      const Align(
                        alignment:
                            Alignment
                                .centerLeft,
                        child: Text(
                          'Calibration Timing',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontSize: 14,
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 9,
                      ),

                      Row(
                        children: [
                          // =========================================
                          // QUICK
                          // =========================================

                          Expanded(
                            child:
                                ChoiceChip(
                              label:
                                  const SizedBox(
                                width: double
                                    .infinity,
                                child: Text(
                                  'Quick · 3 sec',
                                  textAlign:
                                      TextAlign
                                          .center,
                                ),
                              ),

                              selected:
                                  _calibrationMode ==
                                      _ReferenceCalibrationMode
                                          .quick,

                              onSelected: (
                                selected,
                              ) {
                                if (!selected) {
                                  return;
                                }

                                setState(
                                  () {
                                    _calibrationMode =
                                        _ReferenceCalibrationMode
                                            .quick;
                                  },
                                );
                              },

                              selectedColor:
                                  _C.red
                                      .withValues(
                                alpha: .22,
                              ),

                              backgroundColor:
                                  const Color(
                                0xFF15191F,
                              ),

                              side:
                                  BorderSide(
                                color:
                                    _calibrationMode ==
                                            _ReferenceCalibrationMode
                                                .quick
                                        ? _C.red
                                        : const Color(
                                            0xFF444A53,
                                          ),
                              ),

                              labelStyle:
                                  TextStyle(
                                color:
                                    _calibrationMode ==
                                            _ReferenceCalibrationMode
                                                .quick
                                        ? Colors
                                            .white
                                        : const Color(
                                            0xFFB6BBC4,
                                          ),
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),
                          ),

                          const SizedBox(
                            width: 9,
                          ),

                          // =========================================
                          // CUSTOM COUNTDOWN
                          // =========================================

                          Expanded(
                            child:
                                ChoiceChip(
                              label:
                                  const SizedBox(
                                width: double
                                    .infinity,
                                child: Text(
                                  'Countdown',
                                  textAlign:
                                      TextAlign
                                          .center,
                                ),
                              ),

                              selected:
                                  _calibrationMode ==
                                      _ReferenceCalibrationMode
                                          .countdown,

                              onSelected: (
                                selected,
                              ) {
                                if (!selected) {
                                  return;
                                }

                                setState(
                                  () {
                                    _calibrationMode =
                                        _ReferenceCalibrationMode
                                            .countdown;
                                  },
                                );
                              },

                              selectedColor:
                                  _C.red
                                      .withValues(
                                alpha: .22,
                              ),

                              backgroundColor:
                                  const Color(
                                0xFF15191F,
                              ),

                              side:
                                  BorderSide(
                                color:
                                    _calibrationMode ==
                                            _ReferenceCalibrationMode
                                                .countdown
                                        ? _C.red
                                        : const Color(
                                            0xFF444A53,
                                          ),
                              ),

                              labelStyle:
                                  TextStyle(
                                color:
                                    _calibrationMode ==
                                            _ReferenceCalibrationMode
                                                .countdown
                                        ? Colors
                                            .white
                                        : const Color(
                                            0xFFB6BBC4,
                                          ),
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // =============================================
                      // CUSTOM DELAY DROPDOWN
                      // =============================================

                      if (_calibrationMode ==
                          _ReferenceCalibrationMode
                              .countdown) ...[
                        const SizedBox(
                          height: 10,
                        ),

                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 14,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFF15191F,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                            border:
                                Border.all(
                              color:
                                  const Color(
                                0xFF444A53,
                              ),
                            ),
                          ),
                          child:
                              DropdownButtonHideUnderline(
                            child:
                                DropdownButton<
                                    int>(
                              value:
                                  _customCountdownSeconds,

                              isExpanded:
                                  true,

                              dropdownColor:
                                  const Color(
                                0xFF15191F,
                              ),

                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                                fontSize: 15,
                              ),

                              items:
                                  const [
                                DropdownMenuItem(
                                  value: 5,
                                  child:
                                      Text(
                                    '5 seconds',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 10,
                                  child:
                                      Text(
                                    '10 seconds',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 15,
                                  child:
                                      Text(
                                    '15 seconds',
                                  ),
                                ),
                              ],

                              onChanged: (
                                value,
                              ) {
                                if (value ==
                                    null) {
                                  return;
                                }

                                setState(
                                  () {
                                    _customCountdownSeconds =
                                        value;
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(
                        height: 14,
                      ),

                      // =============================================
                      // START
                      // =============================================

                      SizedBox(
                        width:
                            double.infinity,
                        height: 54,
                        child:
                            ElevatedButton(
                          onPressed:
                              _initializing ||
                                      _controller ==
                                          null
                                  ? null
                                  : _startCalibration,

                          style:
                              ElevatedButton
                                  .styleFrom(
                            backgroundColor:
                                _C.red,
                            foregroundColor:
                                Colors.white,
                            disabledBackgroundColor:
                                const Color(
                              0xFF444850,
                            ),
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                14,
                              ),
                            ),
                          ),

                          child: Text(
                            _calibrationMode ==
                                    _ReferenceCalibrationMode
                                        .quick
                                ? 'Start Quick Calibration'
                                : 'Start $_customCountdownSeconds-Second Countdown',
                            style:
                                const TextStyle(
                              fontSize: 17,
                              fontWeight:
                                  FontWeight
                                      .w800,
                            ),
                          ),
                        ),
                      ),
                    ]

                    // =============================================
                    // COUNTDOWN / CALIBRATION CURRENTLY RUNNING
                    // =============================================

                    else ...[
                      SizedBox(
                        width:
                            double.infinity,
                        height: 48,
                        child:
                            OutlinedButton(
                          onPressed: () {
                            _cancelCalibration();
                          },

                          style:
                              OutlinedButton
                                  .styleFrom(
                            foregroundColor:
                                Colors.white,

                            side:
                                const BorderSide(
                              color: Color(
                                0xFF555B65,
                              ),
                            ),

                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                14,
                              ),
                            ),
                          ),

                          child:
                              const Text(
                            'Cancel Calibration',
                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _cameraView() {
    if (_initializing) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: _C.red)),
      );
    }

    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    return _cameraPreview ?? RepaintBoundary(child: CameraPreview(controller));
  }
}

// =============================================================
// REFERENCE CAMERA PAINTER
// =============================================================

class _ReferenceCameraPainter extends CustomPainter {
  const _ReferenceCameraPainter({required this.detected});

  final bool detected;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = detected ? const Color(0xFF22C55E) : _C.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 24.0;

    const length = 37.0;

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
  bool shouldRepaint(covariant _ReferenceCameraPainter oldDelegate) {
    return oldDelegate.detected != detected;
  }
}

// =============================================================
// SMALL UI COMPONENTS
// =============================================================

class _TaskModeButton extends StatelessWidget {
  const _TaskModeButton({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String imagePath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 100),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFF1F2)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _C.red : Theme.of(context).dividerColor,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              imagePath,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),

            const SizedBox(height: 5),

            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? _C.red
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 2),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: const TextStyle(fontSize: 10, color: Color(0xFF777A84)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutTypeButton extends StatelessWidget {
  const _WorkoutTypeButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF1F2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _C.red : Theme.of(context).dividerColor,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected
                  ? _C.red
                  : Theme.of(context).colorScheme.onSurface,
              size: 24,
            ),

            const SizedBox(height: 4),

            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? _C.red
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: Color(0xFF777A84)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSettingRow extends StatelessWidget {
  const _ModeSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 27),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF777A84),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          trailing,
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Divider(height: 1),
    );
  }
}

class _AssetIconBox extends StatelessWidget {
  const _AssetIconBox({
    required this.imagePath,
    required this.dark,
  });

  final String imagePath;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF202126)
            : const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Image.asset(
        imagePath,
        width: 39,
        height: 39,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _PinkIcon extends StatelessWidget {
  const _PinkIcon({required this.icon, required this.dark});

  final IconData icon;

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF28171B) : const Color(0xFFFFECEE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: _C.red, size: 23),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.dark,
    required this.onTap,
  });

  final IconData icon;

  final String title;

  final String subtitle;

  final String value;

  final bool dark;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          children: [
            _PinkIcon(icon: icon, dark: dark),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    subtitle,
                    style: TextStyle(
                      color: dark ? _T.muted : const Color(0xFF777A84),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dark ? _T.text : Colors.black,
                  fontSize: 13,
                ),
              ),
            ),

            const SizedBox(width: 3),

            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _VerificationRow extends StatelessWidget {
  const _VerificationRow({
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.dark,
    required this.onTap,
  });

  final String imagePath;
  final String title;
  final String subtitle;
  final bool checked;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            _AssetIconBox(
              imagePath: imagePath,
              dark: dark,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    subtitle,
                    style: TextStyle(
                      color: dark ? _T.muted : const Color(0xFF555861),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                color: checked
                    ? _C.red
                    : dark
                    ? _T.selected
                    : const Color(0xFFF0F1F3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: checked
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({
    required this.title,
    required this.subtitle,
    required this.complete,
    required this.dark,
    required this.onTap,
    this.icon,
    this.imagePath,
  });

  final IconData? icon;
  final String? imagePath;
  final String title;
  final String subtitle;
  final bool complete;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? _T.selected : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: complete
                      ? _C.red
                      : dark
                      ? _T.border
                      : const Color(0xFFD5D7DD),
                ),
              ),
              child: imagePath != null
                  ? Image.asset(
                      imagePath!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                    )
                  : Icon(
                      icon,
                      color: complete
                          ? _C.red
                          : dark
                          ? _T.muted
                          : const Color(0xFF777A84),
                      size: 27,
                    ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    style: TextStyle(
                      color: dark ? _T.muted : const Color(0xFF666A74),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _C.red,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        'Pro',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// =============================================================
// DURATION COMPONENTS
// =============================================================

class _RepGoalWheel extends StatelessWidget {
  const _RepGoalWheel({
    required this.controller,
    required this.selectedValue,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int selectedValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 112,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 36,
            physics: const FixedExtentScrollPhysics(),
            perspective: 0.003,
            diameterRatio: 1.35,
            onSelectedItemChanged: (index) {
              onChanged(index + 1);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: 200,
              builder: (context, index) {
                final value = index + 1;
                final selected = value == selectedValue;

                return Center(
                  child: Text(
                    '$value',
                    style: TextStyle(
                      fontSize: selected ? 30 : 16,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
                      color: selected
                          ? Theme.of(context).colorScheme.onSurface
                          : const Color(0xFF8D9099),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 4),

        const Text(
          'REPS',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF777A84),
          ),
        ),
      ],
    );
  }
}

class _DurationWheel extends StatelessWidget {
  const _DurationWheel({
    required this.controller,
    required this.selectedValue,
    required this.itemCount,
    required this.label,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;

  final int selectedValue;

  final int itemCount;

  final String label;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Column(
        children: [
          SizedBox(
            height: 112,
            child: ListWheelScrollView.useDelegate(
              controller: controller,
              itemExtent: 36,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: itemCount,
                builder: (context, index) {
                  final selected = index == selectedValue;

                  return Center(
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: selected ? 28 : 15,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: selected
                            ? Theme.of(context).colorScheme.onSurface
                            : const Color(0xFF8D9099),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 4),

          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Color(0xFF777A84)),
          ),
        ],
      ),
    );
  }
}

class _DurationColon extends StatelessWidget {
  const _DurationColon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 13,
      height: 112,
      child: Center(
        child: Text(
          ':',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// =============================================================
// ICON COMPONENT
// =============================================================

class _TaskIconTile extends StatelessWidget {
  const _TaskIconTile({required this.type, required this.size});

  final TaskIconType type;

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEE),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        taskIconData(type),
        color: const Color(0xFF24262D),
        size: size * .52,
      ),
    );
  }
}

// =============================================================
// PUBLIC ICON HELPERS
// =============================================================

IconData taskIconData(TaskIconType type) {
  switch (type) {
    case TaskIconType.generic:
      return Icons.list_rounded;

    case TaskIconType.study:
      return Icons.menu_book_rounded;

    case TaskIconType.cleaning:
      return Icons.cleaning_services_rounded;

    case TaskIconType.workout:
      return Icons.fitness_center_rounded;

    case TaskIconType.running:
      return Icons.directions_run_rounded;

    case TaskIconType.computer:
      return Icons.laptop_mac_rounded;

    case TaskIconType.cooking:
      return Icons.restaurant_rounded;

    case TaskIconType.laundry:
      return Icons.local_laundry_service_rounded;

    case TaskIconType.meditation:
      return Icons.self_improvement_rounded;

    case TaskIconType.garden:
      return Icons.local_florist_rounded;

    case TaskIconType.sleep:
      return Icons.bed_rounded;

    case TaskIconType.shopping:
      return Icons.shopping_cart_rounded;

    case TaskIconType.hydration:
      return Icons.water_drop_rounded;

    case TaskIconType.health:
      return Icons.medication_rounded;

    case TaskIconType.music:
      return Icons.music_note_rounded;

    case TaskIconType.phone:
      return Icons.phone_rounded;

    case TaskIconType.pet:
      return Icons.pets_rounded;

    case TaskIconType.selfCare:
      return Icons.spa_rounded;
  }
}

String taskIconLabel(TaskIconType type) {
  switch (type) {
    case TaskIconType.generic:
      return 'Task';

    case TaskIconType.study:
      return 'Study';

    case TaskIconType.cleaning:
      return 'Clean';

    case TaskIconType.workout:
      return 'Workout';

    case TaskIconType.running:
      return 'Run';

    case TaskIconType.computer:
      return 'Work';

    case TaskIconType.cooking:
      return 'Cook';

    case TaskIconType.laundry:
      return 'Laundry';

    case TaskIconType.meditation:
      return 'Meditate';

    case TaskIconType.garden:
      return 'Garden';

    case TaskIconType.sleep:
      return 'Sleep';

    case TaskIconType.shopping:
      return 'Shop';

    case TaskIconType.hydration:
      return 'Water';

    case TaskIconType.health:
      return 'Health';

    case TaskIconType.music:
      return 'Music';

    case TaskIconType.phone:
      return 'Call';

    case TaskIconType.pet:
      return 'Pet';

    case TaskIconType.selfCare:
      return 'Self Care';
  }
}

// =============================================================
// COLORS
// =============================================================

class _C {
  static const red = Color(0xFFFF101C);
}

class _T {
  static const background = Color(0xFF0B1016);

  static const surface = Color(0xFF10161D);

  static const selected = Color(0xFF171E27);

  static const border = Color(0xFF252D37);

  static const text = Color(0xFFF4F6F8);

  static const muted = Color(0xFF9DA8B8);
}
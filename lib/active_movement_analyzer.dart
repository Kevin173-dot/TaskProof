import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'new_task_page.dart' show ActivityLevel;

/// Movement information derived from the best person pose in one camera frame.
///
/// [bodyCenter] and [bodyBounds] use normalized image coordinates. Bounds can
/// extend slightly outside 0..1, which is useful for camera-placement hints.
/// [bodyScale] is the detected body scale divided by the frame's short side.
class ActiveMovementObservation {
  const ActiveMovementObservation({
    required this.personPresent,
    required this.movementScore,
    required this.smoothedMovementScore,
    required this.visibleLandmarkCount,
    required this.bodyScale,
    required this.hasUpperBody,
    required this.hasLowerBody,
    this.bodyCenter,
    this.bodyBounds,
  });

  final bool personPresent;

  /// The immediate movement score for this pair of frames, in the range 0..1.
  final double movementScore;

  /// A robust, time-weighted movement score over roughly three seconds.
  final double smoothedMovementScore;

  /// Number of confident shoulders, elbows, wrists, hips, knees, and ankles.
  final int visibleLandmarkCount;

  final Offset? bodyCenter;
  final Rect? bodyBounds;
  final double bodyScale;
  final bool hasUpperBody;
  final bool hasLowerBody;

  double get landmarkCoverage =>
      (visibleLandmarkCount / ActiveMovementAnalyzer.usefulLandmarkCount).clamp(
        0.0,
        1.0,
      );

  bool get hasRecommendedBodyCoverage =>
      visibleLandmarkCount >=
          ActiveMovementAnalyzer.recommendedVisibleLandmarks &&
      hasUpperBody &&
      hasLowerBody;
}

/// Converts an ML Kit pose stream into scale-independent movement scores.
///
/// Expected-activity thresholds are deliberately fixed. Sensitivity only
/// changes the landmark and body-translation noise floors.
class ActiveMovementAnalyzer {
  ActiveMovementAnalyzer();

  static const Duration smoothingWindow = Duration(seconds: 3);

  static const double landmarkLikelihoodThreshold = 0.45;
  static const int minimumPresentLandmarks = 4;
  static const int recommendedVisibleLandmarks = 8;
  static const int usefulLandmarkCount = 12;

  static const double lightActivityThreshold = 0.035;
  static const double moderateActivityThreshold = 0.085;
  static const double highActivityThreshold = 0.17;

  static const Duration _maximumComparisonGap = Duration(milliseconds: 650);
  static const double _referenceIntervalSeconds = 0.18;
  static const double _localMovementGain = 8.0;
  static const double _centerMovementGain = 2.6;
  static const double _maximumInstantaneousScore = 1.0;

  static const Set<PoseLandmarkType> _usefulTypes = {
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

  static const Set<PoseLandmarkType> _upperBodyTypes = {
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
  };

  static const Set<PoseLandmarkType> _lowerBodyTypes = {
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  };

  _PoseSample? _previousPose;
  DateTime? _lastTimestamp;
  final List<double> _recentMovementScores = <double>[];
  final List<_MovementInterval> _movementWindow = <_MovementInterval>[];

  static double thresholdFor(ActivityLevel level) {
    return switch (level) {
      ActivityLevel.light => lightActivityThreshold,
      ActivityLevel.moderate => moderateActivityThreshold,
      ActivityLevel.high => highActivityThreshold,
    };
  }

  ActiveMovementObservation analyze({
    required List<Pose> poses,
    required Size imageSize,
    required DateTime timestamp,
    required double sensitivity,
  }) {
    if (_lastTimestamp != null && timestamp.isBefore(_lastTimestamp!)) {
      reset();
    }
    _lastTimestamp = timestamp;

    _pruneMovementWindow(timestamp);

    if (imageSize.width <= 0 || imageSize.height <= 0 || poses.isEmpty) {
      return _absentObservation(timestamp);
    }

    final sample = _bestPoseSample(poses, imageSize);
    if (sample == null || sample.landmarks.length < minimumPresentLandmarks) {
      _clearComparisonAfterLongGap(timestamp);
      return _observationForSample(
        sample,
        personPresent: false,
        movementScore: 0,
        smoothedMovementScore: _smoothedScore(timestamp),
      );
    }

    var movementScore = 0.0;
    final previous = _previousPose;

    if (previous != null) {
      final elapsed = timestamp.difference(previous.timestamp);
      if (elapsed > Duration.zero && elapsed <= _maximumComparisonGap) {
        movementScore = _movementBetween(
          previous,
          sample,
          elapsed,
          sensitivity.clamp(0.0, 1.0),
        );

        final stableScore = _temporallyStableScore(movementScore);
        _movementWindow.add(
          _MovementInterval(
            end: timestamp,
            duration: elapsed,
            score: stableScore,
          ),
        );
      } else if (elapsed > _maximumComparisonGap) {
        _recentMovementScores.clear();
      }
    }

    _previousPose = sample;
    _pruneMovementWindow(timestamp);

    return _observationForSample(
      sample,
      personPresent: true,
      movementScore: movementScore,
      smoothedMovementScore: _smoothedScore(timestamp),
    );
  }

  void reset() {
    _previousPose = null;
    _lastTimestamp = null;
    _recentMovementScores.clear();
    _movementWindow.clear();
  }

  ActiveMovementObservation _absentObservation(DateTime timestamp) {
    _clearComparisonAfterLongGap(timestamp);
    return ActiveMovementObservation(
      personPresent: false,
      movementScore: 0,
      smoothedMovementScore: _smoothedScore(timestamp),
      visibleLandmarkCount: 0,
      bodyScale: 0,
      hasUpperBody: false,
      hasLowerBody: false,
    );
  }

  ActiveMovementObservation _observationForSample(
    _PoseSample? sample, {
    required bool personPresent,
    required double movementScore,
    required double smoothedMovementScore,
  }) {
    return ActiveMovementObservation(
      personPresent: personPresent,
      movementScore: movementScore,
      smoothedMovementScore: smoothedMovementScore,
      visibleLandmarkCount: sample?.landmarks.length ?? 0,
      bodyCenter: sample?.normalizedCenter,
      bodyBounds: sample?.normalizedBounds,
      bodyScale: sample?.normalizedScale ?? 0,
      hasUpperBody: sample?.hasUpperBody ?? false,
      hasLowerBody: sample?.hasLowerBody ?? false,
    );
  }

  _PoseSample? _bestPoseSample(List<Pose> poses, Size imageSize) {
    _PoseSample? best;

    for (final pose in poses) {
      final sample = _sampleFromPose(pose, imageSize);
      if (sample == null) {
        continue;
      }

      if (best == null || sample.selectionScore > best.selectionScore) {
        best = sample;
      }
    }

    return best;
  }

  _PoseSample? _sampleFromPose(Pose pose, Size imageSize) {
    final landmarks = <PoseLandmarkType, Offset>{};
    var likelihoodTotal = 0.0;

    for (final type in _usefulTypes) {
      final landmark = pose.landmarks[type];
      if (landmark == null ||
          landmark.likelihood < landmarkLikelihoodThreshold ||
          !_isNearImage(landmark, imageSize)) {
        continue;
      }

      landmarks[type] = Offset(landmark.x, landmark.y);
      likelihoodTotal += landmark.likelihood;
    }

    if (landmarks.isEmpty) {
      return null;
    }

    final center = _robustBodyCenter(landmarks);
    final bounds = _boundsFor(landmarks.values);
    final scale = _bodyScale(landmarks, bounds, imageSize);
    final upperCount = landmarks.keys.where(_upperBodyTypes.contains).length;
    final lowerCount = landmarks.keys.where(_lowerBodyTypes.contains).length;
    final hasUpperBody = upperCount >= 4;
    final hasLowerBody = lowerCount >= 4;
    final shortSide = math.min(imageSize.width, imageSize.height);

    // Landmark count dominates, followed by broad body coverage and average
    // confidence. This consistently selects the most useful person pose.
    final averageLikelihood = likelihoodTotal / landmarks.length;
    final selectionScore =
        (landmarks.length * 100.0) +
        (hasUpperBody ? 12.0 : 0.0) +
        (hasLowerBody ? 12.0 : 0.0) +
        averageLikelihood;

    return _PoseSample(
      timestamp: _lastTimestamp!,
      landmarks: landmarks,
      scale: scale,
      normalizedCenter: Offset(
        center.dx / imageSize.width,
        center.dy / imageSize.height,
      ),
      normalizedBounds: Rect.fromLTRB(
        bounds.left / imageSize.width,
        bounds.top / imageSize.height,
        bounds.right / imageSize.width,
        bounds.bottom / imageSize.height,
      ),
      normalizedScale: shortSide > 0 ? scale / shortSide : 0,
      hasUpperBody: hasUpperBody,
      hasLowerBody: hasLowerBody,
      selectionScore: selectionScore,
    );
  }

  bool _isNearImage(PoseLandmark landmark, Size imageSize) {
    const margin = 0.08;
    return landmark.x >= -imageSize.width * margin &&
        landmark.x <= imageSize.width * (1 + margin) &&
        landmark.y >= -imageSize.height * margin &&
        landmark.y <= imageSize.height * (1 + margin);
  }

  double _movementBetween(
    _PoseSample previous,
    _PoseSample current,
    Duration elapsed,
    double sensitivity,
  ) {
    final sharedTypes = previous.landmarks.keys
        .where(current.landmarks.containsKey)
        .toList(growable: false);
    if (sharedTypes.length < minimumPresentLandmarks) {
      return 0;
    }

    final elapsedSeconds =
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (elapsedSeconds <= 0) {
      return 0;
    }

    final averageScale = (previous.scale + current.scale) / 2;
    if (averageScale <= 0) {
      return 0;
    }

    final scaleRatio = current.scale / previous.scale;
    if (scaleRatio < 0.55 || scaleRatio > 1.8) {
      return 0;
    }

    final intervalFactor = (_referenceIntervalSeconds / elapsedSeconds).clamp(
      0.35,
      2.2,
    );
    final displacements = <Offset>[];

    for (final type in sharedTypes) {
      final previousPoint = previous.landmarks[type]!;
      final currentPoint = current.landmarks[type]!;
      displacements.add(
        Offset(
          (currentPoint.dx - previousPoint.dx) / averageScale * intervalFactor,
          (currentPoint.dy - previousPoint.dy) / averageScale * intervalFactor,
        ),
      );
    }

    // The component-wise median is a robust estimate of whole-body
    // translation. Subtracting it prevents camera jitter from looking like
    // motion in every joint, while still allowing sufficiently large body
    // translation to contribute separately.
    final translation = Offset(
      _median(displacements.map((value) => value.dx)),
      _median(displacements.map((value) => value.dy)),
    );

    // A pose swap or catastrophic detector jump is a new baseline, not a
    // burst of user movement.
    if (translation.distance > 0.9) {
      return 0;
    }

    final landmarkNoiseFloor = _lerp(0.038, 0.014, sensitivity);
    final centerNoiseFloor = _lerp(0.060, 0.024, sensitivity);
    final adjustedLandmarkMovement = <double>[];
    var responsiveLandmarks = 0;

    for (final displacement in displacements) {
      final localDistance = (displacement - translation).distance;
      final adjusted = math.max(0.0, localDistance - landmarkNoiseFloor);
      if (adjusted > 0) {
        responsiveLandmarks++;
      }
      adjustedLandmarkMovement.add(adjusted);
    }

    adjustedLandmarkMovement.sort();
    if (adjustedLandmarkMovement.length >= 5) {
      // One bad landmark should never be able to drive the result.
      adjustedLandmarkMovement.removeLast();
    }

    final localAverage = adjustedLandmarkMovement.isEmpty
        ? 0.0
        : adjustedLandmarkMovement.reduce((a, b) => a + b) /
              adjustedLandmarkMovement.length;

    final supportFactor = switch (responsiveLandmarks) {
      0 || 1 => 0.0,
      2 => 0.55,
      3 => 0.8,
      _ => 1.0,
    };

    final localScore = localAverage * _localMovementGain * supportFactor;
    final centerMovement = math.max(
      0.0,
      translation.distance - centerNoiseFloor,
    );
    final centerScore = centerMovement * _centerMovementGain;

    return (localScore + centerScore).clamp(0.0, _maximumInstantaneousScore);
  }

  double _temporallyStableScore(double score) {
    _recentMovementScores.add(score);
    if (_recentMovementScores.length > 3) {
      _recentMovementScores.removeAt(0);
    }

    // Requiring movement in two neighboring comparisons keeps a single bad
    // frame out of the rolling score without making real motion feel delayed.
    if (_recentMovementScores.length == 1) {
      return 0;
    }
    if (_recentMovementScores.length == 2) {
      return math.min(_recentMovementScores.first, _recentMovementScores.last);
    }
    return _median(_recentMovementScores);
  }

  void _clearComparisonAfterLongGap(DateTime timestamp) {
    final previous = _previousPose;
    if (previous != null &&
        timestamp.difference(previous.timestamp) > _maximumComparisonGap) {
      _previousPose = null;
      _recentMovementScores.clear();
    }
  }

  void _pruneMovementWindow(DateTime timestamp) {
    final windowStart = timestamp.subtract(smoothingWindow);
    _movementWindow.removeWhere((sample) => !sample.end.isAfter(windowStart));
  }

  double _smoothedScore(DateTime timestamp) {
    if (_movementWindow.isEmpty) {
      return 0;
    }

    final windowStart = timestamp.subtract(smoothingWindow);
    var weightedScore = 0.0;
    var totalSeconds = 0.0;

    for (final sample in _movementWindow) {
      final sampleStart = sample.end.subtract(sample.duration);
      final overlapStart = sampleStart.isAfter(windowStart)
          ? sampleStart
          : windowStart;
      final overlapEnd = sample.end.isBefore(timestamp)
          ? sample.end
          : timestamp;
      final overlap = overlapEnd.difference(overlapStart);
      if (overlap <= Duration.zero) {
        continue;
      }

      final seconds = overlap.inMicroseconds / Duration.microsecondsPerSecond;
      weightedScore += sample.score * seconds;
      totalSeconds += seconds;
    }

    return totalSeconds > 0 ? weightedScore / totalSeconds : 0;
  }

  static Offset _robustBodyCenter(Map<PoseLandmarkType, Offset> landmarks) {
    final torso = <Offset>[];
    for (final type in const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ]) {
      final point = landmarks[type];
      if (point != null) {
        torso.add(point);
      }
    }

    final points = torso.length >= 2 ? torso : landmarks.values.toList();
    return Offset(
      _median(points.map((point) => point.dx)),
      _median(points.map((point) => point.dy)),
    );
  }

  static Rect _boundsFor(Iterable<Offset> points) {
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;

    for (final point in points) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  static double _bodyScale(
    Map<PoseLandmarkType, Offset> landmarks,
    Rect bounds,
    Size imageSize,
  ) {
    final candidates = <double>[];

    void addPair(
      PoseLandmarkType first,
      PoseLandmarkType second,
      double multiplier,
    ) {
      final firstPoint = landmarks[first];
      final secondPoint = landmarks[second];
      if (firstPoint != null && secondPoint != null) {
        candidates.add((firstPoint - secondPoint).distance * multiplier);
      }
    }

    addPair(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, 2.4);
    addPair(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, 2.8);
    addPair(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, 2.2);
    addPair(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, 2.2);

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null) {
      final shoulderCenter = (leftShoulder + rightShoulder) / 2;
      final hipCenter = (leftHip + rightHip) / 2;
      candidates.add((shoulderCenter - hipCenter).distance * 2.2);
    }

    final minimumScale = math.min(imageSize.width, imageSize.height) * 0.08;
    final fallback = math.max(bounds.width, bounds.height) * 0.75;
    final scale = candidates.isEmpty ? fallback : _median(candidates);
    return math.max(scale, minimumScale);
  }

  static double _median(Iterable<double> input) {
    final values = input.toList()..sort();
    if (values.isEmpty) {
      return 0;
    }
    final middle = values.length ~/ 2;
    if (values.length.isOdd) {
      return values[middle];
    }
    return (values[middle - 1] + values[middle]) / 2;
  }

  static double _lerp(double start, double end, double amount) {
    return start + ((end - start) * amount);
  }
}

class _PoseSample {
  const _PoseSample({
    required this.timestamp,
    required this.landmarks,
    required this.scale,
    required this.normalizedCenter,
    required this.normalizedBounds,
    required this.normalizedScale,
    required this.hasUpperBody,
    required this.hasLowerBody,
    required this.selectionScore,
  });

  final DateTime timestamp;
  final Map<PoseLandmarkType, Offset> landmarks;
  final double scale;
  final Offset normalizedCenter;
  final Rect normalizedBounds;
  final double normalizedScale;
  final bool hasUpperBody;
  final bool hasLowerBody;
  final double selectionScore;
}

class _MovementInterval {
  const _MovementInterval({
    required this.end,
    required this.duration,
    required this.score,
  });

  final DateTime end;
  final Duration duration;
  final double score;
}

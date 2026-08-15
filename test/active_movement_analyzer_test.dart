import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:taskguard/active_movement_analyzer.dart';
import 'package:taskguard/new_task_page.dart' show ActivityLevel;

const _imageSize = Size(1000, 1000);

const _basePoints = <PoseLandmarkType, Offset>{
  PoseLandmarkType.leftShoulder: Offset(-50, -120),
  PoseLandmarkType.rightShoulder: Offset(50, -120),
  PoseLandmarkType.leftElbow: Offset(-75, -55),
  PoseLandmarkType.rightElbow: Offset(75, -55),
  PoseLandmarkType.leftWrist: Offset(-90, 15),
  PoseLandmarkType.rightWrist: Offset(90, 15),
  PoseLandmarkType.leftHip: Offset(-35, 0),
  PoseLandmarkType.rightHip: Offset(35, 0),
  PoseLandmarkType.leftKnee: Offset(-32, 105),
  PoseLandmarkType.rightKnee: Offset(32, 105),
  PoseLandmarkType.leftAnkle: Offset(-30, 210),
  PoseLandmarkType.rightAnkle: Offset(30, 210),
};

void main() {
  group('ActiveMovementAnalyzer', () {
    test('uses fixed, ordered expected-activity thresholds', () {
      expect(
        ActiveMovementAnalyzer.thresholdFor(ActivityLevel.light),
        ActiveMovementAnalyzer.lightActivityThreshold,
      );
      expect(
        ActiveMovementAnalyzer.thresholdFor(ActivityLevel.light),
        lessThan(ActiveMovementAnalyzer.thresholdFor(ActivityLevel.moderate)),
      );
      expect(
        ActiveMovementAnalyzer.thresholdFor(ActivityLevel.moderate),
        lessThan(ActiveMovementAnalyzer.thresholdFor(ActivityLevel.high)),
      );
    });

    test('selects the best pose and reports placement coverage', () {
      final analyzer = ActiveMovementAnalyzer();
      final partial = _pose(
        center: const Offset(180, 400),
        included: const {
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.rightElbow,
        },
      );
      final complete = _pose(center: const Offset(600, 450));

      final observation = analyzer.analyze(
        poses: [partial, complete],
        imageSize: _imageSize,
        timestamp: DateTime.utc(2026),
        sensitivity: 0.5,
      );

      expect(observation.personPresent, isTrue);
      expect(observation.visibleLandmarkCount, 12);
      expect(observation.landmarkCoverage, 1);
      expect(observation.hasRecommendedBodyCoverage, isTrue);
      expect(observation.bodyCenter!.dx, closeTo(0.6, 0.03));
      expect(observation.bodyBounds, isNotNull);
      expect(observation.bodyScale, greaterThan(0));
    });

    test('filters low-likelihood landmarks from person presence', () {
      final analyzer = ActiveMovementAnalyzer();
      final observation = analyzer.analyze(
        poses: [_pose(likelihood: 0.44)],
        imageSize: _imageSize,
        timestamp: DateTime.utc(2026),
        sensitivity: 0.5,
      );

      expect(observation.personPresent, isFalse);
      expect(observation.visibleLandmarkCount, 0);
    });

    test('ignores camera jitter, one bad landmark, and a hand fidget', () {
      final start = DateTime.utc(2026);
      final analyzer = ActiveMovementAnalyzer();
      final poses = [
        _pose(),
        _pose(center: const Offset(504, 433)),
        _pose(changes: const {PoseLandmarkType.leftWrist: Offset(210, -120)}),
        _pose(
          changes: const {
            PoseLandmarkType.leftWrist: Offset(24, -20),
            PoseLandmarkType.leftElbow: Offset(8, -5),
          },
        ),
        _pose(),
      ];

      ActiveMovementObservation? result;
      for (var index = 0; index < poses.length; index++) {
        result = analyzer.analyze(
          poses: [poses[index]],
          imageSize: _imageSize,
          timestamp: start.add(Duration(milliseconds: 150 * index)),
          sensitivity: 0.5,
        );
      }

      expect(
        result!.smoothedMovementScore,
        lessThan(ActiveMovementAnalyzer.lightActivityThreshold),
      );
    });

    test('detects repeated broad chore movement', () {
      final start = DateTime.utc(2026);
      final analyzer = ActiveMovementAnalyzer();
      ActiveMovementObservation? result;

      for (var index = 0; index < 16; index++) {
        final phase = switch (index % 4) {
          0 => 0.0,
          1 => 1.0,
          2 => 0.0,
          _ => -1.0,
        };
        result = analyzer.analyze(
          poses: [_pose(changes: _choreChanges(phase))],
          imageSize: _imageSize,
          timestamp: start.add(Duration(milliseconds: 150 * index)),
          sensitivity: 0.5,
        );
      }

      expect(result!.personPresent, isTrue);
      expect(
        result.smoothedMovementScore,
        greaterThan(ActiveMovementAnalyzer.moderateActivityThreshold),
      );
    });

    test('sensitivity changes noise response, not activity thresholds', () {
      final start = DateTime.utc(2026);
      final lowSensitivity = ActiveMovementAnalyzer();
      final highSensitivity = ActiveMovementAnalyzer();
      final smallChanges = <PoseLandmarkType, Offset>{
        PoseLandmarkType.leftElbow: const Offset(-10, 0),
        PoseLandmarkType.rightElbow: const Offset(10, 0),
        PoseLandmarkType.leftWrist: const Offset(-10, 0),
        PoseLandmarkType.rightWrist: const Offset(10, 0),
      };

      lowSensitivity.analyze(
        poses: [_pose()],
        imageSize: _imageSize,
        timestamp: start,
        sensitivity: 0,
      );
      highSensitivity.analyze(
        poses: [_pose()],
        imageSize: _imageSize,
        timestamp: start,
        sensitivity: 1,
      );

      final low = lowSensitivity.analyze(
        poses: [_pose(changes: smallChanges)],
        imageSize: _imageSize,
        timestamp: start.add(const Duration(milliseconds: 150)),
        sensitivity: 0,
      );
      final high = highSensitivity.analyze(
        poses: [_pose(changes: smallChanges)],
        imageSize: _imageSize,
        timestamp: start.add(const Duration(milliseconds: 150)),
        sensitivity: 1,
      );

      expect(high.movementScore, greaterThan(low.movementScore));
      expect(
        ActiveMovementAnalyzer.thresholdFor(ActivityLevel.moderate),
        ActiveMovementAnalyzer.moderateActivityThreshold,
      );
    });

    test('normalizes equivalent movement at different body scales', () {
      final start = DateTime.utc(2026);
      final nearAnalyzer = ActiveMovementAnalyzer();
      final farAnalyzer = ActiveMovementAnalyzer();
      final changes = _choreChanges(1);

      farAnalyzer.analyze(
        poses: [_pose(scale: 1)],
        imageSize: _imageSize,
        timestamp: start,
        sensitivity: 0.5,
      );
      nearAnalyzer.analyze(
        poses: [_pose(scale: 2)],
        imageSize: _imageSize,
        timestamp: start,
        sensitivity: 0.5,
      );

      final far = farAnalyzer.analyze(
        poses: [_pose(scale: 1, changes: changes)],
        imageSize: _imageSize,
        timestamp: start.add(const Duration(milliseconds: 150)),
        sensitivity: 0.5,
      );
      final near = nearAnalyzer.analyze(
        poses: [_pose(scale: 2, changes: changes)],
        imageSize: _imageSize,
        timestamp: start.add(const Duration(milliseconds: 150)),
        sensitivity: 0.5,
      );

      expect(near.movementScore, closeTo(far.movementScore, 0.005));
    });

    test('reset clears both comparison and smoothing history', () {
      final analyzer = ActiveMovementAnalyzer();
      final start = DateTime.utc(2026);

      analyzer.analyze(
        poses: [_pose()],
        imageSize: _imageSize,
        timestamp: start,
        sensitivity: 0.5,
      );
      analyzer.analyze(
        poses: [_pose(changes: _choreChanges(1))],
        imageSize: _imageSize,
        timestamp: start.add(const Duration(milliseconds: 150)),
        sensitivity: 0.5,
      );
      analyzer.reset();

      final result = analyzer.analyze(
        poses: [_pose(changes: _choreChanges(-1))],
        imageSize: _imageSize,
        timestamp: start.add(const Duration(seconds: 1)),
        sensitivity: 0.5,
      );

      expect(result.movementScore, 0);
      expect(result.smoothedMovementScore, 0);
    });
  });
}

Map<PoseLandmarkType, Offset> _choreChanges(double phase) {
  return {
    PoseLandmarkType.leftShoulder: Offset(-5 * phase, 5 * phase),
    PoseLandmarkType.rightShoulder: Offset(5 * phase, -5 * phase),
    PoseLandmarkType.leftElbow: Offset(-16 * phase, 10 * phase),
    PoseLandmarkType.rightElbow: Offset(16 * phase, -10 * phase),
    PoseLandmarkType.leftWrist: Offset(-28 * phase, 14 * phase),
    PoseLandmarkType.rightWrist: Offset(28 * phase, -14 * phase),
  };
}

Pose _pose({
  Offset center = const Offset(500, 430),
  double scale = 1,
  double likelihood = 0.99,
  Map<PoseLandmarkType, Offset> changes = const {},
  Set<PoseLandmarkType>? included,
}) {
  final landmarks = <PoseLandmarkType, PoseLandmark>{};

  for (final entry in _basePoints.entries) {
    if (included != null && !included.contains(entry.key)) {
      continue;
    }
    final change = changes[entry.key] ?? Offset.zero;
    final point = center + ((entry.value + change) * scale);
    landmarks[entry.key] = PoseLandmark(
      type: entry.key,
      x: point.dx,
      y: point.dy,
      z: 0,
      likelihood: likelihood,
    );
  }

  return Pose(landmarks: landmarks);
}

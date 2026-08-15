import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:taskguard/new_task_page.dart';
import 'package:taskguard/workout_pose_analyzer.dart';

void main() {
  final start = DateTime(2026);

  WorkoutPoseObservation frame(
    WorkoutPoseAnalyzer analyzer,
    Map<PoseLandmarkType, Offset> points,
    int index,
  ) {
    return analyzer.analyzeLandmarks({
      for (final entry in points.entries)
        entry.key: WorkoutLandmark(entry.value),
    }, timestamp: start.add(Duration(milliseconds: index * 180)));
  }

  int jumpingJackSequence(
    WorkoutPoseAnalyzer analyzer,
    List<Map<PoseLandmarkType, Offset>> frames,
  ) {
    var reps = 0;
    for (var index = 0; index < 5; index++) {
      frame(analyzer, _jackClosed, index);
    }
    for (var index = 0; index < frames.length; index++) {
      if (frame(analyzer, frames[index], index + 5).repCounted) reps++;
    }
    return reps;
  }

  test('squat standing to bottom to standing counts exactly one rep', () {
    final analyzer = _analyzer(WorkoutExercise.squats);

    expect(frame(analyzer, _standingSquat, 0).repCounted, isFalse);
    final ready = frame(analyzer, _standingSquat, 1);
    expect(ready.repetitionTrackingEnabled, isTrue);
    expect(ready.repetitionSignalsAvailable, isTrue);
    expect(ready.repetitionReady, isTrue);
    expect(frame(analyzer, _bottomSquat, 2).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 3).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isTrue);
  });

  test('small squat movement does not count', () {
    final analyzer = _analyzer(WorkoutExercise.squats);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _standingSquat, 1);
    frame(analyzer, _shallowSquat, 2);
    expect(frame(analyzer, _standingSquat, 3).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isFalse);
  });

  test('push-up top to bottom to top counts exactly one rep', () {
    final analyzer = _analyzer(WorkoutExercise.pushUps);

    frame(analyzer, _pushUpTop, 0);
    frame(analyzer, _pushUpTop, 1);
    expect(frame(analyzer, _pushUpBottom, 2).repCounted, isFalse);
    expect(frame(analyzer, _pushUpTop, 3).repCounted, isFalse);
    expect(frame(analyzer, _pushUpTop, 4).repCounted, isTrue);
  });

  test('jumping jack closed to open to closed counts exactly one rep', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackOpen,
        _jackOpen,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('jumping jack counts with two clear closing frames', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackOpen,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('narrow jumping jack with a small bounce counts', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackNarrowOpen,
        _jackNarrowOpen,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('very wide jumping jack still counts normally', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackWideOpen,
        _jackWideOpen,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('jumping jack needs no feet or ankle landmarks', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);
    final coverageAnalyzer = _analyzer(WorkoutExercise.jumpingJacks);
    final initial = frame(coverageAnalyzer, _jackClosed, 0);

    expect(_jackClosed, isNot(contains(PoseLandmarkType.leftAnkle)));
    expect(_jackClosed, isNot(contains(PoseLandmarkType.rightAnkle)));
    expect(initial.coverage, isNot(WorkoutBodyCoverage.insufficient));
    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackNarrowOpen,
        _jackNarrowOpen,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('small-in-frame jumping jack still counts', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _scaledPose(_jackClosed, .10),
        _scaledPose(_jackClosed, .10),
        _scaledPose(_jackNarrowOpen, .10),
        _scaledPose(_jackNarrowOpen, .10),
        _scaledPose(_jackClosed, .10),
        _scaledPose(_jackClosed, .10),
      ]),
      1,
    );
  });

  test('low-confidence jumping jack landmarks are rejected', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);
    final poses = [
      _jackClosed,
      _jackClosed,
      _jackNarrowOpen,
      _jackNarrowOpen,
      _jackClosed,
    ];
    var reps = 0;

    for (var index = 0; index < poses.length; index++) {
      final observation = analyzer.analyzeLandmarks({
        for (final entry in poses[index].entries)
          entry.key: WorkoutLandmark(entry.value, confidence: .22),
      }, timestamp: start.add(Duration(milliseconds: index * 180)));
      if (observation.repCounted) reps++;
    }

    expect(reps, 0);
  });

  test('jumping jack camera becomes ready after five baseline samples', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);
    WorkoutPoseObservation? observation;

    for (var index = 0; index < 4; index++) {
      observation = frame(analyzer, _jackClosed, index);
      expect(observation.cameraReady, isFalse);
    }
    observation = frame(analyzer, _jackClosed, 4);

    expect(observation.cameraStable, isTrue);
    expect(observation.cameraReady, isTrue);
    expect(observation.overlayLandmarks, contains(PoseLandmarkType.leftWrist));
    expect(
      workoutCameraGuidance(WorkoutExercise.jumpingJacks, observation),
      'Camera position looks good',
    );
  });

  test('jumping jack baseline freezes after five samples', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);
    for (var index = 0; index < 5; index++) {
      frame(analyzer, _jackClosed, index);
    }

    final narrowerClosed = _jumpingJackPose(kneeSpread: .096, armsOpen: false);
    WorkoutPoseObservation? observation;
    for (var index = 5; index < 12; index++) {
      observation = frame(analyzer, narrowerClosed, index);
    }

    expect(observation!.jumpingJackDebug!.baselineReady, isTrue);
    expect(observation.jumpingJackDebug!.kneeSpreadRatio, closeTo(.8, .001));
  });

  test('slow valid frames do not reset an open jumping jack', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);
    for (var index = 0; index < 5; index++) {
      frame(analyzer, _jackClosed, index);
    }

    frame(analyzer, _jackNarrowOpen, 5);
    final firstClosed = frame(analyzer, _jackClosed, 11);
    final secondClosed = frame(analyzer, _jackClosed, 12);

    expect(firstClosed.jumpingJackDebug!.phase, JumpingJackPhase.closing);
    expect(firstClosed.repCounted, isFalse);
    expect(secondClosed.repCounted, isTrue);
  });

  test('held open jumping jack does not repeatedly count', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackNarrowOpen,
        _jackNarrowOpen,
        _jackNarrowOpen,
        _jackNarrowOpen,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('small jumping jack landmark jitter does not count', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackJitterArmsUp,
        _jackJitterArmsUp,
        _jackClosed,
        _jackClosed,
      ]),
      0,
    );
  });

  test('raising arms without knee opening does not count a jack', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackArmsOnly,
        _jackArmsOnly,
        _jackClosed,
        _jackClosed,
      ]),
      0,
    );
  });

  test('arm and knee opening in adjacent frames counts a jack', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackArmsOnly,
        _jackLegsOnly,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('brief knee landmark loss preserves jumping jack phase', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackNarrowOpen,
        _jackOpenMissingRightKnee,
        _jackNarrowOpen,
        _jackClosed,
        _jackClosed,
      ]),
      1,
    );
  });

  test('two complete jumping jack cycles count exactly two reps', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    expect(
      jumpingJackSequence(analyzer, [
        _jackClosed,
        _jackClosed,
        _jackNarrowOpen,
        _jackNarrowOpen,
        _jackClosed,
        _jackClosed,
        _jackNarrowOpen,
        _jackNarrowOpen,
        _jackClosed,
        _jackClosed,
      ]),
      2,
    );
  });

  test('rep goal one is reached by the first complete jack', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);
    const repGoal = 1;
    final reps = jumpingJackSequence(analyzer, [
      _jackClosed,
      _jackClosed,
      _jackNarrowOpen,
      _jackNarrowOpen,
      _jackClosed,
      _jackClosed,
    ]);

    expect(reps, repGoal);
    expect(reps >= repGoal, isTrue);
  });

  test('countdown calibration is preserved for the first jack', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);
    for (var index = 0; index < 12; index++) {
      frame(analyzer, _jackClosed, index);
    }

    analyzer.resetRepPhase();

    expect(frame(analyzer, _jackNarrowOpen, 12).repCounted, isFalse);
    expect(frame(analyzer, _jackNarrowOpen, 13).repCounted, isFalse);
    expect(frame(analyzer, _jackClosed, 14).repCounted, isFalse);
    expect(frame(analyzer, _jackClosed, 15).repCounted, isTrue);
  });

  test('all active jumping jack phases report exercise activity', () {
    final analyzer = _analyzer(WorkoutExercise.jumpingJacks);

    for (var index = 0; index < 5; index++) {
      frame(analyzer, _jackClosed, index);
    }
    final opening = frame(analyzer, _jackNarrowOpen, 5);
    final open = frame(analyzer, _jackNarrowOpen, 6);
    final closing = frame(analyzer, _jackClosed, 7);
    final completed = frame(analyzer, _jackClosed, 8);
    final idleClosed = frame(analyzer, _jackClosed, 9);

    expect(opening.exerciseActive, isTrue);
    expect(open.exerciseActive, isTrue);
    expect(closing.exerciseActive, isTrue);
    expect(closing.repCounted, isFalse);
    expect(completed.exerciseActive, isTrue);
    expect(completed.repCounted, isTrue);
    expect(idleClosed.exerciseActive, isFalse);
  });

  test('held bottom state cannot repeatedly count', () {
    final analyzer = _analyzer(WorkoutExercise.squats);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _standingSquat, 1);
    frame(analyzer, _bottomSquat, 2);
    expect(frame(analyzer, _bottomSquat, 3).repCounted, isFalse);
    expect(frame(analyzer, _bottomSquat, 4).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 5).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 6).repCounted, isTrue);
  });

  test('threshold jitter does not double count', () {
    final analyzer = _analyzer(WorkoutExercise.squats);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _standingSquat, 1);
    frame(analyzer, _bottomSquat, 2);
    frame(analyzer, _bottomJitter, 3);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 5).repCounted, isTrue);
    expect(frame(analyzer, _almostStandingSquat, 6).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 7).repCounted, isFalse);
  });

  test('same raised high knee held counts only once', () {
    final analyzer = _analyzer(WorkoutExercise.highKnees);

    frame(analyzer, _highKneesNeutral, 0);
    expect(frame(analyzer, _leftKneeRaised, 1).repCounted, isTrue);
    expect(frame(analyzer, _leftKneeRaised, 2).repCounted, isFalse);
    expect(frame(analyzer, _leftKneeRaised, 3).repCounted, isFalse);
  });

  test('reset between phases prevents a phantom rep', () {
    final analyzer = _analyzer(WorkoutExercise.squats);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _standingSquat, 1);
    frame(analyzer, _bottomSquat, 2);
    analyzer.reset();
    expect(frame(analyzer, _standingSquat, 3).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isFalse);
  });

  test('lunge standing to flexed knee to standing counts one rep', () {
    final analyzer = _analyzer(WorkoutExercise.lunges);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _standingSquat, 1);
    frame(analyzer, _lungeBottom, 2);
    expect(frame(analyzer, _standingSquat, 3).repCounted, isFalse);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isTrue);
  });

  test('sit-up reclined to upright to reclined counts one rep', () {
    final analyzer = _analyzer(WorkoutExercise.sitUps);

    frame(analyzer, _sitUpReclined, 0);
    frame(analyzer, _sitUpReclined, 1);
    frame(analyzer, _sitUpUpright, 2);
    expect(frame(analyzer, _sitUpReclined, 3).repCounted, isFalse);
    expect(frame(analyzer, _sitUpReclined, 4).repCounted, isTrue);
  });

  test('squat tracker rejects lunges', () {
    final analyzer = _analyzer(WorkoutExercise.squats);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _standingSquat, 1);
    frame(analyzer, _lungeBottom, 2);
    frame(analyzer, _standingSquat, 3);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isFalse);
  });

  test('lunge tracker rejects squats', () {
    final analyzer = _analyzer(WorkoutExercise.lunges);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _standingSquat, 1);
    frame(analyzer, _bottomSquat, 2);
    frame(analyzer, _standingSquat, 3);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isFalse);
  });

  test('push-up tracker rejects arm bends without a push-up body shape', () {
    final analyzer = _analyzer(WorkoutExercise.pushUps);

    frame(analyzer, _verticalPushUpTop, 0);
    frame(analyzer, _verticalPushUpTop, 1);
    frame(analyzer, _verticalArmBend, 2);
    frame(analyzer, _verticalPushUpTop, 3);
    expect(frame(analyzer, _verticalPushUpTop, 4).repCounted, isFalse);
  });

  test('sit-up tracker rejects knee movement without raising the torso', () {
    final analyzer = _analyzer(WorkoutExercise.sitUps);

    frame(analyzer, _sitUpReclined, 0);
    frame(analyzer, _sitUpReclined, 1);
    frame(analyzer, _sitUpKneesOnly, 2);
    frame(analyzer, _sitUpReclined, 3);
    expect(frame(analyzer, _sitUpReclined, 4).repCounted, isFalse);
  });

  test('burpee requires crouch and plank before returning to stand', () {
    final analyzer = _analyzer(WorkoutExercise.burpees);

    frame(analyzer, _standingSquat, 0);
    frame(analyzer, _bottomSquat, 1);
    frame(analyzer, _plank, 2);
    frame(analyzer, _bottomSquat, 3);
    expect(frame(analyzer, _standingSquat, 4).repCounted, isTrue);
  });

  test('mountain climber counts a distinct knee drive once', () {
    final analyzer = _analyzer(WorkoutExercise.mountainClimbers);

    frame(analyzer, _mountainClimberNeutral, 0);
    expect(frame(analyzer, _mountainClimberDrive, 1).repCounted, isTrue);
    expect(frame(analyzer, _mountainClimberDrive, 2).repCounted, isFalse);
  });

  test('plank and wall sit hold poses are recognized', () {
    final plank = WorkoutPoseAnalyzer(
      exercise: WorkoutExercise.plank,
      movementType: WorkoutMovementType.hold,
    );
    final wallSit = WorkoutPoseAnalyzer(
      exercise: WorkoutExercise.wallSit,
      movementType: WorkoutMovementType.hold,
    );

    expect(frame(plank, _plank, 0).exercisePoseValid, isTrue);
    expect(frame(wallSit, _wallSit, 0).exercisePoseValid, isTrue);
  });

  test(
    'running and jump-rope lower-body motion become continuous activity',
    () {
      final running = WorkoutPoseAnalyzer(
        exercise: WorkoutExercise.runningInPlace,
        movementType: WorkoutMovementType.continuous,
      );
      final rope = WorkoutPoseAnalyzer(
        exercise: WorkoutExercise.jumpRope,
        movementType: WorkoutMovementType.continuous,
      );

      frame(running, _highKneesNeutral, 0);
      expect(frame(running, _leftKneeRaised, 1).exerciseActive, isTrue);
      frame(rope, _highKneesNeutral, 0);
      expect(frame(rope, _jumpedPose, 1).exerciseActive, isTrue);
    },
  );
}

WorkoutPoseAnalyzer _analyzer(WorkoutExercise exercise) {
  return WorkoutPoseAnalyzer(
    exercise: exercise,
    movementType: WorkoutMovementType.repetitions,
  );
}

Map<PoseLandmarkType, Offset> _bilateralLower({
  required Offset leftHip,
  required Offset leftKnee,
  required Offset leftAnkle,
  required Offset rightHip,
  required Offset rightKnee,
  required Offset rightAnkle,
}) {
  return {
    PoseLandmarkType.leftShoulder: const Offset(.40, .20),
    PoseLandmarkType.rightShoulder: const Offset(.60, .20),
    PoseLandmarkType.leftHip: leftHip,
    PoseLandmarkType.rightHip: rightHip,
    PoseLandmarkType.leftKnee: leftKnee,
    PoseLandmarkType.rightKnee: rightKnee,
    PoseLandmarkType.leftAnkle: leftAnkle,
    PoseLandmarkType.rightAnkle: rightAnkle,
  };
}

final _standingSquat = _bilateralLower(
  leftHip: const Offset(.43, .45),
  leftKnee: const Offset(.43, .68),
  leftAnkle: const Offset(.43, .89),
  rightHip: const Offset(.57, .45),
  rightKnee: const Offset(.57, .68),
  rightAnkle: const Offset(.57, .89),
);

final _bottomSquat = _bilateralLower(
  leftHip: const Offset(.32, .58),
  leftKnee: const Offset(.46, .66),
  leftAnkle: const Offset(.40, .86),
  rightHip: const Offset(.68, .58),
  rightKnee: const Offset(.54, .66),
  rightAnkle: const Offset(.60, .86),
);

final _shallowSquat = _bilateralLower(
  leftHip: const Offset(.39, .49),
  leftKnee: const Offset(.45, .68),
  leftAnkle: const Offset(.43, .89),
  rightHip: const Offset(.61, .49),
  rightKnee: const Offset(.55, .68),
  rightAnkle: const Offset(.57, .89),
);

final _almostStandingSquat = _bilateralLower(
  leftHip: const Offset(.41, .46),
  leftKnee: const Offset(.44, .68),
  leftAnkle: const Offset(.43, .89),
  rightHip: const Offset(.59, .46),
  rightKnee: const Offset(.56, .68),
  rightAnkle: const Offset(.57, .89),
);

const _pushUpTop = {
  PoseLandmarkType.leftShoulder: Offset(.18, .42),
  PoseLandmarkType.rightShoulder: Offset(.18, .48),
  PoseLandmarkType.leftElbow: Offset(.38, .42),
  PoseLandmarkType.rightElbow: Offset(.38, .48),
  PoseLandmarkType.leftWrist: Offset(.58, .42),
  PoseLandmarkType.rightWrist: Offset(.58, .48),
  PoseLandmarkType.leftHip: Offset(.56, .43),
  PoseLandmarkType.rightHip: Offset(.56, .49),
  PoseLandmarkType.leftKnee: Offset(.78, .44),
  PoseLandmarkType.rightKnee: Offset(.78, .50),
};

const _pushUpBottom = {
  PoseLandmarkType.leftShoulder: Offset(.18, .38),
  PoseLandmarkType.rightShoulder: Offset(.18, .44),
  PoseLandmarkType.leftElbow: Offset(.38, .58),
  PoseLandmarkType.rightElbow: Offset(.38, .64),
  PoseLandmarkType.leftWrist: Offset(.58, .38),
  PoseLandmarkType.rightWrist: Offset(.58, .44),
  PoseLandmarkType.leftHip: Offset(.56, .41),
  PoseLandmarkType.rightHip: Offset(.56, .47),
  PoseLandmarkType.leftKnee: Offset(.78, .42),
  PoseLandmarkType.rightKnee: Offset(.78, .48),
};

const _verticalPushUpTop = {
  PoseLandmarkType.leftShoulder: Offset(.42, .20),
  PoseLandmarkType.rightShoulder: Offset(.58, .20),
  PoseLandmarkType.leftElbow: Offset(.42, .35),
  PoseLandmarkType.rightElbow: Offset(.58, .35),
  PoseLandmarkType.leftWrist: Offset(.42, .50),
  PoseLandmarkType.rightWrist: Offset(.58, .50),
  PoseLandmarkType.leftHip: Offset(.43, .56),
  PoseLandmarkType.rightHip: Offset(.57, .56),
  PoseLandmarkType.leftKnee: Offset(.44, .80),
  PoseLandmarkType.rightKnee: Offset(.56, .80),
};

final _verticalArmBend = {
  ..._verticalPushUpTop,
  PoseLandmarkType.leftElbow: Offset(.32, .35),
  PoseLandmarkType.rightElbow: Offset(.68, .35),
};

final _bottomJitter = {
  ..._bottomSquat,
  PoseLandmarkType.leftHip: const Offset(.33, .58),
  PoseLandmarkType.rightHip: const Offset(.67, .58),
};

Map<PoseLandmarkType, Offset> _jumpingJackPose({
  required double kneeSpread,
  required bool armsOpen,
  double bounce = 0,
}) {
  const centerX = .50;
  return {
    PoseLandmarkType.leftShoulder: Offset(.42, .30 - bounce),
    PoseLandmarkType.rightShoulder: Offset(.58, .30 - bounce),
    PoseLandmarkType.leftWrist: armsOpen
        ? Offset(.34, .22 - bounce)
        : Offset(.39, .58 - bounce),
    PoseLandmarkType.rightWrist: armsOpen
        ? Offset(.66, .22 - bounce)
        : Offset(.61, .58 - bounce),
    PoseLandmarkType.leftHip: Offset(.44, .57 - bounce),
    PoseLandmarkType.rightHip: Offset(.56, .57 - bounce),
    PoseLandmarkType.leftKnee: Offset(centerX - kneeSpread / 2, .80 - bounce),
    PoseLandmarkType.rightKnee: Offset(centerX + kneeSpread / 2, .80 - bounce),
  };
}

Map<PoseLandmarkType, Offset> _scaledPose(
  Map<PoseLandmarkType, Offset> pose,
  double scale,
) {
  const center = Offset(.5, .5);
  return {
    for (final entry in pose.entries)
      entry.key: center + (entry.value - center) * scale,
  };
}

final _jackClosed = _jumpingJackPose(kneeSpread: .12, armsOpen: false);
final _jackOpen = _jumpingJackPose(
  kneeSpread: .18,
  armsOpen: true,
  bounce: .008,
);
final _jackNarrowOpen = _jumpingJackPose(
  kneeSpread: .1263,
  armsOpen: true,
  bounce: .008,
);
final _jackWideOpen = _jumpingJackPose(
  kneeSpread: .36,
  armsOpen: true,
  bounce: .012,
);
final _jackJitterArmsUp = _jumpingJackPose(
  kneeSpread: .122,
  armsOpen: true,
  bounce: .002,
);
final _jackArmsOnly = _jumpingJackPose(
  kneeSpread: .12,
  armsOpen: true,
  bounce: .008,
);
final _jackLegsOnly = _jumpingJackPose(
  kneeSpread: .1263,
  armsOpen: false,
  bounce: .008,
);
final _jackOpenMissingRightKnee = Map<PoseLandmarkType, Offset>.of(
  _jackNarrowOpen,
)..remove(PoseLandmarkType.rightKnee);

final _highKneesNeutral = _bilateralLower(
  leftHip: const Offset(.44, .50),
  leftKnee: const Offset(.44, .75),
  leftAnkle: const Offset(.44, .92),
  rightHip: const Offset(.56, .50),
  rightKnee: const Offset(.56, .75),
  rightAnkle: const Offset(.56, .92),
);

final _leftKneeRaised = _bilateralLower(
  leftHip: const Offset(.44, .50),
  leftKnee: const Offset(.44, .53),
  leftAnkle: const Offset(.40, .70),
  rightHip: const Offset(.56, .50),
  rightKnee: const Offset(.56, .75),
  rightAnkle: const Offset(.56, .92),
);

final _lungeBottom = _bilateralLower(
  leftHip: const Offset(.34, .58),
  leftKnee: const Offset(.48, .62),
  leftAnkle: const Offset(.48, .82),
  rightHip: const Offset(.58, .48),
  rightKnee: const Offset(.66, .67),
  rightAnkle: const Offset(.73, .86),
);

const _sitUpReclined = {
  PoseLandmarkType.leftShoulder: Offset(.18, .44),
  PoseLandmarkType.rightShoulder: Offset(.18, .54),
  PoseLandmarkType.leftHip: Offset(.43, .44),
  PoseLandmarkType.rightHip: Offset(.43, .54),
  PoseLandmarkType.leftKnee: Offset(.70, .44),
  PoseLandmarkType.rightKnee: Offset(.70, .54),
};

const _sitUpUpright = {
  PoseLandmarkType.leftShoulder: Offset(.43, .18),
  PoseLandmarkType.rightShoulder: Offset(.49, .18),
  PoseLandmarkType.leftHip: Offset(.43, .48),
  PoseLandmarkType.rightHip: Offset(.49, .48),
  PoseLandmarkType.leftKnee: Offset(.70, .48),
  PoseLandmarkType.rightKnee: Offset(.70, .48),
};

const _sitUpKneesOnly = {
  PoseLandmarkType.leftShoulder: Offset(.18, .44),
  PoseLandmarkType.rightShoulder: Offset(.18, .54),
  PoseLandmarkType.leftHip: Offset(.43, .44),
  PoseLandmarkType.rightHip: Offset(.43, .54),
  PoseLandmarkType.leftKnee: Offset(.43, .20),
  PoseLandmarkType.rightKnee: Offset(.43, .30),
};

const _plank = {
  PoseLandmarkType.leftShoulder: Offset(.18, .40),
  PoseLandmarkType.rightShoulder: Offset(.18, .46),
  PoseLandmarkType.leftHip: Offset(.48, .41),
  PoseLandmarkType.rightHip: Offset(.48, .47),
  PoseLandmarkType.leftKnee: Offset(.68, .42),
  PoseLandmarkType.rightKnee: Offset(.68, .48),
  PoseLandmarkType.leftAnkle: Offset(.86, .43),
  PoseLandmarkType.rightAnkle: Offset(.86, .49),
};

final _mountainClimberNeutral = {
  ..._plank,
  PoseLandmarkType.leftKnee: Offset(.74, .42),
  PoseLandmarkType.rightKnee: Offset(.74, .48),
};

final _mountainClimberDrive = {
  ..._plank,
  PoseLandmarkType.leftKnee: Offset(.34, .42),
  PoseLandmarkType.rightKnee: Offset(.74, .48),
};

const _wallSit = {
  PoseLandmarkType.leftShoulder: Offset(.39, .20),
  PoseLandmarkType.rightShoulder: Offset(.49, .20),
  PoseLandmarkType.leftHip: Offset(.39, .50),
  PoseLandmarkType.rightHip: Offset(.49, .50),
  PoseLandmarkType.leftKnee: Offset(.56, .50),
  PoseLandmarkType.rightKnee: Offset(.66, .50),
  PoseLandmarkType.leftAnkle: Offset(.56, .76),
  PoseLandmarkType.rightAnkle: Offset(.66, .76),
};

final _jumpedPose = {
  for (final entry in _highKneesNeutral.entries)
    entry.key: Offset(entry.value.dx, entry.value.dy - .035),
};

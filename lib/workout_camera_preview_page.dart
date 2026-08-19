import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'new_task_page.dart';
import 'workout_pose_analyzer.dart';

class WorkoutCameraPreviewPage extends StatefulWidget {
  const WorkoutCameraPreviewPage({
    super.key,
    required this.isDarkMode,
    required this.exercise,
    required this.movementType,
    required this.sensitivity,
    required this.initialOrientation,
  });

  final bool isDarkMode;
  final WorkoutExercise exercise;
  final WorkoutMovementType movementType;
  final double sensitivity;
  final WorkoutCameraOrientation initialOrientation;

  @override
  State<WorkoutCameraPreviewPage> createState() =>
      _WorkoutCameraPreviewPageState();
}

class _WorkoutCameraPreviewPageState extends State<WorkoutCameraPreviewPage>
    with WidgetsBindingObserver {
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFFF101C);
  static const _analysisInterval = Duration(milliseconds: 100);

late WorkoutCameraOrientation _selectedOrientation;
  late final WorkoutPoseAnalyzer _analyzer;
  PoseDetector? _detector;
  CameraController? _controller;
  CameraDescription? _camera;
  Future<void>? _analysis;
  Future<void>? _cameraStart;
  Future<void>? _shutdown;

  bool _processing = false;
  bool _closing = false;
  bool _cameraWanted = false;
  bool _initializing = true;
  int _epoch = 0;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  WorkoutPoseObservation? _observation;
  String _status = 'Step back so TaskProof can see you';
  String? _error;

    @override
    void initState() {
      super.initState();
      WidgetsBinding.instance.addObserver(this);

      _selectedOrientation = widget.initialOrientation;

      _analyzer = WorkoutPoseAnalyzer(
      exercise: widget.exercise,
      movementType: widget.movementType,
      sensitivity: widget.sensitivity,
    );
      _detector = PoseDetector(
      options: PoseDetectorOptions(
        // Match live verification: Push-ups use
        // the higher-precision model.
        // Every other exercise remains on base.
        model:
            widget.exercise ==
                WorkoutExercise.pushUps
            ? PoseDetectionModel.accurate
            : PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closing = true;
    unawaited(_disposeResources());
    super.dispose();
  }

Future<void> _changeOrientation(
  WorkoutCameraOrientation orientation,
) async {
  if (_selectedOrientation == orientation) {
    return;
  }

  setState(() {
    _selectedOrientation = orientation;
  });

  if (orientation == WorkoutCameraOrientation.landscape) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  await _stopCamera();

  if (!_closing) {
    await _startCamera();
  }
}

Widget _buildOrientationSelector() {
  final dark = widget.isDarkMode;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Camera Orientation',
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF191B20),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),

      Row(
        children: [
          Expanded(
            child: _orientationButton(
              label: 'Portrait',
              icon: Icons.stay_current_portrait_rounded,
              orientation: WorkoutCameraOrientation.portrait,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _orientationButton(
              label: 'Landscape',
              icon: Icons.stay_current_landscape_rounded,
              orientation: WorkoutCameraOrientation.landscape,
            ),
          ),
        ],
      ),

      if (widget.exercise == WorkoutExercise.pushUps) ...[
        const SizedBox(height: 8),
        const Text(
          'Landscape is recommended for Push-ups so more of your body stays in frame.',
          style: TextStyle(
            color: Color(0xFF8B8E97),
            fontSize: 12,
          ),
        ),
      ],
    ],
  );
}

Widget _orientationButton({
  required String label,
  required IconData icon,
  required WorkoutCameraOrientation orientation,
}) {
  final selected = _selectedOrientation == orientation;
  final dark = widget.isDarkMode;

  return InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => _changeOrientation(orientation),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 52,
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFFF111C).withValues(alpha: 0.10)
            : dark
                ? const Color(0xFF18191D)
                : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? const Color(0xFFFF111C)
              : dark
                  ? const Color(0xFF303238)
                  : const Color(0xFFD7D9DF),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: selected
                ? const Color(0xFFFF111C)
                : dark
                    ? Colors.white70
                    : const Color(0xFF555860),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFFF111C)
                  : dark
                      ? Colors.white
                      : const Color(0xFF24262B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stopCamera());
    } else if (state == AppLifecycleState.resumed) {
      _analyzer.reset();
      unawaited(_startCamera());
    }
  }

  Future<void> _startCamera() {
    final existing = _cameraStart;
    if (existing != null) return existing;
    late final Future<void> future;
    future = _performCameraStart();
    _cameraStart = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_cameraStart, future)) _cameraStart = null;
        if (!_closing && _cameraWanted && _controller == null) {
          unawaited(_startCamera());
        }
      }),
    );
    return future;
  }

  Future<void> _performCameraStart() async {
    if (_closing || _controller != null) return;
    if (!MlKitCameraImageConverter.supported) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Workout preview requires Android or iPhone.';
        });
      }
      return;
    }
    _cameraWanted = true;
    _initializing = true;
    _error = null;
    final epoch = ++_epoch;
    CameraController? local;
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
      if (!_canUse(epoch)) {
        await _disposeController(local);
        return;
      }
      try {
      await local.lockCaptureOrientation(
        _selectedOrientation == WorkoutCameraOrientation.landscape
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.portraitUp,
      );
    } catch (_) {}
      _camera = camera;
      _controller = local;
      await local.startImageStream(_onImage);
      if (!_canUse(epoch)) {
        if (identical(_controller, local)) _controller = null;
        await _disposeController(local);
        return;
      }
      _initializing = false;
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Workout camera preview error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _cameraWanted = false;
      if (local != null) await _disposeController(local);
      if (mounted && !_closing) {
        setState(() {
          _initializing = false;
          _error = error is CameraException
              ? 'Camera unavailable: ${error.description ?? error.code}'
              : 'Could not start the camera.';
        });
      }
    }
  }

  bool _canUse(int epoch) =>
      mounted && !_closing && _cameraWanted && epoch == _epoch;

  Future<void> _stopCamera() async {
    _cameraWanted = false;
    _epoch++;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
    }
    final analysis = _analysis;
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

  Future<void> _disposeController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    final analysis = _analysis;
    if (analysis != null) {
      try {
        await analysis;
      } catch (_) {}
    }
    try {
      await controller.dispose();
    } catch (_) {}
  }

  Future<void> _disposeResources() {
    return _shutdown ??= _performDispose();
  }

  Future<void> _performDispose() async {
    await _stopCamera();
    final detector = _detector;
    _detector = null;
    if (detector != null) {
      try {
        await detector.close();
      } catch (_) {}
    }
  }

  void _onImage(CameraImage image) {
    if (_processing || _closing || !_cameraWanted) return;
    final controller = _controller;
    final camera = _camera;
    final detector = _detector;
    if (controller == null || camera == null || detector == null) return;
    final now = DateTime.now();
    if (now.difference(_lastAnalysis) < _analysisInterval) return;
    final frame = MlKitCameraImageConverter.convert(
      image: image,
      camera: camera,
      deviceOrientation: controller.value.deviceOrientation,
    );
    if (frame == null) return;
    _lastAnalysis = now;
    _processing = true;
    late final Future<void> analysis;
    analysis = _process(detector, frame, now).whenComplete(() {
      if (identical(_analysis, analysis)) _analysis = null;
      _processing = false;
    });
    _analysis = analysis;
  }

  Future<void> _process(
    PoseDetector detector,
    MlKitCameraFrame frame,
    DateTime timestamp,
  ) async {
    try {
      final poses = await detector.processImage(frame.inputImage);
      if (_closing || !_cameraWanted) return;
      final observation = _analyzer.analyzePoses(
        poses: poses,
        imageSize: frame.imageSize,
        timestamp: timestamp,
      );
      final status = workoutCameraGuidance(widget.exercise, observation);
      if (!mounted ||
          (status == _status &&
              observation.coverage == _observation?.coverage)) {
        _observation = observation;
        return;
      }
      setState(() {
        _observation = observation;
        _status = status;
      });
    } catch (error, stackTrace) {
      debugPrint('Workout preview pose error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Color get _accent {
    final observation = _observation;
    if (observation == null || !observation.personPresent) return Colors.white;
    if (observation.tooClose ||
        observation.coverage == WorkoutBodyCoverage.insufficient) {
      return _red;
    }
    return observation.cameraReady ? _green : Colors.white;
  }

  @override
Widget build(BuildContext context) {
  final background = widget.isDarkMode
      ? const Color(0xFF090B0E)
      : const Color(0xFFF3F4F6);

  final foreground = widget.isDarkMode
      ? Colors.white
      : const Color(0xFF111318);

  return Scaffold(
    backgroundColor: background,
    appBar: AppBar(
      backgroundColor: background,
      foregroundColor: foreground,
      title: const Text('Workout Camera'),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
        child: Column(
          children: [
            _buildOrientationSelector(),
            const SizedBox(height: 16),

            Text(
              workoutExerciseLabel(widget.exercise),
              style: TextStyle(
                color: foreground,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
              const SizedBox(height: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _cameraBody(),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _PreviewFramePainter(color: _accent),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xDD111318),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _accent),
                          ),
                          child: Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This preview checks camera position only. It does not start or count the workout.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF777A84), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _cameraBody() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final size = controller.value.previewSize;
      if (size != null) {
        return RepaintBoundary(
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.height,
                height: size.width,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      }
    }
    return ColoredBox(
      color: const Color(0xFF111318),
      child: Center(
        child: _initializing
            ? const CircularProgressIndicator(color: Colors.white)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'Camera unavailable',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
      ),
    );
  }
}

class _PreviewFramePainter extends CustomPainter {
  const _PreviewFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const inset = 18.0;
    final length = (size.shortestSide * .12).clamp(28.0, 48.0);
    final l = inset;
    final t = inset;
    final r = size.width - inset;
    final b = size.height - inset;
    canvas
      ..drawLine(Offset(l, t + length), Offset(l, t), paint)
      ..drawLine(Offset(l, t), Offset(l + length, t), paint)
      ..drawLine(Offset(r - length, t), Offset(r, t), paint)
      ..drawLine(Offset(r, t), Offset(r, t + length), paint)
      ..drawLine(Offset(l, b - length), Offset(l, b), paint)
      ..drawLine(Offset(l, b), Offset(l + length, b), paint)
      ..drawLine(Offset(r - length, b), Offset(r, b), paint)
      ..drawLine(Offset(r, b), Offset(r, b - length), paint);
  }

  @override
  bool shouldRepaint(covariant _PreviewFramePainter oldDelegate) =>
      oldDelegate.color != color;
}

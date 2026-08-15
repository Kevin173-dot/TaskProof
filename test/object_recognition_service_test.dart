import 'package:camera/camera.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:taskguard/object_recognition_service.dart';
import 'package:taskguard/object_scan_repository.dart';

const _profilePath = 'memory://object/view.png';
const _camera = CameraDescription(
  name: 'test-camera',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('ObjectRecognitionService profile loading', () {
    test(
      'empty requirements are ready without reading the repository',
      () async {
        final repository = _FakeObjectScanRepository();
        final service = ObjectRecognitionService(repository: repository);
        addTearDown(service.dispose);

        final result = await service.loadRequiredObjects(const []);

        expect(service.isReady, isTrue);
        expect(result.objects, isEmpty);
        expect(result.unavailableIds, isEmpty);
        expect(service.requiredObjects, isEmpty);
        expect(repository.loadAllCalls, 0);
      },
    );

    test('reports requested IDs that have no usable saved profile', () async {
      const readable = SavedObjectScan(
        id: 'readable',
        name: 'Readable tool',
        scanPath: 'memory://object',
        samplePaths: [_profilePath],
      );
      const unreadable = SavedObjectScan(
        id: 'unreadable',
        name: 'Unreadable tool',
        scanPath: 'memory://missing',
        samplePaths: ['memory://missing/view.png'],
      );
      final repository = _FakeObjectScanRepository(
        scans: const [readable, unreadable],
        images: {_profilePath: _encodedProfileImage()},
      );
      final service = ObjectRecognitionService(repository: repository);
      addTearDown(service.dispose);

      final result = await service.loadRequiredObjects(const [
        'readable',
        'unreadable',
        'deleted',
      ]);

      expect(result.objects.map((object) => object.id), ['readable']);
      expect(result.unavailableIds, ['unreadable', 'deleted']);
      expect(service.unavailableIds, ['unreadable', 'deleted']);
      expect(repository.loadAllCalls, 1);
      expect(repository.readImageCalls, 2);
    });
  });

  group('ObjectRecognitionService BGRA matching', () {
    test('exact rotated saved view requires two confirmed hits', () async {
      final fixture = await _recognitionFixture();
      addTearDown(fixture.service.dispose);

      final first = await fixture.service.analyzeFrame(
        fixture.matchingFrame,
        camera: _camera,
        deviceOrientation: DeviceOrientation.portraitUp,
      );
      final second = await fixture.service.analyzeFrame(
        fixture.matchingFrame,
        camera: _camera,
        deviceOrientation: DeviceOrientation.portraitUp,
      );

      expect(first.single.confidence, greaterThanOrEqualTo(0.98));
      expect(first.single.isMatch, isFalse);
      expect(second.single.confidence, greaterThanOrEqualTo(0.98));
      expect(second.single.isMatch, isTrue);
    });

    test('clearly different frame does not match a saved profile', () async {
      final fixture = await _recognitionFixture();
      addTearDown(fixture.service.dispose);
      final different = _bgraFrame(
        _solidImage(fixture.image.width, fixture.image.height),
        rotationDegrees: _camera.sensorOrientation,
      );

      final first = await fixture.service.analyzeFrame(
        different,
        camera: _camera,
        deviceOrientation: DeviceOrientation.portraitUp,
      );
      final second = await fixture.service.analyzeFrame(
        different,
        camera: _camera,
        deviceOrientation: DeviceOrientation.portraitUp,
      );

      expect(first.single.isMatch, isFalse);
      expect(second.single.isMatch, isFalse);
      expect(second.single.confidence, lessThan(0.50));
    });

    test(
      'matches a small localized object against a different background',
      () async {
        final profile = _profileImage();
        const scan = SavedObjectScan(
          id: 'localized-tool',
          name: 'Localized tool',
          scanPath: 'memory://localized',
          samplePaths: [_profilePath],
        );
        final service = ObjectRecognitionService(
          repository: _FakeObjectScanRepository(
            scans: const [scan],
            images: {_profilePath: Uint8List.fromList(img.encodePng(profile))},
          ),
          analysisInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        await service.loadRequiredObjects(const ['localized-tool']);

        final scene = _texturedScene(240, 180);
        const left = 132;
        const top = 76;
        _pasteImage(scene, profile, left: left, top: top);
        const bounds = Rect.fromLTWH(132.0, 76.0, 72, 56);
        const camera = CameraDescription(
          name: 'upright-test-camera',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 0,
        );
        final frame = _bgraFrame(scene, rotationDegrees: 0);

        final first = await service.analyzeFrame(
          frame,
          camera: camera,
          deviceOrientation: DeviceOrientation.portraitUp,
          detectedBounds: const [bounds],
        );
        final second = await service.analyzeFrame(
          frame,
          camera: camera,
          deviceOrientation: DeviceOrientation.portraitUp,
          detectedBounds: const [bounds],
        );

        expect(first.single.confidence, greaterThanOrEqualTo(0.80));
        expect(first.single.isMatch, isFalse);
        expect(second.single.isMatch, isTrue);
      },
    );

    test(
      'resetTemporalState clears partial and completed confirmation',
      () async {
        final fixture = await _recognitionFixture();
        addTearDown(fixture.service.dispose);

        final first = await fixture.service.analyzeFrame(
          fixture.matchingFrame,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );
        expect(first.single.isMatch, isFalse);

        fixture.service.resetTemporalState();
        final afterPartialReset = await fixture.service.analyzeFrame(
          fixture.matchingFrame,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );
        final confirmed = await fixture.service.analyzeFrame(
          fixture.matchingFrame,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );
        expect(afterPartialReset.single.isMatch, isFalse);
        expect(confirmed.single.isMatch, isTrue);

        fixture.service.resetTemporalState();
        expect(fixture.service.lastResults.single.isMatch, isFalse);

        final afterConfirmedReset = await fixture.service.analyzeFrame(
          fixture.matchingFrame,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );
        expect(afterConfirmedReset.single.isMatch, isFalse);
      },
    );
  });

  group('ObjectRecognitionService NV21 matching', () {
    test(
      'matches a rotated padded one-plane Android frame after two hits',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final image = _nv21ProfileImage();
        const scan = SavedObjectScan(
          id: 'tool',
          name: 'Patterned tool',
          scanPath: 'memory://object',
          samplePaths: [_profilePath],
        );
        final service = ObjectRecognitionService(
          repository: _FakeObjectScanRepository(
            scans: const [scan],
            images: {_profilePath: Uint8List.fromList(img.encodePng(image))},
          ),
          analysisInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        await service.loadRequiredObjects(const ['tool']);

        final matching = _nv21Frame(
          image,
          rotationDegrees: _camera.sensorOrientation,
        );
        final first = await service.analyzeFrame(
          matching,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );
        final second = await service.analyzeFrame(
          matching,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );

        expect(first.single.confidence, greaterThanOrEqualTo(0.98));
        expect(first.single.isMatch, isFalse);
        expect(second.single.confidence, greaterThanOrEqualTo(0.98));
        expect(second.single.isMatch, isTrue);

        service.resetTemporalState();
        final different = _nv21Frame(
          _solidImage(image.width, image.height),
          rotationDegrees: _camera.sensorOrientation,
        );
        final differentFirst = await service.analyzeFrame(
          different,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );
        final differentSecond = await service.analyzeFrame(
          different,
          camera: _camera,
          deviceOrientation: DeviceOrientation.portraitUp,
        );

        expect(differentFirst.single.isMatch, isFalse);
        expect(differentSecond.single.isMatch, isFalse);
        expect(differentSecond.single.confidence, lessThan(0.50));
      },
    );
  });
}

Future<_RecognitionFixture> _recognitionFixture() async {
  final image = _profileImage();
  const scan = SavedObjectScan(
    id: 'tool',
    name: 'Striped tool',
    scanPath: 'memory://object',
    samplePaths: [_profilePath],
  );
  final service = ObjectRecognitionService(
    repository: _FakeObjectScanRepository(
      scans: const [scan],
      images: {_profilePath: Uint8List.fromList(img.encodePng(image))},
    ),
    analysisInterval: Duration.zero,
  );
  await service.loadRequiredObjects(const ['tool']);
  return _RecognitionFixture(
    service: service,
    image: image,
    matchingFrame: _bgraFrame(
      image,
      rotationDegrees: _camera.sensorOrientation,
    ),
  );
}

class _RecognitionFixture {
  const _RecognitionFixture({
    required this.service,
    required this.image,
    required this.matchingFrame,
  });

  final ObjectRecognitionService service;
  final img.Image image;
  final CameraImage matchingFrame;
}

Uint8List _encodedProfileImage() {
  return Uint8List.fromList(img.encodePng(_profileImage()));
}

img.Image _profileImage() {
  const width = 72;
  const height = 56;
  final image = img.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final tile = ((x ~/ 7) + (y ~/ 6)).isEven;
      final red = tile ? 218 : 24 + (y * 3) % 96;
      final green = tile ? 38 + (x * 2) % 80 : 178;
      final blue = tile ? 48 : 222 - (x + y) % 72;
      image.setPixelRgb(x, y, red, green, blue);
    }
  }

  return image;
}

img.Image _solidImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, 4, 8, 12);
    }
  }
  return image;
}

img.Image _texturedScene(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        18 + (x * 3 + y) % 80,
        28 + (x + y * 2) % 70,
        42 + (x * 2 + y * 3) % 90,
      );
    }
  }
  return image;
}

void _pasteImage(
  img.Image destination,
  img.Image source, {
  required int left,
  required int top,
}) {
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      destination.setPixel(left + x, top + y, source.getPixel(x, y));
    }
  }
}

img.Image _nv21ProfileImage() {
  const width = 72;
  const height = 56;
  final image = img.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final checker = ((x ~/ 6) + (y ~/ 7)).isEven;
      final diagonal = (x * 3 + y * 5) % 72;
      final value = checker ? 176 + diagonal ~/ 2 : 32 + diagonal;
      image.setPixelRgb(x, y, value, value, value);
    }
  }

  return image;
}

CameraImage _bgraFrame(img.Image oriented, {required int rotationDegrees}) {
  final swapsAxes = rotationDegrees == 90 || rotationDegrees == 270;
  final sourceWidth = swapsAxes ? oriented.height : oriented.width;
  final sourceHeight = swapsAxes ? oriented.width : oriented.height;
  final rowStride = sourceWidth * 4 + 12;
  final bytes = Uint8List(rowStride * sourceHeight);

  for (var y = 0; y < oriented.height; y++) {
    for (var x = 0; x < oriented.width; x++) {
      final (sourceX, sourceY) = switch (rotationDegrees) {
        0 => (x, y),
        90 => (y, sourceHeight - 1 - x),
        180 => (sourceWidth - 1 - x, sourceHeight - 1 - y),
        270 => (sourceWidth - 1 - y, x),
        _ => throw ArgumentError.value(rotationDegrees, 'rotationDegrees'),
      };
      final pixel = oriented.getPixel(x, y);
      final index = sourceY * rowStride + sourceX * 4;
      bytes[index] = (pixel.bNormalized * 255).round();
      bytes[index + 1] = (pixel.gNormalized * 255).round();
      bytes[index + 2] = (pixel.rNormalized * 255).round();
      bytes[index + 3] = 255;
    }
  }

  // This public legacy constructor is the only CameraImage test constructor
  // that does not require importing camera's transitive platform package.
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData(<dynamic, dynamic>{
    'format': 1111970369, // kCVPixelFormatType_32BGRA
    'height': sourceHeight,
    'width': sourceWidth,
    'planes': <dynamic>[
      <dynamic, dynamic>{
        'bytes': bytes,
        'bytesPerPixel': 4,
        'bytesPerRow': rowStride,
        'height': sourceHeight,
        'width': sourceWidth,
      },
    ],
  });
}

CameraImage _nv21Frame(img.Image oriented, {required int rotationDegrees}) {
  final swapsAxes = rotationDegrees == 90 || rotationDegrees == 270;
  final sourceWidth = swapsAxes ? oriented.height : oriented.width;
  final sourceHeight = swapsAxes ? oriented.width : oriented.height;
  final yRowStride = sourceWidth + 8;
  final uvRowStride = sourceWidth + 12;
  final yPlaneLength = yRowStride * sourceHeight;
  final chromaRows = (sourceHeight + 1) ~/ 2;
  final bytes = Uint8List(yPlaneLength + uvRowStride * chromaRows);

  for (var y = 0; y < oriented.height; y++) {
    for (var x = 0; x < oriented.width; x++) {
      final (sourceX, sourceY) = switch (rotationDegrees) {
        0 => (x, y),
        90 => (y, sourceHeight - 1 - x),
        180 => (sourceWidth - 1 - x, sourceHeight - 1 - y),
        270 => (sourceWidth - 1 - y, x),
        _ => throw ArgumentError.value(rotationDegrees, 'rotationDegrees'),
      };
      final luminance = oriented.getPixel(x, y).luminanceNormalized;
      final gray = (luminance * 255).round();
      final videoRangeY = ((220 * gray + 128) >> 8) + 16;
      bytes[sourceY * yRowStride + sourceX] = videoRangeY.clamp(0, 255);
    }
  }

  // Neutral chroma keeps the patterned test profile grayscale. Padding is
  // intentionally present in both Y and interleaved VU rows.
  for (var y = 0; y < chromaRows; y++) {
    for (var x = 0; x < sourceWidth; x += 2) {
      final index = yPlaneLength + y * uvRowStride + x;
      bytes[index] = 128;
      bytes[index + 1] = 128;
    }
  }

  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData(<dynamic, dynamic>{
    'format': 17, // android.graphics.ImageFormat.NV21
    'height': sourceHeight,
    'width': sourceWidth,
    'planes': <dynamic>[
      <dynamic, dynamic>{
        'bytes': bytes,
        'bytesPerPixel': 1,
        'bytesPerRow': yRowStride,
        'height': sourceHeight,
        'width': sourceWidth,
      },
    ],
  });
}

class _FakeObjectScanRepository implements ObjectScanRepository {
  _FakeObjectScanRepository({this.scans = const [], this.images = const {}});

  final List<SavedObjectScan> scans;
  final Map<String, Uint8List> images;
  int loadAllCalls = 0;
  int readImageCalls = 0;

  @override
  Future<List<SavedObjectScan>> loadAll() async {
    loadAllCalls++;
    return scans;
  }

  @override
  Future<Uint8List?> readImage(String path) async {
    readImageCalls++;
    return images[path];
  }

  @override
  String createId() => throw UnimplementedError();

  @override
  Future<String> createScanDirectory(String scanId) =>
      throw UnimplementedError();

  @override
  Future<void> delete(SavedObjectScan scan) => throw UnimplementedError();

  @override
  Future<void> discardScan(String directory) => throw UnimplementedError();

  @override
  Future<SavedObjectScan?> findById(String id) => throw UnimplementedError();

  @override
  Future<void> save(SavedObjectScan scan) => throw UnimplementedError();

  @override
  Future<String> saveSample({
    required String scanId,
    required int index,
    required Uint8List bytes,
  }) => throw UnimplementedError();
}

// The JSON lines printed here are the on-device benchmark output collected by
// the host script; this file is not part of the shipped app.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:awake/data/coco_detector.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a real Android device/emulator. The two fixture images are bundled
/// as test-only assets so a reinstall cannot wipe them mid-run:
///   integration_test/fixtures/awake_ssd.jpg    300x300 cat photo
///   integration_test/fixtures/awake_yolo.jpg   416x416 appliance photo
///
/// Pass `--dart-define=PROFILE=name` to label the device profile in the JSON.
/// Remove the fixture asset entry from pubspec.yaml before shipping a release
/// build; these images are not part of the app.
///
/// The test loads both shipped models, runs a warm inference, then times 20
/// frames and prints one JSON line per model. It is intentionally kept out of
/// `flutter test` (which runs on the host) because only the Android build has
/// the TFLite native library.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('both on-device models load and predict', (tester) async {
    const profile = String.fromEnvironment(
      'PROFILE',
      defaultValue: 'default-1080x2400-420',
    );

    final ssd = await _benchmark(
      ModelChoice.ssdMobileNet,
      'integration_test/fixtures/awake_ssd.jpg',
    );
    expect(
      ssd.labels,
      contains('cat'),
      reason: 'SSD should recognise the cat test image',
    );
    print(
      'ONDEVICE ${jsonEncode({'profile': profile, ...ssd.toJson()})}',
    );

    final yolo = await _benchmark(
      ModelChoice.yolo11nTuned,
      'integration_test/fixtures/awake_yolo.jpg',
    );
    expect(
      yolo.labels,
      anyOf(contains('refrigerator'), contains('oven')),
      reason: 'YOLO should recognise the kitchen appliances',
    );
    print(
      'ONDEVICE ${jsonEncode({'profile': profile, ...yolo.toJson()})}',
    );
  });
}

const int _iterations = int.fromEnvironment(
  'BENCH_ITERS',
  defaultValue: 20,
);

class _BenchmarkResult {
  const _BenchmarkResult({
    required this.model,
    required this.loadMs,
    required this.labels,
    required this.topScore,
    required this.meanMs,
    required this.p95Ms,
  });

  final String model;
  final int loadMs;
  final List<String> labels;
  final double topScore;
  final double meanMs;
  final double p95Ms;

  Map<String, Object> toJson() => {
    'model': model,
    'load_ms': loadMs,
    'labels': labels,
    'top_score': topScore,
    'mean_ms': meanMs,
    'p95_ms': p95Ms,
  };
}

Future<_BenchmarkResult> _benchmark(
  ModelChoice choice,
  String assetPath,
) async {
  CocoDetector.select(choice);
  final loadWatch = Stopwatch()..start();
  await CocoDetector.I.load();
  final loadMs = loadWatch.elapsedMilliseconds;

  final size = CocoDetector.I.inputSize;
  final rgb = await _loadRgb(assetPath, size);

  // Warm the interpreter and page in the image buffers.
  CocoDetector.I.detect(rgb);

  final times = <double>[];
  var detections = const <Detection>[];
  for (var i = 0; i < _iterations; i++) {
    final watch = Stopwatch()..start();
    detections = CocoDetector.I.detect(rgb);
    times.add(watch.elapsedMicroseconds / 1000.0);
  }
  times.sort();
  final mean = times.reduce((a, b) => a + b) / times.length;
  final p95 = times[(times.length * 0.95).floor().clamp(0, times.length - 1)];

  return _BenchmarkResult(
    model: choice == ModelChoice.ssdMobileNet ? 'SSD MobileNet' : 'YOLO11n tuned',
    loadMs: loadMs,
    labels: detections.map((d) => d.label).toList(growable: false),
    topScore: detections.isEmpty ? 0 : detections.first.score,
    meanMs: mean,
    p95Ms: p95,
  );
}

Future<Uint8List> _loadRgb(String assetPath, int size) async {
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: size,
    targetHeight: size,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (rgba == null) throw StateError('Could not decode $assetPath');
  final pixels = rgba.buffer.asUint8List();
  final rgb = Uint8List(size * size * 3);
  for (var i = 0, o = 0; i < pixels.length; i += 4, o += 3) {
    rgb[o] = pixels[i];
    rgb[o + 1] = pixels[i + 1];
    rgb[o + 2] = pixels[i + 2];
  }
  image.dispose();
  codec.dispose();
  return rgb;
}

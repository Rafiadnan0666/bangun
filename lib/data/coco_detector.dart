/// On-device object detector used by the scan gate.
///
/// Model: TFLite SSD MobileNet v1 trained on COCO (90 classes), quantized
/// uint8 input [1,300,300,3], float outputs boxes/classes/scores/num with 10
/// post-NMS detections (verified locally with a tensor probe).
/// All inference stays on-device.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

int _ic(int v, int lo, int hi) => math.min(hi, math.max(lo, v));

class Detection {
  const Detection({
    required this.classId,
    required this.label,
    required this.score,
    this.box = Rect.zero,
  });

  final int classId;
  final String label;
  final double score;

  /// Normalized [0..1] box on the square detector input, order (xMin, yMin,
  /// xMax, yMax) — used by the scan gate's on-screen overlay.
  final Rect box;

  @override
  String toString() => '$label ${(score * 100).round()}%';
}

/// COCO-SSD detector singleton. Call [load] once at startup so the model is
/// warm long before any alarm rings.
class CocoDetector {
  CocoDetector._();

  static final CocoDetector I = CocoDetector._();

  static const modelAsset =
      'assets/models/coco_ssd_mobilenet_v1_1.0_quant.tflite';
  static const labelsAsset = 'assets/models/labels.txt';

  static const double minScore = 0.4;

  Interpreter? _interpreter;
  List<String> _labels = const [];
  bool _loaded = false;
  Future<void>? _loading;
  Object? _loadError;

  List<List<List<double>>> _boxes = const [];
  List<List<double>> _classes = const [];
  List<List<double>> _scores = const [];
  List<double> _count = const [];
  int _inputSize = 300;
  int _maxDet = 10;
  final Map<int, Object> _outputs = {};

  bool get isReady => _loaded && _interpreter != null;

  /// The last load failure, if any. A failed load leaves [isReady] false and
  /// clears the in-flight future so [load] can be retried.
  Object? get loadError => _loadError;

  /// Loads model + labels once. Safe to call repeatedly. On failure the
  /// in-flight future is cleared so a later call can retry; the error is
  /// rethrown so the scan screen can show a retry card.
  Future<void> load() {
    if (isReady) return Future.value();
    final pending = _loading;
    if (pending != null) return pending;
    final future = _loadNow();
    _loading = future;
    return future.whenComplete(() {
      if (identical(_loading, future)) _loading = null;
    });
  }

  Future<void> _loadNow() async {
    _loadError = null;
    try {
      final raw = await rootBundle.loadString(labelsAsset);
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final options = InterpreterOptions()..threads = 4;
      final interpreter = await Interpreter.fromAsset(
        modelAsset,
        options: options,
      );

      final inShape = interpreter.getInputTensor(0).shape;
      if (inShape.length != 4 || inShape[3] != 3) {
        interpreter.close();
        throw StateError('Unexpected input shape $inShape');
      }
      _inputSize = inShape[1];

      final out = interpreter.getOutputTensors();
      _maxDet = out.length >= 2 && out[0].shape.length == 3
          ? out[0].shape[1]
          : 10;

      _boxes = [List.generate(_maxDet, (_) => List.filled(4, 0.0))];
      _classes = [List.filled(_maxDet, 0.0)];
      _scores = [List.filled(_maxDet, 0.0)];
      _count = [0.0];
      _outputs[0] = _boxes;
      _outputs[1] = _classes;
      _outputs[2] = _scores;
      _outputs[3] = _count;

      _interpreter = interpreter;
      _loaded = true;
      debugPrint(
        'CocoDetector ready: ${_labels.length} labels, '
        'input ${_inputSize}x$_inputSize, maxDet $_maxDet',
      );
    } catch (e) {
      _loadError = e;
      debugPrint('CocoDetector load failed: $e');
      rethrow;
    }
  }

  int get inputSize => _inputSize;

  /// Runs one frame. Input: tight RGB bytes (`inputSize² × 3`), raw 0..255.
  /// Returns detections above [minScore], best first.
  List<Detection> detect(Uint8List rgb) {
    final interpreter = _interpreter;
    if (interpreter == null || !_loaded) return const [];
    if (rgb.length != _inputSize * _inputSize * 3) return const [];
    interpreter.runForMultipleInputs([rgb], _outputs);

    final n = _ic(_count[0].toInt(), 0, _maxDet);

    final found = <Detection>[];
    for (var i = 0; i < n; i++) {
      final score = _scores[0][i];
      if (score < minScore) continue;
      final classId = _classes[0][i].toInt();
      final label = (classId >= 0 && classId < _labels.length)
          ? _labels[classId]
          : 'unknown';
      final b = _boxes[0][i];
      // SSD emits [yMin, xMin, yMax, xMax] per row.
      found.add(
        Detection(
          classId: classId,
          label: label,
          score: score,
          box: Rect.fromLTRB(b[1], b[0], b[3], b[2]),
        ),
      );
    }
    found.sort((a, b) => b.score.compareTo(a.score));
    return found;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _loaded = false;
    _loading = null;
    _loadError = null;
  }
}

/// Camera YUV420 frame -> tightly packed RGB bytes, center-cropped square,
/// rotated to portrait using the sensor orientation. Output: uint8 model
/// input, raw 0–255 values (`outSize × outSize × 3`).
///
/// Note: some devices report interleaved U/V planes (NV12/NV21 variants);
/// indexing with pixelStride keeps chroma valid, and for the rare interleaved
/// case chroma is merely swapped — detection is luma-dominated, so quality
/// holds.
Uint8List yuvToSquareRgb(
  CameraImage image, {
  required int sensorOrientation,
  required int outSize,
}) {
  final planes = image.planes;
  if (planes.length < 3) {
    throw StateError('Expected YUV420 (3 planes), got ${planes.length}');
  }
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];
  final yB = yPlane.bytes;
  final uB = uPlane.bytes;
  final vB = vPlane.bytes;

  // Sensor-plane geometry (Android reports the raw sensor layout).
  final w = image.width;
  final h = image.height;
  final yRow = yPlane.bytesPerRow;
  final uRow = uPlane.bytesPerRow;
  final vRow = vPlane.bytesPerRow;
  final uStep = uPlane.bytesPerPixel ?? 1;
  final vStep = vPlane.bytesPerPixel ?? 1;

  final o = ((sensorOrientation % 360) + 360) % 360;
  final rot = switch (o) {
    0 => '0',
    90 => '90',
    180 => '180',
    _ => '270',
  };

  // Portrait-space crop square.
  final swapped = rot == '90' || rot == '270';
  final pw = swapped ? h : w;
  final ph = swapped ? w : h;
  final s = math.min(pw, ph);
  final ox = (pw - s) ~/ 2;
  final oy = (ph - s) ~/ 2;

  final out = Uint8List(outSize * outSize * 3);
  final scale = s / outSize;

  var oi = 0;
  for (var sy = 0; sy < outSize; sy++) {
    final yp = _ic(oy + (sy * scale).floor(), 0, ph - 1);
    for (var sx = 0; sx < outSize; sx++) {
      final xp = _ic(ox + (sx * scale).floor(), 0, pw - 1);

      int px;
      int py;
      switch (rot) {
        case '90': // portrait = sensor rotated 90° CW
          px = yp;
          py = h - 1 - xp;
        case '270': // portrait = sensor rotated 90° CCW
          px = w - 1 - yp;
          py = xp;
        case '180':
          px = w - 1 - xp;
          py = h - 1 - yp;
        default:
          px = xp;
          py = yp;
      }
      px = _ic(px, 0, w - 1);
      py = _ic(py, 0, h - 1);

      final y = yB[py * yRow + px];
      final cx = px >> 1;
      final cy = py >> 1;
      final u = uB[cy * uRow + cx * uStep] - 128;
      final v = vB[cy * vRow + cx * vStep] - 128;

      // BT.601, fixed-point (scaled ×1024): R+=1.403·V, G−=0.344·U+0.714·V,
      // B+=1.772·U.
      out[oi++] = _ic(y + ((v * 1437) >> 10), 0, 255);
      out[oi++] = _ic(y - (((u * 352) + (v * 731)) >> 10), 0, 255);
      out[oi++] = _ic(y + ((u * 1814) >> 10), 0, 255);
    }
  }
  return out;
}

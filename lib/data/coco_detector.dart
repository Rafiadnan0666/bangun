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

  /// Only draw and accept clear detections. The class-label fix removes the
  /// biggest source of nonsense; this cutoff removes the remaining weak boxes
  /// without making low-light objects impossible to scan.
  static const double minScore = 0.60;

  /// Reject tiny specks. A real held object covers a meaningful part of the
  /// square input; tiny boxes are usually background noise.
  static const double minBoxArea = 0.01;

  /// The model emits at most 10 post-NMS boxes. Draw every clear one so the
  /// scan screen shows all objects in frame, not only the current target.
  static const int maxDetections = 10;

  /// A box must have a sane, non-trivial area before it can be shown.
  static bool isPlausibleBox(Rect box) {
    if (box.width <= 0 || box.height <= 0) return false;
    return box.width * box.height >= minBoxArea;
  }

  /// Maps a raw model class id to a label.
  ///
  /// The TFLite model emits 0-based COCO class ids (person = 0, cat = 16,
  /// cup = 46, book = 83, ...). The asset label map is the 91-line COCO map
  /// with a leading placeholder at index 0, so the model id must be shifted
  /// by one. Without this, every detection is labeled as the class before it.
  static String? labelForClassId(List<String> labels, int classId) {
    final index = classId + 1;
    if (index < 0 || index >= labels.length) return null;
    final label = labels[index];
    return isUsableLabel(label) ? label : null;
  }

  /// The COCO labels file uses `???` for unused class indexes. Those are not
  /// objects and must never appear as detection tags or targets.
  static bool isUsableLabel(String label) {
    final value = label.trim().toLowerCase();
    return value.isNotEmpty && value != '???' && value != 'unknown';
  }

  /// Spot-checks the label asset before the model is used.
  ///
  /// The model emits 0-based COCO ids, so index 0 must be the placeholder and
  /// index 1 must be `person`. If the asset ever ships shifted or truncated,
  /// fail loudly instead of silently naming every object as its neighbour.
  static void verifyLabelMap(List<String> labels) {
    const expected = <int, String>{
      0: '???',
      1: 'person',
      17: 'cat',
      61: 'cake',
      62: 'chair',
      67: 'dining table',
      84: 'book',
    };
    for (final entry in expected.entries) {
      final actual = entry.key < labels.length ? labels[entry.key] : null;
      if (actual != entry.value) {
        throw StateError(
          'Detector label map mismatch at index ${entry.key}: '
          'expected "${entry.value}", got "${actual ?? 'missing'}".',
        );
      }
    }
  }

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
      verifyLabelMap(_labels);

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
      final label = labelForClassId(_labels, classId);
      if (label == null) continue;
      final b = _boxes[0][i];
      // SSD emits [yMin, xMin, yMax, xMax] per row.
      final box = Rect.fromLTRB(b[1], b[0], b[3], b[2]);
      if (!isPlausibleBox(box)) continue;
      found.add(
        Detection(classId: classId, label: label, score: score, box: box),
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

/// Reusable tightly-packed RGB buffer for [yuvToSquareRgb].
///
/// The scan gate converts a frame roughly nine times per second. Reusing one
/// allocation keeps the GC quiet and avoids a 270 KB allocation per frame.
class RgbFrameBuffer {
  Uint8List _bytes = Uint8List(0);

  /// Returns a buffer of exactly [length] bytes, reusing the previous one when
  /// the size has not changed.
  Uint8List ensure(int length) {
    if (_bytes.length != length) _bytes = Uint8List(length);
    return _bytes;
  }

  int get length => _bytes.length;
}

/// Camera YUV420 frame -> tightly packed RGB bytes, center-cropped square,
/// rotated to portrait using the sensor orientation. Output: uint8 model
/// input, raw 0-255 values (`outSize x outSize x 3`).
///
/// Pass a [RgbFrameBuffer] to reuse the output allocation across frames.
///
/// Note: some devices report interleaved U/V planes (NV12/NV21 variants);
/// indexing with pixelStride keeps chroma valid, and for the rare interleaved
/// case chroma is merely swapped - detection is luma-dominated, so quality
/// holds.
Uint8List yuvToSquareRgb(
  CameraImage image, {
  required int sensorOrientation,
  required int outSize,
  RgbFrameBuffer? buffer,
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

  final orientation = ((sensorOrientation % 360) + 360) % 360;

  // Portrait-space crop square.
  final swapped = orientation == 90 || orientation == 270;
  final pw = swapped ? h : w;
  final ph = swapped ? w : h;
  final s = math.min(pw, ph);
  final ox = (pw - s) ~/ 2;
  final oy = (ph - s) ~/ 2;

  final out =
      buffer?.ensure(outSize * outSize * 3) ?? Uint8List(outSize * outSize * 3);
  final scale = s / outSize;

  var oi = 0;
  for (var sy = 0; sy < outSize; sy++) {
    final yp = _ic(oy + (sy * scale).floor(), 0, ph - 1);
    for (var sx = 0; sx < outSize; sx++) {
      final xp = _ic(ox + (sx * scale).floor(), 0, pw - 1);

      // Rotate the portrait sample back onto the sensor plane. Every branch
      // maps into [0, w) x [0, h), so no clamp is needed after the switch.
      int px;
      int py;
      switch (orientation) {
        case 90: // portrait = sensor rotated 90 deg CW
          px = yp;
          py = h - 1 - xp;
        case 270: // portrait = sensor rotated 90 deg CCW
          px = w - 1 - yp;
          py = xp;
        case 180:
          px = w - 1 - xp;
          py = h - 1 - yp;
        default:
          px = xp;
          py = yp;
      }

      final y = yB[py * yRow + px];
      final cx = px >> 1;
      final cy = py >> 1;
      final u = uB[cy * uRow + cx * uStep] - 128;
      final v = vB[cy * vRow + cx * vStep] - 128;

      // BT.601, fixed-point (scaled x1024): R+=1.403*V, G-=0.344*U+0.714*V,
      // B+=1.772*U.
      out[oi++] = _ic(y + ((v * 1437) >> 10), 0, 255);
      out[oi++] = _ic(y - (((u * 352) + (v * 731)) >> 10), 0, 255);
      out[oi++] = _ic(y + ((u * 1814) >> 10), 0, 255);
    }
  }
  return out;
}

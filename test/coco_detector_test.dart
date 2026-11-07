import 'dart:io';
import 'dart:ui';

import 'package:awake/data/coco_detector.dart';
import 'package:awake/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('format helpers', () {
    test('two pads with leading zero', () {
      expect(two(5), '05');
      expect(two(12), '12');
      expect(two(0), '00');
    });

    test('hhmm formats 24h label', () {
      expect(hhmm(6, 30), '06:30');
      expect(hhmm(0, 0), '00:00');
      expect(hhmm(23, 59), '23:59');
    });

    test('repeatLabel returns correct strings', () {
      expect(repeatLabel(daily: true, days: const [1, 2, 3]), 'Mon Tue Wed');
      expect(repeatLabel(daily: false, days: const [1, 2, 3]), 'Mon Tue Wed');
      expect(repeatLabel(daily: true, days: []), 'Once');
      expect(repeatLabel(daily: false, days: []), 'Once');
      expect(repeatLabel(daily: true, days: [1, 2, 3, 4, 5, 6, 7]), 'Every day');
    });

    test('countdownText returns expected strings', () {
      expect(countdownText(null), 'not scheduled');
      expect(countdownText(DateTime.now().subtract(const Duration(hours: 1))), 'ringing');
      // Cover the 'in X min' branch (h == 0)
      final nearFuture = DateTime.now().add(const Duration(minutes: 10));
      final nearResult = countdownText(nearFuture);
      expect(nearResult, isNot('not scheduled'));
      expect(nearResult, isNot('ringing'));
      expect(nearResult, contains('min'));
      // Cover the 'in X h Y min' branch (h > 0)
      final farFuture = DateTime.now().add(const Duration(hours: 2));
      final farResult = countdownText(farFuture);
      expect(farResult, contains('h'));
    });

    test('todayKey returns correct date string', () {
      expect(todayKey(), DateTime.now().year.toString() +
          '-${two(DateTime.now().month)}-${two(DateTime.now().day)}');
    });
  });

  group('detection presentation', () {
    test('placeholder labels are filtered out', () {
      expect(CocoDetector.isUsableLabel('???'), isFalse);
      expect(CocoDetector.isUsableLabel(' unknown '), isFalse);
      expect(CocoDetector.isUsableLabel(''), isFalse);
      expect(CocoDetector.isUsableLabel('cup'), isTrue);
      expect(CocoDetector.isUsableLabel('cell phone'), isTrue);
    });

    test('confidence cutoff stays conservative and all boxes are shown', () {
      expect(CocoDetector.minScore, greaterThanOrEqualTo(0.6));
      expect(CocoDetector.minBoxArea, greaterThan(0));
      expect(CocoDetector.maxDetections, greaterThanOrEqualTo(8));
    });

    test('tiny background boxes are rejected', () {
      expect(
        CocoDetector.isPlausibleBox(const Rect.fromLTWH(0.5, 0.5, 0, 0)),
        isFalse,
      );
      expect(
        CocoDetector.isPlausibleBox(const Rect.fromLTWH(0.5, 0.5, 0.05, 0.05)),
        isFalse,
      );
      expect(
        CocoDetector.isPlausibleBox(const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2)),
        isTrue,
      );
    });

    test('model class ids are shifted past the leading placeholder', () {
      const labels = ['???', 'person', 'bicycle', 'cat'];
      expect(CocoDetector.labelForClassId(labels, 0), 'person');
      expect(CocoDetector.labelForClassId(labels, 2), 'cat');
      expect(CocoDetector.labelForClassId(labels, 3), isNull);
      expect(CocoDetector.labelForClassId(labels, -1), isNull);
    });

    test('real label asset matches the model class ids', () {
      final raw = File('assets/models/labels.txt').readAsStringSync();
      final labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      expect(labels.first, '???');
      expect(CocoDetector.labelForClassId(labels, 0), 'person');
      expect(CocoDetector.labelForClassId(labels, 16), 'cat');
      expect(CocoDetector.labelForClassId(labels, 17), 'dog');
      expect(CocoDetector.labelForClassId(labels, 46), 'cup');
      expect(CocoDetector.labelForClassId(labels, 61), 'chair');
      expect(CocoDetector.labelForClassId(labels, 83), 'book');
    });

    test('real label asset passes the runtime map guard', () {
      final raw = File('assets/models/labels.txt').readAsStringSync();
      final labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      expect(() => CocoDetector.verifyLabelMap(labels), returnsNormally);
    });

    test('a shifted label asset is rejected instead of mislabeling', () {
      final raw = File('assets/models/labels.txt').readAsStringSync();
      final labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      // Simulate the old off-by-one asset: drop the leading placeholder.
      expect(
        () => CocoDetector.verifyLabelMap(labels.sublist(1)),
        throwsStateError,
      );
    });

    test('YOLO class ids map directly and its five-label guard passes', () {
      final raw = File('assets/models/yolo_labels.txt').readAsStringSync();
      final labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      expect(labels, CocoDetector.yoloClasses);
      expect(() => CocoDetector.verifyYoloLabelMap(labels), returnsNormally);
      expect(CocoDetector.labelForYoloClassId(labels, 0), 'microwave');
      expect(CocoDetector.labelForYoloClassId(labels, 4), 'refrigerator');
      expect(CocoDetector.labelForYoloClassId(labels, -1), isNull);
      expect(CocoDetector.labelForYoloClassId(labels, 5), isNull);
    });

    test('a drifted YOLO label asset is rejected', () {
      final labels = [...CocoDetector.yoloClasses];
      labels[2] = 'oven';
      expect(() => CocoDetector.verifyYoloLabelMap(labels), throwsStateError);
      expect(
        () => CocoDetector.verifyYoloLabelMap(labels.sublist(1)),
        throwsStateError,
      );
    });
  });

  group('RgbFrameBuffer', () {
    test('reuses the same allocation for the same frame size', () {
      final buffer = RgbFrameBuffer();
      final first = buffer.ensure(300 * 300 * 3);
      expect(first, hasLength(270000));
      expect(identical(buffer.ensure(270000), first), isTrue);
      expect(buffer.length, 270000);
    });

    test('allocates a fresh buffer when the size changes', () {
      final buffer = RgbFrameBuffer();
      final first = buffer.ensure(12);
      final second = buffer.ensure(24);
      expect(second, hasLength(24));
      expect(identical(first, second), isFalse);
      expect(identical(buffer.ensure(24), second), isTrue);
    });
  });

  group('CocoDetector state', () {
    test('isReady is false when not loaded', () {
      expect(CocoDetector.I.isReady, isFalse);
    });

    test('inputSize defaults to 300', () {
      expect(CocoDetector.I.inputSize, 300);
    });

    test('loadError is null when nothing failed', () {
      expect(CocoDetector.I.loadError, isNull);
    });

    test('dispose clears state', () {
      expect(() => CocoDetector.I.dispose(), returnsNormally);
      expect(CocoDetector.I.isReady, isFalse);
      // inputSize is not reset by dispose, so it remains the last known value
    });
  });
}

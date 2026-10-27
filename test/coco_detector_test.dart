import 'dart:io';
import 'dart:ui';

import 'package:bangun/data/coco_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

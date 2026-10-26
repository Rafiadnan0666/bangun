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

    test('confidence cutoff and overlay cap stay conservative', () {
      expect(CocoDetector.minScore, greaterThanOrEqualTo(0.6));
      expect(CocoDetector.minBoxArea, greaterThan(0));
      expect(CocoDetector.maxDetections, lessThanOrEqualTo(5));
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
  });
}

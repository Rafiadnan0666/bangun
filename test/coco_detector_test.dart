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
      expect(CocoDetector.minScore, greaterThanOrEqualTo(0.5));
      expect(CocoDetector.maxDetections, lessThanOrEqualTo(5));
    });
  });
}

import 'dart:ui';

import 'package:bangun/data/scan_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectionBoxOnScreen', () {
    test('square sensor maps identity-ported onto the cover fit', () {
      // 480² portrait frame, portrait screen: cover scale = 2400/480.
      final rect = detectionBoxOnScreen(
        unit: const Rect.fromLTRB(0, 0, 1, 1),
        frameWidth: 480,
        frameHeight: 480,
        sensorOrientation: 90,
        squareSize: 300,
        screen: const Size(1080, 2400),
      );
      expect(rect, const Rect.fromLTWH(-660, 0, 2400, 2400));
    });

    test(
      '4:3 sensor: square crop offset + cover crop both accounted for',
      () {
        // Sensor 640x480 rotated 90° → portrait 480x640; the square crop sits
        // at y∈[80,560] in portrait pixels; cover scale fills height (3.75),
        // cropping (1080−1800)/2 from each side.
        final rect = detectionBoxOnScreen(
          unit: const Rect.fromLTRB(0.25, 0.4, 0.75, 0.6),
          frameWidth: 640,
          frameHeight: 480,
          sensorOrientation: 90,
          squareSize: 300,
          screen: const Size(1080, 2400),
        );
        expect(rect.left, closeTo(90, 0.01));
        expect(rect.top, closeTo(1020, 0.01));
        expect(rect.width, closeTo(900, 0.01));
        expect(rect.height, closeTo(360, 0.01));
      },
    );

    test('sensor orientation 0 keeps unbinned geometry', () {
      // Unrotated 480x640 frame: portrait px space is frameWidth x frameHeight
      // as-is; the square covers it fully (min(480,640)=480 crop height).
      final rect = detectionBoxOnScreen(
        unit: const Rect.fromLTRB(0, 0.5, 1, 1),
        frameWidth: 480,
        frameHeight: 640,
        sensorOrientation: 0,
        squareSize: 300,
        screen: const Size(480, 640), // 1:1 fit, no scaling
      );
      // Crop top/bottom off: oy=(640-480)/2=80 → unit 0.5..1 maps y 320..560.
      expect(rect.left, closeTo(0, 0.01));
      expect(rect.top, closeTo(320, 0.01));
      expect(rect.width, closeTo(480, 0.01));
      expect(rect.height, closeTo(240, 0.01));
    });

    test('keeps sizes sane for full-frame detector boxes', () {
      final rect = detectionBoxOnScreen(
        unit: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
        frameWidth: 640,
        frameHeight: 480,
        sensorOrientation: 270,
        squareSize: 300,
        screen: const Size(1080, 2400),
      );
      expect(rect.width.isNegative, isFalse);
      expect(rect.height.isNegative, isFalse);
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    });
  });
}

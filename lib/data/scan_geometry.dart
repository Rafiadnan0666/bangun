/// Pure mapping math for drawing detector outputs on the live preview.
///
/// The detection pipeline crops the camera frame manually, so raw normalized
/// SSD boxes can't be painted straight onto the screen: YUV sensor frame →
/// portrait center-cropped square (see `yuvToSquareRgb`) → model input. This
/// file mirrors those exact transforms so a box lands on the real object.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Maps a model-space unit `rect` ([0..1] on the square detector input) to
/// display coordinates for the cover-fitted camera preview.
///
/// * [frameWidth]/[frameHeight] — raw sensor frame (`CameraImage.width/height`,
///   unrotated).
/// * [sensorOrientation] — the camera description's sensor orientation, the
///   same value the YUV converter rotates by.
/// * [squareSize] — detector input edge (e.g. 300).
/// * [screen] — size of the widget area the preview is fitted into.
Rect detectionBoxOnScreen({
  required Rect unit,
  required int frameWidth,
  required int frameHeight,
  required int sensorOrientation,
  required int squareSize,
  required Size screen,
}) {
  final o = ((sensorOrientation % 360) + 360) % 360;
  final swapped = o == 90 || o == 270;
  // Portrait-space frame: what the user sees on screen.
  final pw = swapped ? frameHeight : frameWidth;
  final ph = swapped ? frameWidth : frameHeight;
  final s = math.min(pw, ph).toDouble();
  final ox = (pw - s) / 2;
  final oy = (ph - s) / 2;

  // Square-relative [0..1] → portrait pixels (the frame's crop window).
  final px = ox + unit.left * s;
  final py = oy + unit.top * s;
  final pxw = unit.width * s;
  final pyh = unit.height * s;

  // BoxFit.cover: scale to fill, centered, overflow clipped.
  final k = math.max(screen.width / pw, screen.height / ph);
  final dx = (screen.width - pw * k) / 2;
  final dy = (screen.height - ph * k) / 2;

  return Rect.fromLTWH(dx + px * k, dy + py * k, pxw * k, pyh * k);
}

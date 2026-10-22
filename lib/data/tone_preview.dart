/// In-editor sound preview.
///
/// Lets the user hear exactly what will wake them — built-in tone, their own
/// file, or (for Spotify links) the enforced fallback siren that keeps ringing
/// until the Spotify handoff opens — straight from the sound card.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

/// Reusable preview player; one instance keeps codec warm and cheap.
final class TonePreview {
  TonePreview._();

  static final AudioPlayer _player = AudioPlayer();
  static final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  static Timer? _cutoff;

  /// Preview hard-stop, so a 40-minute picked playlist never keeps playing.
  static const previewMs = 5000;

  static bool _wired = false;

  static void _init() {
    if (_wired) return;
    _wired = true;
    _player.onPlayerComplete.listen((_) => stop());
  }

  /// Plays a ~[previewMs] slice of the alarm's configured ring sound.
  static Future<void> test(BangunAlarm alarm) {
    _init();
    return _run(alarm);
  }

  static Future<void> _run(BangunAlarm alarm) async {
    final src = switch (alarm.toneKind) {
      ToneKind.builtin => AssetSource(
          alarm.tone.assetPath.replaceFirst('assets/', ''),
        ),
      ToneKind.file =>
        alarm.filePath == null ? null : DeviceFileSource(alarm.filePath!),
      ToneKind.spotify => AssetSource(
          BuiltInTone.sirenRush.assetPath.replaceFirst('assets/', ''),
        ),
    };
    if (src == null) {
      if (kDebugMode) debugPrint('TONE preview: no source to play');
      return;
    }
    if (kDebugMode) debugPrint('TONE preview: ${alarm.toneKind} playing…');
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      // Mirror the ring engine's enforced floor so the preview is honest.
      await _player.setVolume(math.max(0.35, alarm.volume));
      _cutoff?.cancel();
      _cutoff = Timer(const Duration(milliseconds: previewMs), stop);
      playing.value = true;
      await _player.play(src);
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('TONE preview failed: $e');
      stop();
    }
  }

  static Future<void> stop() async {
    _cutoff?.cancel();
    _cutoff = null;
    playing.value = false;
    try {
      await _player.stop();
    } on Exception {
      // Already stopped — fine for a preview.
    }
  }
}

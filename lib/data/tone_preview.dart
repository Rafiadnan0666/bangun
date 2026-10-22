/// In-editor sound preview.
///
/// Built-in tones and picked files play a five-second slice straight in the
/// app at the exact volume floor the ring engine enforces. Spotify links do
/// not play inside Bangun (Spotify owns that audio): the preview runs the
/// same start sequence as ring time — open the item and press play via the
/// media-session bridge — and reports the outcome so the editor can show an
/// honest message instead of masking it with a siren demo.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'spotify_launch.dart';

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

  /// Plays the alarm's configured ring sound.
  ///
  /// Returns null for local playback (built-in tone / picked file), or the
  /// Spotify start result when the alarm uses a Spotify link.
  static Future<SpotifyStart?> test(BangunAlarm alarm) async {
    _init();
    if (alarm.toneKind == ToneKind.spotify) {
      final result = await startSpotify(alarm.spotifyUrl ?? '');
      if (kDebugMode) debugPrint('TONE preview: spotify → $result');
      return result;
    }
    final path = switch (alarm.toneKind) {
      ToneKind.builtin => alarm.tone.assetPath,
      // Durable local copy made at pick time — survives cache eviction and
      // expired SAF grants, so preview and ring behave the same forever.
      ToneKind.file => alarm.filePath,
      ToneKind.spotify => null,
    };
    if (path == null || path.isEmpty) {
      if (kDebugMode) debugPrint('TONE preview: no source to play');
      return null;
    }
    await _play(path, alarm.volume);
    return null;
  }

  static Future<void> _play(String path, double volume) async {
    final src = path.startsWith('assets/')
        ? AssetSource(path.replaceFirst('assets/', ''))
        : DeviceFileSource(path);
    if (kDebugMode) debugPrint('TONE preview: $path playing…');
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      // Mirror the ring engine's enforced floor so the preview is honest.
      await _player.setVolume(math.max(0.35, volume));
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

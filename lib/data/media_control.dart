/// Platform bridge to Android media + permission settings.
///
/// The interesting call is [spotifyPlay]: Android gives MediaController
/// access (i.e. the ability to press play in Spotify) only to apps that own a
/// notification listener. Bangun registers one, the user enables "notification
/// access" once, and from then on the ring screen can start the configured
/// playlist/song itself instead of hoping Spotify honours a deep-link flag.
library;

import 'package:flutter/services.dart';

final class MediaControl {
  MediaControl._();

  static const _channel = MethodChannel('bangun/media');

  /// Android 14+ can drop full-screen intents unless the user allows them.
  /// On older versions the call short-circuits to true on the native side.
  static Future<bool> canUseFullScreenIntent() async {
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ??
          true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<void> openFullScreenIntentSettings() async {
    try {
      await _channel.invokeMethod<void>('openFullScreenIntentSettings');
    } on PlatformException {
      // Settings screen unavailable; the home banner explains the manual path.
    } on MissingPluginException {
      // Non-Android platform.
    }
  }

  /// True when the user granted "notification access" to Bangun, which is what
  /// unlocks Spotify's [MediaController].
  static Future<bool> hasNotificationAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasNotificationAccess') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openNotificationAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationAccessSettings');
    } on PlatformException {
      // Nothing to open; the UI keeps the setup hint visible.
    } on MissingPluginException {
      // Non-Android platform.
    }
  }

  /// Presses play in Spotify's live media session. Returns false when there is
  /// no session yet (Spotify not launched, not installed, or the app lacks
  /// notification access).
  static Future<bool> spotifyPlay() async {
    try {
      return await _channel.invokeMethod<bool>('spotifyPlay') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Android's "play from search" intent pointed at Spotify. Some Spotify
  /// builds ignore the `:play` deep-link switch but honour this native media
  /// intent and start the item directly.
  static Future<bool> spotifyPlayFromSearch(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('spotifyPlayFromSearch', {
            'uri': uri,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// True when Spotify's media session reports STATE_PLAYING.
  static Future<bool> spotifyIsPlaying() async {
    try {
      return await _channel.invokeMethod<bool>('spotifyIsPlaying') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Re-opens the ring screen over whatever external app (Spotify, browser)
  /// took the foreground during the handoff, using a silent alarm-category
  /// notification with a full-screen intent.
  static Future<void> bringToFront() async {
    try {
      await _channel.invokeMethod<void>('bringToFront');
    } on PlatformException {
      // Cannot re-assert; the alarm notification is still tappable.
    } on MissingPluginException {
      // Non-Android platform.
    }
  }
}

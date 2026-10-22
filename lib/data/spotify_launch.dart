/// Single handoff routine shared by the ring screen and the editor preview.
///
/// Launching a Spotify deep link only gets you *into* Spotify: depending on
/// the app version the item can sit paused until someone taps play. Bangun
/// closes that gap with the Android media-session bridge
/// ([MediaControl.spotifyPlay]): once Spotify has published its session it
/// accepts a `play()` command from a notification listener, so the alarm can
/// start the playlist/song by itself at ring time.
///
/// Candidate order for the link itself:
/// 1. `spotify:…:play` deep link — opens the item AND asks Spotify to autoplay.
/// 2. Plain `spotify:…` deep link — opens the item on builds that reject `:play`.
/// 3. The raw pasted https link — browser / Spotify web player.
/// 4. Bare `spotify://` app shell.
///
/// The caller decides what to do with the outcome. The ring screen keeps
/// nudging `play()` in the background; the preview reports it honestly.
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'media_control.dart';
import 'models.dart';

/// Result of a Spotify start attempt.
enum SpotifyStart {
  /// Spotify accepted a play command — the wake sound is Spotify itself.
  playing,

  /// Spotify opened the item but no media session accepted play (yet):
  /// usually notification access is missing or the app is still booting.
  opened,

  /// No Spotify handler on the device at all.
  unavailable,
}

/// Opens [rawUrl] in Spotify and tries hard to make it actually play.
///
/// [onOpened] fires with the candidate that was handed to an external app as
/// soon as the intent is accepted. The ring screen uses it to re-assert the
/// gate over Spotify after a short delay without waiting for the whole poll.
Future<SpotifyStart> startSpotify(
  String rawUrl, {
  void Function(String candidate)? onOpened,
}) async {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return SpotifyStart.unavailable;

  // Fast path: Spotify already has a session (music was playing earlier, or
  // the user just tested it) — press play before opening anything.
  if (await MediaControl.spotifyPlay()) return SpotifyStart.playing;

  final deep = spotifyDeepLink(trimmed);
  final playLink = _autoplayVariant(deep);
  final itemUri = _itemUri(deep);
  final candidates = <String>[
    ?playLink,
    ?deep,
    trimmed,
    'spotify://',
  ];
  var opened = false;
  for (final candidate in candidates) {
    final uri = Uri.tryParse(candidate);
    if (uri == null) continue;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) {
        opened = true;
        onOpened?.call(candidate);
        break;
      }
    } on Exception {
      // No handler for this variant — try the next candidate.
    }
    if (kDebugMode) debugPrint('SPOTIFY handoff: $candidate → no handler');
  }
  if (!opened) return SpotifyStart.unavailable;

  // Spotify needs a moment to publish its media session after opening. Keep
  // asking it to play; the `:play` deep link is only a hint, this is the
  // actual "press play" a sleeping user cannot do.
  var searchTried = false;
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (await MediaControl.spotifyPlay()) return SpotifyStart.playing;
    // Second native path: some builds ignore `:play` but start playback when
    // the media "play from search" intent carries the Spotify item URI.
    if (!searchTried && itemUri != null && i >= 4) {
      searchTried = true;
      if (await MediaControl.spotifyPlayFromSearch(itemUri)) {
        if (kDebugMode) {
          debugPrint('SPOTIFY play-from-search accepted: $itemUri');
        }
      }
    }
  }
  return SpotifyStart.opened;
}

/// `spotify:kind:id` -> `spotify:kind:id:play` (idempotent).
String? _autoplayVariant(String? deep) {
  if (deep == null || deep.isEmpty) return null;
  return deep.toLowerCase().endsWith(':play') ? deep : '$deep:play';
}

/// Strips a trailing `:play` so the URI names the item, not the action.
String? _itemUri(String? deep) {
  if (deep == null || deep.isEmpty) return null;
  return deep.toLowerCase().endsWith(':play')
      ? deep.substring(0, deep.length - 5)
      : deep;
}

/// Keeps nudging Spotify's session until it reports playing (or [span] ends).
/// Used by the ring screen: Spotify can take 20-40 s to boot on a cold phone.
/// When [deepUri] is given it also retries the native play-from-search path.
Future<bool> keepSpotifyPlaying({
  Duration span = const Duration(seconds: 45),
  Duration every = const Duration(seconds: 2),
  String? deepUri,
}) async {
  final stopAt = DateTime.now().add(span);
  var attempt = 0;
  while (DateTime.now().isBefore(stopAt)) {
    if (await MediaControl.spotifyPlay()) return true;
    if (await MediaControl.spotifyIsPlaying()) return true;
    if (deepUri != null && attempt == 5) {
      await MediaControl.spotifyPlayFromSearch(_itemUri(deepUri) ?? deepUri);
    }
    attempt++;
    await Future<void>.delayed(every);
  }
  return false;
}

/// Plain launcher (no media-session nudge). Kept for the editor's inline
/// "open this link" affordance, where opening Spotify is enough.
Future<bool> launchSpotify(String rawUrl, {bool autoplay = true}) async {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return false;
  final deep = spotifyDeepLink(trimmed);
  final candidates = <String>[
    if (autoplay) ?_autoplayVariant(deep),
    ?deep,
    trimmed,
    'spotify://',
  ];
  for (final candidate in candidates) {
    final uri = Uri.tryParse(candidate);
    if (uri == null) continue;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } on Exception {
      // No handler for this variant — try the next candidate.
    }
    if (kDebugMode) debugPrint('SPOTIFY handoff: $candidate → no handler');
  }
  return false;
}

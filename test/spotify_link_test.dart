import 'package:bangun/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('spotifyDeepLink', () {
    test('playlist link with query params and https', () {
      expect(
        spotifyDeepLink(
          'https://open.spotify.com/playlist/37i9dQZF1E35NbjQoPZcmv?si=abc123',
        ),
        'spotify:playlist:37i9dQZF1E35NbjQoPZcmv',
      );
    });

    test('bare-host track link', () {
      expect(
        spotifyDeepLink('open.spotify.com/track/4NrXzqzG8B0Bgb2ZnKGIcd'),
        'spotify:track:4NrXzqzG8B0Bgb2ZnKGIcd',
      );
    });

    test('intl locale hops are skipped', () {
      expect(
        spotifyDeepLink(
          'https://open.spotify.com/intl-de/artist/4eT8rGLDzM5FmZ0euzn4jW',
        ),
        'spotify:artist:4eT8rGLDzM5FmZ0euzn4jW',
      );
    });

    test('legacy play.spotify.com album link', () {
      expect(
        spotifyDeepLink('https://play.spotify.com/album/1DFixLWuPkv3KT3TnV35m3'),
        'spotify:album:1DFixLWuPkv3KT3TnV35m3',
      );
    });

    test('native spotify URIs pass through untouched', () {
      expect(
        spotifyDeepLink('spotify:playlist:37i9dQZF1E35NbjQoPZcmv'),
        'spotify:playlist:37i9dQZF1E35NbjQoPZcmv',
      );
    });

    test('forPlay appends the autoplay :play switch', () {
      expect(
        spotifyDeepLink(
          'https://open.spotify.com/playlist/37i9dQZF1E35NbjQoPZcmv?si=abc123',
          forPlay: true,
        ),
        'spotify:playlist:37i9dQZF1E35NbjQoPZcmv:play',
      );
      expect(
        spotifyDeepLink('open.spotify.com/track/4NrXzqzG8B0Bgb2ZnKGIcd',
            forPlay: true),
        'spotify:track:4NrXzqzG8B0Bgb2ZnKGIcd:play',
      );
    });

    test('non-item links return null', () {
      expect(spotifyDeepLink('https://example.com/playlist/short'), isNull);
      expect(spotifyDeepLink('https://example.com'), isNull);
      expect(spotifyDeepLink('   '), isNull);
      // A pathological URL that fails to parse entirely.
      expect(spotifyDeepLink('https://{bad url'), isNull);
    });
  });
}

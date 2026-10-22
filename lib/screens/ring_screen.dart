import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/widgets.dart';
import '../data/alarm_repository.dart';
import '../data/media_control.dart';
import '../data/models.dart';
import '../data/spotify_launch.dart';
import 'math_challenge_screen.dart';
import 'scan_challenge_screen.dart';

/// The full-screen ring environment. The app is intentionally left without a
/// stop control here: the notification has no stop button either, so the only
/// path out of this screen is completing the configured challenge.
class RingScreen extends StatefulWidget {
  const RingScreen({super.key, required this.alarmId});

  final int alarmId;

  /// Route with a stable name so the app-level router can de-duplicate pushes.
  static Route<void> route(int alarmId) => MaterialPageRoute<void>(
    builder: (_) => RingScreen(alarmId: alarmId),
    settings: const RouteSettings(name: '/ring'),
  );

  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _spin;
  BangunAlarm? _alarm;
  bool _spotifyAccess = true;
  bool _spotifyPlaying = false;
  Timer? _spotifyWatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Spotify handoff is automatic: once the ring UI is up and the alarm
    // audio session is warm, open the configured link inside Spotify and
    // press play through the media-session bridge. The built-in twin-chime
    // underlay keeps the ring audible until the gate is cleared.
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _autoSpotifyHandoff();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spotifyWatch?.cancel();
    _spin.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the notification-access settings during a ring should
    // reveal the freshly granted state without a rebuild trigger.
    if (state == AppLifecycleState.resumed) _refreshSpotifyAccess();
  }

  Future<void> _refreshSpotifyAccess() async {
    if (_alarm?.toneKind != ToneKind.spotify) return;
    final access = await MediaControl.hasNotificationAccess();
    if (mounted && access != _spotifyAccess) {
      setState(() => _spotifyAccess = access);
    }
  }

  /// Polls Spotify's real playback state so the gate can show whether the
  /// music actually started underneath it.
  void _startSpotifyWatch() {
    _spotifyWatch ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      final playing = await MediaControl.spotifyIsPlaying();
      if (!mounted) return;
      if (playing != _spotifyPlaying) {
        setState(() => _spotifyPlaying = playing);
      }
      if (playing) {
        _spotifyWatch?.cancel();
        _spotifyWatch = null;
      }
    });
  }

  /// Opens the alarm's pasted link and makes Spotify actually start: the
  /// `:play` deep link opens the item, then the media-session bridge presses
  /// play. The twin-chime underlay keeps ringing until the gate is cleared.
  Future<void> _openSpotify() async {
    final alarm = _alarm;
    if (alarm == null) return;
    if (alarm.toneKind != ToneKind.spotify) return;
    final url = alarm.spotifyUrl ?? '';
    if (url.trim().isEmpty) return;
    final deep = spotifyDeepLink(url.trim());
    await _refreshSpotifyAccess();
    final result = await startSpotify(
      url,
      onOpened: (_) {
        // Spotify (or the browser) just took the foreground. Give it a moment
        // to accept the deep link, then re-assert the gate on top with a
        // full-screen intent while the music keeps playing underneath.
        Future<void>.delayed(const Duration(milliseconds: 1300), () {
          if (mounted) MediaControl.bringToFront();
        });
      },
    );
    if (!mounted) return;
    if (kDebugMode) debugPrint('SPOTIFY ring: $result');
    setState(() {
      if (result == SpotifyStart.playing) _spotifyPlaying = true;
    });
    if (result == SpotifyStart.opened) {
      // Spotify opened but has not accepted play yet (cold phone, session
      // still booting). Keep nudging in the background.
      unawaited(keepSpotifyPlaying(deepUri: deep));
      _startSpotifyWatch();
    } else if (result == SpotifyStart.playing) {
      _startSpotifyWatch();
    }
  }

  bool _autoHandoffDone = false;

  Future<void> _autoSpotifyHandoff() async {
    if (_autoHandoffDone || !mounted) return;
    final alarm = _alarm ?? context.read<AlarmRepository>().byId(widget.alarmId);
    if (alarm == null || alarm.toneKind != ToneKind.spotify) return;
    _alarm = alarm;
    final raw = alarm.spotifyUrl?.trim() ?? '';
    if (raw.isEmpty) return;
    _autoHandoffDone = true;
    await _openSpotify();
  }

  void _startChallenge(ChallengeKind gate) {
    HapticFeedback.mediumImpact();
    final isMathGate = gate == ChallengeKind.math;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => isMathGate
            ? MathChallengeScreen(alarm: _alarm!, chosenKind: gate)
            : ScanChallengeScreen(alarm: _alarm!, chosenKind: gate),
        settings: RouteSettings(name: isMathGate ? '/math' : '/scan'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AlarmRepository>();
    _alarm ??= repo.byId(widget.alarmId);
    final now = DateTime.now();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) HapticFeedback.vibrate(); // no exit — that's the point
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: Bg.ring),
                child: CustomPaint(
                  painter: _SunburstPainter(_spin.value),
                  size: Size.infinite,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  const Text('⏰', style: TextStyle(fontSize: 46)),
                  const SizedBox(height: 8),
                  Text(
                    hhmm(_alarm?.hour ?? now.hour, _alarm?.minute ?? now.minute),
                    style: const TextStyle(
                      fontSize: 68,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2,
                      height: 1.02,
                      shadows: [
                        Shadow(color: Color(0x51000000), blurRadius: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'TIME TO WAKE UP',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withValues(alpha: 0.92),
                      letterSpacing: 3.5,
                    ),
                  ),
                  if ((_alarm?.label ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _alarm!.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _LockSheet(
                alarm: _alarm,
                spotifyAccess: _spotifyAccess,
                spotifyPlaying: _spotifyPlaying,
                onMath: () => _startChallenge(ChallengeKind.math),
                onScan: () => _startChallenge(ChallengeKind.scan),
                onSpotify: _openSpotify,
                onAllowSpotify: () async {
                  await MediaControl.openNotificationAccessSettings();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockSheet extends StatelessWidget {
  const _LockSheet({
    required this.alarm,
    required this.spotifyAccess,
    required this.spotifyPlaying,
    required this.onMath,
    required this.onScan,
    required this.onSpotify,
    required this.onAllowSpotify,
  });

  final BangunAlarm? alarm;
  final bool spotifyAccess;
  final bool spotifyPlaying;
  final VoidCallback onMath;
  final VoidCallback onScan;
  final VoidCallback onSpotify;
  final VoidCallback onAllowSpotify;

  @override
  Widget build(BuildContext context) {
    final a = alarm;
    if (a == null) {
      // Shouldn't happen (ring router only opens for known alarm ids), but
      // keep a legible fallback instead of crashing.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: const BoxDecoration(
          color: Bg.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
        ),
        child: const SafeArea(
          top: false,
          child: Text(
            '⚠️ Alarm details missing — restart Bangun to clear this ring '
            '(it keeps ringing until the gate is cleared).',
            style: TextStyle(color: Bg.ink, fontSize: 13),
          ),
        ),
      );
    }
    final mix = a.challengeKind == ChallengeKind.mix;
    final mathGate =
        a.challengeKind == ChallengeKind.math ||
        a.challengeKind == ChallengeKind.mix;
    final scanGate = a.challengeKind == ChallengeKind.scan || mix;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: const BoxDecoration(
        color: Bg.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('🔒', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bangun lockdown',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                          color: Bg.ink,
                        ),
                      ),
                      Text(
                        'No alarms off until you finish the gate.',
                        style: TextStyle(fontSize: 11.5, color: Bg.sub),
                      ),
                    ],
                  ),
                ),
                const Text('🧠', style: TextStyle(fontSize: 20)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            StatusRow(leading: 'Alarm', value: a.label),
            const Divider(),
            StatusRow(leading: 'Sound', value: a.toneName()),
            const Divider(),
            StatusRow(leading: 'Gate', value: a.challengeLabel()),
            const SizedBox(height: 10),
            if (mathGate) ...[
              CtaPill(
                icon: '🧮',
                label: 'Solve ${a.mathProblems} problems',
                onTap: onMath,
              ),
              if (scanGate) const SizedBox(height: 10),
            ],
            if (scanGate) InkPill(icon: '📷', label: 'Scan object', onTap: onScan),
            if (a.toneKind == ToneKind.spotify) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onSpotify,
                icon: Icon(
                  spotifyPlaying
                      ? Icons.graphic_eq_rounded
                      : Icons.music_note_rounded,
                  color: Bg.ink,
                  size: 18,
                ),
                label: Text(
                  spotifyPlaying
                      ? 'Spotify is playing - tap to retry'
                      : 'Start Spotify now',
                  style: const TextStyle(
                    color: Bg.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (!spotifyAccess)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Bg.cardSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Bg.hairline),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Allow notification access so Bangun can press play '
                          'in Spotify by itself.',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            color: Bg.sub,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Bg.toneBlueDeep,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onAllowSpotify,
                        child: const Text(
                          'Allow',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  spotifyPlaying
                      ? 'Music runs underneath the gate.'
                      : 'The playlist starts by itself; this button retries '
                          'the handoff.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5, color: Bg.subFaint),
                ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Ringing continues until the gate is cleared — that\'s the point.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: Bg.subFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slow rotating rays behind the "TIME TO WAKE UP" header — sunrise energy.
class _SunburstPainter extends CustomPainter {
  _SunburstPainter(this._phase);

  final double _phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.28, size.height * 0.24);
    final rays = 18;
    final lenLong = size.width * 0.55;
    final lenShort = size.width * 0.36;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < rays; i++) {
      final angle = (2 * math.pi / rays) * i + 2 * math.pi * _phase;
      final len = i.isEven ? lenLong : lenShort;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final start = center + dir * (size.width * 0.16);
      canvas.drawLine(start, start + dir * len, paint);
    }

    final halo = Paint()..color = Colors.white.withValues(alpha: 0.14);
    canvas.drawCircle(center, size.width * 0.12, halo);
  }

  @override
  bool shouldRepaint(_SunburstPainter oldDelegate) =>
      oldDelegate._phase != _phase;
}

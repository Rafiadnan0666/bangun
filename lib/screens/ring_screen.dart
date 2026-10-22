import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/widgets.dart';
import '../data/alarm_repository.dart';
import '../data/models.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  BangunAlarm? _alarm;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Spotify handoff is automatic: once the ring UI is up and the alarm
    // audio session is warm, open the configured link inside Spotify so
    // the playlist/song/artist becomes the wake sound itself. The built-in
    // siren keeps ringing underneath until the gate is cleared.
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _autoSpotifyHandoff();
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Opens the alarm's pasted link best-first: item deep link
  /// (`spotify:playlist:…`), then the raw URL, then the bare app shell.
  Future<void> _openSpotify() async {
    final raw = _alarm?.spotifyUrl?.trim() ?? '';
    if (raw.isEmpty) return;
    final deep = spotifyDeepLink(raw);
    final candidates = [
      ?deep,
      raw,
      'spotify://',
    ];
    for (final candidate in candidates) {
      final uri = Uri.tryParse(candidate);
      if (uri == null) continue;
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (kDebugMode) debugPrint('SPOTIFY handoff: $candidate → $ok');
        if (ok) return;
      } on Exception {
        // No handler for this variant — try the next candidate.
      }
    }
  }

  bool _autoHandoffDone = false;

  Future<void> _autoSpotifyHandoff() async {
    if (_autoHandoffDone || !mounted) return;
    final alarm = _alarm ?? context.read<AlarmRepository>().byId(widget.alarmId);
    if (alarm == null || alarm.toneKind != ToneKind.spotify) return;
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
                onMath: () => _startChallenge(ChallengeKind.math),
                onScan: () => _startChallenge(ChallengeKind.scan),
                onSpotify: _openSpotify,
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
    required this.onMath,
    required this.onScan,
    required this.onSpotify,
  });

  final BangunAlarm? alarm;
  final VoidCallback onMath;
  final VoidCallback onScan;
  final VoidCallback onSpotify;

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
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onSpotify,
                icon: const Icon(Icons.music_note_rounded,
                    color: Bg.ink, size: 18),
                label: const Text(
                  'Open your Spotify queue',
                  style: TextStyle(
                    color: Bg.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
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

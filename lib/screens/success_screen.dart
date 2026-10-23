import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../data/models.dart';

/// Shown right after a gate is cleared: brief celebration, streak update,
/// then auto-return to the dashboard.
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({
    super.key,
    required this.kind,
    required this.streak,
    required this.totalWins,
    this.scannedLabel,
    this.isTrial = false,
  });

  final ChallengeKind kind;
  final String? scannedLabel;
  final int streak;
  final int totalWins;
  final bool isTrial;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confetti;
  late final List<_Crumb> _crumbs;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    HapticFeedback.mediumImpact();
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    final rng = math.Random();
    _crumbs = List.generate(
      36,
      (i) => _Crumb(
        x: rng.nextDouble(),
        delay: rng.nextDouble() * 0.5,
        fall: 0.9 + rng.nextDouble() * 0.6,
        drift: (rng.nextDouble() - 0.5) * 0.35,
        size: 5 + rng.nextDouble() * 6,
        round: rng.nextBool(),
        color: <Color>[
          Bg.coral,
          Bg.mint,
          Bg.sky,
          Bg.lemon,
          Bg.lilac,
          Bg.rose,
        ][rng.nextInt(6)],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 2900), () {
      if (!mounted) return;
      // A real alarm may have opened its ring screen on top of this
      // celebration. Never pop that screen: it is the only stop path.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final didScan = widget.kind == ChallengeKind.scan;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(gradient: Bg.ring),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.isTrial ? '🧪' : '🎉',
                    style: const TextStyle(fontSize: 66),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.isTrial ? 'Trial cleared!' : 'Challenge cleared!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      shadows: [
                        Shadow(color: Color(0x3D000000), blurRadius: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      widget.isTrial
                          ? 'Demo complete. Your real wake stats did not change.'
                          : 'You beat the gate. Have a good morning.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          CustomPaint(
            painter: _ConfettiPainter(_crumbs, _confetti.value),
            size: Size.infinite,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    didScan
                        ? '${targetEmoji(widget.scannedLabel ?? 'cup')} '
                              '${widget.scannedLabel ?? 'object'}'
                        : '🧮 math',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Bg.ink,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(width: 1, height: 24, color: Bg.hairline),
                  const SizedBox(width: 14),
                  const Text(
                    '🌟',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isTrial
                        ? 'trial · stats unchanged'
                        : 'streak ${widget.streak} · total ${widget.totalWins}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Bg.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Crumb {
  const _Crumb({
    required this.x,
    required this.delay,
    required this.fall,
    required this.drift,
    required this.size,
    required this.round,
    required this.color,
  });

  final double x;
  final double delay;
  final double fall;
  final double drift;
  final double size;
  final bool round;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this._crumbs, this._phase);

  final List<_Crumb> _crumbs;
  final double _phase;

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in _crumbs) {
      final t = (_phase * c.fall - c.delay) % 1.0;
      final dx = size.width * (c.x + c.drift * t);
      final dy = size.height * t;
      final s = c.size * (size.width / 400);
      final paint = Paint()..color = c.color;
      if (c.round) {
        canvas.drawCircle(Offset(dx, dy), s / 2, paint);
      } else {
        final r = math.pi * 2 * _phase;
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(r + c.x * 6);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.6),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate._phase != _phase;
}

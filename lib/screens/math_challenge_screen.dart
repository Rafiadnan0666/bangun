import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../core/widgets.dart';
import '../data/alarm_repository.dart';
import '../data/math_engine.dart';
import '../data/models.dart';
import 'success_screen.dart';

/// The math gate. The keypad is the only interactivity: no timers, no skip.
/// Puzzles are generated procedurally (see [MathEngine]) — fresh at every
/// ring, integer-safe, with a warm-up → brain-melt ramp.
class MathChallengeScreen extends StatefulWidget {
  const MathChallengeScreen({super.key, required this.alarm, this.chosenKind});

  final BangunAlarm alarm;

  /// Which gate the user picked when the alarm rang (math or scan).
  final ChallengeKind? chosenKind;

  @override
  State<MathChallengeScreen> createState() => _MathChallengeScreenState();
}

class _MathChallengeScreenState extends State<MathChallengeScreen> {
  late final int _total;
  late final List<MathPuzzle> _puzzles;
  int _index = 0;
  String _input = '';
  int _shakeTick = 0;
  bool _finishing = false;

  bool get _isTrial => widget.alarm.id == trialAlarmId;

  @override
  void initState() {
    super.initState();
    _total = widget.alarm.mathProblems.clamp(3, 7);
    final used = <String>{};
    _puzzles = List.generate(
      _total,
      (i) => MathEngine.generate(index: i, count: _total, exclude: used),
    );
    if (kDebugMode) {
      for (final (i, p) in _puzzles.indexed) {
        debugPrint('MATH[$i]: ${p.prompt} = ${p.answer}');
      }
    }
  }

  void _press(String d) {
    if (_finishing || _input.length >= 7) return;
    HapticFeedback.selectionClick();
    setState(() => _input += d);
  }

  void _backspace() {
    if (_finishing || _input.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  void _submit() {
    if (_finishing || _input.isEmpty) return;
    final got = int.tryParse(_input);
    final answer = _puzzles[_index].answer;
    if (got == answer) {
      HapticFeedback.mediumImpact();
      if (_index == _total - 1) {
        _finish();
      } else {
        setState(() {
          _index++;
          _input = '';
        });
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _shakeTick++;
        _input = '';
      });
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    final kind =
        widget.chosenKind ??
        (widget.alarm.challengeKind == ChallengeKind.scan
            ? ChallengeKind.scan
            : ChallengeKind.math);
    final repo = context.read<AlarmRepository>();
    await repo.completeRing(widget.alarm.id, kind);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: _isTrial ? null : const RouteSettings(name: '/gate-success'),
        builder: (_) => SuccessScreen(
          kind: kind,
          streak: repo.stats.currentStreak,
          totalWins: repo.stats.totalWins,
          isTrial: _isTrial,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warm = _puzzles[_index].tier == MathTier.warm;
    final sharp = _puzzles[_index].tier == MathTier.sharp;
    final tierLabel = warm ? 'warm-up' : (sharp ? 'sharp' : 'brain melt');
    final tierColor = warm ? Bg.mint : (sharp ? Bg.sky : Bg.plum);

    return PopScope(
      canPop: _isTrial,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) HapticFeedback.vibrate();
      },
      child: Scaffold(
        backgroundColor: Bg.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('🧮', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isTrial
                            ? 'Trial · problem ${_index + 1} of $_total'
                            : 'Problem ${_index + 1} of $_total',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: Bg.ink,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tierLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: tierColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < _total; i++) ...[
                      Container(
                        width: i == _index ? 26 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: i < _index
                              ? Bg.mint
                              : (i == _index ? Bg.lemon : Bg.hairline),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      if (i != _total - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const Spacer(),
                ShakeFx(
                  trigger: _shakeTick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 34,
                    ),
                    decoration: BoxDecoration(
                      color: Bg.card,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Bg.lilac.withValues(alpha: 0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _puzzles[_index].prompt,
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              color: Bg.ink,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(width: 22, height: 3, color: Bg.hairline),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 180,
                              child: Text(
                                _input.isEmpty ? '?' : _input,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: _input.isEmpty ? Bg.subFaint : Bg.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (!_isTrial)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '🔒 can\'t quit — wrong answer = fresh start on this problem',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: Bg.subFaint),
                    ),
                  ),
                const Spacer(),
                _Keypad(
                  input: _input,
                  onDigit: _press,
                  onBackspace: _backspace,
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.input,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
  });

  final String input;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  static Widget _cell(Widget child, VoidCallback onTap, {Color? bg}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: bg ?? Bg.card,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget digitRow(List<String> ds) => Row(
      children: [
        for (final d in ds)
          _cell(
            Text(
              d,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Bg.ink,
              ),
            ),
            () => onDigit(d),
          ),
      ],
    );

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.42,
      child: Column(
        children: [
          Expanded(child: digitRow(const ['1', '2', '3'])),
          Expanded(child: digitRow(const ['4', '5', '6'])),
          Expanded(child: digitRow(const ['7', '8', '9'])),
          Expanded(
            child: Row(
              children: [
                _cell(
                  const Text(
                    '⌫',
                    style: TextStyle(fontSize: 22, color: Bg.sub),
                  ),
                  onBackspace,
                  bg: Bg.cardSoft,
                ),
                _cell(
                  const Text(
                    '0',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Bg.ink,
                    ),
                  ),
                  () => onDigit('0'),
                ),
                _cell(
                  Text(
                    input.isEmpty ? '—' : '✓ done',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  () {
                    if (input.isNotEmpty) onSubmit();
                  },
                  bg: input.isEmpty ? Bg.subFaint : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

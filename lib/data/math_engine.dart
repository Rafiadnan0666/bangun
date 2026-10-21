/// Procedurally generated math gate.
///
/// Every puzzle is built fresh at ring time from a constrained grammar:
/// * integer-safe by construction — division always divides exactly and no
///   branch can produce a negative result,
/// * difficulty ramps across the alarm's problem count
///   (warm-up → sharp → brain-melt tiers),
/// * an exclusion set prevents the same prompt from repeating within a
///   session, so the gate can't be memorized.
library;

import 'dart:math';

enum MathTier { warm, sharp, brainMelt }

class MathPuzzle {
  const MathPuzzle({required this.prompt, required this.answer, required this.tier});

  final String prompt;
  final int answer;
  final MathTier tier;
}

class MathEngine {
  static final Random _rng = Random();

  /// Generates puzzle [index] of [count], avoiding prompts in [exclude].
  static MathPuzzle generate({
    required int index,
    required int count,
    Set<String>? exclude,
  }) {
    MathPuzzle? puzzle;
    for (var attempt = 0; attempt < 128; attempt++) {
      final p = _one(_tier(index, count));
      if (exclude == null || !exclude.contains(p.prompt)) {
        puzzle = p;
        break;
      }
    }
    puzzle ??= _one(_tier(index, count));
    exclude?.add(puzzle.prompt);
    return puzzle;
  }

  static int _iri(int min, int max) {
    assert(min <= max, 'range ($min, $max)');
    return _rng.nextInt(max - min + 1) + min;
  }

  static MathTier _tier(int index, int count) {
    final c = count <= 0 ? 1 : count;
    final rel = index.clamp(0, c);
    if (rel < c * 0.4) return MathTier.warm;
    if (rel < c * 0.72) return MathTier.sharp;
    return MathTier.brainMelt;
  }

  static MathPuzzle _one(MathTier tier) => switch (tier) {
    MathTier.warm => _warm(),
    MathTier.sharp => _sharp(),
    MathTier.brainMelt => _brainMelt(),
  };

  // ---- Tier 1 (warm-up): single-op mental math. ----
  static MathPuzzle _warm() {
    switch (_iri(0, 3)) {
      case 0:
        final a = _iri(4, 29);
        final b = _iri(4, 29);
        return MathPuzzle(prompt: '$a + $b', answer: a + b, tier: MathTier.warm);
      case 1:
        final a = _iri(17, 49);
        final b = _iri(4, a - 5);
        return MathPuzzle(prompt: '$a − $b', answer: a - b, tier: MathTier.warm);
      case 2:
        final a = _iri(3, 9);
        final b = _iri(3, 9);
        return MathPuzzle(prompt: '$a × $b', answer: a * b, tier: MathTier.warm);
      default:
        final b = _iri(2, 9);
        final q = _iri(2, 9);
        return MathPuzzle(prompt: '${b * q} ÷ $b', answer: q, tier: MathTier.warm);
    }
  }

  // ---- Tier 2 (sharp): two steps, brackets may appear. ----
  static MathPuzzle _sharp() {
    switch (_iri(0, 3)) {
      case 0:
        final a = _iri(3, 9);
        final b = _iri(3, 9);
        final c = _iri(2, 9);
        return MathPuzzle(
          prompt: '($a + $b) × $c',
          answer: (a + b) * c,
          tier: MathTier.sharp,
        );
      case 1:
        final a = _iri(3, 9);
        final b = _iri(3, 9);
        final c = _iri(5, 40);
        return MathPuzzle(
          prompt: '$a × $b + $c',
          answer: a * b + c,
          tier: MathTier.sharp,
        );
      case 2:
        final a = _iri(4, 12);
        final b = _iri(4, 12);
        final c = _iri(5, a * b - 5);
        return MathPuzzle(
          prompt: '$a × $b − $c',
          answer: a * b - c,
          tier: MathTier.sharp,
        );
      default:
        final c = _iri(2, 9);
        final q = _iri(3, 12);
        final sub = _iri(2, q - 1).clamp(1, q - 1);
        return MathPuzzle(
          prompt: '${c * q} ÷ $c + $sub',
          answer: q + sub,
          tier: MathTier.sharp,
        );
    }
  }

  // ---- Tier 3 (brain melt): three steps / nested precedence. ----
  static MathPuzzle _brainMelt() {
    switch (_iri(0, 3)) {
      case 0:
        final a = _iri(3, 9);
        final b = _iri(3, 9);
        final c = _iri(2, 5);
        final d = _iri(2, 5);
        // Order the two products so the difference is never negative
        // ((3 × 5) − (4 × 5) = −5 violated the integer-safe invariant).
        final left = a * b;
        final right = c * d;
        return left >= right
            ? MathPuzzle(
                prompt: '($a × $b) − ($c × $d)',
                answer: left - right,
                tier: MathTier.brainMelt,
              )
            : MathPuzzle(
                prompt: '($c × $d) − ($a × $b)',
                answer: right - left,
                tier: MathTier.brainMelt,
              );
      case 1:
        final a = _iri(3, 7);
        final b = _iri(3, 7);
        final c = _iri(2, 6);
        final d = _iri(2, (a + b) * c - 5);
        return MathPuzzle(
          prompt: '($a + $b) × $c − $d',
          answer: (a + b) * c - d,
          tier: MathTier.brainMelt,
        );
      case 2:
        final c = _iri(2, 9);
        final q = _iri(4, 9); // q * d >= 8 keeps the subtrahend range valid.
        final d = _iri(2, 7);
        final e = _iri(2, q * d - 5);
        return MathPuzzle(
          prompt: '(${c * q} ÷ $c) × $d − $e',
          answer: q * d - e,
          tier: MathTier.brainMelt,
        );
      default:
        final a = _iri(9, 20);
        final b = _iri(2, a - 3);
        final c = _iri(2, 9);
        final d = _iri(3, 12);
        return MathPuzzle(
          prompt: '($a − $b) × $c + $d',
          answer: (a - b) * c + d,
          tier: MathTier.brainMelt,
        );
    }
  }
}

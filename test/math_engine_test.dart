import 'package:bangun/data/math_engine.dart';
import 'package:bangun/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MathEngine', () {
    test('always yields a non-negative integer answer and non-empty prompt',
        () {
      for (var count = 3; count <= 7; count++) {
        for (var i = 0; i < 120; i++) {
          final p = MathEngine.generate(index: i, count: count);
          expect(p.prompt.isNotEmpty, isTrue, reason: 'prompt empty');
          expect(p.answer, isA<int>());
          expect(p.answer, greaterThanOrEqualTo(0));
        }
      }
    });

    test('ramps tiers across the problem count', () {
      final tiers = [
        for (var i = 0; i < 7; i++)
          MathEngine.generate(index: i, count: 7).tier,
      ];
      expect(tiers.take(3), everyElement(MathTier.warm));
      expect(tiers.sublist(3, 5), everyElement(MathTier.sharp));
      expect(tiers[5], anyOf(MathTier.sharp, MathTier.brainMelt));
      expect(tiers[6], MathTier.brainMelt);
    });

    test('excludes repeats within a session', () {
      final used = <String>{};
      for (var i = 0; i < 30; i++) {
        MathEngine.generate(index: i % 7, count: 7, exclude: used);
      }
      // All 30 prompts unique → the gate can't be memorized.
      expect(
        used.length,
        30,
        reason: 'generator spin-limited to 128 distinct tries per prompt',
      );
    });

    test('promotion of difficulty does not reach negatives in stress loop',
        () {
      // Brain-melt branch probes every mode repeatedly; deterministic checks
      // of the construction bounds (divisor chains etc) would be brittle —
      // instead assert the invariants over a wide sweep.
      for (var i = 0; i < 400; i++) {
        final p = MathEngine.generate(index: 6, count: 7);
        expect(p.answer, greaterThanOrEqualTo(0), reason: p.prompt);
        expect(p.tier, MathTier.brainMelt);
      }
    });
  });

  group('BangunAlarm.nextOccurrence', () {
    final from = DateTime(2026, 10, 20, 6, 0); // Tuesday

    test('once: later today stays today', () {
      final a = _alarm(hour: 7, minute: 30, mode: RepeatMode.once);
      expect(a.nextOccurrence(from), DateTime(2026, 10, 20, 7, 30));
    });

    test('once: same-day past time rolls to tomorrow', () {
      final a = _alarm(hour: 5, minute: 0, mode: RepeatMode.once);
      expect(a.nextOccurrence(from), DateTime(2026, 10, 21, 5, 0));
    });

    test('daily rolls every day', () {
      final a = _alarm(hour: 5, minute: 0, mode: RepeatMode.daily);
      expect(a.nextOccurrence(from), DateTime(2026, 10, 21, 5, 0));
    });

    test('weekly picks the selected weekday', () {
      final a = _alarm(
        hour: 8,
        minute: 15,
        mode: RepeatMode.weekly,
        days: const [1, 3, 5], // Mon Wed Fri
      );
      // Tue 06:00 → next matching is Wed 21st 08:15.
      expect(a.nextOccurrence(from), DateTime(2026, 10, 21, 8, 15));
    });

    test('weekly same-day already-passed skips to next selected day', () {
      final later = DateTime(2026, 10, 21, 9, 0); // Wednesday after 08:15
      final a = _alarm(
        hour: 8,
        minute: 15,
        mode: RepeatMode.weekly,
        days: const [1, 3, 5],
      );
      // Wed 08:15 passed → next is Fri 23rd 08:15.
      expect(a.nextOccurrence(later), DateTime(2026, 10, 23, 8, 15));
    });

    test('json round-trip keeps all fields', () {
      final a = BangunAlarm(
        id: 42,
        label: 'Morning run',
        hour: 6,
        minute: 5,
        repeatMode: RepeatMode.weekly,
        days: const [1, 4],
        enabled: false,
        challengeKind: ChallengeKind.scan,
        mathProblems: 5,
        scanTargets: const ['cup', 'book'],
        toneKind: ToneKind.spotify,
        tone: BuiltInTone.twinChime,
        spotifyUrl: 'https://open.spotify.com/track/x',
        volume: 0.9,
        createdAt: DateTime(2026, 1, 2),
      );
      final b = BangunAlarm.fromJson(a.toJson());
      expect(b.id, 42);
      expect(b.label, 'Morning run');
      expect(b.days, [1, 4]);
      expect(b.enabled, isFalse);
      expect(b.challengeKind, ChallengeKind.scan);
      expect(b.scanTargets, ['cup', 'book']);
      expect(b.toneKind, ToneKind.spotify);
      expect(b.spotifyUrl, 'https://open.spotify.com/track/x');
      expect(b.volume, 0.9);
      expect(b.createdAt, DateTime(2026, 1, 2));
    });

    test('stats streaks count consecutive days', () {
      final s = WakeStats();
      s.record(ChallengeKind.math);
      s.record(ChallengeKind.scan);
      expect(s.currentStreak, 1);
      expect(s.totalWins, 2);
      expect(s.mathWins, 1);
      expect(s.scanWins, 1);
    });
  });
}

BangunAlarm _alarm({
  required int hour,
  required int minute,
  required RepeatMode mode,
  List<int>? days,
}) {
  return BangunAlarm(
    id: 7,
    label: 'test',
    hour: hour,
    minute: minute,
    repeatMode: mode,
    days: days,
    scanTargets: const ['cup'],
    createdAt: DateTime(2026, 10, 1),
  );
}

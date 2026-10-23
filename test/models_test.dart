import 'package:bangun/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BangunAlarm problem count', () {
    Map<String, dynamic> json(int problems) => {
      'id': 1,
      'label': 'Test',
      'hour': 7,
      'minute': 0,
      'mathProblems': problems,
    };

    test('defaults to three problems', () {
      expect(BangunAlarm.fromJson(json(3)).mathProblems, 3);
    });

    test('normalizes old four-problem records to three', () {
      expect(BangunAlarm.fromJson(json(4)).mathProblems, 3);
    });

    test('keeps and normalizes the offered counts', () {
      expect(BangunAlarm.fromJson(json(5)).mathProblems, 5);
      expect(BangunAlarm.fromJson(json(6)).mathProblems, 5);
      expect(BangunAlarm.fromJson(json(7)).mathProblems, 7);
      expect(BangunAlarm.fromJson(json(99)).mathProblems, 7);
      expect(BangunAlarm.fromJson(json(0)).mathProblems, 3);
    });
  });

  group('missedOneShot', () {
    BangunAlarm alarm({
      required DateTime createdAt,
      RepeatMode repeatMode = RepeatMode.once,
      int hour = 7,
      bool enabled = true,
    }) => BangunAlarm(
      id: 1,
      label: 'Test',
      hour: hour,
      minute: 0,
      repeatMode: repeatMode,
      enabled: enabled,
      createdAt: createdAt,
    );

    final now = DateTime(2026, 10, 23, 9, 0);

    test('retires a one-shot whose slot passed while the app was dead', () {
      expect(
        alarm(createdAt: DateTime(2026, 10, 22, 9)).missedOneShot(now),
        isTrue,
      );
    });

    test('keeps a one-shot created after its clock time for tomorrow', () {
      expect(
        alarm(createdAt: DateTime(2026, 10, 23, 9)).missedOneShot(now),
        isFalse,
      );
    });

    test('keeps a one-shot later today and all repeating alarms', () {
      expect(
        alarm(
          createdAt: DateTime(2026, 10, 22, 9),
          hour: 10,
        ).missedOneShot(now),
        isFalse,
      );
      expect(
        alarm(
          createdAt: DateTime(2026, 10, 22, 9),
          repeatMode: RepeatMode.daily,
        ).missedOneShot(now),
        isFalse,
      );
    });

    test('ignores already disabled alarms', () {
      expect(
        alarm(
          createdAt: DateTime(2026, 10, 22, 9),
          enabled: false,
        ).missedOneShot(now),
        isFalse,
      );
    });
  });

  group('scan target migration', () {
    Map<String, dynamic> json({List<String>? targets, int? schema}) => {
      'id': 1,
      'label': 'Test',
      'hour': 7,
      'minute': 0,
      'scanTargets': targets,
      'scanTargetsSchema': schema,
    };

    test('missing targets use the broad common default', () {
      final target = BangunAlarm.fromJson(json()).scanTargets;
      expect(target, kDefaultScanTargets);
    });

    test('old cup-only records expand once to the default pool', () {
      final target = BangunAlarm.fromJson(json(targets: ['cup'])).scanTargets;
      expect(target, kDefaultScanTargets);
    });

    test('new cup-only records keep the deliberate choice', () {
      final target = BangunAlarm.fromJson(
        json(targets: ['cup'], schema: kScanTargetsSchema),
      ).scanTargets;
      expect(target, ['cup']);
    });

    test('records write the schema version', () {
      final record = BangunAlarm.fromJson(
        json(targets: ['book'], schema: kScanTargetsSchema),
      );
      expect(record.toJson()['scanTargetsSchema'], kScanTargetsSchema);
    });
  });

  group('scan challenge label', () {
    BangunAlarm alarm(List<String> targets) => BangunAlarm(
      id: 1,
      label: 'Test',
      hour: 7,
      minute: 0,
      challengeKind: ChallengeKind.scan,
      scanTargets: targets,
      createdAt: DateTime(2026, 10, 23),
    );

    test('names a single target but hides a randomized pool', () {
      expect(alarm(['cup']).challengeLabel(), contains('cup'));
      expect(
        alarm(kDefaultScanTargets).challengeLabel(),
        contains('random object'),
      );
    });
  });
}

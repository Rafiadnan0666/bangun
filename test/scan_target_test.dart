import 'package:bangun/core/format.dart';
import 'package:bangun/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scan target pools', () {
    test('default pool is common and fully easy', () {
      expect(kDefaultScanTargets, containsAll(['glass', 'screen', 'book']));
      expect(kDefaultScanTargets, contains('cell phone'));
      expect(kDefaultScanTargets.every(kEasyScanTargets.contains), isTrue);
    });

    test('trial pool is common and fully easy', () {
      expect(kTrialScanTargets, containsAll(['glass', 'screen']));
      expect(kTrialScanTargets.every(kEasyScanTargets.contains), isTrue);
    });

    test('every default target is selectable in the editor', () {
      for (final target in kDefaultScanTargets) {
        expect(kPickableTargets, contains(target));
      }
    });
  });

  group('pickScanTarget', () {
    test('trial runs randomize across the trial pool', () {
      final picks = <String>{};
      for (var i = 0; i < 80; i++) {
        picks.add(pickScanTarget(kTrialScanTargets, isTrial: true));
      }
      expect(picks.length, greaterThan(1));
      expect(kTrialScanTargets.toSet().containsAll(picks), isTrue);
    });

    test('a single-item trial pool stays deterministic', () {
      expect(pickScanTarget(['cup'], isTrial: true), 'cup');
    });

    test('rings randomize among multiple easy objects', () {
      final pool = ['cup', 'book', 'cell phone', 'glass'];
      final picks = <String>{};
      for (var i = 0; i < 80; i++) {
        picks.add(pickScanTarget(pool));
      }
      expect(picks.length, greaterThan(1));
      expect(pool.toSet().containsAll(picks), isTrue);
    });

    test('rings prefer the easiest configured object', () {
      for (var i = 0; i < 24; i++) {
        final pick = pickScanTarget(['scissors', 'cup', 'toothbrush']);
        expect(pick, 'cup');
      }
    });

    test('rings fall back to the full pool when nothing easy exists', () {
      final hard = ['scissors', 'toothbrush', 'hair drier'];
      for (var i = 0; i < 24; i++) {
        expect(hard.contains(pickScanTarget(hard)), isTrue);
      }
    });

    test('empty pool uses the randomized default pool', () {
      final picks = <String>{};
      for (var i = 0; i < 80; i++) {
        picks.add(pickScanTarget(const []));
      }
      expect(kDefaultScanTargets.toSet().containsAll(picks), isTrue);
      expect(picks.length, greaterThan(1));
    });
  });

  group('acceptedScanLabels', () {
    test('shape-confusable labels count toward a cup', () {
      final accepted = acceptedScanLabels('cup');
      for (final label in ['cup', 'wine glass', 'bottle']) {
        expect(accepted.contains(label), isTrue, reason: 'cup -> $label');
      }
      // Unrelated labels must not sneak in.
      expect(accepted.contains('person'), isFalse);
      expect(accepted.contains('scissors'), isFalse);
    });

    test('a glass target accepts cup, wine glass, and bottle', () {
      final accepted = acceptedScanLabels('glass');
      expect(accepted, containsAll(['cup', 'wine glass', 'bottle']));
      expect(accepted.contains('book'), isFalse);
    });

    test('a screen target accepts tv, laptop, and phone', () {
      final accepted = acceptedScanLabels('screen');
      expect(accepted, containsAll(['tv', 'laptop', 'cell phone']));
      expect(accepted.contains('glass'), isFalse);
    });

    test('unknown target degrades to itself only', () {
      expect(acceptedScanLabels('person'), ['person']);
    });
  });

  group('targetEmoji', () {
    test('composite targets inherit a familiar emoji', () {
      expect(targetEmoji('glass'), targetEmoji('wine glass'));
      expect(targetEmoji('screen'), targetEmoji('tv'));
    });
  });
}

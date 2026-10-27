import 'dart:io';

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

  group('full COCO coverage', () {
    test('all 80 named COCO classes are pickable', () {
      expect(kCocoScanTargets, hasLength(80));
      expect(kCocoScanTargets.toSet(), hasLength(80));
      expect(kPickableTargets, containsAll(kCocoScanTargets));
      expect(kPickableTargets, containsAll(['glass', 'screen']));
      expect(kPickableTargets, hasLength(82));
      expect(kPickableTargets, isNot(contains('???')));
    });

    test('the bundled label asset matches the pickable COCO classes', () {
      final raw = File('assets/models/labels.txt').readAsStringSync();
      final labels = raw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .where((line) => line != '???' && line != 'unknown')
          .toList(growable: false);
      expect(labels, kCocoScanTargets);
    });

    test('every pickable target has a real emoji', () {
      for (final target in kPickableTargets) {
        expect(
          targetEmoji(target),
          isNot('🎯'),
          reason: 'missing emoji for $target',
        );
      }
    });

    test('object-family groups cover every target exactly once', () {
      final families = kTargetGroups.where(
        (group) => group.name != 'Common' && group.name != 'All',
      );
      final covered = <String>[for (final group in families) ...group.targets];
      expect(covered.toSet(), kPickableTargets.toSet());
      expect(covered.length, covered.toSet().length);
    });

    test('group lookup falls back safely', () {
      expect(scanTargetsForGroup('Food'), contains('cake'));
      expect(scanTargetsForGroup('Animals'), contains('zebra'));
      expect(scanTargetsForGroup('nope'), kDefaultScanTargets);
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

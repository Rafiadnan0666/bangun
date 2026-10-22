import 'package:bangun/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickScanTarget', () {
    test('trial always asks for the cup', () {
      expect(
        pickScanTarget(['cup'], isTrial: true),
        'cup',
      );
      expect(
        // Trial pools without a cup fall back to the first configured item.
        pickScanTarget(['bottle', 'scissors'], isTrial: true),
        'bottle',
      );
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

    test('empty pool degrades to cup', () {
      expect(pickScanTarget(const []), 'cup');
    });
  });

  group('acceptedScanLabels', () {
    test('shape-confusable labels count toward a cup', () {
      final accepted = acceptedScanLabels('cup');
      for (final label in ['cup', 'wine glass', 'bottle']) {
        expect(accepted.contains(label), isTrue, reason: 'cup ↔ $label');
      }
      // Unrelated labels must not sneak in.
      expect(accepted.contains('person'), isFalse);
      expect(accepted.contains('scissors'), isFalse);
    });

    test('unknown target degrades to itself only', () {
      expect(acceptedScanLabels('person'), ['person']);
    });

    test('pool acceptance unions every configured target', () {
      final accepted = acceptedScanLabelSet(['scissors', 'mouse']);
      // mouse pulls remote in; scissors pulls nothing foreign.
      expect(accepted, containsAll(['scissors', 'mouse', 'remote']));
      expect(accepted, isNot(contains('cup')));
    });
  });
}

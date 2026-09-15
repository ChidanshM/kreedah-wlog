import 'package:flutter_test/flutter_test.dart';
import 'package:workout_log/util.dart';

/// Conversion, rounding and the small shared helpers.
///
/// These are pure functions with no database and no screen behind them, and
/// they are where every arithmetic mistake in this application has lived. A
/// wrong answer here is invisible until it has been multiplied by a rep
/// count and summed across a year.
void main() {
  group('weight conversion', () {
    test('a pound is exactly 0.45359237 kg', () {
      expect(kLbToKg, 0.45359237);
      expect(toKg(1, 'lb'), closeTo(0.45359237, 1e-12));
    });

    test('kilograms pass through untouched', () {
      expect(toKg(32.5, 'kg'), 32.5);
      expect(toKg(0, 'kg'), 0);
    });

    test('toKg does not round', () {
      // The mistake this guards against: rounding here to two decimals and
      // then multiplying by the rep count multiplies the error too.
      final kg = toKg(17.5, 'lb');
      expect(kg, isNot(7.94));
      expect(kg, closeTo(7.93786, 1e-5));
    });

    test('a set of twelve at 17.5 lb is 95.25 kg, not 95.28', () {
      // Multiplying a stored weight by the reps must agree with converting
      // the whole set at once. They did not when the weight was pre-rounded.
      final perSet = toKg(17.5, 'lb') * 12;
      final wholeSet = toKg(17.5 * 12, 'lb');
      expect(perSet, closeTo(wholeSet, 1e-9));
      expect(double.parse(perSet.toStringAsFixed(2)), 95.25);
    });

    test('volume divided by reps returns the stored weight', () {
      final kg = toKg(45, 'lb');
      final volume = kg * 8;
      expect(volume / 8, closeTo(kg, 1e-12));
    });

    test('fromKg rounds for display and returns what was typed', () {
      expect(fromKg(toKg(17.5, 'lb'), 'lb'), 17.5);
      expect(fromKg(toKg(45, 'lb'), 'lb'), 45);
      expect(fromKg(32.5, 'kg'), 32.5);
    });

    test('converting between the same unit changes nothing', () {
      expect(convertWeight(17.5, 'lb', 'lb'), 17.5);
      expect(convertWeight(32.5, 'kg', 'kg'), 32.5);
    });
  });

  group('muscle codes', () {
    test('every code named by a body part is a real code', () {
      for (final entry in BodyPart.muscles.entries) {
        for (final code in entry.value) {
          expect(muscleOrder, contains(code),
              reason: '${entry.key} names $code, which is not a muscle code');
        }
      }
    });

    test('every code belongs to exactly one body part', () {
      for (final code in muscleOrder) {
        final parts =
            BodyPart.muscles.entries.where((e) => e.value.contains(code));
        expect(parts.length, 1,
            reason: '$code belongs to ${parts.length} body parts');
      }
    });

    test('every code has a readable label', () {
      for (final code in muscleOrder) {
        expect(muscleLabels.containsKey(code), isTrue,
            reason: '$code has no label');
      }
    });

    test('sorting runs head to toe, not alphabetically', () {
      expect(sortMuscles(['CALVES', 'CHEST', 'TRAPS']),
          ['TRAPS', 'CHEST', 'CALVES']);
    });

    test('an unknown code sorts last rather than being dropped', () {
      expect(sortMuscles(['SOMETHING_NEW', 'CHEST']),
          ['CHEST', 'SOMETHING_NEW']);
    });
  });

  group('set types', () {
    test('the three known types are the whole set', () {
      expect(SetType.all,
          containsAll([SetType.reps, SetType.time, SetType.distance]));
    });

    test('each has a label', () {
      for (final t in SetType.all) {
        expect(SetType.label(t), isNotEmpty);
      }
    });
  });

  group('dates', () {
    test('ymd is zero padded', () {
      expect(ymd(DateTime(2026, 1, 5)), '2026-01-05');
      expect(ymd(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('a timestamp round-trips', () {
      final d = DateTime(2026, 9, 15, 18, 4, 11);
      final parsed = parseIso(isoLocal(d));
      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 9);
      expect(parsed.day, 15);
      expect(parsed.hour, 18);
      expect(parsed.minute, 4);
    });

    test('parsing survives rubbish', () {
      expect(parseIso(null), isNull);
      expect(parseIso(''), isNull);
      expect(parseIso('not a date'), isNull);
    });
  });
}

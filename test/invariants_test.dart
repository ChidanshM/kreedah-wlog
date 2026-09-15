import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_log/util.dart';

/// Things that must stay true of the codebase itself.
///
/// These are not tests of behaviour. They are checks that two places which
/// have to agree still do, because every silent data loss in this
/// application came from two hand-written lists drifting apart: a muscle
/// code invented that the data never had, and tables added to the schema
/// that nobody added to the backup.
///
/// They read the real files rather than anything mocked, so drift fails the
/// build rather than being noticed months later.
void main() {
  late List<Map<String, dynamic>> library;

  setUpAll(() {
    final raw = File('assets/exercises.json').readAsStringSync();
    library = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  });

  group('the muscle codes this app knows match the data', () {
    test('every code in the data is one this app orders and labels', () {
      final inData = <String>{};
      for (final e in library) {
        inData.addAll(((e['p'] as List?) ?? const []).cast<String>());
        inData.addAll(((e['s'] as List?) ?? const []).cast<String>());
      }

      final unknown = inData.difference(muscleOrder.toSet());
      expect(unknown, isEmpty,
          reason: 'the data uses codes this app does not know: $unknown');
    });

    test('every code this app knows appears in the data', () {
      // A code here that nothing can ever set is a region drawn permanently
      // grey, which reads as untrained rather than as unrecordable.
      final inData = <String>{};
      for (final e in library) {
        inData.addAll(((e['p'] as List?) ?? const []).cast<String>());
        inData.addAll(((e['s'] as List?) ?? const []).cast<String>());
      }

      final invented = muscleOrder.toSet().difference(inData);
      expect(invented, isEmpty,
          reason: 'this app names codes the data never uses: $invented');
    });

    test('no source file refers to a muscle code that does not exist', () {
      // This is what would have caught the track session being registered
      // against QUADRICEPS, a code that has never existed: it counted for
      // nothing on the body map while everything beside it counted.
      final known = muscleOrder.toSet();
      final suspect = RegExp(r"'([A-Z][A-Z_]{3,})'");
      final offenders = <String, Set<String>>{};

      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        for (final m in suspect.allMatches(text)) {
          final word = m.group(1)!;
          // Only judge words that look like muscle codes: ones that are a
          // near miss for something known, rather than every constant in
          // the file.
          final nearMiss = known.any((k) =>
              k != word && (k.startsWith(word) || word.startsWith(k)));
          if (nearMiss && !known.contains(word)) {
            offenders.putIfAbsent(f.path, () => {}).add(word);
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'these look like muscle codes but are not: $offenders');
    });
  });

  group('the exercise data is shaped as expected', () {
    test('every entry has a key and a name', () {
      for (final e in library) {
        expect(e['k'], isA<String>());
        expect(e['n'], isA<String>());
        expect((e['k'] as String), isNotEmpty);
      }
    });

    test('keys are unique', () {
      final keys = library.map((e) => e['k'] as String).toList();
      expect(keys.length, keys.toSet().length,
          reason: 'the data holds duplicate exercise keys');
    });

    test('a key is CATEGORY/NAME', () {
      for (final e in library) {
        expect((e['k'] as String), contains('/'),
            reason: '${e['k']} is not in the expected form');
      }
    });
  });

  group('equipment kinds', () {
    test('every kind offered has a tag list', () {
      for (final k in EquipKind.all) {
        expect(EquipKind.tags.containsKey(k), isTrue,
            reason: '$k is offered but maps to no equipment codes');
      }
    });

    test('no equipment code belongs to two kinds', () {
      // A code in two kinds would offer the same weights twice, and make
      // which chips appear depend on map ordering.
      final seen = <String, String>{};
      for (final entry in EquipKind.tags.entries) {
        for (final code in entry.value) {
          expect(seen.containsKey(code), isFalse,
              reason: '$code is under both ${seen[code]} and ${entry.key}');
          seen[code] = entry.key;
        }
      }
    });

    test('an exercise is matched to the kinds that could load it', () {
      expect(EquipKind.kindsFor(['DUMBBELL']), [EquipKind.dumbbell]);
      expect(EquipKind.kindsFor(['CABLE_MACHINE']), [EquipKind.machine]);
      expect(EquipKind.kindsFor(['BODY_ONLY']), isEmpty);
    });

    test('every equipment code named is one the data actually uses', () {
      final inData = <String>{};
      for (final e in library) {
        inData.addAll(((e['e'] as List?) ?? const []).cast<String>());
      }
      final invented = <String>{};
      for (final codes in EquipKind.tags.values) {
        for (final c in codes) {
          if (!inData.contains(c)) invented.add(c);
        }
      }
      expect(invented, isEmpty,
          reason: 'these equipment codes appear nowhere in the data: '
              '$invented');
    });
  });
}

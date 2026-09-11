import 'dart:convert';
import 'package:flutter/services.dart';
import 'db.dart';

/// One exercise from the Garmin database (or a user-created one).
class Exercise {
  final String key; // CATEGORY/NAME_GARMIN, stable id
  final String name;
  final String category; // Garmin category code
  final String garminName; // Garmin exercise code
  final List<String> primary; // primary muscles
  final List<String> secondary; // secondary muscles
  final List<String> equipment;
  final bool custom;

  const Exercise({
    required this.key,
    required this.name,
    this.category = '',
    this.garminName = '',
    this.primary = const [],
    this.secondary = const [],
    this.equipment = const [],
    this.custom = false,
  });

  factory Exercise.fromAsset(Map<String, dynamic> j) => Exercise(
        key: j['k'] as String,
        name: j['n'] as String,
        category: (j['c'] ?? '') as String,
        garminName: (j['g'] ?? '') as String,
        primary: List<String>.from(j['p'] as List? ?? const []),
        secondary: List<String>.from(j['s'] as List? ?? const []),
        equipment: List<String>.from(j['e'] as List? ?? const []),
      );

  factory Exercise.fromRow(Map<String, dynamic> r) => Exercise(
        key: r['k'] as String,
        name: r['n'] as String,
        category: (r['c'] ?? '') as String,
        garminName: (r['g'] ?? '') as String,
        primary: _split(r['p']),
        secondary: _split(r['s']),
        equipment: _split(r['e']),
        custom: true,
      );

  static List<String> _split(Object? v) {
    final s = (v ?? '') as String;
    if (s.isEmpty) return const [];
    return s.split(',').where((e) => e.isNotEmpty).toList();
  }

  /// "Chest, Triceps" — primary muscles, human readable.
  String get primaryLabel => primary.map(pretty2).join(', ');
  String get equipmentLabel => equipment.map(pretty2).join(', ');

  static String pretty2(String code) {
    final words = code.toLowerCase().split('_');
    final head = words.first;
    final rest = words.skip(1).join(' ');
    final h = head.isEmpty ? head : head[0].toUpperCase() + head.substring(1);
    return rest.isEmpty ? h : '$h $rest';
  }
}

/// In-memory index over the whole exercise catalogue.
class ExerciseLibrary {
  static List<Exercise> all = const [];
  static Map<String, Exercise> byKey = const {};
  static Set<String> pinned = {};

  /// Every equipment / muscle code that actually occurs, for filter chips.
  static List<String> equipmentCodes = const [];
  static List<String> muscleCodes = const [];

  static Future<void> load() async {
    final raw = await rootBundle.loadString('assets/exercises.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final items = list.map(Exercise.fromAsset).toList();

    // Merge in anything the user added by hand.
    final customRows = await Db.customExercises();
    items.addAll(customRows.map(Exercise.fromRow));

    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    all = items;
    byKey = {for (final e in items) e.key: e};

    final eq = <String>{};
    final mu = <String>{};
    for (final e in items) {
      eq.addAll(e.equipment);
      mu.addAll(e.primary);
      mu.addAll(e.secondary);
    }
    equipmentCodes = eq.toList()..sort();
    muscleCodes = mu.toList()..sort();

    pinned = (await Db.pinnedKeys()).toSet();
  }

  static Future<void> reloadPinned() async {
    pinned = (await Db.pinnedKeys()).toSet();
  }

  /// How many entries match the filters alone, ignoring any typed text. The
  /// search field says this rather than the library total, since a filtered
  /// list of twelve should not claim to hold fifteen hundred.
  static int countMatching({
    Set<String> equipment = const {},
    Set<String> muscles = const {},
    bool onlyCustom = false,
  }) =>
      search('',
              equipment: equipment,
              muscles: muscles,
              onlyCustom: onlyCustom,
              limit: 1 << 30)
          .length;

  static Exercise? get(String key) => byKey[key];

  static String nameOf(String key, [String fallback = '']) =>
      byKey[key]?.name ?? (fallback.isEmpty ? key : fallback);

  /// Search + filter. Pinned exercises float to the top.
  ///
  /// [equipment] and [muscles] are OR-within / AND-across: an exercise must
  /// match at least one of the selected equipment codes AND at least one of
  /// the selected muscle codes.
  static List<Exercise> search(
    String query, {
    Set<String> equipment = const {},
    Set<String> muscles = const {},
    bool onlyCustom = false,
    int limit = 400,
  }) {
    final q = query.trim().toLowerCase();
    final terms = q.isEmpty ? const <String>[] : q.split(RegExp(r'\s+'));

    final results = <Exercise>[];
    for (final e in all) {
      if (onlyCustom && !e.custom) continue;
      if (equipment.isNotEmpty && !e.equipment.any(equipment.contains)) {
        continue;
      }
      if (muscles.isNotEmpty &&
          !e.primary.any(muscles.contains) &&
          !e.secondary.any(muscles.contains)) {
        continue;
      }
      if (terms.isNotEmpty) {
        final hay = e.name.toLowerCase();
        if (!terms.every(hay.contains)) continue;
      }
      results.add(e);
    }

    results.sort((a, b) {
      final pa = pinned.contains(a.key) ? 0 : 1;
      final pb = pinned.contains(b.key) ? 0 : 1;
      if (pa != pb) return pa - pb;
      if (terms.isNotEmpty) {
        // Prefer names that start with the query.
        final sa = a.name.toLowerCase().startsWith(terms.first) ? 0 : 1;
        final sb = b.name.toLowerCase().startsWith(terms.first) ? 0 : 1;
        if (sa != sb) return sa - sb;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return results.length > limit ? results.sublist(0, limit) : results;
  }
}

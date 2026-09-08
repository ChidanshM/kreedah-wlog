import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'library.dart';
import 'util.dart';

/// Export and backup.
///
/// Two files, because they do different jobs:
///   * a long-format CSV, one row per confirmed set, for analysis
///   * a JSON backup that restores the database exactly
class Exporter {
  /// Where files land. On Android this is
  /// /Android/data/<package>/files/exports, which a file manager can open
  /// and which needs no storage permission.
  static Future<Directory> exportDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static const csvHeader = [
    'workout_id',
    'workout_start',
    'workout_date',
    'weekday',
    'routine_name',
    'routine_id',
    'workout_notes',
    'exercise_order',
    'exercise_name',
    'garmin_category',
    'garmin_name',
    'equipment',
    'primary_muscles',
    'exercise_notes',
    'set_number',
    'set_type',
    'side',
    'entry_unit',
    'weight_entered',
    'weight_lb',
    'weight_kg',
    'reps',
    'duration_sec',
    'distance_steps',
    'rpe',
    'set_volume_kg',
    'set_timestamp',
  ];

  static String _cell(Object? v) {
    if (v == null) return '';
    final s = v is double ? num2(v) : v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static Future<String> buildCsv() async {
    final rows = await Db.exportRows();
    final buf = StringBuffer()..writeln(csvHeader.join(','));

    for (final r in rows) {
      final started = parseIso(r['workout_start'] as String?);
      final ex = ExerciseLibrary.get(r['ex_key'] as String);
      final unit = (r['entry_unit'] ?? 'kg') as String;
      final entered = (r['weight_entered'] as num?)?.toDouble();

      // weight_lb is populated only for rows that were actually entered in lb.
      final lb = unit == 'lb' ? entered : null;

      final line = <Object?>[
        r['workout_id'],
        r['workout_start'],
        started == null ? '' : ymd(started),
        started == null ? '' : weekdayName(started),
        r['routine_name'],
        r['routine_id'],
        r['workout_notes'],
        r['exercise_order'],
        r['exercise_name'],
        ex?.category ?? '',
        ex?.garminName ?? '',
        ex?.equipment.join('|') ?? '',
        ex?.primary.join('|') ?? '',
        r['exercise_notes'],
        r['set_number'],
        r['set_type'],
        r['side'],
        unit,
        entered,
        lb,
        (r['weight_kg'] as num?)?.toDouble(),
        r['reps'],
        r['duration_sec'],
        r['distance_steps'],
        (r['rpe'] as num?)?.toDouble(),
        (r['set_volume_kg'] as num?)?.toDouble(),
        r['set_timestamp'],
      ];
      buf.writeln(line.map(_cell).join(','));
    }
    return buf.toString();
  }

  static Future<String> buildJson() async {
    const tables = [
      'routines',
      'routine_exercises',
      'workouts',
      'workout_exercises',
      'sets',
      'equipment',
      'custom_exercises',
      'pinned',
      'settings',
    ];
    final data = <String, dynamic>{
      'format': 'workout_log_backup',
      'version': 1,
      'exported_at': isoLocal(DateTime.now()),
    };
    for (final t in tables) {
      data[t] = await Db.dumpTable(t);
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Writes both files and returns their paths.
  static Future<List<File>> exportAll() async {
    final dir = await exportDir();
    final now = DateTime.now();
    final stamp =
        '${ymd(now)}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

    final csv = File('${dir.path}/workout_sets_$stamp.csv');
    await csv.writeAsString(await buildCsv());

    final json = File('${dir.path}/backup_$stamp.json');
    await json.writeAsString(await buildJson());

    return [csv, json];
  }

  /// Backup files sitting in the export folder, newest first.
  static Future<List<File>> availableBackups() async {
    final dir = await exportDir();
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static Future<void> restoreFrom(File file) async {
    final raw = await file.readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['format'] != 'workout_log_backup') {
      throw const FormatException('Not a workout log backup file.');
    }
    await Db.restore(data);
  }
}

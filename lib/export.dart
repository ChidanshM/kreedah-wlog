import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'library.dart';
import 'saf.dart';
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

  static Future<({String csv, int rows})> buildCsv({
    String? fromIso,
    String? toIso,
    List<int>? routineIds,
  }) async {
    final rows = await Db.exportRows(
        fromIso: fromIso, toIso: toIso, routineIds: routineIds);
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
    return (csv: buf.toString(), rows: rows.length);
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

  /// Writes the chosen files to wherever the user picked, falling back to the
  /// app's own folder when no folder has been chosen.
  ///
  /// Filters narrow the spreadsheet only. The backup is always complete,
  /// because a partial one would restore quietly and leave gaps with nothing
  /// to announce them.
  static Future<({List<String> names, String where, bool reachable, int rows})>
      exportAll({
    bool csv = true,
    bool backup = true,
    DateTime? from,
    DateTime? to,
    List<int>? routineIds,
  }) async {
    final now = DateTime.now();
    final stamp =
        '${ymd(now)}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final narrowed =
        from != null || to != null || (routineIds?.isNotEmpty ?? false);
    final csvName =
        'workout_sets_$stamp${narrowed ? '_selection' : ''}.csv';
    final jsonName = 'backup_$stamp.json';

    final files = <({String name, String mime, String body})>[];
    var rowCount = 0;

    if (csv) {
      final built = await buildCsv(
        fromIso: from == null ? null : isoLocal(from),
        toIso: to == null ? null : isoLocal(to),
        routineIds: routineIds,
      );
      rowCount = built.rows;
      files.add((name: csvName, mime: 'text/csv', body: built.csv));
    }
    if (backup) {
      files.add((
        name: jsonName,
        mime: 'application/json',
        body: await buildJson()
      ));
    }

    final tree = await Db.setting(exportTreeKey);
    if (await Saf.hasAccess(tree)) {
      for (final f in files) {
        await Saf.writeFile(
            tree: tree!, name: f.name, mime: f.mime, content: f.body);
      }
      return (
        names: files.map((f) => f.name).toList(),
        where: await Saf.folderName(tree!),
        reachable: true,
        rows: rowCount,
      );
    }

    final dir = await exportDir();
    for (final f in files) {
      await File('${dir.path}/${f.name}').writeAsString(f.body);
    }
    return (
      names: files.map((f) => f.name).toList(),
      where: dir.path,
      reachable: false,
      rows: rowCount,
    );
  }

  /// Backups available to restore from, newest first.
  static Future<List<({String name, String ref})>> availableBackups() async {
    final all = await _jsonFiles();
    return all.where((f) => f.name.startsWith('backup')).toList();
  }

  /// [ref] is either a document URI from the chosen folder or a file path.
  static Future<void> restoreFrom(String ref) async {
    final raw = ref.startsWith('content://')
        ? await Saf.readFile(ref)
        : await File(ref).readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['format'] != 'workout_log_backup') {
      throw const FormatException('Not a workout log backup file.');
    }
    await Db.restore(data);
  }

  /// One file per session, in the shape the platform merges with Garmin.
  ///
  /// Carries only what the phone observed. Heart rate, the time each set
  /// took and the rest actually taken are absent rather than null: the watch
  /// knows them and this does not, and a null would say "we tried and
  /// failed" where nothing was attempted.
  ///
  /// Every confirmed set keeps the moment it was logged. That timestamp is
  /// what the merge joins on, since matching by position breaks the moment
  /// the two disagree about how many sets there were, and one mismatch
  /// shifts everything after it.
  static Future<Map<String, dynamic>> buildSessionJson(int workoutId) async {
    final w = await Db.workout(workoutId);
    if (w == null) throw StateError('No session $workoutId');

    final started = parseIso(w['started_at'] as String?);
    final ended = parseIso(w['ended_at'] as String?);
    final summary = await Db.workoutSummary(workoutId);
    final exercises = await Db.workoutExercises(workoutId);

    final out = <String, dynamic>{};
    var order = 1;

    for (final e in exercises) {
      final sets = await Db.setsFor(e['id'] as int);
      final done = sets.where((s) => (s['done'] as int) == 1).toList();
      if (done.isEmpty) continue;

      final unilateral = (e['unilateral'] as int) == 1;
      final unit = e['unit'] as String;
      final byNumber = <String, dynamic>{};

      for (final s in done) {
        final side = s['side'] as String;
        final n = s['set_number'];
        final label = unilateral && side != 'both'
            ? 'Set $n - ${side == 'R' ? 'right' : 'left'} arm'
            : 'Set $n';

        final kg = (s['weight_kg'] as num?)?.toDouble();
        final volKg = (s['volume_kg'] as num?)?.toDouble() ?? 0;

        byNumber[label] = {
          'weight': s['weight_entered'],
          'unit': unit == 'lb' ? 'lbs' : 'kgs',
          if (s['reps'] != null) 'reps': s['reps'],
          if (s['duration_sec'] != null) 'duration_sec': s['duration_sec'],
          if (s['distance_m'] != null) 'distance_m': s['distance_m'],
          // Both, always. Kilograms are what the app adds up; pounds keep
          // these files comparable with logs kept before it existed.
          'volume_kg': volKg,
          'volume_lb': double.parse(fromKg(volKg, 'lb').toStringAsFixed(2)),
          if (s['rpe'] != null) 'RPE': s['rpe'],
          if (kg != null) 'weight_kg': kg,
          'logged_at': s['ts'],
        };
      }

      final notes = (e['notes'] as String?) ?? '';
      out['Exercise_${order.toString().padLeft(2, '0')}'] = {
        'Name': e['ex_name'],
        'ex_key': e['ex_key'],
        'set_type': e['set_type'],
        'unilateral': unilateral,
        'Sets': byNumber,
        'Notes': notes.isEmpty ? <String>[] : [notes],
      };
      order++;
    }

    final comments = (w['notes'] as String?) ?? '';

    return {
      'format': 'workout_log_session',
      'version': 1,
      'workout_stats': {
        'name': _sessionFileStem(w),
        'date': started == null ? null : ymd(started).replaceAll('-', ''),
        'routine_id': w['routine_id'],
        'routine_name': w['routine_name'],
        'started_at': w['started_at'],
        'ended_at': w['ended_at'],
        'time_known': (w['time_known'] as int? ?? 1) == 1,
        if (started != null && ended != null)
          'Timing': {
            // Wall clock only. The split between working and resting comes
            // from the watch, which is the only thing that knows it.
            'Total_Time': ended.difference(started).inSeconds,
          },
        'Workout_Details': {
          'Total_Reps': summary['reps'],
          'Total_Sets': summary['sets'],
          'Volume_kg': summary['volume'],
          'Volume_lb': double.parse(
              fromKg((summary['volume'] as num).toDouble(), 'lb')
                  .toStringAsFixed(2)),
        },
      },
      'workout_routine': out,
      'comments': comments.isEmpty ? <String>[] : [comments],
    };
  }

  /// strnth-20251218-r_u_002_b, or the routine name when there is no id.
  static String _sessionFileStem(Map<String, dynamic> w) {
    final started = parseIso(w['started_at'] as String?);
    final date = started == null ? 'undated' : ymd(started).replaceAll('-', '');
    final slug = (w['routine_name'] as String)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'strnth-$date-$slug';
  }

  /// Write one file per session over the chosen span.
  static Future<({int files, String where, bool reachable})> exportSessions({
    DateTime? from,
    DateTime? to,
    List<int>? routineIds,
  }) async {
    final workouts = await Db.workoutHistory(
      limit: 2000,
      fromIso: from == null ? null : isoLocal(from),
      toIso: to == null ? null : isoLocal(to),
      routineIds: routineIds,
    );

    final tree = await Db.setting(exportTreeKey);
    final viaTree = await Saf.hasAccess(tree);
    final dir = viaTree ? null : await exportDir();
    final encoder = const JsonEncoder.withIndent('  ');

    var written = 0;
    for (final w in workouts) {
      final data = await buildSessionJson(w['id'] as int);
      final name = '${_sessionFileStem(w)}.json';
      final body = encoder.convert(data);
      if (viaTree) {
        await Saf.writeFile(
            tree: tree!, name: name, mime: 'application/json', content: body);
      } else {
        await File('${dir!.path}/$name').writeAsString(body);
      }
      written++;
    }

    return (
      files: written,
      where: viaTree ? await Saf.folderName(tree!) : dir!.path,
      reachable: viaTree,
    );
  }

  // ---------------------------------------------------------------- routines

  static const _routinePrefix = 'wlog-routines';

  /// Writes the chosen routines out on their own, separate from a full
  /// backup, so a single routine can be moved or shared without carrying
  /// every session with it.
  static Future<({String name, String where, bool reachable})> exportRoutines(
      List<int> ids) async {
    final now = DateTime.now();
    final stamp =
        '${ymd(now)}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final name = '${_routinePrefix}_$stamp.json';
    final body = const JsonEncoder.withIndent('  ')
        .convert(await Db.routinesExport(ids));

    final tree = await Db.setting(exportTreeKey);
    if (await Saf.hasAccess(tree)) {
      await Saf.writeFile(
          tree: tree!, name: name, mime: 'application/json', content: body);
      return (name: name, where: await Saf.folderName(tree), reachable: true);
    }

    final dir = await exportDir();
    await File('${dir.path}/$name').writeAsString(body);
    return (name: name, where: dir.path, reachable: false);
  }

  /// Routine files available to import, newest first. Kept apart from full
  /// backups by their name, so the two lists never mix.
  static Future<List<({String name, String ref})>> availableRoutineFiles() async {
    final all = await _jsonFiles();
    return all.where((f) => f.name.startsWith(_routinePrefix)).toList();
  }

  static Future<int> importRoutinesFrom(String ref) async {
    final raw = ref.startsWith('content://')
        ? await Saf.readFile(ref)
        : await File(ref).readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['format'] != 'workout_log_routines') {
      throw const FormatException(
          'Not a routine file. A full backup is restored from Restore instead.');
    }
    return Db.importRoutines(data);
  }

  /// Every .json in whichever location is in use.
  static Future<List<({String name, String ref})>> _jsonFiles() async {
    final tree = await Db.setting(exportTreeKey);
    if (await Saf.hasAccess(tree)) {
      final files = await Saf.listFiles(tree!, suffix: '.json');
      return files
          .map((f) => (name: f['name']!, ref: f['uri']!))
          .toList(growable: false);
    }
    final dir = await exportDir();
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files
        .map((f) => (name: f.path.split('/').last, ref: f.path))
        .toList(growable: false);
  }
}

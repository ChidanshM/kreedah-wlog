import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'util.dart';

/// All persistence lives here. One SQLite file in the app's private
/// directory, so it survives app updates and rides along with Android's
/// auto-backup.
class Db {
  static late Database _db;
  static Database get raw => _db;

  /// What a routine prescribes. Null throughout means no target set; an
  /// absent upper bound means a single value rather than a range.
  ///
  /// Weights here are in the exercise's own unit, unlike logged sets which
  /// are canonical kilograms. A target is an intention rather than a
  /// measurement: it is never summed with anything, so it gains nothing from
  /// a canonical form, and round-tripping it through kilograms would return
  /// a target of 15 lb as 14.99.
  static const _targetColumns = [
    'target_reps_min INTEGER',
    'target_reps_max INTEGER',
    'target_rpe_min REAL',
    'target_rpe_max REAL',
    'target_weight_min REAL',
    'target_weight_max REAL',
  ];

  static const targetFields = [
    'target_reps_min',
    'target_reps_max',
    'target_rpe_min',
    'target_rpe_max',
    'target_weight_min',
    'target_weight_max',
  ];

  /// Per-set departures from an exercise's shared target.
  ///
  /// A row exists only for a set that differs. With nothing here every set
  /// takes the exercise's own targets, which is the common case and costs
  /// one edit rather than one per set.
  static const _routineSetsTable = '''
    CREATE TABLE routine_sets(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      re_id INTEGER NOT NULL REFERENCES routine_exercises(id) ON DELETE CASCADE,
      set_number INTEGER NOT NULL,
      target_reps INTEGER,
      target_weight REAL,
      target_rpe REAL,
      rest_sec INTEGER,
      UNIQUE(re_id, set_number)
    )''';

  /// A routine placed on the calendar.
  ///
  /// The rule is stored, not the individual days it produces. Occurrences are
  /// worked out on demand, which keeps a year of training as one row and
  /// means changing a rule does not leave stale days behind. Nothing needs to
  /// mark a day as skipped, because missing one is a non-event: the schedule
  /// says what was planned, the logbook says what happened, and they are
  /// allowed to disagree.
  static const _scheduleTable = '''
    CREATE TABLE schedule(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      routine_id INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
      start_date TEXT NOT NULL,
      repeat_kind TEXT NOT NULL DEFAULT 'once',
      repeat_days TEXT NOT NULL DEFAULT '',
      until_date TEXT,
      repeat_count INTEGER,
      paused INTEGER NOT NULL DEFAULT 0,
      remind_at TEXT,
      created_at TEXT NOT NULL
    )''';

  static Future<void> init() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'workout_log.db'),
      version: 6,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (d, from, to) async {
        // v2: sessions can be entered after the fact, and the time of day is
        // often not remembered. time_known distinguishes "trained at 00:00"
        // from "trained that day, time not recorded".
        if (from < 2) {
          await d.execute(
              'ALTER TABLE workouts ADD COLUMN time_known INTEGER NOT NULL DEFAULT 1');
        }
        // v3: a routine can prescribe what to aim for. Copied onto the
        // session as well, so a past session shows the target that applied at
        // the time rather than whatever the routine says now.
        if (from < 3) {
          for (final t in ['routine_exercises', 'workout_exercises']) {
            for (final c in _targetColumns) {
              await d.execute('ALTER TABLE $t ADD COLUMN $c');
            }
          }
        }
        // v4: routines can be placed on the calendar, optionally repeating.
        if (from < 4) {
          await d.execute(_scheduleTable);
        }
        // v5: a routine's sets can differ from one another, and each can
        // carry a rest. Shared values stay on the exercise; a row here
        // exists only for a set that departs from them.
        if (from < 5) {
          await d.execute(_routineSetsTable);
          await d.execute(
              'ALTER TABLE routine_exercises ADD COLUMN per_set INTEGER NOT NULL DEFAULT 0');
          await d.execute(
              'ALTER TABLE routine_exercises ADD COLUMN rest_sec INTEGER');
          await d.execute('ALTER TABLE sets ADD COLUMN rest_sec INTEGER');
        }
        // v6: a rep on the track is a distance in metres, which the step
        // count built for carries cannot express.
        if (from < 6) {
          await d.execute('ALTER TABLE sets ADD COLUMN distance_m REAL');
        }
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE routines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )''');

        await d.execute('''
          CREATE TABLE routine_exercises(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            routine_id INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
            ex_key TEXT NOT NULL,
            ex_name TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            set_type TEXT NOT NULL DEFAULT 'reps',
            unilateral INTEGER NOT NULL DEFAULT 0,
            unit TEXT NOT NULL DEFAULT 'kg',
            target_sets INTEGER NOT NULL DEFAULT 3,
            per_set INTEGER NOT NULL DEFAULT 0,
            rest_sec INTEGER,
            target_reps_min INTEGER,
            target_reps_max INTEGER,
            target_rpe_min REAL,
            target_rpe_max REAL,
            target_weight_min REAL,
            target_weight_max REAL
          )''');

        await d.execute('''
          CREATE TABLE workouts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            routine_id INTEGER,
            routine_name TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            time_known INTEGER NOT NULL DEFAULT 1,
            notes TEXT NOT NULL DEFAULT ''
          )''');

        await d.execute('''
          CREATE TABLE workout_exercises(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
            ex_key TEXT NOT NULL,
            ex_name TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            set_type TEXT NOT NULL DEFAULT 'reps',
            unilateral INTEGER NOT NULL DEFAULT 0,
            unit TEXT NOT NULL DEFAULT 'kg',
            notes TEXT NOT NULL DEFAULT '',
            target_reps_min INTEGER,
            target_reps_max INTEGER,
            target_rpe_min REAL,
            target_rpe_max REAL,
            target_weight_min REAL,
            target_weight_max REAL
          )''');

        // done = 0 means "planned, pre-filled, not yet confirmed".
        // Planned sets are discarded when the session is finished.
        await d.execute('''
          CREATE TABLE sets(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            we_id INTEGER NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
            set_number INTEGER NOT NULL,
            side TEXT NOT NULL DEFAULT 'both',
            entry_unit TEXT NOT NULL DEFAULT 'kg',
            weight_entered REAL,
            weight_kg REAL,
            reps INTEGER,
            duration_sec INTEGER,
            distance_steps INTEGER,
            rpe REAL,
            volume_kg REAL NOT NULL DEFAULT 0,
            distance_m REAL,
            done INTEGER NOT NULL DEFAULT 0,
            ts TEXT
          )''');

        await d.execute('''
          CREATE TABLE equipment(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            weight REAL NOT NULL,
            unit TEXT NOT NULL DEFAULT 'kg'
          )''');

        await d.execute('''
          CREATE TABLE custom_exercises(
            k TEXT PRIMARY KEY,
            n TEXT NOT NULL,
            c TEXT NOT NULL DEFAULT 'CUSTOM',
            g TEXT NOT NULL DEFAULT '',
            p TEXT NOT NULL DEFAULT '',
            s TEXT NOT NULL DEFAULT '',
            e TEXT NOT NULL DEFAULT ''
          )''');

        await d.execute('CREATE TABLE pinned(ex_key TEXT PRIMARY KEY)');
        await d.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
        await d.execute(_scheduleTable);
        await d.execute(_routineSetsTable);

        await d.execute(
            'CREATE INDEX idx_we_workout ON workout_exercises(workout_id)');
        await d.execute('CREATE INDEX idx_we_key ON workout_exercises(ex_key)');
        await d.execute('CREATE INDEX idx_sets_we ON sets(we_id)');
        await d.execute('CREATE INDEX idx_workouts_start ON workouts(started_at)');
      },
    );
  }

  // ---------------------------------------------------------------- settings

  static Future<String?> setting(String key) async {
    final r = await _db.query('settings', where: 'k = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  static Future<void> setSetting(String key, String value) async {
    await _db.insert('settings', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<bool> flag(String key, {bool fallback = false}) async {
    final v = await setting(key);
    if (v == null) return fallback;
    return v == '1';
  }

  // ---------------------------------------------------------------- routines

  /// Returned as a mutable copy: sqflite hands back a read-only result set,
  /// and a ReorderableListView needs to be able to move items within it.
  static Future<List<Map<String, dynamic>>> routines() async =>
      (await _db.query('routines', orderBy: 'position ASC, id ASC'))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  static Future<int> createRoutine(String name) async {
    final r = await _db.rawQuery('SELECT COALESCE(MAX(position), -1) m FROM routines');
    final pos = ((r.first['m'] as int?) ?? -1) + 1;
    return _db.insert('routines', {
      'name': name,
      'position': pos,
      'created_at': isoLocal(DateTime.now()),
    });
  }

  static Future<void> renameRoutine(int id, String name) =>
      _db.update('routines', {'name': name}, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteRoutine(int id) =>
      _db.delete('routines', where: 'id = ?', whereArgs: [id]);

  static Future<void> reorderRoutines(List<int> idsInOrder) async {
    final batch = _db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('routines', {'position': i},
          where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }

  /// Duplicate a routine including all of its exercises.
  static Future<int> duplicateRoutine(int id, String newName) async {
    final newId = await createRoutine(newName);
    final rows = await routineExercises(id);
    final batch = _db.batch();
    for (final e in rows) {
      final copy = Map<String, dynamic>.from(e);
      copy.remove('id');
      copy['routine_id'] = newId;
      batch.insert('routine_exercises', copy);
    }
    await batch.commit(noResult: true);
    return newId;
  }

  // ------------------------------------------------------- routine exercises

  static Future<List<Map<String, dynamic>>> routineExercises(
          int routineId) async =>
      (await _db.query('routine_exercises',
              where: 'routine_id = ?',
              whereArgs: [routineId],
              orderBy: 'position ASC, id ASC'))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  static Future<int> addRoutineExercise(
    int routineId, {
    required String exKey,
    required String exName,
    String setType = SetType.reps,
    bool unilateral = false,
    String unit = 'kg',
    int targetSets = 3,
  }) async {
    final r = await _db.rawQuery(
        'SELECT COALESCE(MAX(position), -1) m FROM routine_exercises WHERE routine_id = ?',
        [routineId]);
    final pos = ((r.first['m'] as int?) ?? -1) + 1;
    return _db.insert('routine_exercises', {
      'routine_id': routineId,
      'ex_key': exKey,
      'ex_name': exName,
      'position': pos,
      'set_type': setType,
      'unilateral': unilateral ? 1 : 0,
      'unit': unit,
      'target_sets': targetSets,
    });
  }

  static Future<void> updateRoutineExercise(int id, Map<String, dynamic> patch) =>
      _db.update('routine_exercises', patch, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteRoutineExercise(int id) =>
      _db.delete('routine_exercises', where: 'id = ?', whereArgs: [id]);

  static Future<void> reorderRoutineExercises(List<int> idsInOrder) async {
    final batch = _db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('routine_exercises', {'position': i},
          where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }

  // --------------------------------------------------------- per-set detail

  /// Departures from an exercise's shared target, keyed by set number.
  ///
  /// Empty when every set is the same, which is the usual case. A routine
  /// only grows rows here for sets that actually differ.
  static Future<Map<int, Map<String, dynamic>>> routineSetOverrides(
      int reId) async {
    final rows = await _db.query('routine_sets',
        where: 're_id = ?', whereArgs: [reId], orderBy: 'set_number ASC');
    return {
      for (final r in rows)
        (r['set_number'] as int): Map<String, dynamic>.from(r)
    };
  }

  static Future<void> setRoutineSetOverride(
    int reId,
    int setNumber, {
    int? reps,
    double? weight,
    double? rpe,
    int? restSec,
  }) async {
    await _db.insert(
      'routine_sets',
      {
        're_id': reId,
        'set_number': setNumber,
        'target_reps': reps,
        'target_weight': weight,
        'target_rpe': rpe,
        'rest_sec': restSec,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> clearRoutineSetOverride(int reId, int setNumber) =>
      _db.delete('routine_sets',
          where: 're_id = ? AND set_number = ?', whereArgs: [reId, setNumber]);

  /// Drop every per-set row, used when an exercise goes back to one shared
  /// target so stale rows cannot linger invisibly.
  static Future<void> clearRoutineSetOverrides(int reId) =>
      _db.delete('routine_sets', where: 're_id = ?', whereArgs: [reId]);

  // ------------------------------------------------- routines, in and out

  /// A portable copy of the chosen routines.
  ///
  /// Any custom exercise a routine refers to travels with it, otherwise the
  /// routine would arrive elsewhere pointing at something that does not
  /// exist there.
  static Future<Map<String, dynamic>> routinesExport(List<int> ids) async {
    final routines = <Map<String, dynamic>>[];
    final customKeys = <String>{};

    for (final id in ids) {
      final found = await _db.query('routines', where: 'id = ?', whereArgs: [id]);
      if (found.isEmpty) continue;
      final exercises = await routineExercises(id);
      for (final e in exercises) {
        final k = e['ex_key'] as String;
        if (k.startsWith('CUSTOM/')) customKeys.add(k);
      }
      routines.add({
        'name': found.first['name'],
        'exercises': exercises
            .map((e) => {
                  'ex_key': e['ex_key'],
                  'ex_name': e['ex_name'],
                  'position': e['position'],
                  'set_type': e['set_type'],
                  'unilateral': e['unilateral'],
                  'unit': e['unit'],
                  'target_sets': e['target_sets'],
                  for (final f in targetFields) f: e[f],
                })
            .toList(),
      });
    }

    final customs = <Map<String, dynamic>>[];
    for (final k in customKeys) {
      final r = await _db.query('custom_exercises', where: 'k = ?', whereArgs: [k]);
      if (r.isNotEmpty) customs.add(Map<String, dynamic>.from(r.first));
    }

    return {
      'format': 'workout_log_routines',
      'version': 1,
      'exported_at': isoLocal(DateTime.now()),
      'routines': routines,
      'custom_exercises': customs,
    };
  }

  /// Adds routines from an export. Never overwrites: a clashing name gains a
  /// suffix, so importing can lose nothing that is already here.
  static Future<int> importRoutines(Map<String, dynamic> data) async {
    // Same care as restore: these keys come from a file and land in the SQL
    // statement as column names, not as bound values, so they are checked
    // against the real schema before use.
    final allowed = await _columnsOf(_db, 'custom_exercises');
    for (final row in (data['custom_exercises'] as List? ?? const [])) {
      if (row is! Map) continue;
      final clean = <String, Object?>{};
      row.forEach((k, v) {
        if (k is String && allowed.contains(k)) clean[k] = v;
      });
      if (clean['k'] is! String) continue;
      await _db.insert('custom_exercises', clean,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    var added = 0;
    for (final entry in (data['routines'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(entry as Map);
      var name = (m['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;

      final clash = await _db.query('routines', where: 'name = ?', whereArgs: [name]);
      if (clash.isNotEmpty) name = '$name (imported)';

      final newId = await createRoutine(name);
      final exercises = (m['exercises'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
        ..sort((a, b) =>
            ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0));

      for (final ex in exercises) {
        final key = ex['ex_key'];
        final label = ex['ex_name'];
        if (key is! String || label is! String) continue;
        await addRoutineExercise(
          newId,
          exKey: key,
          exName: label,
          setType: SetType.all.contains(ex['set_type'])
              ? ex['set_type'] as String
              : SetType.reps,
          unilateral: ((ex['unilateral'] as num?) ?? 0) == 1,
          unit: ex['unit'] == 'lb' ? 'lb' : 'kg',
          targetSets: ((ex['target_sets'] as num?) ?? 3).toInt().clamp(1, 20),
        );
        // Targets are optional and arbitrary numbers, so they are written
        // after the row exists rather than widening the insert helper.
        final patch = <String, Object?>{};
        for (final f in targetFields) {
          final v = ex[f];
          if (v is num) patch[f] = v;
        }
        if (patch.isNotEmpty) {
          final rows = await _db.query('routine_exercises',
              where: 'routine_id = ?',
              whereArgs: [newId],
              orderBy: 'position DESC, id DESC',
              limit: 1);
          if (rows.isNotEmpty) {
            await updateRoutineExercise(rows.first['id'] as int, patch);
          }
        }
      }
      added++;
    }
    return added;
  }

  // --------------------------------------------------------------- schedule

  /// How a placement repeats. Weekly uses weekday numbers in repeat_days
  /// (Monday is 1); monthly uses days of the month.
  static const repeatOnce = 'once';
  static const repeatWeekly = 'weekly';
  static const repeatMonthly = 'monthly';

  static Future<List<Map<String, dynamic>>> schedules() async =>
      (await _db.rawQuery('''
        SELECT s.*, r.name AS routine_name
        FROM schedule s
        JOIN routines r ON r.id = s.routine_id
        ORDER BY s.paused ASC, s.start_date ASC, s.id ASC'''))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  static Future<int> addSchedule({
    required int routineId,
    required DateTime startDate,
    String repeatKind = repeatOnce,
    List<int> days = const [],
    DateTime? until,
    int? repeatCount,
    String? remindAt,
  }) =>
      _db.insert('schedule', {
        'routine_id': routineId,
        'start_date': ymd(startDate),
        'repeat_kind': repeatKind,
        'repeat_days': days.join(','),
        // An ending is either a date or a number of times, never both.
        'until_date': repeatCount == null && until != null ? ymd(until) : null,
        'repeat_count': repeatCount,
        'paused': 0,
        'remind_at': remindAt,
        'created_at': isoLocal(DateTime.now()),
      });

  static Future<void> updateSchedule(int id, Map<String, dynamic> patch) =>
      _db.update('schedule', patch, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteSchedule(int id) =>
      _db.delete('schedule', where: 'id = ?', whereArgs: [id]);

  static Future<void> pauseSchedule(int id, bool paused) => _db.update(
      'schedule', {'paused': paused ? 1 : 0},
      where: 'id = ?', whereArgs: [id]);

  /// A rule broken into cycles: a week for a weekly rule, a month for a
  /// monthly one.
  ///
  /// The cycle is the unit a repeat count refers to. Twelve times with Monday
  /// and Friday chosen means twelve weeks and twenty-four sessions, not
  /// twelve sessions. It is also the unit adherence is measured in, so a week
  /// where only one of two days happened counts as half.
  ///
  /// The first cycle can hold fewer dates than the rest when the start falls
  /// mid-week, which is correct: only the days from the start onwards were
  /// ever asked for, and adherence for that cycle is judged against them.
  static List<({DateTime start, List<DateTime> dates})> scheduleCycles(
    Map<String, dynamic> s, {
    int horizonCycles = 520,
  }) {
    final start = DateTime.parse(s['start_date'] as String);
    final kind = s['repeat_kind'] as String;
    final count = s['repeat_count'] as int?;
    final untilRaw = s['until_date'] as String?;
    final until = untilRaw == null ? null : DateTime.parse(untilRaw);
    final days = (s['repeat_days'] as String)
        .split(',')
        .where((e) => e.isNotEmpty)
        .map(int.parse)
        .toList()
      ..sort();

    final out = <({DateTime start, List<DateTime> dates})>[];

    if (kind == repeatOnce || days.isEmpty) {
      return [(start: start, dates: [start])];
    }

    final limit = (count ?? horizonCycles).clamp(1, horizonCycles);

    for (var i = 0; i < limit; i++) {
      late DateTime cycleStart;
      final dates = <DateTime>[];

      if (kind == repeatWeekly) {
        final monday = start.subtract(Duration(days: start.weekday - 1));
        cycleStart = monday.add(Duration(days: 7 * i));
        for (final wd in days) {
          final d = cycleStart.add(Duration(days: wd - 1));
          if (d.isBefore(start)) continue;
          if (until != null && d.isAfter(until)) continue;
          dates.add(d);
        }
      } else {
        cycleStart = DateTime(start.year, start.month + i);
        final lastDay = DateTime(cycleStart.year, cycleStart.month + 1, 0).day;
        for (final dayNum in days) {
          // A day the month does not have is skipped rather than moved.
          // Rolling the 31st into March would place a session in a month
          // that was never chosen.
          if (dayNum > lastDay) continue;
          final d = DateTime(cycleStart.year, cycleStart.month, dayNum);
          if (d.isBefore(start)) continue;
          if (until != null && d.isAfter(until)) continue;
          dates.add(d);
        }
      }

      if (count == null && until != null && cycleStart.isAfter(until)) break;
      if (dates.isEmpty && count == null && until != null) break;
      out.add((start: cycleStart, dates: dates));
    }

    return out;
  }

  /// Every planned session between two dates, inclusive. Paused placements
  /// produce nothing.
  static Future<
      List<
          ({
            DateTime date,
            int scheduleId,
            int routineId,
            String routineName,
            String? remindAt
          })>> occurrencesBetween(DateTime from, DateTime to) async {
    final rows = await schedules();
    final out = <({
      DateTime date,
      int scheduleId,
      int routineId,
      String routineName,
      String? remindAt
    })>[];

    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);

    for (final s in rows) {
      if ((s['paused'] as int) == 1) continue;
      for (final c in scheduleCycles(s)) {
        for (final d in c.dates) {
          if (d.isBefore(a) || d.isAfter(b)) continue;
          out.add((
            date: d,
            scheduleId: s['id'] as int,
            routineId: s['routine_id'] as int,
            routineName: s['routine_name'] as String,
            remindAt: s['remind_at'] as String?,
          ));
        }
      }
    }

    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Dates on which this routine was actually trained, as yyyy-mm-dd.
  /// Backdated sessions count, so filling one in later closes the gap.
  static Future<Set<String>> trainedDates(int routineId) async {
    final r = await _db.rawQuery('''
      SELECT DISTINCT substr(started_at, 1, 10) AS d
      FROM workouts
      WHERE routine_id = ? AND ended_at IS NOT NULL''', [routineId]);
    return r.map((e) => e['d'] as String).toSet();
  }

  /// How much of a schedule was actually kept.
  ///
  /// Each cycle is worth one unit, shared across the days it asked for, so a
  /// week of Monday and Friday where only Monday happened counts as a half.
  /// Only cycles whose days have already passed are judged; the rest are
  /// still ahead and would otherwise drag the figure down.
  static Future<
      ({
        double unitsDone,
        int cyclesDue,
        int sessionsDone,
        int sessionsDue,
        int? totalCycles,
      })> scheduleAdherence(Map<String, dynamic> s) async {
    final cycles = scheduleCycles(s);
    final trained = await trainedDates(s['routine_id'] as int);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var units = 0.0;
    var cyclesDue = 0;
    var done = 0;
    var due = 0;

    for (final c in cycles) {
      final past = c.dates.where((d) => !d.isAfter(today)).toList();
      if (past.isEmpty) continue;
      cyclesDue++;
      final hit = past.where((d) => trained.contains(ymd(d))).length;
      due += past.length;
      done += hit;
      units += hit / past.length;
    }

    return (
      unitsDone: units,
      cyclesDue: cyclesDue,
      sessionsDone: done,
      sessionsDue: due,
      totalCycles: s['repeat_count'] as int?,
    );
  }

  /// What is left of a placement: when it next runs, how many cycles remain,
  /// or the date it stops.
  static ({DateTime? next, int? cyclesLeft, DateTime? endsOn, int? totalCycles})
      scheduleStatus(Map<String, dynamic> s) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final untilRaw = s['until_date'] as String?;
    final cycles = scheduleCycles(s);

    DateTime? next;
    var cyclesLeft = 0;
    for (final c in cycles) {
      final ahead = c.dates.where((d) => !d.isBefore(today)).toList();
      if (ahead.isEmpty) continue;
      cyclesLeft++;
      next ??= ahead.first;
    }

    return (
      next: next,
      cyclesLeft: s['repeat_count'] == null ? null : cyclesLeft,
      endsOn: untilRaw == null ? null : DateTime.parse(untilRaw),
      totalCycles: s['repeat_count'] as int?,
    );
  }

  /// Whether a session for this routine was logged on that date. Backdated
  /// entries count, so filling one in later closes the gap.
  static Future<bool> wasTrained(int routineId, DateTime day) async {
    final from = ymd(day);
    final to = ymd(day.add(const Duration(days: 1)));
    final r = await _db.rawQuery('''
      SELECT 1 FROM workouts
      WHERE routine_id = ? AND ended_at IS NOT NULL
        AND started_at >= ? AND started_at < ?
      LIMIT 1''', [routineId, from, to]);
    return r.isNotEmpty;
  }

  /// Store a finished track session: one exercise, one set per rep.
  ///
  /// Kept on the same tables as everything else rather than a parallel
  /// structure, so it appears in the logbook, the calendar and the export
  /// without any of them needing to know it came from a stopwatch.
  ///
  /// [laps] carries the seconds elapsed from the start of the session at the
  /// moment each rep finished, so a timestamp is that offset applied to the
  /// start rather than anything derived from the lap's own duration.
  static Future<int> saveTrackSession({
    required List<({int seconds, int metres, int atSecond})> laps,
    required DateTime start,
    DateTime? end,
    String name = 'Track session',
  }) async {
    // The library needs a row for this or every reference to it dangles:
    // no detail, and empty equipment and muscle columns in the export.
    await _db.insert(
      'custom_exercises',
      {
        'k': trackExerciseKey,
        'n': 'Track interval',
        'c': 'CUSTOM',
        'g': '',
        'p': 'QUADRICEPS,HAMSTRINGS,GLUTES,CALVES',
        's': '',
        'e': '',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final workoutId = await _db.insert('workouts', {
      'routine_id': null,
      'routine_name': name,
      'started_at': isoLocal(start),
      'ended_at': isoLocal(end ?? DateTime.now()),
      'time_known': 1,
      'notes': '',
    });

    final weId = await _db.insert('workout_exercises', {
      'workout_id': workoutId,
      'ex_key': trackExerciseKey,
      'ex_name': 'Track interval',
      'position': 0,
      'set_type': SetType.time,
      'unilateral': 0,
      'unit': 'kg',
      'notes': '',
    });

    final batch = _db.batch();
    for (var i = 0; i < laps.length; i++) {
      batch.insert('sets', {
        'we_id': weId,
        'set_number': i + 1,
        'side': 'both',
        'entry_unit': 'kg',
        'duration_sec': laps[i].seconds,
        'distance_m': laps[i].metres.toDouble(),
        'volume_kg': 0,
        'done': 1,
        'ts': isoLocal(start.add(Duration(seconds: laps[i].atSecond))),
      });
    }
    await batch.commit(noResult: true);
    return workoutId;
  }

  // ---------------------------------------------------------------- workouts

  /// A session that was started but never finished, if any.
  static Future<Map<String, dynamic>?> openWorkout() async {
    final r = await _db.query('workouts',
        where: 'ended_at IS NULL', orderBy: 'started_at DESC', limit: 1);
    return r.isEmpty ? null : r.first;
  }

  static Future<Map<String, dynamic>?> workout(int id) async {
    final r = await _db.query('workouts', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<List<Map<String, dynamic>>> workoutHistory({
    int limit = 200,
    String? fromIso,
    String? toIso,
    List<int>? routineIds,
  }) async {
    final where = <String>['ended_at IS NOT NULL'];
    final args = <Object?>[];
    if (fromIso != null) {
      where.add('started_at >= ?');
      args.add(fromIso);
    }
    if (toIso != null) {
      where.add('started_at < ?');
      args.add(toIso);
    }
    if (routineIds != null && routineIds.isNotEmpty) {
      final marks = List.filled(routineIds.length, '?').join(', ');
      where.add('routine_id IN ($marks)');
      args.addAll(routineIds);
    }
    return (await _db.query('workouts',
            where: where.join(' AND '),
            whereArgs: args,
            orderBy: 'started_at DESC',
            limit: limit))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Rename a session without unlinking it.
  ///
  /// Only the label changes; routine_id stays put, so the session still
  /// counts as that routine for pre-filling and for filtering.
  static Future<void> setWorkoutName(int id, String name) => _db.update(
      'workouts', {'routine_name': name},
      where: 'id = ?', whereArgs: [id]);

  /// Start a session from a routine: copies the exercise list, then
  /// pre-fills every set from the last time this routine was trained.
  ///
  /// [at] backdates the session. When backdating, the pre-filled numbers come
  /// from sessions *before* that date, otherwise entering an old workout would
  /// show you numbers from its future, and the sets arrive already confirmed
  /// because filling in last Tuesday is transcription rather than logging.
  static Future<int> startWorkout(
    int routineId,
    String routineName, {
    DateTime? at,
    bool timeKnown = true,
    DateTime? endedAt,
  }) async {
    final backdated = at != null;
    final start = at ?? DateTime.now();

    final workoutId = await _db.insert('workouts', {
      'routine_id': routineId,
      'routine_name': routineName,
      'started_at': isoLocal(start),
      'ended_at': backdated ? isoLocal(endedAt ?? start) : null,
      'time_known': timeKnown ? 1 : 0,
      'notes': '',
    });

    final planned = await routineExercises(routineId);
    for (final re in planned) {
      final weId = await _db.insert('workout_exercises', {
        'workout_id': workoutId,
        'ex_key': re['ex_key'],
        'ex_name': re['ex_name'],
        'position': re['position'],
        'set_type': re['set_type'],
        'unilateral': re['unilateral'],
        'unit': re['unit'],
        'notes': '',
        for (final f in targetFields) f: re[f],
      });

      final last = await lastPerformance(
        re['ex_key'] as String,
        routineId,
        workoutId,
        before: backdated ? isoLocal(start) : null,
      );
      await _seedSets(
        weId: weId,
        setType: re['set_type'] as String,
        unilateral: (re['unilateral'] as int) == 1,
        unit: re['unit'] as String,
        targetSets: re['target_sets'] as int,
        previous: last?['sets'] as List<Map<String, dynamic>>?,
        confirmFilled: backdated,
        stamp: backdated ? isoLocal(start) : null,
        // With no history, the prescription is the best starting point there
        // is. Better than empty fields on a routine's first outing. The
        // target is in the exercise's unit; a logged set is canonical, so it
        // converts on the way in.
        fallbackWeightKg: (re['target_weight_min'] as num?) == null
            ? null
            : toKg((re['target_weight_min'] as num).toDouble(),
                re['unit'] as String),
        fallbackReps: (re['target_reps_min'] as num?)?.toInt(),
        fallbackRpe: (re['target_rpe_min'] as num?)?.toDouble(),
        perSet: (re['per_set'] as int? ?? 0) == 1
            ? await routineSetOverrides(re['id'] as int)
            : null,
        restDefault: re['rest_sec'] as int?,
      );
    }
    return workoutId;
  }

  /// Change when a session happened. [timeKnown] false means only the date
  /// was recorded.
  static Future<void> setWorkoutTimes(
    int id, {
    required DateTime start,
    DateTime? end,
    required bool timeKnown,
  }) =>
      _db.update(
        'workouts',
        {
          'started_at': isoLocal(start),
          'ended_at': end == null ? null : isoLocal(end),
          'time_known': timeKnown ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Tidy a session that is already finished, without restamping when it
  /// happened. Used when editing a past session rather than ending a live one.
  static Future<void> saveEdits(int id) async {
    await _db.rawDelete('''
      DELETE FROM sets WHERE done = 0 AND we_id IN
        (SELECT id FROM workout_exercises WHERE workout_id = ?)''', [id]);
    await _db.rawDelete('''
      DELETE FROM workout_exercises
      WHERE workout_id = ?
        AND id NOT IN (SELECT DISTINCT we_id FROM sets)''', [id]);
  }

  /// An ad-hoc session with no routine behind it.
  static Future<int> startEmptyWorkout(String label) => _db.insert('workouts', {
        'routine_id': null,
        'routine_name': label,
        'started_at': isoLocal(DateTime.now()),
        'notes': '',
      });

  static Future<void> finishWorkout(int id) async {
    // Planned-but-never-confirmed sets are noise; drop them.
    await _db.rawDelete('''
      DELETE FROM sets WHERE done = 0 AND we_id IN
        (SELECT id FROM workout_exercises WHERE workout_id = ?)''', [id]);
    // Exercises you skipped entirely shouldn't clutter the history either.
    await _db.rawDelete('''
      DELETE FROM workout_exercises
      WHERE workout_id = ?
        AND id NOT IN (SELECT DISTINCT we_id FROM sets)''', [id]);
    await _db.update('workouts', {'ended_at': isoLocal(DateTime.now())},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> discardWorkout(int id) =>
      _db.delete('workouts', where: 'id = ?', whereArgs: [id]);

  static Future<void> setWorkoutNotes(int id, String notes) =>
      _db.update('workouts', {'notes': notes}, where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------- workout exercises

  static Future<List<Map<String, dynamic>>> workoutExercises(int workoutId) async =>
      (await _db.query('workout_exercises',
              where: 'workout_id = ?',
              whereArgs: [workoutId],
              orderBy: 'position ASC, id ASC'))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  /// Rewrite the running order of a session. Used when equipment is occupied
  /// and the plan has to bend around what is actually free.
  static Future<void> reorderWorkoutExercises(List<int> idsInOrder) async {
    final batch = _db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('workout_exercises', {'position': i},
          where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }

  static Future<int> addWorkoutExercise(
    int workoutId, {
    required String exKey,
    required String exName,
    String setType = SetType.reps,
    bool unilateral = false,
    String unit = 'kg',
    int? routineId,
  }) async {
    final r = await _db.rawQuery(
        'SELECT COALESCE(MAX(position), -1) m FROM workout_exercises WHERE workout_id = ?',
        [workoutId]);
    final pos = ((r.first['m'] as int?) ?? -1) + 1;
    final weId = await _db.insert('workout_exercises', {
      'workout_id': workoutId,
      'ex_key': exKey,
      'ex_name': exName,
      'position': pos,
      'set_type': setType,
      'unilateral': unilateral ? 1 : 0,
      'unit': unit,
      'notes': '',
    });
    final last = await lastPerformance(exKey, routineId, workoutId);
    await _seedSets(
      weId: weId,
      setType: setType,
      unilateral: unilateral,
      unit: unit,
      targetSets: 3,
      previous: last?['sets'] as List<Map<String, dynamic>>?,
    );
    return weId;
  }

  static Future<void> updateWorkoutExercise(int id, Map<String, dynamic> patch) =>
      _db.update('workout_exercises', patch, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteWorkoutExercise(int id) =>
      _db.delete('workout_exercises', where: 'id = ?', whereArgs: [id]);

  /// Change the display unit for an exercise mid-session, converting the
  /// entered values so the numbers on screen keep meaning the same load.
  static Future<void> switchUnit(int weId, String newUnit) async {
    await updateWorkoutExercise(weId, {'unit': newUnit});
    final rows = await _db.query('sets', where: 'we_id = ?', whereArgs: [weId]);
    final batch = _db.batch();
    for (final s in rows) {
      final entered = (s['weight_entered'] as num?)?.toDouble();
      final oldUnit = (s['entry_unit'] as String?) ?? 'kg';
      if (entered == null) continue;
      // Converting from what was typed, rather than from the stored kg value,
      // avoids compounding the 2-decimal rounding on every switch.
      batch.update(
        'sets',
        {
          'entry_unit': newUnit,
          'weight_entered': convertWeight(entered, oldUnit, newUnit),
        },
        where: 'id = ?',
        whereArgs: [s['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  // -------------------------------------------------------------------- sets

  static Future<List<Map<String, dynamic>>> setsFor(int weId) => _db.query('sets',
      where: 'we_id = ?', whereArgs: [weId], orderBy: 'set_number ASC, side DESC, id ASC');

  /// Create the pre-filled rows for a fresh exercise.
  ///
  /// Set 1 copies last time's set 1, set 2 copies set 2, and any extra set
  /// copies the last one that existed.
  static Future<void> _seedSets({
    required int weId,
    required String setType,
    required bool unilateral,
    required String unit,
    required int targetSets,
    List<Map<String, dynamic>>? previous,
    bool confirmFilled = false,
    String? stamp,
    double? fallbackWeightKg,
    int? fallbackReps,
    double? fallbackRpe,
    Map<int, Map<String, dynamic>>? perSet,
    int? restDefault,
  }) async {
    // Group the previous performance by set number.
    final prevBySet = <int, List<Map<String, dynamic>>>{};
    for (final s in previous ?? const <Map<String, dynamic>>[]) {
      prevBySet.putIfAbsent(s['set_number'] as int, () => []).add(s);
    }
    final prevNumbers = prevBySet.keys.toList()..sort();

    var count = targetSets > 0 ? targetSets : 0;
    if (count == 0) count = prevNumbers.isNotEmpty ? prevNumbers.length : 3;

    final batch = _db.batch();
    for (var i = 1; i <= count; i++) {
      // A set that departs from the exercise's shared target overrides it.
      // What was actually done last time still wins over both: a target is
      // an intention, history is evidence.
      final ov = perSet?[i];
      final ovKg = (ov?['target_weight'] as num?) == null
          ? null
          : toKg((ov!['target_weight'] as num).toDouble(), unit);
      final rest = (ov?['rest_sec'] as int?) ?? restDefault;

      final source = prevBySet[i] ??
          (prevNumbers.isEmpty ? null : prevBySet[prevNumbers.last]);
      final sides = unilateral ? const ['R', 'L'] : const ['both'];
      for (final side in sides) {
        Map<String, dynamic>? src;
        if (source != null) {
          src = source.firstWhere(
            (e) => e['side'] == side,
            orElse: () => source.first,
          );
        }
        final kg = (src?['weight_kg'] as num?)?.toDouble() ??
            ovKg ??
            fallbackWeightKg;
        final reps = (src?['reps'] as int?) ??
            (setType == SetType.reps
                ? ((ov?['target_reps'] as int?) ?? fallbackReps)
                : null);
        final rpe = (src?['rpe'] as num?)?.toDouble() ??
            (ov?['target_rpe'] as num?)?.toDouble() ??
            fallbackRpe;
        // Backdated sessions arrive already confirmed where there is
        // something to confirm, since filling one in is transcription.
        final filled = kg != null ||
            reps != null ||
            src?['duration_sec'] != null ||
            src?['distance_steps'] != null;
        final done = confirmFilled && filled;
        final vol = (setType == SetType.reps && kg != null && reps != null)
            ? kg * reps
            : 0.0;
        batch.insert('sets', {
          'we_id': weId,
          'set_number': i,
          'side': side,
          'entry_unit': unit,
          'weight_entered': kg == null ? null : fromKg(kg, unit),
          'weight_kg': kg,
          'reps': reps,
          'duration_sec': src?['duration_sec'],
          'distance_steps': src?['distance_steps'],
          'rpe': rpe,
          'volume_kg': done ? double.parse(vol.toStringAsFixed(2)) : 0,
          'done': done ? 1 : 0,
          'ts': done ? stamp : null,
          'rest_sec': rest,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<void> addSet(int weId,
      {required bool unilateral, required String unit}) async {
    final r = await _db.rawQuery(
        'SELECT COALESCE(MAX(set_number), 0) m FROM sets WHERE we_id = ?', [weId]);
    final next = ((r.first['m'] as int?) ?? 0) + 1;
    final last = await _db.query('sets',
        where: 'we_id = ? AND set_number = ?',
        whereArgs: [weId, next - 1],
        orderBy: 'side DESC');

    final batch = _db.batch();
    for (final side in unilateral ? const ['R', 'L'] : const ['both']) {
      Map<String, dynamic>? src;
      if (last.isNotEmpty) {
        src = last.firstWhere((e) => e['side'] == side, orElse: () => last.first);
      }
      final kg = (src?['weight_kg'] as num?)?.toDouble();
      batch.insert('sets', {
        'we_id': weId,
        'set_number': next,
        'side': side,
        'entry_unit': unit,
        'weight_entered': kg == null ? null : fromKg(kg, unit),
        'weight_kg': kg,
        'reps': src?['reps'],
        'duration_sec': src?['duration_sec'],
        'distance_steps': src?['distance_steps'],
        'rpe': src?['rpe'],
        'volume_kg': 0,
        'done': 0,
        'ts': null,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<void> deleteSetNumber(int weId, int setNumber) async {
    await _db.delete('sets',
        where: 'we_id = ? AND set_number = ?', whereArgs: [weId, setNumber]);
    // Close the gap so set numbers stay 1..n.
    final rows = await _db.rawQuery(
        'SELECT DISTINCT set_number FROM sets WHERE we_id = ? ORDER BY set_number',
        [weId]);
    final batch = _db.batch();
    for (var i = 0; i < rows.length; i++) {
      final old = rows[i]['set_number'] as int;
      if (old != i + 1) {
        batch.update('sets', {'set_number': i + 1},
            where: 'we_id = ? AND set_number = ?', whereArgs: [weId, old]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Save one side of one set. Volume is always kg.
  static Future<void> saveSet(
    int setId, {
    required String setType,
    required String unit,
    double? weightEntered,
    int? reps,
    int? durationSec,
    int? distanceSteps,
    double? rpe,
    required bool done,
  }) async {
    final kg = weightEntered == null ? null : toKg(weightEntered, unit);
    final volume =
        (setType == SetType.reps && kg != null && reps != null) ? kg * reps : 0.0;
    await _db.update(
      'sets',
      {
        'entry_unit': unit,
        'weight_entered': weightEntered,
        'weight_kg': kg,
        'reps': reps,
        'duration_sec': durationSec,
        'distance_steps': distanceSteps,
        'rpe': rpe,
        'volume_kg': double.parse(volume.toStringAsFixed(2)),
        'done': done ? 1 : 0,
        'ts': done ? isoLocal(DateTime.now()) : null,
      },
      where: 'id = ?',
      whereArgs: [setId],
    );
  }

  static Future<void> markDone(int setId, bool done) async {
    await _db.update(
      'sets',
      {'done': done ? 1 : 0, 'ts': done ? isoLocal(DateTime.now()) : null},
      where: 'id = ?',
      whereArgs: [setId],
    );
    if (done) {
      // Recompute volume in case the row was confirmed straight off autofill.
      final r = await _db.query('sets', where: 'id = ?', whereArgs: [setId]);
      if (r.isNotEmpty) {
        final s = r.first;
        final kg = (s['weight_kg'] as num?)?.toDouble();
        final reps = s['reps'] as int?;
        final vol = (kg != null && reps != null) ? kg * reps : 0.0;
        await _db.update('sets',
            {'volume_kg': double.parse(vol.toStringAsFixed(2))},
            where: 'id = ?', whereArgs: [setId]);
      }
    }
  }

  // ---------------------------------------------------------------- autofill

  /// The numbers that get pre-filled when you open a workout.
  ///
  /// Preference is the last time this exercise appeared *in this routine*,
  /// because the same lift in different weekly slots sits in a different
  /// fatigue context. Falls back to the last time you did it anywhere.
  /// Returns null when there is no history at all.
  ///
  /// [before] restricts the search to sessions earlier than that timestamp,
  /// used when entering a session after the fact so it is filled from what
  /// preceded it rather than from its own future.
  static Future<Map<String, dynamic>?> lastPerformance(
      String exKey, int? routineId, int excludeWorkoutId,
      {String? before}) async {
    Map<String, dynamic>? found;
    var scope = 'routine';
    final cut = before == null ? '' : ' AND w.started_at < ?';

    if (routineId != null) {
      final args = <Object?>[exKey, routineId, excludeWorkoutId];
      if (before != null) args.add(before);
      final r = await _db.rawQuery('''
        SELECT w.id AS wid, w.started_at AS started_at
        FROM workouts w
        JOIN workout_exercises we ON we.workout_id = w.id
        JOIN sets s ON s.we_id = we.id
        WHERE we.ex_key = ? AND w.routine_id = ? AND w.id <> ?
          AND w.ended_at IS NOT NULL AND s.done = 1$cut
        ORDER BY w.started_at DESC LIMIT 1''', args);
      if (r.isNotEmpty) found = r.first;
    }

    if (found == null) {
      final args = <Object?>[exKey, excludeWorkoutId];
      if (before != null) args.add(before);
      final r = await _db.rawQuery('''
        SELECT w.id AS wid, w.started_at AS started_at
        FROM workouts w
        JOIN workout_exercises we ON we.workout_id = w.id
        JOIN sets s ON s.we_id = we.id
        WHERE we.ex_key = ? AND w.id <> ?
          AND w.ended_at IS NOT NULL AND s.done = 1$cut
        ORDER BY w.started_at DESC LIMIT 1''', args);
      if (r.isEmpty) return null;
      found = r.first;
      scope = 'any';
    }

    final wid = found['wid'] as int;
    final sets = await _db.rawQuery('''
      SELECT s.* FROM sets s
      JOIN workout_exercises we ON s.we_id = we.id
      WHERE we.workout_id = ? AND we.ex_key = ? AND s.done = 1
      ORDER BY s.set_number ASC, s.side DESC''', [wid, exKey]);

    return {
      'workoutId': wid,
      'startedAt': found['started_at'] as String,
      'scope': scope,
      'sets': sets.map((e) => Map<String, dynamic>.from(e)).toList(),
    };
  }

  // ------------------------------------------------------------------- stats

  /// Total session volume in kg (always kg, whatever unit was typed).
  static Future<double> workoutVolume(int workoutId) async {
    final r = await _db.rawQuery('''
      SELECT COALESCE(SUM(s.volume_kg), 0) v FROM sets s
      JOIN workout_exercises we ON s.we_id = we.id
      WHERE we.workout_id = ? AND s.done = 1''', [workoutId]);
    return ((r.first['v'] as num?) ?? 0).toDouble();
  }

  static Future<Map<String, dynamic>> workoutSummary(int workoutId) async {
    final r = await _db.rawQuery('''
      SELECT COALESCE(SUM(s.volume_kg), 0) volume,
             COUNT(s.id) sets,
             COALESCE(SUM(s.reps), 0) reps,
             MAX(s.weight_kg) top
      FROM sets s
      JOIN workout_exercises we ON s.we_id = we.id
      WHERE we.workout_id = ? AND s.done = 1''', [workoutId]);
    final row = r.first;
    return {
      'volume': ((row['volume'] as num?) ?? 0).toDouble(),
      'sets': ((row['sets'] as num?) ?? 0).toInt(),
      'reps': ((row['reps'] as num?) ?? 0).toInt(),
      'top': (row['top'] as num?)?.toDouble(),
    };
  }

  /// Heaviest confirmed kg ever recorded for an exercise.
  static Future<double?> bestKg(String exKey) async {
    final r = await _db.rawQuery('''
      SELECT MAX(s.weight_kg) m FROM sets s
      JOIN workout_exercises we ON s.we_id = we.id
      WHERE we.ex_key = ? AND s.done = 1''', [exKey]);
    return (r.first['m'] as num?)?.toDouble();
  }

  // --------------------------------------------------------------- equipment

  static Future<List<Map<String, dynamic>>> equipment() =>
      _db.query('equipment', orderBy: 'kind ASC, weight ASC');

  static Future<List<Map<String, dynamic>>> equipmentOfKind(String kind) =>
      _db.query('equipment',
          where: 'kind = ?', whereArgs: [kind], orderBy: 'weight ASC');

  static Future<int> addEquipment(String kind, double weight, String unit) =>
      _db.insert('equipment', {'kind': kind, 'weight': weight, 'unit': unit});

  static Future<void> deleteEquipment(int id) =>
      _db.delete('equipment', where: 'id = ?', whereArgs: [id]);

  static Future<List<String>> equipmentKindsOwned() async {
    final r = await _db.rawQuery('SELECT DISTINCT kind FROM equipment');
    return r.map((e) => e['kind'] as String).toList();
  }

  // ------------------------------------------------- custom exercises & pins

  static Future<List<Map<String, dynamic>>> customExercises() =>
      _db.query('custom_exercises', orderBy: 'n ASC');

  static Future<void> addCustomExercise({
    required String name,
    List<String> muscles = const [],
    List<String> equipment = const [],
  }) async {
    final key = 'CUSTOM/${name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_')}';
    await _db.insert(
      'custom_exercises',
      {
        'k': key,
        'n': name,
        'c': 'CUSTOM',
        'g': '',
        'p': muscles.join(','),
        's': '',
        'e': equipment.join(','),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Change a custom exercise in place.
  ///
  /// The key never moves, so routines and logged sessions keep pointing at
  /// the same entry however the name changes. Routines are updated to the new
  /// name because a plan should say what a thing is called now; logged
  /// sessions keep the name they were recorded under, because that is what
  /// the record said at the time.
  static Future<void> updateCustomExercise(
    String key, {
    required String name,
    List<String> muscles = const [],
    List<String> equipment = const [],
  }) async {
    await _db.update(
      'custom_exercises',
      {'n': name, 'p': muscles.join(','), 'e': equipment.join(',')},
      where: 'k = ?',
      whereArgs: [key],
    );
    await _db.update('routine_exercises', {'ex_name': name},
        where: 'ex_key = ?', whereArgs: [key]);
  }

  /// Remove a custom exercise from the library.
  ///
  /// Routines and logged sessions keep their own copy of the name, so nothing
  /// already recorded loses its label. What breaks is the link back to the
  /// library entry: pinning, filtering and the heaviest-ever figure stop
  /// finding it.
  static Future<void> deleteCustomExercise(String key) async {
    await _db.delete('custom_exercises', where: 'k = ?', whereArgs: [key]);
    await _db.delete('pinned', where: 'ex_key = ?', whereArgs: [key]);
  }

  /// How many routines and sessions refer to an exercise, so deleting it can
  /// say what it would strand.
  static Future<({int routines, int sessions})> customExerciseUsage(
      String key) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) c FROM routine_exercises WHERE ex_key = ?', [key]);
    final w = await _db.rawQuery(
        'SELECT COUNT(DISTINCT workout_id) c FROM workout_exercises WHERE ex_key = ?',
        [key]);
    return (
      routines: (r.first['c'] as num).toInt(),
      sessions: (w.first['c'] as num).toInt(),
    );
  }

  static Future<List<String>> pinnedKeys() async {
    final r = await _db.query('pinned');
    return r.map((e) => e['ex_key'] as String).toList();
  }

  static Future<void> togglePin(String exKey, bool pin) async {
    if (pin) {
      await _db.insert('pinned', {'ex_key': exKey},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db.delete('pinned', where: 'ex_key = ?', whereArgs: [exKey]);
    }
  }

  // ------------------------------------------------------------ bulk / backup

  static Future<List<Map<String, dynamic>>> dumpTable(String table) async {
    final rows = await _db.query(table);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Column names allowed for a table, read from the live schema.
  ///
  /// Restore and routine import both take their column names from the keys
  /// of a file, and those keys land in the SQL statement itself rather than
  /// in a bound parameter. Filtering them against the real schema means a
  /// hand-edited or hostile file cannot smuggle anything through.
  static Future<Set<String>> _columnsOf(DatabaseExecutor db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((r) => r['name'] as String).toSet();
  }

  static Future<void> restore(Map<String, dynamic> data) async {
    const tables = [
      'sets',
      'workout_exercises',
      'workouts',
      'routine_exercises',
      'routines',
      'equipment',
      'custom_exercises',
      'pinned',
      'settings',
    ];
    await _db.transaction((txn) async {
      for (final t in tables) {
        await txn.delete(t);
      }
      for (final t in tables.reversed) {
        final rows = (data[t] as List?) ?? const [];
        if (rows.isEmpty) continue;
        final allowed = await _columnsOf(txn, t);
        for (final row in rows) {
          if (row is! Map) continue;
          final clean = <String, Object?>{};
          row.forEach((k, v) {
            if (k is String && allowed.contains(k)) clean[k] = v;
          });
          if (clean.isEmpty) continue;
          await txn.insert(t, clean,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  /// Every confirmed set, flattened, for the CSV export.
  ///
  /// The optional bounds narrow it to a span of dates or a set of routines.
  /// Sessions logged without a routine fall outside a routine filter, since
  /// they belong to none of the chosen ones.
  static Future<List<Map<String, dynamic>>> exportRows({
    String? fromIso,
    String? toIso,
    List<int>? routineIds,
  }) async {
    final where = <String>['s.done = 1', 'w.ended_at IS NOT NULL'];
    final args = <Object?>[];

    if (fromIso != null) {
      where.add('w.started_at >= ?');
      args.add(fromIso);
    }
    if (toIso != null) {
      where.add('w.started_at < ?');
      args.add(toIso);
    }
    if (routineIds != null && routineIds.isNotEmpty) {
      final marks = List.filled(routineIds.length, '?').join(', ');
      where.add('w.routine_id IN ($marks)');
      args.addAll(routineIds);
    }

    return (await _db.rawQuery('''
      SELECT
        w.id            AS workout_id,
        w.started_at    AS workout_start,
        w.routine_id    AS routine_id,
        w.routine_name  AS routine_name,
        w.notes         AS workout_notes,
        we.position     AS exercise_order,
        we.ex_key       AS ex_key,
        we.ex_name      AS exercise_name,
        we.set_type     AS set_type,
        we.notes        AS exercise_notes,
        s.set_number    AS set_number,
        s.side          AS side,
        s.entry_unit    AS entry_unit,
        s.weight_entered AS weight_entered,
        s.weight_kg     AS weight_kg,
        s.reps          AS reps,
        s.duration_sec  AS duration_sec,
        s.distance_steps AS distance_steps,
        s.rpe           AS rpe,
        s.volume_kg     AS set_volume_kg,
        s.ts            AS set_timestamp
      FROM sets s
      JOIN workout_exercises we ON s.we_id = we.id
      JOIN workouts w ON we.workout_id = w.id
      WHERE ${where.join(' AND ')}
      ORDER BY w.started_at ASC, we.position ASC, s.set_number ASC, s.side DESC
    ''', args))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

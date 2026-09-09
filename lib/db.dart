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

  static Future<void> init() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'workout_log.db'),
      version: 3,
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

  static Future<List<Map<String, dynamic>>> workoutHistory({int limit = 200}) =>
      _db.query('workouts',
          where: 'ended_at IS NOT NULL',
          orderBy: 'started_at DESC',
          limit: limit);

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
        final kg = (src?['weight_kg'] as num?)?.toDouble() ?? fallbackWeightKg;
        final reps = (src?['reps'] as int?) ??
            (setType == SetType.reps ? fallbackReps : null);
        final rpe = (src?['rpe'] as num?)?.toDouble() ?? fallbackRpe;
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
  static Future<List<Map<String, dynamic>>> exportRows() async {
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
      WHERE s.done = 1 AND w.ended_at IS NOT NULL
      ORDER BY w.started_at ASC, we.position ASC, s.set_number ASC, s.side DESC
    '''))
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

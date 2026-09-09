import 'dart:async';

import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'exercise_picker.dart';
import 'session_time_sheet.dart';
import 'set_editor.dart';

class _ExerciseVM {
  _ExerciseVM({
    required this.row,
    required this.setsBySetNumber,
    required this.hint,
  });

  final Map<String, dynamic> row;
  final Map<int, List<Map<String, dynamic>>> setsBySetNumber;
  final String? hint;

  int get id => row['id'] as int;
  String get name => row['ex_name'] as String;
  String get exKey => row['ex_key'] as String;
  String get setType => row['set_type'] as String;
  String get unit => row['unit'] as String;
  bool get unilateral => (row['unilateral'] as int) == 1;
  List<int> get setNumbers => setsBySetNumber.keys.toList()..sort();

  /// What the routine prescribed, frozen onto the session when it started so
  /// a past session shows the target that applied then. Weights are in this
  /// exercise's own unit, not converted.
  String? get target => targetLabel(
        repsMin: (row['target_reps_min'] as num?)?.toInt(),
        repsMax: (row['target_reps_max'] as num?)?.toInt(),
        rpeMin: (row['target_rpe_min'] as num?)?.toDouble(),
        rpeMax: (row['target_rpe_max'] as num?)?.toDouble(),
        weightMin: (row['target_weight_min'] as num?)?.toDouble(),
        weightMax: (row['target_weight_max'] as num?)?.toDouble(),
        unit: unit,
        setTypeCode: setType,
      );
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.workoutId});
  final int workoutId;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  Map<String, dynamic>? _workout;
  List<_ExerciseVM> _exercises = [];
  double _volume = 0;
  bool _loading = true;
  bool _showTimer = false;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  /// A session that already has an end time is being edited rather than run:
  /// no live timer, no restamping when it happened, and Finish becomes Save.
  bool get _editing => _workout?['ended_at'] != null;
  bool get _timeKnown => (_workout?['time_known'] as int? ?? 1) == 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final workout = await Db.workout(widget.workoutId);
    final showTimer = await Db.flag('show_timer');
    final rows = await Db.workoutExercises(widget.workoutId);

    final vms = <_ExerciseVM>[];
    for (final r in rows) {
      final sets = await Db.setsFor(r['id'] as int);
      final grouped = <int, List<Map<String, dynamic>>>{};
      for (final s in sets) {
        grouped
            .putIfAbsent(s['set_number'] as int, () => [])
            .add(Map<String, dynamic>.from(s));
      }
      final last = await Db.lastPerformance(
        r['ex_key'] as String,
        workout?['routine_id'] as int?,
        widget.workoutId,
        // An edited past session fills from what came before it, not from
        // sessions that happened afterwards.
        before: workout?['ended_at'] == null
            ? null
            : workout?['started_at'] as String?,
      );
      vms.add(_ExerciseVM(
        row: Map<String, dynamic>.from(r),
        setsBySetNumber: grouped,
        hint: _hintFor(last),
      ));
    }

    final volume = await Db.workoutVolume(widget.workoutId);
    if (!mounted) return;

    setState(() {
      _workout = workout;
      _exercises = vms;
      _volume = volume;
      _showTimer = showTimer;
      _loading = false;
    });

    _setupTimer();
  }

  void _setupTimer() {
    _ticker?.cancel();
    if (!_showTimer || _editing) return;
    final started = parseIso(_workout?['started_at'] as String?);
    if (started == null) return;
    void tick() {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(started));
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// "Last Fri, 12d ago — 3 sets @ 20 lb" (or a note that it came from
  /// another routine).
  String? _hintFor(Map<String, dynamic>? last) {
    if (last == null) return null;
    final when = parseIso(last['startedAt'] as String?);
    final sets = (last['sets'] as List).cast<Map<String, dynamic>>();
    if (when == null || sets.isEmpty) return null;

    final unit = sets.first['entry_unit'] as String? ?? 'kg';
    final weights = sets
        .map((s) => (s['weight_entered'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final top = weights.isEmpty
        ? null
        : weights.reduce((a, b) => a > b ? a : b);
    final count = sets.map((s) => s['set_number']).toSet().length;

    final scope = last['scope'] == 'any' ? ', other routine' : '';
    final load = top == null ? '' : ' @ ${num2(top)} $unit';
    return 'Last ${weekdayShort(when)}, ${agoLabel(when)}$scope — $count sets$load';
  }

  Future<void> _toggleDone(_ExerciseVM vm, int setNumber) async {
    final rows = vm.setsBySetNumber[setNumber]!;
    final anyUndone = rows.any((r) => (r['done'] as int) == 0);

    if (anyUndone) {
      // Refuse to confirm a set that has no numbers in it yet.
      final blank = rows.any((r) =>
          r['weight_entered'] == null &&
          r['reps'] == null &&
          r['duration_sec'] == null &&
          r['distance_steps'] == null);
      if (blank) {
        await _openEditor(vm, setNumber);
        return;
      }
    }
    for (final r in rows) {
      await Db.markDone(r['id'] as int, anyUndone);
    }
    await _load();
  }

  Future<void> _openEditor(_ExerciseVM vm, int setNumber) async {
    final saved = await editSet(
      context: context,
      exerciseName: vm.name,
      exKey: vm.exKey,
      setType: vm.setType,
      unit: vm.unit,
      setNumber: setNumber,
      rows: vm.setsBySetNumber[setNumber]!,
    );
    if (saved == true) await _load();
  }

  /// True once any set of this exercise has been confirmed.
  bool _started(_ExerciseVM vm) => vm.setsBySetNumber.values
      .any((rows) => rows.any((r) => (r['done'] as int) == 1));

  Future<void> _move(_ExerciseVM vm, int delta) async {
    final ids = _exercises.map((e) => e.id).toList();
    final i = ids.indexOf(vm.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= ids.length) return;
    ids[i] = ids[j];
    ids[j] = vm.id;
    await Db.reorderWorkoutExercises(ids);
    await _load();
  }

  /// Jump an exercise to the front of the queue, landing it just after the
  /// last thing already underway rather than above work in progress.
  Future<void> _doNext(_ExerciseVM vm) async {
    final ids = _exercises.map((e) => e.id).toList()..remove(vm.id);
    var insertAt = 0;
    for (final e in _exercises) {
      if (e.id != vm.id && _started(e)) {
        insertAt = ids.indexOf(e.id) + 1;
      }
    }
    ids.insert(insertAt, vm.id);
    await Db.reorderWorkoutExercises(ids);
    await _load();
  }

  Future<void> _exerciseMenu(_ExerciseVM vm) async {
    final idx = _exercises.indexWhere((e) => e.id == vm.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.low_priority),
              title: const Text('Do this next'),
              subtitle: const Text('For when the equipment you wanted is busy'),
              onTap: () => Navigator.pop(c, 'next'),
            ),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('Move up'),
                    enabled: idx > 0,
                    onTap: () => Navigator.pop(c, 'up'),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    leading: const Icon(Icons.arrow_downward),
                    title: const Text('Move down'),
                    enabled: idx >= 0 && idx < _exercises.length - 1,
                    onTap: () => Navigator.pop(c, 'down'),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text('Switch to ${vm.unit == 'kg' ? 'lb' : 'kg'}'),
              subtitle: const Text('Converts the numbers already entered'),
              onTap: () => Navigator.pop(c, 'unit'),
            ),
            ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: Text(vm.unilateral
                  ? 'Log as a single side'
                  : 'Log right and left separately'),
              onTap: () => Navigator.pop(c, 'unilateral'),
            ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('Exercise note'),
              onTap: () => Navigator.pop(c, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from this session'),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'next':
        await _doNext(vm);
        return;
      case 'up':
        await _move(vm, -1);
        return;
      case 'down':
        await _move(vm, 1);
        return;
      case 'unit':
        await Db.switchUnit(vm.id, vm.unit == 'kg' ? 'lb' : 'kg');
        break;
      case 'unilateral':
        await Db.updateWorkoutExercise(
            vm.id, {'unilateral': vm.unilateral ? 0 : 1});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Applies to sets you add from here on.'),
          ));
        }
        break;
      case 'note':
        final note = await _promptText(
            context, 'Note', vm.row['notes'] as String? ?? '');
        if (note != null) {
          await Db.updateWorkoutExercise(vm.id, {'notes': note});
        }
        break;
      case 'delete':
        await Db.deleteWorkoutExercise(vm.id);
        break;
    }
    await _load();
  }

  Future<void> _addExercise() async {
    final picked = await pickExercises(context);
    if (picked == null || picked.isEmpty) return;
    for (final ex in picked) {
      await Db.addWorkoutExercise(
        widget.workoutId,
        exKey: ex.key,
        exName: ex.name,
        routineId: _workout?['routine_id'] as int?,
      );
    }
    await _load();
  }

  Future<void> _editTimes() async {
    final started = parseIso(_workout?['started_at'] as String?) ?? DateTime.now();
    final ended = parseIso(_workout?['ended_at'] as String?);
    final picked = await pickSessionTime(
      context,
      date: started,
      start: _timeKnown ? TimeOfDay.fromDateTime(started) : null,
      end: _timeKnown && ended != null ? TimeOfDay.fromDateTime(ended) : null,
      title: 'When was this session?',
    );
    if (picked == null) return;
    final r = resolveSessionTime(picked);
    await Db.setWorkoutTimes(widget.workoutId,
        start: r.start,
        end: r.end ?? (_editing ? r.start : null),
        timeKnown: r.timeKnown);
    notifyDataChanged();
    await _load();
  }

  Future<void> _finish() async {
    final summary = await Db.workoutSummary(widget.workoutId);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finish session?'),
        content: Text(
          '${summary['sets']} sets logged, ${num2(summary['volume'] as double)} kg total volume.\n\n'
          'Sets you left unconfirmed will be discarded.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep going')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Finish')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.finishWorkout(widget.workoutId);
    notifyDataChanged();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard session?'),
        content: const Text('Everything logged in this session is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.discardWorkout(widget.workoutId);
    notifyDataChanged();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveEdits() async {
    await Db.saveEdits(widget.workoutId);
    notifyDataChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = parseIso(_workout?['started_at'] as String?);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_workout?['routine_name'] as String? ?? 'Session',
                style: theme.textTheme.titleMedium),
            InkWell(
              onTap: _editTimes,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_whenLabel(started), style: BvType.bodySm),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 13, color: Bv.ink600),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'discard') _discard();
              if (v == 'note') _sessionNote();
              if (v == 'when') _editTimes();
            },
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'note', child: Text('Session note')),
              const PopupMenuItem(value: 'when', child: Text('Change date and time')),
              PopupMenuItem(
                  value: 'discard',
                  child: Text(_editing ? 'Delete session' : 'Discard session')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editing ? _saveEdits : _finish,
        icon: Icon(_editing ? Icons.done : Icons.check),
        label: Text(_editing ? 'Save' : 'Finish'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 110),
              itemCount: _exercises.length,
              // Dragging starts from the handle only. The cards are full of
              // tap targets, and a long press anywhere would rearrange the
              // session while you were reaching for Log.
              buildDefaultDragHandles: false,
              header: _volumeHeader(),
              footer: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: OutlinedButton.icon(
                  onPressed: _addExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Add exercise'),
                ),
              ),
              onReorder: (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex -= 1;
                if (oldIndex == newIndex) return;
                // Move locally first so the list settles under the finger,
                // then persist and reload.
                setState(() {
                  final vm = _exercises.removeAt(oldIndex);
                  _exercises.insert(newIndex, vm);
                });
                await Db.reorderWorkoutExercises(
                    _exercises.map((e) => e.id).toList());
                await _load();
              },
              itemBuilder: (context, i) => _exerciseCard(_exercises[i], i),
            ),
    );
  }

  String _whenLabel(DateTime? started) {
    if (started == null) return 'Session in progress';
    if (_editing) {
      return _timeKnown
          ? '${prettyDate(started)}, ${hhmm(started)}'
          : '${prettyDate(started)}, time not recorded';
    }
    return _showTimer
        ? 'Started ${hhmm(started)}, running ${mmss(_elapsed.inSeconds)}'
        : 'Started ${hhmm(started)}';
  }

  Future<void> _sessionNote() async {
    final note = await _promptText(
        context, 'Session note', _workout?['notes'] as String? ?? '');
    if (note == null) return;
    await Db.setWorkoutNotes(widget.workoutId, note);
    await _load();
  }

  Widget _volumeHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s3, Bv.s4, Bv.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('SESSION VOLUME', style: BvType.label),
          const Spacer(),
          Text(num2(_volume), style: BvType.metricLg),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 3),
            child: Text('kg', style: BvType.unit),
          ),
        ],
      ),
    );
  }

  Widget _exerciseCard(_ExerciseVM vm, int index) {
    final note = vm.row['notes'] as String? ?? '';

    return Card(
      key: ValueKey(vm.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, Bv.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(vm.name, style: BvType.headlineSm)),
                Padding(
                  padding: const EdgeInsets.only(left: Bv.s2, top: 2),
                  child: Text(vm.unit.toUpperCase(), style: BvType.label),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(Bv.s3, 0, Bv.s1, Bv.s2),
                    child: Icon(Icons.drag_indicator,
                        size: 20, color: Bv.sand500),
                  ),
                ),
                SizedBox(
                  height: 28,
                  width: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: const Icon(Icons.more_horiz, color: Bv.ink600),
                    onPressed: () => _exerciseMenu(vm),
                  ),
                ),
              ],
            ),
            if (vm.hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(vm.hint!, style: BvType.bodySm),
              ),
            if (vm.target != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(vm.target!,
                    style: BvType.bodySm.copyWith(color: Bv.forest700)),
              ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(note,
                    style: BvType.bodySm.copyWith(color: Bv.sage600)),
              ),
            const SizedBox(height: Bv.s3),
            _columnHeader(vm),
            const Divider(),
            const SizedBox(height: Bv.s1),
            ...vm.setNumbers.map((n) => _setRow(vm, n)),
            const SizedBox(height: Bv.s1),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Db.addSet(vm.id,
                        unilateral: vm.unilateral, unit: vm.unit);
                    await _load();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add set'),
                ),
                const Spacer(),
                if (vm.setNumbers.length > 1)
                  TextButton(
                    onPressed: () async {
                      await Db.deleteSetNumber(vm.id, vm.setNumbers.last);
                      await _load();
                    },
                    child: const Text('Remove set'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Column labels. Uppercase overlines, per the brand's label rule.
  Widget _columnHeader(_ExerciseVM vm) {
    String valueLabel;
    switch (vm.setType) {
      case SetType.time:
        valueLabel = 'SECONDS';
        break;
      case SetType.distance:
        valueLabel = 'STEPS';
        break;
      default:
        valueLabel = 'REPS';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Bv.s2),
      child: Row(
        children: [
          const SizedBox(width: _colSet, child: Text('SET', style: BvType.label)),
          const Expanded(child: Text('WEIGHT', style: BvType.label)),
          SizedBox(width: _colValue, child: Text(valueLabel, style: BvType.label)),
          const SizedBox(width: _colRpe, child: Text('RPE', style: BvType.label)),
          const SizedBox(width: _colAction),
        ],
      ),
    );
  }

  /// One set. Confirmed sets recede onto a sage ground; the set you are
  /// about to do sits on white with a real button.
  Widget _setRow(_ExerciseVM vm, int setNumber) {
    final rows = vm.setsBySetNumber[setNumber]!;
    final done = rows.every((r) => (r['done'] as int) == 1);

    return Padding(
      padding: const EdgeInsets.only(bottom: Bv.s1),
      child: Material(
        color: done ? Bv.sage200 : Colors.transparent,
        borderRadius: BorderRadius.circular(Bv.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(Bv.rMd),
          onTap: () => _openEditor(vm, setNumber),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Bv.s2, vertical: Bv.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _colSet,
                  child: Text('$setNumber',
                      style: BvType.label.copyWith(color: Bv.forest600)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        rows.map((r) => _weightCell(vm, r, done)).toList(),
                  ),
                ),
                SizedBox(
                  width: _colValue,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        rows.map((r) => _valueCell(vm, r, done)).toList(),
                  ),
                ),
                SizedBox(
                  width: _colRpe,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rows.map((r) => _rpeCell(r, done)).toList(),
                  ),
                ),
                SizedBox(
                  width: _colAction,
                  child: done
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Undo this set',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 44, minHeight: 40),
                            icon: const Icon(Icons.check_circle,
                                color: Bv.sage600, size: 24),
                            onPressed: () => _toggleDone(vm, setNumber),
                          ),
                        )
                      : SizedBox(
                          height: 34,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            onPressed: () => _toggleDone(vm, setNumber),
                            child: const Text('Log'),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Carried-over numbers render lighter than confirmed ones, so a
  /// pre-filled set never looks like a logged set.
  Widget _rpeCell(Map<String, dynamic> r, bool done) {
    final rpe = (r['rpe'] as num?)?.toDouble();
    return Text(
      rpe == null ? '—' : num2(rpe),
      style: rpe == null
          ? BvType.metricEmpty
          : done
              ? BvType.metricRpe
              : BvType.metricRpePending,
    );
  }

  Widget _weightCell(_ExerciseVM vm, Map<String, dynamic> r, bool done) {
    final w = (r['weight_entered'] as num?)?.toDouble();
    final side = r['side'] as String;
    return Row(
      children: [
        if (side != 'both')
          SizedBox(
            width: 16,
            child: Text(side,
                style: BvType.label.copyWith(color: Bv.forest600)),
          ),
        Text(w == null ? '—' : num2(w),
            style: w == null
                ? BvType.metricEmpty
                : done
                    ? BvType.metric
                    : BvType.metricPending),
      ],
    );
  }

  Widget _valueCell(_ExerciseVM vm, Map<String, dynamic> r, bool done) {
    int? v;
    switch (vm.setType) {
      case SetType.time:
        v = r['duration_sec'] as int?;
        break;
      case SetType.distance:
        v = r['distance_steps'] as int?;
        break;
      default:
        v = r['reps'] as int?;
    }
    return Text(v == null ? '—' : '$v',
        style: v == null
            ? BvType.metricEmpty
            : done
                ? BvType.metric
                : BvType.metricPending);
  }
}

const double _colSet = 26;
const double _colValue = 56;
const double _colRpe = 44;
const double _colAction = 72;

Future<String?> _promptText(
    BuildContext context, String title, String initial) async {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'Anything worth remembering'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db.dart';
import '../library.dart';
import '../theme.dart';
import '../util.dart';
import 'exercise_picker.dart';

class RoutineEditScreen extends StatefulWidget {
  const RoutineEditScreen({
    super.key,
    required this.routineId,
    required this.routineName,
  });

  final int routineId;
  final String routineName;

  @override
  State<RoutineEditScreen> createState() => _RoutineEditScreenState();
}

class _RoutineEditScreenState extends State<RoutineEditScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Db.routineExercises(widget.routineId);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final picked = await pickExercises(context);
    if (picked == null || picked.isEmpty) return;
    for (final ex in picked) {
      await Db.addRoutineExercise(
        widget.routineId,
        exKey: ex.key,
        exName: ex.name,
        setType: _guessSetType(ex),
        unilateral: _guessUnilateral(ex),
        unit: _guessUnit(ex),
      );
    }
    await _load();
  }

  /// Sensible starting guesses; all of them are editable afterwards.
  String _guessSetType(Exercise ex) {
    final n = ex.name.toLowerCase();
    if (ex.category == 'CARRY' || n.contains('carry')) return SetType.distance;
    if (ex.category == 'PLANK' || n.contains('plank') || n.contains('hold')) {
      return SetType.time;
    }
    return SetType.reps;
  }

  bool _guessUnilateral(Exercise ex) {
    final n = ex.name.toLowerCase();
    return n.contains('single-arm') ||
        n.contains('single arm') ||
        n.contains('one-arm') ||
        n.contains('one arm') ||
        n.contains('single-leg') ||
        n.contains('single leg') ||
        n.contains('alternating');
  }

  String _guessUnit(Exercise ex) =>
      ex.equipment.contains('KETTLEBELL') ? 'kg' : 'kg';

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExerciseConfigSheet(row: row),
    );
    if (result == null) return;
    if (result['_delete'] == true) {
      await Db.deleteRoutineExercise(row['id'] as int);
    } else {
      result.remove('_delete');
      await Db.updateRoutineExercise(row['id'] as int, result);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.routineName)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Exercise'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No exercises yet.\nAdd them from the library — 1531 to pick from.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _rows.length,
                  onReorder: (oldIndex, newIndex) async {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _rows.removeAt(oldIndex);
                      _rows.insert(newIndex, item);
                    });
                    await Db.reorderRoutineExercises(
                        _rows.map((e) => e['id'] as int).toList());
                  },
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    return Card(
                      key: ValueKey(r['id']),
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(r['ex_name'] as String),
                        subtitle: Text(_summary(r)),
                        trailing: const Icon(Icons.tune),
                        onTap: () => _edit(r),
                      ),
                    );
                  },
                ),
    );
  }

  String _summary(Map<String, dynamic> r) {
    final parts = <String>[
      '${r['target_sets']} sets',
      SetType.label(r['set_type'] as String),
      (r['unit'] as String).toUpperCase(),
    ];
    if ((r['unilateral'] as int) == 1) parts.add('R then L');
    final t = targetLabel(
      repsMin: (r['target_reps_min'] as num?)?.toInt(),
      repsMax: (r['target_reps_max'] as num?)?.toInt(),
      rpeMin: (r['target_rpe_min'] as num?)?.toDouble(),
      rpeMax: (r['target_rpe_max'] as num?)?.toDouble(),
      weightMinKg: (r['target_weight_min_kg'] as num?)?.toDouble(),
      weightMaxKg: (r['target_weight_max_kg'] as num?)?.toDouble(),
      unit: r['unit'] as String,
      setTypeCode: r['set_type'] as String,
    );
    return t == null ? parts.join(', ') : '${parts.join(', ')}\n$t';
  }
}

class _ExerciseConfigSheet extends StatefulWidget {
  const _ExerciseConfigSheet({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_ExerciseConfigSheet> createState() => _ExerciseConfigSheetState();
}

class _ExerciseConfigSheetState extends State<_ExerciseConfigSheet> {
  late String _setType = widget.row['set_type'] as String;
  late String _unit = widget.row['unit'] as String;
  late bool _unilateral = (widget.row['unilateral'] as int) == 1;
  late int _sets = widget.row['target_sets'] as int;

  // Targets. Each is a low value and an optional high one: leave the second
  // empty for a single figure rather than a range.
  late final _repsLo = _ctl(widget.row['target_reps_min']);
  late final _repsHi = _ctl(widget.row['target_reps_max']);
  late final _rpeLo = _ctl(widget.row['target_rpe_min']);
  late final _rpeHi = _ctl(widget.row['target_rpe_max']);
  late final _wLo = _ctlKg(widget.row['target_weight_min_kg']);
  late final _wHi = _ctlKg(widget.row['target_weight_max_kg']);

  TextEditingController _ctl(Object? v) => TextEditingController(
      text: v is num ? num2(v.toDouble()) : '');

  /// Stored in kilograms, shown in whatever unit the exercise uses.
  TextEditingController _ctlKg(Object? v) => TextEditingController(
      text: v is num ? num2(fromKg(v.toDouble(), widget.row['unit'] as String)) : '');

  @override
  void dispose() {
    for (final c in [_repsLo, _repsHi, _rpeLo, _rpeHi, _wLo, _wHi]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  Widget _rangeRow(String label, TextEditingController lo,
      TextEditingController hi, String suffix) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 86, child: Text(label, style: BvType.label)),
          Expanded(
            child: TextField(
              controller: lo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(hintText: 'from'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('to'),
          ),
          Expanded(
            child: TextField(
              controller: hi,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(hintText: 'optional'),
            ),
          ),
          SizedBox(
            width: 34,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(suffix, style: BvType.bodySm),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.row['ex_name'] as String,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text('Set type'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: SetType.all
                  .map((t) => ChoiceChip(
                        label: Text(SetType.label(t)),
                        selected: _setType == t,
                        onSelected: (_) => setState(() => _setType = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('Default unit'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['kg', 'lb']
                  .map((u) => ChoiceChip(
                        label: Text(u.toUpperCase()),
                        selected: _unit == u,
                        onSelected: (_) => setState(() => _unit = u),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _unilateral,
              onChanged: (v) => setState(() => _unilateral = v),
              title: const Text('Unilateral'),
              subtitle: const Text('Logs right side first, then left'),
            ),
            Row(
              children: [
                const Text('Sets'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _sets > 1 ? () => setState(() => _sets--) : null,
                ),
                Text('$_sets', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _sets < 12 ? () => setState(() => _sets++) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 4),
            Text('WHAT TO AIM FOR', style: BvType.label),
            const SizedBox(height: 2),
            Text(
              'All optional. Fill only the first box for a single figure.',
              style: BvType.bodySm,
            ),
            const SizedBox(height: 12),
            _rangeRow(
                _setType == SetType.time
                    ? 'Seconds'
                    : _setType == SetType.distance
                        ? 'Steps'
                        : 'Reps',
                _repsLo,
                _repsHi,
                ''),
            _rangeRow('Weight', _wLo, _wHi, _unit),
            _rangeRow('RPE', _rpeLo, _rpeHi, ''),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, {'_delete': true}),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final wLo = _num(_wLo);
                    final wHi = _num(_wHi);
                    Navigator.pop(context, {
                      'set_type': _setType,
                      'unit': _unit,
                      'unilateral': _unilateral ? 1 : 0,
                      'target_sets': _sets,
                      'target_reps_min': _num(_repsLo)?.round(),
                      'target_reps_max': _num(_repsHi)?.round(),
                      'target_rpe_min': _num(_rpeLo),
                      'target_rpe_max': _num(_rpeHi),
                      'target_weight_min_kg':
                          wLo == null ? null : convertWeight(wLo, _unit, 'kg'),
                      'target_weight_max_kg':
                          wHi == null ? null : convertWeight(wHi, _unit, 'kg'),
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

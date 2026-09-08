import 'package:flutter/material.dart';

import '../db.dart';
import '../library.dart';
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
    return parts.join(', ');
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
                  onPressed: () => Navigator.pop(context, {
                    'set_type': _setType,
                    'unit': _unit,
                    'unilateral': _unilateral ? 1 : 0,
                    'target_sets': _sets,
                  }),
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

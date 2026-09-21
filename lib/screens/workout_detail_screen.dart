import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'workout_screen.dart';

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});
  final int workoutId;

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  Map<String, dynamic>? _workout;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _exercises = const [];
  final Map<int, List<Map<String, dynamic>>> _sets = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workout = await Db.workout(widget.workoutId);
    final summary = await Db.workoutSummary(widget.workoutId);
    final exercises = await Db.workoutExercises(widget.workoutId);
    final sets = <int, List<Map<String, dynamic>>>{};
    for (final e in exercises) {
      sets[e['id'] as int] = await Db.setsFor(e['id'] as int);
    }
    if (!mounted) return;
    setState(() {
      _workout = workout;
      _summary = summary;
      _exercises = exercises;
      _sets
        ..clear()
        ..addAll(sets);
      _loading = false;
    });
  }

  /// Rename the session without unlinking it. The label changes; the routine
  /// it followed does not, so it still counts for pre-filling and filtering.
  Future<void> _rename() async {
    final controller = TextEditingController(
        text: _workout?['routine_name'] as String? ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
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
    if (name == null || name.isEmpty) return;
    await Db.setWorkoutName(widget.workoutId, name);
    notifyDataChanged();
    await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.discardWorkout(widget.workoutId);
    notifyDataChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = parseIso(_workout?['started_at'] as String?);
    final ended = parseIso(_workout?['ended_at'] as String?);
    final notes = _workout?['notes'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(_workout?['routine_name'] as String? ?? 'Session'),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: _rename,
          ),
          IconButton(
            tooltip: 'Edit this session',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WorkoutScreen(workoutId: widget.workoutId)));
              await _load();
            },
          ),
          IconButton(
              onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (started != null)
                          Text(
                            (_workout?['time_known'] as int? ?? 1) == 0
                                ? '${weekdayName(started)} ${prettyDate(started)}, time not recorded'
                                : '${weekdayName(started)} ${prettyDate(started)}, started ${hhmm(started)}'
                                    '${ended == null ? '' : ', finished ${hhmm(ended)}'}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            _stat('Volume',
                                '${num2((_summary['volume'] as double?) ?? 0)} kg'),
                            _stat('Sets', '${_summary['sets'] ?? 0}'),
                            _stat('Reps', '${_summary['reps'] ?? 0}'),
                            if (_summary['top'] != null)
                              _stat('Heaviest',
                                  '${num2(_summary['top'] as double)} kg'),
                          ],
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(notes, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
                ..._exercises.map((e) {
                  final rows = _sets[e['id'] as int] ?? const [];
                  final grouped = <int, List<Map<String, dynamic>>>{};
                  for (final s in rows) {
                    grouped.putIfAbsent(s['set_number'] as int, () => []).add(s);
                  }
                  final numbers = grouped.keys.toList()..sort();
                  return Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: Text(e['ex_name'] as String),
                          subtitle: (e['notes'] as String).isEmpty
                              ? null
                              : Text(e['notes'] as String),
                        ),
                        ...numbers.map((n) {
                          final g = grouped[n]!;
                          final v = _volume(g);
                          final setType = e['set_type'] as String;
                          // One style down the whole row. Two sizes side by
                          // side sat on different baselines, which is what
                          // made the figures look like they were bobbing
                          // above and below each other.
                          final cell = theme.textTheme.bodySmall;
                          return Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 3, 16, 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    width: 18,
                                    child: Text('$n', style: cell)),
                                // A side per line, matching the ratings
                                // beside them. Run together they wrapped,
                                // and a wrapped row threw every column out
                                // of line with the row above.
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: g
                                        .map((s) => Text(
                                              _one(setType, s,
                                                  withSide: g.length > 1),
                                              style: cell,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ))
                                        .toList(),
                                  ),
                                ),
                                Expanded(
                                  flex: 6,
                                  child: Text(v.text,
                                      style: cell,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                SizedBox(
                                  width: 34,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: g.map((s) {
                                      final rpe =
                                          (s['rpe'] as num?)?.toDouble();
                                      return Text(
                                          rpe == null ? '' : '@${num2(rpe)}',
                                          style: cell);
                                    }).toList(),
                                  ),
                                ),
                                // Always reserved, so a set entered in
                                // kilograms lines up with one entered in
                                // pounds instead of its rating sliding to
                                // the edge of the card.
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                  child: Text(v.showKg ? '|' : ' ',
                                      style: cell?.copyWith(
                                          color: Bv.sand500)),
                                ),
                                SizedBox(
                                  width: 84,
                                  child: Text(v.kgText,
                                      style: cell,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 10),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _stat(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }

  /// What a set moved, in the unit it was entered in and in kilograms.
  ///
  /// Kilograms alone were shown whatever was typed, so a set logged in
  /// pounds reported a figure that matched neither the weight beside it nor
  /// anything on the machine. The entered unit leads; the canonical
  /// kilograms follow, and only when the two differ.
  ({String text, String kgText, bool showKg}) _volume(
      List<Map<String, dynamic>> rows) {
    var kg = 0.0;
    var entered = 0.0;
    var loadKg = 0.0;
    // Worked out from the load and the repetitions rather than read from
    // the stored figure, so what is shown is the multiplication it claims
    // to be.
    var kgFromLoad = 0.0;
    String? unit;
    var comparable = true;

    for (final s in rows) {
      kg += (s['volume_kg'] as num?)?.toDouble() ?? 0;
      final w = (s['weight_entered'] as num?)?.toDouble();
      final reps = s['reps'] as int?;
      final u = s['entry_unit'] as String?;
      if (w == null || reps == null || u == null) {
        comparable = false;
        continue;
      }
      // Two sides on different machines cannot be added up in either of
      // their units, only in kilograms.
      unit ??= u;
      if (u != unit) comparable = false;
      entered += w * reps;
      final lk = (s['weight_kg'] as num?)?.toDouble() ?? 0;
      loadKg = lk;
      kgFromLoad += lk * reps;
    }

    if (kg <= 0) return (text: '', kgText: '', showKg: false);
    if (!comparable || unit == null || unit == 'kg') {
      return (text: '${num2(kg)} kg', kgText: '', showKg: false);
    }
    return (
      text: '${num2(entered)} $unit (${num2(kg)} kg)',
      kgText: '${num2(loadKg)}  ${num2(kgFromLoad)}',
      showKg: true,
    );
  }

  /// One side of a set: the load, its unit, and what was done with it.
  String _one(String setType, Map<String, dynamic> r,
      {required bool withSide}) {
    final w = (r['weight_entered'] as num?)?.toDouble();
    final parts = <String>[];
    if (withSide) parts.add(r['side'] as String);
    if (w != null) parts.add('${num2(w)} ${r['entry_unit']}');
    switch (setType) {
      case SetType.time:
        final v = r['duration_sec'] as int?;
        if (v != null) parts.add('${v}s');
        break;
      case SetType.distance:
        final v = r['distance_steps'] as int?;
        if (v != null) parts.add('$v steps');
        break;
      default:
        final v = r['reps'] as int?;
        if (v != null) parts.add('x $v');
    }
    return parts.isEmpty ? '—' : parts.join(' ');
  }
}

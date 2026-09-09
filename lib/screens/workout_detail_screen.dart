import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
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
                          final vol = g.fold<double>(
                              0,
                              (a, s) =>
                                  a + ((s['volume_kg'] as num?)?.toDouble() ?? 0));
                          return Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 2, 16, 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 24, child: Text('$n')),
                                Expanded(
                                    child: Text(_describe(
                                        e['set_type'] as String, g))),
                                // One rating per side, stacked to line up with
                                // the sides described alongside them.
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: g.map((s) {
                                    final rpe =
                                        (s['rpe'] as num?)?.toDouble();
                                    return Text(
                                        rpe == null
                                            ? ''
                                            : 'RPE ${num2(rpe)}',
                                        style: theme.textTheme.labelSmall);
                                  }).toList(),
                                ),
                                if (vol > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: Text('${num2(vol)} kg',
                                        style: theme.textTheme.labelSmall),
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

  String _describe(String setType, List<Map<String, dynamic>> rows) {
    String one(Map<String, dynamic> r) {
      final w = (r['weight_entered'] as num?)?.toDouble();
      final parts = <String>[];
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

    if (rows.length == 1) return one(rows.first);
    return rows.map((r) => '${r['side']} ${one(r)}').join('   ');
  }
}

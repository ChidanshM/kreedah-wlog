import 'package:flutter/material.dart';

import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'routine_edit_screen.dart';
import 'schedule_screen.dart';

/// What a routine is, at a glance, with the two things you most often want
/// to do to it as buttons rather than buried in a menu.
///
/// Opened by tapping a routine rather than starting it: Start has its own
/// button on the tile, so a tap can afford to mean "show me this one".
class RoutineDetailScreen extends StatefulWidget {
  const RoutineDetailScreen({
    super.key,
    required this.routineId,
    required this.routineName,
  });

  final int routineId;
  final String routineName;

  @override
  State<RoutineDetailScreen> createState() => _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends State<RoutineDetailScreen> {
  late String _name = widget.routineName;
  List<Map<String, dynamic>> _exercises = const [];
  List<Map<String, dynamic>> _schedules = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exercises = await Db.routineExercises(widget.routineId);
    final all = await Db.schedules();
    final row = await Db.raw.query('routines',
        where: 'id = ?', whereArgs: [widget.routineId]);
    if (!mounted) return;
    setState(() {
      _exercises = exercises;
      _schedules =
          all.where((s) => s['routine_id'] == widget.routineId).toList();
      if (row.isNotEmpty) _name = row.first['name'] as String;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          RoutineEditScreen(routineId: widget.routineId, routineName: _name),
    ));
    await _load();
  }

  Future<void> _schedule() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScheduleScreen()));
    await _load();
  }

  /// "3 sets, reps, KG, 8–12 reps" — what the routine asks for, per exercise.
  String _line(Map<String, dynamic> r) {
    final parts = <String>[
      '${r['target_sets']} sets',
      SetType.label(r['set_type'] as String),
    ];
    if ((r['unilateral'] as int) == 1) parts.add('R then L');
    if ((r['per_set'] as int? ?? 0) == 1) parts.add('per-set values');
    final rest = r['rest_sec'] as int?;
    if (rest != null && rest > 0) parts.add('${rest}s rest');
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: Bv.s6),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Bv.s3, Bv.s3, Bv.s3, Bv.s2),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _schedule,
                          icon: const Icon(Icons.event_repeat_outlined),
                          label: const Text('Schedule'),
                        ),
                      ),
                      const SizedBox(width: Bv.s2),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _edit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_schedules.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s1),
                    child: Text('SCHEDULED', style: BvType.label),
                  ),
                  ..._schedules.map((s) {
                    final st = Db.scheduleStatus(s);
                    final paused = (s['paused'] as int) == 1;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        paused ? Icons.pause_circle_outline : Icons.event_repeat,
                        color: paused ? Bv.ink600 : Bv.forest600,
                      ),
                      title: Text(paused
                          ? 'Paused'
                          : st.next == null
                              ? 'Finished'
                              : 'Next ${prettyDate(st.next!)}'),
                    );
                  }),
                ],

                Padding(
                  padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s3, Bv.s4, Bv.s1),
                  child: Text(
                    _exercises.isEmpty
                        ? 'NO EXERCISES YET'
                        : '${_exercises.length} EXERCISES',
                    style: BvType.label,
                  ),
                ),
                if (_exercises.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Bv.s4, 0, Bv.s4, 0),
                    child: Text('Tap Edit to add some.', style: BvType.bodySm),
                  ),
                ..._exercises.map((r) {
                  final target = targetLabel(
                    repsMin: (r['target_reps_min'] as num?)?.toInt(),
                    repsMax: (r['target_reps_max'] as num?)?.toInt(),
                    rpeMin: (r['target_rpe_min'] as num?)?.toDouble(),
                    rpeMax: (r['target_rpe_max'] as num?)?.toDouble(),
                    weightMin: (r['target_weight_min'] as num?)?.toDouble(),
                    weightMax: (r['target_weight_max'] as num?)?.toDouble(),
                    unit: r['unit'] as String,
                    setTypeCode: r['set_type'] as String,
                  );
                  return ListTile(
                    title: Text(r['ex_name'] as String),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_line(r), style: BvType.bodySm),
                        if (target != null)
                          Text(target,
                              style:
                                  BvType.bodySm.copyWith(color: Bv.forest700)),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

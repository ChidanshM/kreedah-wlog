import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'session_time_sheet.dart';
import 'workout_detail_screen.dart';
import 'workout_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _workouts = const [];
  final _volumes = <int, double>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // The tab is kept alive by the IndexedStack, so a finished session has to
    // announce itself rather than waiting for a rebuild that never comes.
    dataRevision.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _load();
  }

  Future<void> _load() async {
    final workouts = await Db.workoutHistory();
    final volumes = <int, double>{};
    for (final w in workouts) {
      volumes[w['id'] as int] = await Db.workoutVolume(w['id'] as int);
    }
    if (!mounted) return;
    setState(() {
      _workouts = workouts;
      _volumes.clear();
      _volumes.addAll(volumes);
      _loading = false;
    });
  }

  /// Add a session that already happened, starting from the routine list.
  Future<void> _addPast() async {
    final routines = await Db.routines();
    if (!mounted) return;
    if (routines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Make a routine first.')),
      );
      return;
    }

    final routine = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, Bv.s2),
              child: Text('Which routine did you do?'),
            ),
            ...routines.map((r) => ListTile(
                  leading: const Icon(Icons.fitness_center_outlined),
                  title: Text(r['name'] as String),
                  onTap: () => Navigator.pop(c, r),
                )),
          ],
        ),
      ),
    );
    if (routine == null || !mounted) return;

    final exercises = await Db.routineExercises(routine['id'] as int);
    if (!mounted) return;
    if (exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That routine has no exercises yet.')),
      );
      return;
    }

    final picked = await pickSessionTime(context, title: 'When did you train?');
    if (picked == null || !mounted) return;
    final t = resolveSessionTime(picked);

    final id = await Db.startWorkout(
      routine['id'] as int,
      routine['name'] as String,
      at: t.start,
      endedAt: t.end,
      timeKnown: t.timeKnown,
    );
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WorkoutScreen(workoutId: id)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPast,
        icon: const Icon(Icons.add),
        label: const Text('Past session'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workouts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Nothing logged yet.', textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _workouts.length,
                    itemBuilder: (context, i) {
                      final w = _workouts[i];
                      final id = w['id'] as int;
                      final started = parseIso(w['started_at'] as String?);
                      final vol = _volumes[id] ?? 0;
                      return Card(
                        child: ListTile(
                          title: Text(w['routine_name'] as String),
                          subtitle: Text(started == null
                              ? '${num2(vol)} kg'
                              : '${prettyDate(started)}, ${hhmm(started)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${num2(vol)} kg', style: BvType.bodySm),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right,
                                  color: Bv.ink600, size: 20),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => WorkoutDetailScreen(workoutId: id),
                            ));
                            await _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
      bottomSheet: _workouts.isEmpty
          ? null
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.secondaryContainer,
              child: Text(
                '${_workouts.length} sessions, '
                '${num2(_volumes.values.fold<double>(0, (a, b) => a + b))} kg lifted all time',
                style: theme.textTheme.bodySmall,
              ),
            ),
    );
  }
}

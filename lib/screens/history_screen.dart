import 'package:flutter/material.dart';

import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'workout_detail_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
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

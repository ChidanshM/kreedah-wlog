import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'equipment_screen.dart';
import 'library_screen.dart';
import 'schedule_screen.dart';
import 'track_screen.dart';
import 'workout_detail_screen.dart';
import 'workout_screen.dart';

/// The landing screen: what is happening now, what is due, what just
/// happened, and the way in to everything that is not a tab.
///
/// Deliberately not a dashboard of statistics. The question this answers is
/// "what do I do next", which is a different question from "how am I doing".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _open;
  List<({DateTime date, int scheduleId, int routineId, String routineName, String? remindAt})>
      _today = const [];
  List<({DateTime date, int scheduleId, int routineId, String routineName, String? remindAt})>
      _ahead = const [];
  List<Map<String, dynamic>> _recent = const [];
  final _volumes = <int, double>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    dataRevision.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    dataRevision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() => _load();

  Future<void> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final open = await Db.openWorkout();
    final planned = await Db.occurrencesBetween(today, today);
    // Tomorrow through the day after next: enough to know whether to train
    // tonight or rest, without turning this into a second calendar.
    final ahead = await Db.occurrencesBetween(
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 3)),
    );
    final recent = await Db.workoutHistory(limit: 3);
    final volumes = <int, double>{};
    for (final w in recent) {
      volumes[w['id'] as int] = await Db.workoutVolume(w['id'] as int);
    }

    if (!mounted) return;
    setState(() {
      _open = open;
      _today = planned;
      _ahead = ahead;
      _recent = recent;
      _volumes
        ..clear()
        ..addAll(volumes);
      _loading = false;
    });
  }

  Future<bool> _alreadyDone(int routineId) =>
      Db.wasTrained(routineId, DateTime.now());

  Future<void> _startPlanned(int routineId, String name) async {
    if (_open != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_open!['routine_name']} is still running.')),
      );
      return;
    }
    final id = await Db.startWorkout(routineId, name);
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WorkoutScreen(workoutId: id)));
    notifyDataChanged();
  }

  Future<void> _open_(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kr\u012b\u1e0d\u0101 WLog'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: Bv.s6),
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(Bv.s4, Bv.s3, Bv.s4, Bv.s2),
                    child: Text(
                      '${weekdayName(now)}, ${prettyDate(now)}',
                      style: BvType.label,
                    ),
                  ),

                  // A session left running is the single most important thing
                  // on this screen, so nothing sits above it.
                  if (_open != null) _resumeCard(),

                  _todaySection(),
                  const SizedBox(height: Bv.s2),
                  _recentSection(),
                  const Divider(height: Bv.s5),
                  _links(),
                  const Divider(height: Bv.s5),
                  _aheadSection(),
                ],
              ),
            ),
    );
  }

  Widget _resumeCard() {
    final started = parseIso(_open!['started_at'] as String?);
    return Card(
      margin: const EdgeInsets.fromLTRB(Bv.s3, 0, Bv.s3, Bv.s2),
      color: Bv.sage200,
      child: ListTile(
        leading: const Icon(Icons.play_circle, color: Bv.forest800),
        title: Text(_open!['routine_name'] as String, style: BvType.headlineSm),
        subtitle: Text(
          started == null
              ? 'In progress'
              : 'Started ${hhmm(started)}, still running',
          style: BvType.bodySm,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkoutScreen(workoutId: _open!['id'] as int),
          ));
          await _load();
        },
      ),
    );
  }

  Widget _todaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s1),
          child: Text('PLANNED TODAY', style: BvType.label),
        ),
        if (_today.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Bv.s4, 0, Bv.s4, Bv.s2),
            child: Text(
              'Nothing scheduled. Start anything from Train.',
              style: BvType.bodySm,
            ),
          )
        else
          ..._today.map((p) => FutureBuilder<bool>(
                future: _alreadyDone(p.routineId),
                builder: (context, snap) {
                  final done = snap.data ?? false;
                  return Card(
                    margin: const EdgeInsets.fromLTRB(Bv.s3, 0, Bv.s3, Bv.s2),
                    child: ListTile(
                      leading: Icon(
                        done
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: done ? Bv.sage600 : Bv.forest600,
                      ),
                      title: Text(p.routineName),
                      subtitle: Text(done ? 'Done today' : 'Not logged yet',
                          style: BvType.bodySm),
                      trailing: done
                          ? null
                          : FilledButton(
                              onPressed: () =>
                                  _startPlanned(p.routineId, p.routineName),
                              child: const Text('Start'),
                            ),
                    ),
                  );
                },
              )),
      ],
    );
  }

  Widget _recentSection() {
    if (_recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s1),
          child: Text('RECENTLY', style: BvType.label),
        ),
        ..._recent.map((w) {
          final id = w['id'] as int;
          final started = parseIso(w['started_at'] as String?);
          return ListTile(
            dense: true,
            leading: const Icon(Icons.event_available_outlined,
                color: Bv.lavender600),
            title: Text(w['routine_name'] as String),
            subtitle: Text(
              started == null ? '' : prettyDate(started),
              style: BvType.bodySm,
            ),
            trailing: Text('${num2(_volumes[id] ?? 0)} kg',
                style: BvType.bodySm),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkoutDetailScreen(workoutId: id),
              ));
              await _load();
            },
          );
        }),
      ],
    );
  }

  /// The next three days, one line each.
  ///
  /// A summary rather than a second calendar: enough to know whether
  /// tomorrow is a training day, with the calendar tab a tap away for
  /// anything more.
  Widget _aheadSection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s3, Bv.s4, Bv.s2),
          child: Text('NEXT THREE DAYS', style: BvType.label),
        ),
        for (var i = 1; i <= 3; i++) _aheadRow(today.add(Duration(days: i))),
        const SizedBox(height: Bv.s3),
      ],
    );
  }

  Widget _aheadRow(DateTime day) {
    final on = _ahead
        .where((p) =>
            p.date.year == day.year &&
            p.date.month == day.month &&
            p.date.day == day.day)
        .map((p) => p.routineName)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Bv.s4, 0, Bv.s4, Bv.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              '${weekdayShort(day)} ${day.day} ${_monthShort(day)}',
              style: BvType.bodySm,
            ),
          ),
          Expanded(
            child: on.isEmpty
                ? Text('Rest', style: BvType.bodySm.copyWith(color: Bv.sand500))
                : Text(
                    on.join(', '),
                    style: BvType.bodySm.copyWith(color: Bv.forest700),
                  ),
          ),
        ],
      ),
    );
  }

  static String _monthShort(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return m[d.month - 1];
  }

  /// Everything that is not a tab. The library lives here now rather than in
  /// the bar, since it is something you go to occasionally rather than a
  /// place you work from.
  Widget _links() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Track session'),
          subtitle: const Text('Stopwatch for intervals'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open_(const TrackScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('Exercise library'),
          subtitle: const Text('Search, filter, pin, add your own'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open_(const LibraryScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.event_repeat_outlined),
          title: const Text('Scheduling'),
          subtitle: const Text('Planned days and what you kept to'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open_(const ScheduleScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Equipment'),
          subtitle: const Text('Your weights and gear'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open_(const EquipmentScreen()),
        ),
      ],
    );
  }
}

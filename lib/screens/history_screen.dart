import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'session_time_sheet.dart';
import 'workout_detail_screen.dart';
import 'workout_screen.dart';

enum _Span { all, days30, days90, year, custom }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _workouts = const [];
  List<Map<String, dynamic>> _routines = const [];
  final _volumes = <int, double>{};
  bool _loading = true;

  _Span _span = _Span.all;
  DateTime? _from;
  DateTime? _to;
  final _routineIds = <int>{};

  bool get _filtered => _span != _Span.all || _routineIds.isNotEmpty;

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

  ({DateTime? from, DateTime? to}) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_span) {
      case _Span.all:
        return (from: null, to: null);
      case _Span.days30:
        return (from: today.subtract(const Duration(days: 30)), to: null);
      case _Span.days90:
        return (from: today.subtract(const Duration(days: 90)), to: null);
      case _Span.year:
        return (from: DateTime(now.year), to: null);
      case _Span.custom:
        // Inclusive of the end date, so the boundary is the following day.
        return (
          from: _from,
          to: _to == null ? null : DateTime(_to!.year, _to!.month, _to!.day + 1),
        );
    }
  }

  Future<void> _load() async {
    final r = _range();
    final routines = await Db.routines();
    final workouts = await Db.workoutHistory(
      fromIso: r.from == null ? null : isoLocal(r.from!),
      toIso: r.to == null ? null : isoLocal(r.to!),
      routineIds: _routineIds.isEmpty ? null : _routineIds.toList(),
    );
    final volumes = <int, double>{};
    for (final w in workouts) {
      volumes[w['id'] as int] = await Db.workoutVolume(w['id'] as int);
    }
    if (!mounted) return;
    setState(() {
      _routines = routines;
      _workouts = workouts;
      _volumes
        ..clear()
        ..addAll(volumes);
      _loading = false;
    });
  }

  // ------------------------------------------------------------------ filter

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              Bv.s4, Bv.s4, Bv.s4, MediaQuery.of(c).viewInsets.bottom + Bv.s4),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Show', style: BvType.headlineSm),
                const SizedBox(height: Bv.s3),
                Text('WHEN', style: BvType.label),
                const SizedBox(height: Bv.s2),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    (_Span.all, 'All time'),
                    (_Span.days30, 'Last 30 days'),
                    (_Span.days90, 'Last 90 days'),
                    (_Span.year, 'This year'),
                    (_Span.custom, 'Between dates'),
                  ]
                      .map((o) => ChoiceChip(
                            label: Text(o.$2),
                            selected: _span == o.$1,
                            onSelected: (_) => setSheet(() => _span = o.$1),
                          ))
                      .toList(),
                ),
                if (_span == _Span.custom) ...[
                  const SizedBox(height: Bv.s2),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final d = await _pickDate(c, _from);
                            if (d != null) setSheet(() => _from = d);
                          },
                          child:
                              Text(_from == null ? 'From' : prettyDate(_from!)),
                        ),
                      ),
                      const SizedBox(width: Bv.s2),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final d = await _pickDate(c, _to);
                            if (d != null) setSheet(() => _to = d);
                          },
                          child: Text(_to == null ? 'To' : prettyDate(_to!)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Bv.s4),
                Text('ROUTINE', style: BvType.label),
                const SizedBox(height: Bv.s1),
                Text(
                  'None selected shows everything, including sessions logged '
                  'without a routine.',
                  style: BvType.bodySm,
                ),
                ..._routines.map((r) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _routineIds.contains(r['id'] as int),
                      title: Text(r['name'] as String),
                      onChanged: (v) => setSheet(() => v == true
                          ? _routineIds.add(r['id'] as int)
                          : _routineIds.remove(r['id'] as int)),
                    )),
                const SizedBox(height: Bv.s3),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setSheet(() {
                        _span = _Span.all;
                        _from = null;
                        _to = null;
                        _routineIds.clear();
                      }),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _load();
  }

  Future<DateTime?> _pickDate(BuildContext c, DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: c,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
  }

  // ------------------------------------------------------------ past session

  Future<void> _addPast() async {
    if (_routines.isEmpty) {
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
            ..._routines.map((r) => ListTile(
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
    final total = _volumes.values.fold<double>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logbook'),
        actions: [
          IconButton(
            tooltip: 'Filter',
            icon: Icon(_filtered ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: _openFilters,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPast,
        icon: const Icon(Icons.add),
        label: const Text('Past session'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workouts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _filtered
                          ? 'Nothing matches those filters.'
                          : 'Nothing logged yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
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
                              ? '\u2014'
                              : (w['time_known'] as int? ?? 1) == 0
                                  ? prettyDate(started)
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
                '${_workouts.length} session${_workouts.length == 1 ? '' : 's'}, '
                '${num2(total)} kg'
                '${_filtered ? ' in this selection' : ' lifted all time'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
    );
  }
}

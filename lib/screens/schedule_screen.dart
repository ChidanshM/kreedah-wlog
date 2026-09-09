import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../theme.dart';
import '../util.dart';

/// Routines placed on the calendar: what repeats, what is left of it, and how
/// much of it actually happened.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Map<String, dynamic>> _rows = const [];
  final _adherence = <int, ({double unitsDone, int cyclesDue})>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Db.schedules();
    final adherence = <int, ({double unitsDone, int cyclesDue})>{};
    for (final s in rows) {
      final a = await Db.scheduleAdherence(s);
      adherence[s['id'] as int] =
          (unitsDone: a.unitsDone, cyclesDue: a.cyclesDue);
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _adherence
        ..clear()
        ..addAll(adherence);
      _loading = false;
    });
  }

  Future<void> _add() async {
    final routines = await Db.routines();
    if (!mounted) return;
    if (routines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Make a routine first.')),
      );
      return;
    }
    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ScheduleSheet(routines: routines),
    );
    if (made == true) {
      notifyDataChanged();
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancel ${s['routine_name']}?'),
        content: const Text(
            'The planned days are removed. Sessions you already logged are '
            'kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Cancel it')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.deleteSchedule(s['id'] as int);
    notifyDataChanged();
    await _load();
  }

  /// "Every Mon and Fri", "Monthly on the 1st and 15th", "Once".
  String _rule(Map<String, dynamic> s) {
    final kind = s['repeat_kind'] as String;
    final days = (s['repeat_days'] as String)
        .split(',')
        .where((e) => e.isNotEmpty)
        .map(int.parse)
        .toList()
      ..sort();

    if (kind == Db.repeatWeekly && days.isNotEmpty) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return 'Every ${days.map((d) => names[d - 1]).join(', ')}';
    }
    if (kind == Db.repeatMonthly && days.isNotEmpty) {
      return 'Monthly on the ${days.map(_ordinal).join(', ')}';
    }
    final start = DateTime.parse(s['start_date'] as String);
    return 'Once, ${prettyDate(start)}';
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// What is left, and what was kept.
  String _status(Map<String, dynamic> s) {
    final st = Db.scheduleStatus(s);
    final a = _adherence[s['id'] as int];
    final parts = <String>[];

    if ((s['paused'] as int) == 1) {
      parts.add('Paused');
    } else if (st.next != null) {
      final days = st.next!.difference(DateTime.now()).inDays;
      parts.add(days <= 0
          ? 'Next today'
          : days == 1
              ? 'Next tomorrow'
              : 'Next ${prettyDate(st.next!)}');
    } else {
      parts.add('Finished');
    }

    if (st.totalCycles != null && st.cyclesLeft != null) {
      parts.add('${st.cyclesLeft} of ${st.totalCycles} left');
    } else if (st.endsOn != null) {
      parts.add('Until ${prettyDate(st.endsOn!)}');
    }

    // Partial credit: a week asking for two days where one happened is a half.
    if (a != null && a.cyclesDue > 0) {
      parts.add('${num2(a.unitsDone)} of ${a.cyclesDue} kept');
    }

    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduling')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nothing scheduled.\nPlace a routine on a day and let it '
                      'repeat if you want it to.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: _rows.map((s) {
                    final paused = (s['paused'] as int) == 1;
                    return Card(
                      child: ListTile(
                        title: Text(
                          s['routine_name'] as String,
                          style: paused
                              ? BvType.headlineSm.copyWith(color: Bv.ink600)
                              : BvType.headlineSm,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_rule(s), style: BvType.bodySm),
                            Text(_status(s),
                                style: BvType.bodySm.copyWith(
                                    color:
                                        paused ? Bv.ink600 : Bv.forest700)),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'pause') {
                              await Db.pauseSchedule(s['id'] as int, !paused);
                              notifyDataChanged();
                              await _load();
                            }
                            if (v == 'delete') await _delete(s);
                          },
                          itemBuilder: (c) => [
                            PopupMenuItem(
                              value: 'pause',
                              child: Text(paused ? 'Resume' : 'Pause'),
                            ),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Cancel')),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.routines});
  final List<Map<String, dynamic>> routines;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

enum _Ending { never, onDate, afterCount }

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late int _routineId = widget.routines.first['id'] as int;
  DateTime _start = DateTime.now();
  String _kind = Db.repeatWeekly;
  final _days = <int>{};
  _Ending _ending = _Ending.never;
  DateTime? _until;
  int _count = 12;

  String get _cycleWord => _kind == Db.repeatMonthly ? 'months' : 'weeks';

  bool get _valid =>
      _kind == Db.repeatOnce ? true : _days.isNotEmpty;

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return;
    setState(() {
      _start = d;
      // Assume the day you picked is one of the days you meant.
      if (_kind == Db.repeatWeekly && _days.isEmpty) _days.add(d.weekday);
      if (_kind == Db.repeatMonthly && _days.isEmpty) _days.add(d.day);
    });
  }

  Future<void> _save() async {
    await Db.addSchedule(
      routineId: _routineId,
      startDate: _start,
      repeatKind: _kind,
      days: _days.toList()..sort(),
      until: _ending == _Ending.onDate ? _until : null,
      repeatCount: _ending == _Ending.afterCount ? _count : null,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    const weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4,
          MediaQuery.of(context).viewInsets.bottom + Bv.s4),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Schedule a routine', style: BvType.headlineSm),
            const SizedBox(height: Bv.s3),

            Text('ROUTINE', style: BvType.label),
            const SizedBox(height: Bv.s2),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.routines
                  .map((r) => ChoiceChip(
                        label: Text(r['name'] as String),
                        selected: _routineId == r['id'],
                        onSelected: (_) =>
                            setState(() => _routineId = r['id'] as int),
                      ))
                  .toList(),
            ),

            const SizedBox(height: Bv.s4),
            Text('STARTING', style: BvType.label),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text('${weekdayName(_start)}, ${prettyDate(_start)}'),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: _pickStart,
            ),

            const SizedBox(height: Bv.s2),
            Text('REPEATS', style: BvType.label),
            const SizedBox(height: Bv.s2),
            Wrap(
              spacing: 6,
              children: [
                (Db.repeatOnce, 'Once'),
                (Db.repeatWeekly, 'Weekly'),
                (Db.repeatMonthly, 'Monthly'),
              ]
                  .map((o) => ChoiceChip(
                        label: Text(o.$2),
                        selected: _kind == o.$1,
                        onSelected: (_) => setState(() {
                          _kind = o.$1;
                          _days.clear();
                          if (o.$1 == Db.repeatWeekly) _days.add(_start.weekday);
                          if (o.$1 == Db.repeatMonthly) _days.add(_start.day);
                        }),
                      ))
                  .toList(),
            ),

            if (_kind == Db.repeatWeekly) ...[
              const SizedBox(height: Bv.s3),
              Text('ON THESE DAYS', style: BvType.label),
              const SizedBox(height: Bv.s2),
              Row(
                children: List.generate(7, (i) {
                  final wd = i + 1;
                  final on = _days.contains(wd);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: FilterChip(
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(weekLabels[i], textAlign: TextAlign.center),
                        ),
                        selected: on,
                        showCheckmark: false,
                        onSelected: (v) => setState(
                            () => v ? _days.add(wd) : _days.remove(wd)),
                      ),
                    ),
                  );
                }),
              ),
            ],

            if (_kind == Db.repeatMonthly) ...[
              const SizedBox(height: Bv.s3),
              Text('ON THESE DATES', style: BvType.label),
              const SizedBox(height: Bv.s1),
              Text(
                'A date a month does not have is skipped, not moved.',
                style: BvType.bodySm,
              ),
              const SizedBox(height: Bv.s2),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: List.generate(31, (i) {
                  final d = i + 1;
                  return FilterChip(
                    label: Text('$d'),
                    selected: _days.contains(d),
                    showCheckmark: false,
                    onSelected: (v) =>
                        setState(() => v ? _days.add(d) : _days.remove(d)),
                  );
                }),
              ),
            ],

            if (_kind != Db.repeatOnce) ...[
              const SizedBox(height: Bv.s4),
              Text('UNTIL', style: BvType.label),
              const SizedBox(height: Bv.s2),
              Wrap(
                spacing: 6,
                children: [
                  (_Ending.never, 'I pause it'),
                  (_Ending.onDate, 'A date'),
                  (_Ending.afterCount, 'A number of $_cycleWord'),
                ]
                    .map((o) => ChoiceChip(
                          label: Text(o.$2),
                          selected: _ending == o.$1,
                          onSelected: (_) => setState(() => _ending = o.$1),
                        ))
                    .toList(),
              ),
              if (_ending == _Ending.onDate) ...[
                const SizedBox(height: Bv.s2),
                OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _until ??
                          _start.add(const Duration(days: 84)),
                      firstDate: _start,
                      lastDate: DateTime(_start.year + 5),
                    );
                    if (d != null) setState(() => _until = d);
                  },
                  child: Text(_until == null
                      ? 'Choose an end date'
                      : 'Until ${prettyDate(_until!)}'),
                ),
              ],
              if (_ending == _Ending.afterCount) ...[
                const SizedBox(height: Bv.s2),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed:
                          _count > 1 ? () => setState(() => _count--) : null,
                    ),
                    Text('$_count $_cycleWord',
                        style: Theme.of(context).textTheme.titleMedium),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed:
                          _count < 104 ? () => setState(() => _count++) : null,
                    ),
                    const Spacer(),
                    if (_days.isNotEmpty)
                      Text('${_count * _days.length} sessions',
                          style: BvType.bodySm),
                  ],
                ),
              ],
            ],

            const SizedBox(height: Bv.s4),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _valid ? _save : null,
                  child: const Text('Schedule'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'workout_detail_screen.dart';

/// Everything one exercise has ever done, ranked three ways.
///
/// "Best" is three questions, not one. The heaviest set is rarely the one
/// with the most volume, and the set with the most reps is usually neither.
/// Each ordering answers a different thing, so each gets its own tab rather
/// than one being chosen on your behalf.
class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({
    super.key,
    required this.exKey,
    required this.exName,
  });

  final String exKey;
  final String exName;

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

enum _Window { week, fourWeeks, threeMonths, year, all }

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) _load();
    });

  _Window _window = _Window.all;
  List<Map<String, dynamic>> _rows = const [];
  ({double? topVolume, double? topWeight, int? topReps, int sets, int sessions})?
      _bests;
  bool _loading = true;

  static const _orders = ['volume', 'weight', 'reps'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String? get _cutoff {
    final now = DateTime.now();
    final from = switch (_window) {
      _Window.week => now.subtract(const Duration(days: 7)),
      _Window.fourWeeks => now.subtract(const Duration(days: 28)),
      _Window.threeMonths => now.subtract(const Duration(days: 91)),
      _Window.year => now.subtract(const Duration(days: 365)),
      _Window.all => null,
    };
    return from == null
        ? null
        : isoLocal(DateTime(from.year, from.month, from.day));
  }

  Future<void> _load() async {
    final cutoff = _cutoff;
    final rows = await Db.exerciseHistory(
      widget.exKey,
      fromIso: cutoff,
      order: _orders[_tabs.index],
    );
    final bests = await Db.exerciseBests(widget.exKey, fromIso: cutoff);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _bests = bests;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exName, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Volume'),
            Tab(text: 'Weight'),
            Tab(text: 'Reps'),
          ],
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Bv.s3),
              children: [
                (_Window.week, '1 week'),
                (_Window.fourWeeks, '4 weeks'),
                (_Window.threeMonths, '3 months'),
                (_Window.year, '1 year'),
                (_Window.all, 'All time'),
              ]
                  .map((o) => Padding(
                        padding: const EdgeInsets.only(right: 6, top: 8),
                        child: ChoiceChip(
                          label: Text(o.$2),
                          selected: _window == o.$1,
                          onSelected: (_) {
                            setState(() => _window = o.$1);
                            _load();
                          },
                        ),
                      ))
                  .toList(),
            ),
          ),
          if (_bests != null) _bestsStrip(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Nothing logged in this window.'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (context, i) => _row(_rows[i], i),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _bestsStrip() {
    final b = _bests!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s3),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          _stat('Best volume',
              b.topVolume == null ? '—' : '${num2(b.topVolume!)} kg'),
          _stat('Heaviest',
              b.topWeight == null ? '—' : '${num2(b.topWeight!)} kg'),
          _stat('Most reps', b.topReps == null ? '—' : '${b.topReps}'),
          _stat('Sets', '${b.sets}'),
          _stat('Sessions', '${b.sessions}'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: BvType.label),
          Text(value, style: BvType.metric),
        ],
      );

  Widget _row(Map<String, dynamic> r, int i) {
    final started = parseIso(r['started_at'] as String?);
    final entered = (r['weight_entered'] as num?)?.toDouble();
    final unit = r['entry_unit'] as String;
    final kg = (r['weight_kg'] as num?)?.toDouble();
    final reps = r['reps'] as int?;
    final vol = (r['volume_kg'] as num?)?.toDouble() ?? 0;
    final rpe = (r['rpe'] as num?)?.toDouble();
    final side = r['side'] as String;

    // The weight as it was typed, since that is what the machine said.
    final weightLabel = entered == null
        ? '—'
        : unit == 'lb'
            ? '${num2(entered)} lb (${num2(kg ?? 0)} kg)'
            : '${num2(entered)} kg';

    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 28,
        child: Text('${i + 1}', style: BvType.label),
      ),
      title: Text(
        [
          weightLabel,
          if (reps != null) '\u00d7 $reps',
          if (side != 'both') side,
        ].join('  '),
      ),
      subtitle: Text(
        [
          if (started != null) prettyDate(started),
          r['routine_name'] as String,
          if (rpe != null) 'RPE ${num2(rpe)}',
        ].join('  \u00b7  '),
        style: BvType.bodySm,
      ),
      trailing: Text(vol > 0 ? '${num2(vol)} kg' : '',
          style: BvType.bodySm.copyWith(color: Bv.forest700)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkoutDetailScreen(workoutId: r['workout_id'] as int),
      )),
    );
  }
}

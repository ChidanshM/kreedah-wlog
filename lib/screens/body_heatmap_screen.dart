import 'package:flutter/material.dart';

import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'body_heatmap.dart';

/// The spans offered wherever the body map appears.
///
/// Three months and a year roll backwards from today rather than snapping to
/// a calendar quarter or a calendar year: in January a calendar year would
/// show almost nothing, which says more about the date than about training.
enum HeatWindow { week, fourWeeks, threeMonths, year }

extension HeatWindowX on HeatWindow {
  String get label => switch (this) {
        HeatWindow.week => '1W',
        HeatWindow.fourWeeks => '4W',
        HeatWindow.threeMonths => '3M',
        HeatWindow.year => '1Y',
      };

  /// What the span actually covers, for the heading. Said in days rather
  /// than as "this month", because it rolls back from today rather than
  /// starting at a boundary.
  String get heading => switch (this) {
        HeatWindow.week => 'WORKED IN THE LAST 7 DAYS',
        HeatWindow.fourWeeks => 'WORKED IN THE LAST 28 DAYS',
        HeatWindow.threeMonths => 'WORKED IN THE LAST 90 DAYS',
        HeatWindow.year => 'WORKED IN THE LAST YEAR',
      };

  int get days => switch (this) {
        HeatWindow.week => 7,
        HeatWindow.fourWeeks => 28,
        HeatWindow.threeMonths => 90,
        HeatWindow.year => 365,
      };
}

/// The body map with its own span buttons, loading as the span changes.
///
/// Used on the landing screen and in the settings list. The calendar passes
/// its own dates instead, since it colours the period on screen rather than a
/// span chosen here.
class BodyHeatmapPanel extends StatefulWidget {
  const BodyHeatmapPanel({super.key, this.initial = HeatWindow.week});

  final HeatWindow initial;

  @override
  State<BodyHeatmapPanel> createState() => _BodyHeatmapPanelState();
}

class _BodyHeatmapPanelState extends State<BodyHeatmapPanel> {
  late HeatWindow _window = widget.initial;
  Map<String, int> _counts = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: _window.days - 1));
    final counts = await Db.muscleSets(from, to);
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The heading belongs here rather than beside this, so it cannot say
        // one span while the buttons say another.
        Text(_window.heading, style: BvType.label),
        const SizedBox(height: Bv.s2),
        Row(
          children: HeatWindow.values
              .map((w) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(w.label),
                      selected: _window == w,
                      onSelected: (_) {
                        setState(() => _window = w);
                        _load();
                      },
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: Bv.s3),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(Bv.s5),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          BodyHeatmap(counts: _counts),
      ],
    );
  }
}

/// The full screen version, reached from the settings list, where a span can
/// be given as two dates rather than chosen from the four.
class BodyHeatmapScreen extends StatefulWidget {
  const BodyHeatmapScreen({super.key});

  @override
  State<BodyHeatmapScreen> createState() => _BodyHeatmapScreenState();
}

class _BodyHeatmapScreenState extends State<BodyHeatmapScreen> {
  DateTime _to = DateTime.now();
  DateTime _from = DateTime.now().subtract(const Duration(days: 27));
  Map<String, int> _counts = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await Db.muscleSets(_from, _to);
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _pick({required bool isFrom}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        _from = d;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = d;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
    await _load();
  }

  void _preset(HeatWindow w) {
    final now = DateTime.now();
    setState(() {
      _to = DateTime(now.year, now.month, now.day);
      _from = _to.subtract(Duration(days: w.days - 1));
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final byMuscle = sortMuscles(_counts.keys);
    return Scaffold(
      appBar: AppBar(title: const Text('Body heatmap')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Bv.s3, Bv.s3, Bv.s3, Bv.s6),
        children: [
          Wrap(
            spacing: 6,
            children: HeatWindow.values
                .map((w) => ActionChip(
                      label: Text(w.label),
                      onPressed: () => _preset(w),
                    ))
                .toList(),
          ),
          const SizedBox(height: Bv.s2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isFrom: true),
                  child: Text('From ${prettyDate(_from)}'),
                ),
              ),
              const SizedBox(width: Bv.s2),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isFrom: false),
                  child: Text('To ${prettyDate(_to)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Bv.s4),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            BodyHeatmap(counts: _counts),
            const SizedBox(height: Bv.s5),
            const Padding(
              padding: EdgeInsets.only(left: Bv.s1, bottom: Bv.s2),
              child: Text('SETS PER MUSCLE', style: BvType.label),
            ),
            if (byMuscle.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: Bv.s1),
                child:
                    Text('Nothing logged in this span.', style: BvType.bodySm),
              ),
            // The figures behind the colours, since a shade alone cannot be
            // read back as a number.
            ...byMuscle.map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(muscleLabel(m))),
                      Text('${_counts[m]}', style: BvType.metric),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

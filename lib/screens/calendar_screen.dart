import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_events.dart';
import '../db.dart';
import '../theme.dart';
import '../util.dart';
import 'workout_detail_screen.dart';
import 'workout_screen.dart';

/// Planned days against logged ones.
///
/// Nothing links the two: a day counts as kept because a session for that
/// routine exists on it, so filling in a missed day later closes the gap with
/// no bookkeeping to fall out of step.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

enum _View { month, week }

enum _Mode { continuous, paged }

typedef _Planned = ({
  DateTime date,
  int scheduleId,
  int routineId,
  String routineName,
  String? remindAt
});

class _CalendarScreenState extends State<CalendarScreen> {
  _View _view = _View.month;
  _Mode _mode = _Mode.continuous;

  /// Middle of the scrollable range, so it runs both ways from today.
  static const _span = 240;

  late DateTime _base;
  late DateTime _paged;
  DateTime _selected = _dayOf(DateTime.now());

  ScrollController? _scroll;
  int _controllerGeneration = 0;

  List<_Planned> _plannedAll = const [];
  List<Map<String, dynamic>> _loggedAll = const [];
  bool _loading = true;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _monthStart(DateTime d) => DateTime(d.year, d.month);
  static DateTime _weekStart(DateTime d) =>
      _dayOf(d).subtract(Duration(days: d.weekday - 1));

  DateTime _periodStart(DateTime d) =>
      _view == _View.month ? _monthStart(d) : _weekStart(d);

  DateTime _periodAt(int index) {
    final offset = index - _span;
    return _view == _View.month
        ? DateTime(_base.year, _base.month + offset)
        : _base.add(Duration(days: 7 * offset));
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _base = _periodStart(now);
    _paged = _base;
    dataRevision.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    dataRevision.removeListener(_onDataChanged);
    _scroll?.dispose();
    super.dispose();
  }

  void _onDataChanged() => _load();

  Future<void> _load() async {
    // Two years either side covers any realistic scroll without reloading
    // mid-gesture. Occurrences are computed from rules, so this is cheap.
    final now = DateTime.now();
    final from = DateTime(now.year - 2, now.month);
    final to = DateTime(now.year + 2, now.month);

    final planned = await Db.occurrencesBetween(from, to);
    final logged = await Db.workoutHistory(
      fromIso: isoLocal(from),
      toIso: isoLocal(to),
      limit: 2000,
    );
    if (!mounted) return;
    setState(() {
      _plannedAll = planned;
      _loggedAll = logged;
      _loading = false;
    });
  }

  void _resetScroll() {
    _scroll?.dispose();
    _scroll = null;
    _controllerGeneration++;
    final now = DateTime.now();
    _base = _periodStart(now);
    _paged = _periodStart(_selected);
  }

  // ------------------------------------------------------------------- data

  List<Map<String, dynamic>> _loggedOn(DateTime day) {
    final key = ymd(day);
    return _loggedAll
        .where((w) => (w['started_at'] as String).startsWith(key))
        .toList();
  }

  List<_Planned> _plannedOn(DateTime day) {
    final d = _dayOf(day);
    return _plannedAll.where((p) => _dayOf(p.date) == d).toList();
  }

  bool _kept(DateTime day, int routineId) =>
      _loggedOn(day).any((w) => w['routine_id'] == routineId);

  // ---------------------------------------------------------------- actions

  Future<void> _startPlanned(_Planned p) async {
    final today = _dayOf(DateTime.now());
    final day = _dayOf(p.date);
    if (day.isAfter(today)) return;

    final open = await Db.openWorkout();
    if (open != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${open['routine_name']} is still running.')),
      );
      return;
    }

    // Today starts a live session; an earlier day is filled in after the
    // fact, with no time of day since none was recorded at the time.
    final id = day == today
        ? await Db.startWorkout(p.routineId, p.routineName)
        : await Db.startWorkout(p.routineId, p.routineName,
            at: day, timeKnown: false);

    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WorkoutScreen(workoutId: id)));
    notifyDataChanged();
  }

  // ------------------------------------------------------------------- cells

  Widget _cell(DateTime day, {required bool inPeriod, required double size}) {
    final today = _dayOf(DateTime.now());
    final planned = _plannedOn(day);
    final logged = _loggedOn(day);
    final isSelected = _dayOf(day) == _selected;
    final isToday = _dayOf(day) == today;
    final past = _dayOf(day).isBefore(today);

    final allKept =
        planned.isNotEmpty && planned.every((p) => _kept(day, p.routineId));
    final missed = planned.isNotEmpty && past && !allKept;

    return InkWell(
      onTap: () => setState(() => _selected = _dayOf(day)),
      child: Container(
        height: size,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? Bv.forest200
              : allKept
                  ? Bv.sage200
                  : null,
          borderRadius: BorderRadius.circular(Bv.rMd),
          border: isToday
              ? Border.all(color: Bv.forest800, width: 1.5)
              : missed
                  ? Border.all(color: Bv.sand500)
                  : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The 1st names its month, which is the only place that context
            // exists in week view now the heading is gone.
            Text(
              day.day == 1 ? '1 ${_monthShort(day)}' : '${day.day}',
              style: BvType.bodySm.copyWith(
                color: inPeriod ? Bv.textPrimary : Bv.sand500,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (planned.isNotEmpty)
                  Icon(Icons.circle,
                      size: 5, color: allKept ? Bv.sage600 : Bv.forest600),
                if (logged.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.circle, size: 5, color: Bv.lavender600),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Width of the week-number gutter, matched by the weekday heading row so
  /// the columns stay in line.
  static const _gutter = 24.0;

  Widget _weekdayHeads() {
    const heads = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        const SizedBox(width: _gutter),
        ...heads.map((h) => Expanded(
              child: Center(child: Text(h, style: BvType.label)),
            )),
      ],
    );
  }

  Widget _weekNumber(DateTime weekStart, double size) => SizedBox(
        width: _gutter,
        height: size,
        child: Center(
          child: Text('${isoWeekNumber(weekStart)}',
              style: BvType.label.copyWith(color: Bv.sand500)),
        ),
      );

  Widget _weekRow(DateTime weekStart, double cellSize) => Row(
        children: [
          _weekNumber(weekStart, cellSize),
          ...List.generate(
            7,
            (i) => Expanded(
              child: _cell(weekStart.add(Duration(days: i)),
                  inPeriod: true, size: cellSize),
            ),
          ),
        ],
      );

  /// One month, always six rows so every page is the same height. Ragged
  /// heights make a continuous scroll jump as it passes a short month.
  Widget _monthBlock(DateTime monthStart, double cellSize) {
    final lead = monthStart.weekday - 1;
    final gridStart = monthStart.subtract(Duration(days: lead));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Bv.s3, Bv.s2, Bv.s3, Bv.s1),
          child: Text(_monthLabel(monthStart), style: BvType.headlineSm),
        ),
        _weekdayHeads(),
        for (var w = 0; w < 6; w++)
          Row(
            children: [
              _weekNumber(gridStart.add(Duration(days: w * 7)), cellSize),
              ...List.generate(7, (i) {
                final day = gridStart.add(Duration(days: w * 7 + i));
                return Expanded(
                  child: _cell(day,
                      inPeriod: day.month == monthStart.month, size: cellSize),
                );
              }),
            ],
          ),
      ],
    );
  }

  /// No heading in week view: the week number is already in the gutter and
  /// the dates are in the cells, so a line repeating both earns nothing. The
  /// month is carried by the cells themselves, which name it on the 1st.
  Widget _weekBlock(DateTime weekStart, double cellSize) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Bv.s2),
          _weekdayHeads(),
          _weekRow(weekStart, cellSize),
        ],
      );

  Widget _block(DateTime start, double cellSize) => _view == _View.month
      ? _monthBlock(start, cellSize)
      : _weekBlock(start, cellSize);

  static String _monthShort(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return m[d.month - 1];
  }

  static String _monthLabel(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  // ---------------------------------------------------------------- toggles

  /// The two view switches live in the app bar rather than a band of their
  /// own, so the calendar itself gets that vertical space back.
  ///
  /// Both are sliding two-position controls rather than icons that light up:
  /// neither state is "off", so a thumb moving between two choices describes
  /// what is happening better than something switching on.
  Widget _viewToggle() => _SlideToggle(
        first: Icons.view_module,
        second: Icons.view_week,
        isFirst: _view == _View.month,
        tooltipFirst: 'Month',
        tooltipSecond: 'Week',
        onChanged: (wantFirst) => setState(() {
          _view = wantFirst ? _View.month : _View.week;
          _resetScroll();
        }),
      );

  Widget _modeToggle() => _SlideToggle(
        first: Icons.unfold_more,
        second: Icons.unfold_less,
        isFirst: _mode == _Mode.continuous,
        tooltipFirst: 'Scroll continuously',
        tooltipSecond: 'One at a time',
        onChanged: (wantFirst) => setState(() {
          _mode = wantFirst ? _Mode.continuous : _Mode.paged;
          _resetScroll();
        }),
      );

  // -------------------------------------------------------------- calendar

  Widget _calendar(double cellSize, bool landscape, double viewportWidth) {
    if (_mode == _Mode.paged) {
      // Both axes move the page: dragging left-to-right or top-to-bottom goes
      // back, the other way forward. A PageView only handles one axis, so the
      // drag is read directly.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 120) _step(-1);
          if (v < -120) _step(1);
        },
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 120) _step(-1);
          if (v < -120) _step(1);
        },
        child: _block(_paged, cellSize),
      );
    }

    // Continuous: down the screen in portrait, across it in landscape.
    final horizontal = landscape;
    final extent = _view == _View.month
        ? (34 + 20 + 6 * (cellSize + 4))
        : (Bv.s2 + 20 + cellSize + 4);

    _scroll ??= ScrollController(
      initialScrollOffset: _span * (horizontal ? viewportWidth : extent),
    );

    return ListView.builder(
      key: ValueKey('cal-$_controllerGeneration-$_view-$horizontal'),
      controller: _scroll,
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      itemCount: _span * 2 + 1,
      itemExtent: horizontal ? viewportWidth : extent,
      itemBuilder: (context, i) => _block(_periodAt(i), cellSize),
    );
  }

  void _step(int by) {
    setState(() {
      _paged = _view == _View.month
          ? DateTime(_paged.year, _paged.month + by)
          : _paged.add(Duration(days: 7 * by));
    });
  }

  // ------------------------------------------------------------------ detail

  Widget _dayDetail() {
    final planned = _plannedOn(_selected);
    final logged = _loggedOn(_selected);
    final today = _dayOf(DateTime.now());

    return ListView(
      padding: const EdgeInsets.only(bottom: Bv.s6),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s3, Bv.s4, Bv.s1),
          child: Text('${weekdayName(_selected)}, ${prettyDate(_selected)}',
              style: BvType.label),
        ),
        if (planned.isEmpty && logged.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, 0),
            child: Text('Nothing planned or logged.', style: BvType.bodySm),
          ),
        ...planned.map((p) {
          final kept = _kept(_selected, p.routineId);
          return ListTile(
            leading: Icon(
              kept ? Icons.check_circle : Icons.radio_button_unchecked,
              color: kept ? Bv.sage600 : Bv.forest600,
            ),
            title: Text(p.routineName),
            subtitle: Text(kept
                ? 'Planned, and done'
                : _selected.isAfter(today)
                    ? 'Planned'
                    : 'Planned, not logged'),
            trailing: kept || _selected.isAfter(today)
                ? null
                : FilledButton(
                    onPressed: () => _startPlanned(p),
                    child: Text(_selected == today ? 'Start' : 'Log it'),
                  ),
          );
        }),
        ...logged.map((w) => ListTile(
              leading: const Icon(Icons.event_available_outlined,
                  color: Bv.lavender600),
              title: Text(w['routine_name'] as String),
              subtitle: const Text('Logged'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      WorkoutDetailScreen(workoutId: w['id'] as int),
                ));
              },
            )),
      ],
    );
  }

  /// Jump to a month, or through the year grid to a different year.
  Future<void> _openJump() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _JumpPicker(initial: _periodStart(_selected)),
    );
    if (picked == null) return;
    setState(() {
      // Land on the first of the chosen month unless today is inside it, in
      // which case today is the more useful place to be.
      final now = DateTime.now();
      _selected = (now.year == picked.year && now.month == picked.month)
          ? _dayOf(now)
          : picked;
      _base = _periodStart(_selected);
      _paged = _base;
      _scroll?.dispose();
      _scroll = null;
      _controllerGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // A week is one row, so it can afford far more height than a cell in a
    // six-row month. At the month's size it left most of the screen empty.
    final cellSize = _view == _View.month
        ? (landscape ? 34.0 : 46.0)
        : (landscape ? 56.0 : 96.0);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Jump to a month',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: _openJump,
        ),
        centerTitle: false,
        titleSpacing: 0,
        // Today sits between two equal halves, each holding its switch
        // centred, so the two switches are the same size and mirror each
        // other about it.
        title: Row(
          children: [
            Expanded(child: Center(child: _viewToggle())),
            TextButton(
              onPressed: () => setState(() {
                _selected = _dayOf(DateTime.now());
                _resetScroll();
              }),
              child: const Text(
                'Today',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Center(child: _modeToggle())),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, box) {
                final calHeight = _view == _View.month
                    ? (34 + 20 + 6 * (cellSize + 4))
                    : (Bv.s2 + 20 + cellSize + 4);
                return Column(
                  children: [
                    SizedBox(
                      height: calHeight,
                      child: _calendar(cellSize, landscape, box.maxWidth),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _dayDetail()),
                  ],
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------

/// A two-position control with a thumb that slides between the choices.
///
/// Used where neither option is an "off" state. A switch that lights up
/// implies one setting is absent; a thumb that moves implies two settings,
/// one of which is currently chosen, which is what these actually are.
class _SlideToggle extends StatelessWidget {
  const _SlideToggle({
    required this.first,
    required this.second,
    required this.isFirst,
    required this.onChanged,
    required this.tooltipFirst,
    required this.tooltipSecond,
  });

  final IconData first;
  final IconData second;
  final bool isFirst;

  /// Called with true when the left option is chosen.
  final ValueChanged<bool> onChanged;

  final String tooltipFirst;
  final String tooltipSecond;

  static const double _w = 96;
  static const double _h = 34;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _w,
      height: _h,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Bv.cream200,
        borderRadius: BorderRadius.circular(_h / 2),
        border: Border.all(color: Bv.cream400),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: isFirst ? Alignment.centerLeft : Alignment.centerRight,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Container(
              width: _w / 2,
              height: _h,
              decoration: BoxDecoration(
                color: Bv.forest600,
                borderRadius: BorderRadius.circular(_h / 2),
              ),
            ),
          ),
          Row(
            children: [
              _half(first, isFirst, tooltipFirst, () {
                if (isFirst) return;
                HapticFeedback.selectionClick();
                onChanged(true);
              }),
              _half(second, !isFirst, tooltipSecond, () {
                if (!isFirst) return;
                HapticFeedback.selectionClick();
                onChanged(false);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _half(IconData icon, bool active, String tip, VoidCallback onTap) {
    return Expanded(
      child: Tooltip(
        message: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                icon,
                key: ValueKey(active),
                size: 18,
                color: active ? Bv.cream100 : Bv.ink600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Year at the top, twelve months beneath it. Tapping the year swaps the grid
/// for a list of years, which is one gesture rather than a pair of arrows you
/// have to press eleven times to reach last winter.
class _JumpPicker extends StatefulWidget {
  const _JumpPicker({required this.initial});
  final DateTime initial;

  @override
  State<_JumpPicker> createState() => _JumpPickerState();
}

class _JumpPickerState extends State<_JumpPicker> {
  late int _year = widget.initial.year;
  bool _pickingYear = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(Bv.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _pickingYear = !_pickingYear),
              icon: Text('$_year', style: BvType.headlineSm),
              label: Icon(
                _pickingYear ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              ),
            ),
            const SizedBox(height: Bv.s2),
            SizedBox(
              height: 260,
              width: 300,
              child: _pickingYear ? _years(now) : _monthGrid(now),
            ),
            const SizedBox(height: Bv.s2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthGrid(DateTime now) => GridView.count(
        crossAxisCount: 3,
        childAspectRatio: 1.6,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(12, (i) {
          final m = i + 1;
          final isCurrent = now.year == _year && now.month == m;
          return InkWell(
            borderRadius: BorderRadius.circular(Bv.rMd),
            onTap: () => Navigator.pop(context, DateTime(_year, m)),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isCurrent ? Bv.sage200 : null,
                borderRadius: BorderRadius.circular(Bv.rMd),
                border: isCurrent
                    ? Border.all(color: Bv.forest800, width: 1.5)
                    : null,
              ),
              child: Center(
                child: Text(
                  _months[i],
                  style: BvType.bodyMd.copyWith(
                    color: Bv.textPrimary,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      );

  Widget _years(DateTime now) {
    // Centred on the year in view, running well past either side.
    const back = 12;
    const forward = 6;
    return GridView.count(
      crossAxisCount: 3,
      childAspectRatio: 1.6,
      controller: ScrollController(
        initialScrollOffset: 0,
      ),
      children: List.generate(back + forward + 1, (i) {
        final y = _year - back + i;
        final isCurrent = y == now.year;
        final isShown = y == _year;
        return InkWell(
          borderRadius: BorderRadius.circular(Bv.rMd),
          onTap: () => setState(() {
            _year = y;
            _pickingYear = false;
          }),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isShown ? Bv.forest200 : null,
              borderRadius: BorderRadius.circular(Bv.rMd),
              border: isCurrent
                  ? Border.all(color: Bv.forest800, width: 1.5)
                  : null,
            ),
            child: Center(
              child: Text(
                '$y',
                style: BvType.bodyMd.copyWith(
                  color: Bv.textPrimary,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

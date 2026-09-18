import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db.dart';
import '../library.dart';
import '../theme.dart';
import '../util.dart';

/// Edits one set. For a unilateral exercise, [rows] holds two records
/// (right first, then left), each carrying its own weight, count and RPE.
///
/// Returns true if anything was saved.
Future<bool?> editSet({
  required BuildContext context,
  required String exerciseName,
  required String exKey,
  required String setType,
  required String unit,
  required int setNumber,
  required List<Map<String, dynamic>> rows,
  double? targetRpeMin,
  double? targetRpeMax,
  int? weId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SetEditorSheet(
      exerciseName: exerciseName,
      exKey: exKey,
      setType: setType,
      unit: unit,
      setNumber: setNumber,
      rows: rows,
      targetRpeMin: targetRpeMin,
      targetRpeMax: targetRpeMax,
      weId: weId,
    ),
  );
}

class SetEditorSheet extends StatefulWidget {
  const SetEditorSheet({
    super.key,
    required this.exerciseName,
    required this.exKey,
    required this.setType,
    required this.unit,
    required this.setNumber,
    required this.rows,
    this.targetRpeMin,
    this.targetRpeMax,
    this.weId,
  });

  final String exerciseName;
  final String exKey;
  final String setType;
  final String unit;
  final int setNumber;
  final List<Map<String, dynamic>> rows;

  /// What the routine asked for, used to decide which part of the effort
  /// scale is worth showing.
  final double? targetRpeMin;
  final double? targetRpeMax;

  /// The exercise this set belongs to, needed to split it into two sides or
  /// put them back together. Absent where that is not offered.
  final int? weId;

  @override
  State<SetEditorSheet> createState() => _SetEditorSheetState();
}

/// Which number a cell holds. Only used to key focus nodes apart, since
/// each number now has one place it is set from.
enum _Field { weight, value }

/// Sizes drawn from the Fibonacci sequence, which is the golden ratio in
/// whole numbers: each is about 1.618 times the one before, and none of them
/// needs rounding.
///
/// Using a sequence rather than picking numbers means the relationships hold
/// when one of them changes, and there is somewhere to go next instead of
/// inventing 23 because 21 felt small.
class _Fib {
  static const s13 = 13.0;
  static const s21 = 21.0;
  static const s34 = 34.0;
  static const s55 = 55.0;
}

/// The marker on each of the three controls.
///
/// One colour each, so a glance says which number a control sets without
/// reading its heading. Effort borrows the lavender the session screen
/// already prints ratings in.
class _Marker {
  const _Marker(this.fill, this.edge);
  final Color fill;
  final Color edge;

  static const weight = _Marker(Color(0xFFD3E2F2), Color(0xFF4A7CB0));
  static const count = _Marker(Color(0xFFF5E3C3), Color(0xFFB98430));
  static const effort = _Marker(Color(0xFFE3DEF4), Bv.lavender600);
}

/// A row of values with a pill on the selected one.
///
/// Seven are in view at a time; the rest are a drag away. Tapping a value
/// selects it, dragging moves the row rather than the selection, so the
/// whole scale is reachable without the row being too cramped to read.
class _PillScale extends StatefulWidget {
  const _PillScale({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
    required this.format,
    required this.startAt,
    required this.marker,
    required this.selectedSize,
    required this.restSize,
    required this.restWidth,
    required this.selectedWidth,
    this.restItalic = false,
  });

  /// How wide each value sits.
  ///
  /// Two widths rather than one: the chosen value needs room for five
  /// characters at the larger size, while the ones either side of it hold a
  /// smaller number and only look sparse when given the same. The scale
  /// works out where to scroll from these rather than from a single step.
  final double restWidth;
  final double selectedWidth;

  final List<double> values;
  final double? value;
  final ValueChanged<double> onChanged;
  final String Function(double) format;
  final _Marker marker;

  /// Sizes per scale rather than one for all: the effort scale carries two
  /// characters and the weight scale up to five, so they do not sit well at
  /// the same size.
  final double selectedSize;
  final double restSize;

  /// Slants the values either side of the marker. Useful where the sizes
  /// are close together and the slant is what separates chosen from not.
  final bool restItalic;

  /// Which value the row opens on, when nothing is chosen yet.
  final int startAt;

  @override
  State<_PillScale> createState() => _PillScaleState();
}

class _PillScaleState extends State<_PillScale> {
  final _scroll = ScrollController();
  bool _placed = false;

  /// The last value this scale itself reported, and the width it was last
  /// laid out at.
  ///
  /// A number set anywhere else — a quick-pick weight, the keyboard, the
  /// focus moving to the other side — has to bring the scale with it, or the
  /// marker sits off screen and the scale looks broken. Its own taps are
  /// excluded, since it is already there.
  double? _self;
  double _viewport = 0;

  int? get _index {
    final v = widget.value;
    if (v == null) return null;
    final i = widget.values.indexOf(v);
    return i == -1 ? null : i;
  }

  double _offsetOf(int i) {
    final selected = _index;
    final before = i * widget.restWidth;
    final grown = (selected != null && selected < i)
        ? widget.selectedWidth - widget.restWidth
        : 0.0;
    return before + grown;
  }

  /// Centre a value in the viewport.
  double _centre(int i, {required bool selected}) {
    final w = selected ? widget.selectedWidth : widget.restWidth;
    return _offsetOf(i) + w / 2 - _viewport / 2;
  }

  @override
  void didUpdateWidget(_PillScale old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    if (widget.value == _self) return;
    final i = _index;
    if (i == null || !_scroll.hasClients || _viewport == 0) return;
    final target = _centre(i, selected: true)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _index;

    return LayoutBuilder(
      builder: (context, box) {
        _viewport = box.maxWidth;

        // Opened with the chosen value in the middle. Done once, so
        // scrolling away and tapping does not snap back.
        if (!_placed) {
          _placed = true;
          final want = selected ?? widget.startAt;
          final offset =
              _centre(want, selected: selected == want).clamp(0.0, 1e9);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.jumpTo(
                  offset.clamp(0.0, _scroll.position.maxScrollExtent));
            }
          });
        }

        return SizedBox(
          // Tall enough for the chosen pill, which stands above the track
          // rather than sitting inside it.
          height: _Fib.s55,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The track is only as tall as the smaller numbers need: 21
              // around a 13 point figure, which is the next step down and
              // leaves no more room than the line itself takes. At 34 there
              // was a band of sand above and below the text doing nothing.
              Container(
                height: _Fib.s21,
                decoration: BoxDecoration(
                  color: Bv.sand400,
                  borderRadius: BorderRadius.circular(Bv.rMd),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(Bv.rMd),
                child: ListView.builder(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.values.length,
                  itemBuilder: (context, i) {
                    final on = i == selected;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _self = widget.values[i];
                        widget.onChanged(widget.values[i]);
                      },
                      child: SizedBox(
                        width: on ? widget.selectedWidth : widget.restWidth,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 4),
                          decoration: on
                              ? BoxDecoration(
                                  color: widget.marker.fill,
                                  borderRadius:
                                      BorderRadius.circular(Bv.rMd),
                                  border: Border.all(
                                      color: widget.marker.edge, width: 1.5),
                                )
                              : null,
                          child: Center(
                            child: Padding(
                              // Close in on the number rather than leaving
                              // it floating in a wide pill.
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: FittedBox(
                                // Lets the pill be sized to the usual value
                                // while an unusually long one shrinks to fit
                                // rather than being cut off.
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  widget.format(widget.values[i]),
                                  style: on
                                      ? BvType.metric.copyWith(
                                          fontSize: widget.selectedSize,
                                          fontWeight: FontWeight.w700,
                                          color: Bv.ink900,
                                        )
                                      : BvType.metric.copyWith(
                                          fontSize: widget.restSize,
                                          color: Bv.ink600,
                                          fontStyle: widget.restItalic
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A narrow vertical wheel of counts, standing beside the table.
///
/// One for the whole table rather than one per row: it changes whichever row
/// is focused, so a two sided set nudges the right side then the left
/// without two controls competing for the same strip of screen.
class _RepsWheel extends StatefulWidget {
  const _RepsWheel({
    required this.values,
    required this.value,
    required this.onChanged,
    required this.marker,
  });

  final List<int> values;
  final int? value;
  final ValueChanged<int> onChanged;
  final _Marker marker;

  @override
  State<_RepsWheel> createState() => _RepsWheelState();
}

class _RepsWheelState extends State<_RepsWheel> {
  static const _itemExtent = _Fib.s34;
  late FixedExtentScrollController _c;

  /// The wheel reports a selection while it is first laying itself out, and
  /// again whenever it is moved to follow a number changed elsewhere.
  /// Neither is the user choosing anything, and passing either on would
  /// rebuild the sheet in the middle of building it.
  bool _ready = false;
  bool _programmatic = false;

  int _indexOf(int? v) {
    if (v == null) return widget.values.indexOf(8).clamp(0, widget.values.length - 1);
    var best = 0, bestD = 1 << 30;
    for (var i = 0; i < widget.values.length; i++) {
      final d = (widget.values[i] - v).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void initState() {
    super.initState();
    _c = FixedExtentScrollController(initialItem: _indexOf(widget.value));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ready = true;
    });
  }

  @override
  void didUpdateWidget(_RepsWheel old) {
    super.didUpdateWidget(old);
    // Follows the number when it is changed elsewhere — by the big scale, by
    // typing, or by the focus moving to the other side.
    if (!_c.hasClients) return;
    final want = _indexOf(widget.value);
    if (_c.selectedItem == want) return;
    _programmatic = true;
    _c.jumpToItem(want);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _programmatic = false;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _indexOf(widget.value);
    return SizedBox(
      // Wide enough for the marker, which stands out either side of the
      // track rather than sitting inside it.
      width: _Fib.s34,
      // Three values, and a fixed height: a wheel with no bound on it grows
      // to whatever it is given, which here was the whole sheet.
      height: _itemExtent * 3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The track is only as wide as the smaller numbers need, the same
          // as the horizontal scales are only as tall.
          Container(
            width: _Fib.s21,
            decoration: BoxDecoration(
              color: Bv.sand400,
              borderRadius: BorderRadius.circular(Bv.rMd),
            ),
          ),
          Container(
            height: _itemExtent - 4,
            decoration: BoxDecoration(
              color: widget.marker.fill,
              borderRadius: BorderRadius.circular(Bv.rSm),
              border: Border.all(color: widget.marker.edge, width: 1.5),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _c,
            itemExtent: _itemExtent,
            perspective: 0.004,
            diameterRatio: 1.4,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) {
              if (!_ready || _programmatic) return;
              if (widget.values[i] == widget.value) return;
              HapticFeedback.selectionClick();
              widget.onChanged(widget.values[i]);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.values.length,
              builder: (context, i) => Center(
                child: Text(
                  '${widget.values[i]}',
                  // Set outright rather than taken from the sequence: these
                  // were chosen for this wheel, and 13 for the unselected
                  // left them too faint beside a 21 point figure.
                  style: i == selected
                      ? BvType.metric.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Bv.ink900,
                        )
                      : BvType.metric.copyWith(
                          fontSize: 15,
                          color: Bv.ink600,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetEditorSheetState extends State<SetEditorSheet> {
  final _weight = <int, TextEditingController>{};
  final _value = <int, TextEditingController>{};
  /// One effort rating per side. The weaker side often works harder at the
  /// same load, which is the whole reason for logging sides separately.
  final _rpe = <int, double?>{};

  /// Unit per set, not per exercise. The same cable exercise gets done on a
  /// machine marked in pounds one day and one marked in kilograms the next,
  /// so which it was belongs to the set. The exercise's unit is only the
  /// default.
  final _unit = <int, String>{};

  /// Focus for each number field, so tapping a cell that is already chosen
  /// puts the cursor in it.
  final _nodes = <String, FocusNode>{};

  /// Which cell is being typed into, as "rowId-field". A cell shows its
  /// scale when first tapped and only opens the keyboard when tapped again,
  /// so reaching for the scale never covers half the sheet.
  String? _typing;

  FocusNode _nodeFor(String key) =>
      _nodes.putIfAbsent(key, () => FocusNode());

  int _focusedRow = 0;

  // Kept for the moment, not deleted: until the wheel proves itself, the
  // arrangement where one scale served both weight and count may be worth
  // returning to. Restoring it means uncommenting this, the branch in
  // _scale below, and the two assignments in _cell and the unit button.
  //
  // /// Which of the two the upper scale is driving. Tapping either moves
  // /// it, so there is one scale rather than two.
  // _Field _field = _Field.weight;

  /// The sides of this set, held here rather than read from the widget.
  ///
  /// Splitting a set changes how many there are, so the sheet reloads them
  /// and rebuilds rather than closing: it was closing the session screen
  /// along with itself.
  late List<Map<String, dynamic>> _rows;

  /// Equipment weights exactly as recorded, each with its own unit. Never
  /// converted: a converted chip enters a converted number, which is how
  /// 32.5 kg became 71.65 lb in the log.
  List<({double weight, String unit})> _chipWeights = const [];

  @override
  void initState() {
    super.initState();
    _rows = widget.rows;
    _fillControllers();
    _focusedRow = _rows.first['id'] as int;
    _loadChips();
  }

  /// A controller per side per number, from whatever rows are current.
  void _fillControllers() {
    for (final r in _rows) {
      final id = r['id'] as int;
      final w = (r['weight_entered'] as num?)?.toDouble();
      _weight[id] ??= TextEditingController();
      _value[id] ??= TextEditingController();
      _weight[id]!.text = w == null ? '' : num2(w);
      _value[id]!.text = _valueText(r);
      _rpe[id] = (r['rpe'] as num?)?.toDouble();
      _unit[id] = (r['entry_unit'] as String?) ?? widget.unit;
    }
  }

  String _valueText(Map<String, dynamic> r) {
    switch (widget.setType) {
      case SetType.time:
        final v = r['duration_sec'] as int?;
        return v == null ? '' : '$v';
      case SetType.distance:
        final v = r['distance_steps'] as int?;
        return v == null ? '' : '$v';
      default:
        final v = r['reps'] as int?;
        return v == null ? '' : '$v';
    }
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    for (final c in _weight.values) {
      c.dispose();
    }
    for (final c in _value.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Quick-pick chips come from the weights on your Equipment page, narrowed
  /// to the kinds this exercise could actually use.
  ///
  /// Each keeps the unit it was recorded in. Converting them was the cause of
  /// odd figures in the log: a stack marked 32.5 kg offered as 71.65 on a
  /// pound exercise, and tapping it stored 71.65 rather than what the machine
  /// actually said.
  Future<void> _loadChips() async {
    final ex = ExerciseLibrary.get(widget.exKey);
    final relevant = ex == null ? <String>[] : EquipKind.kindsFor(ex.equipment);
    final all = await Db.equipment();
    // Only fall back to every weight when the exercise names no equipment we
    // recognise. A cable machine must never offer dumbbell weights.
    final pool = relevant.isEmpty
        ? all
        : all.where((e) => relevant.contains(e['kind'])).toList();

    final seen = <String>{};
    final list = <({double weight, String unit})>[];
    for (final e in pool) {
      final w = (e['weight'] as num).toDouble();
      final u = e['unit'] as String;
      if (seen.add('$w$u')) list.add((weight: w, unit: u));
    }
    // The exercise's own unit first, so the usual machine leads.
    list.sort((a, b) {
      if (a.unit != b.unit) return a.unit == widget.unit ? -1 : 1;
      return a.weight.compareTo(b.weight);
    });

    if (!mounted) return;
    setState(() => _chipWeights = list);
  }

  String get _valueLabel {
    switch (widget.setType) {
      case SetType.time:
        return 'Seconds';
      case SetType.distance:
        return 'Steps';
      default:
        return 'Reps';
    }
  }

  /// Where the effort row opens.
  ///
  /// On what the routine asked for, so the prescription is under your thumb,
  /// or on six when nothing was asked. The whole scale stays reachable by
  /// dragging: what is prescribed decides the starting place, not the limit.
  int get _rpeStart {
    final lo = widget.targetRpeMin;
    if (lo != null) {
      final i = rpeChoices.indexWhere((v) => v >= lo);
      if (i >= 0) return i;
    }
    final six = rpeChoices.indexOf(6.0);
    return six < 0 ? 0 : six;
  }

  /// Split this set into a right and a left, or put the two back together.
  ///
  /// Saves what is on screen first, then reloads the sides in place. The
  /// sheet stays open: an earlier version closed and reopened it, which took
  /// the session screen with it.
  Future<void> _toggleSides() async {
    final weId = widget.weId;
    if (weId == null) return;
    final split = _rows.length > 1;

    if (split) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Put the sides together?'),
          content: const Text(
              'The heavier side is kept and the other is dropped. Where both '
              'were the same load, the one with more repetitions is kept.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Combine')),
          ],
        ),
      );
      if (ok != true) return;
    }

    await _save(done: false, close: false);
    if (split) {
      await Db.mergeSet(weId, widget.setNumber);
    } else {
      await Db.splitSet(weId, widget.setNumber);
    }

    // Reloaded in place. Closing and reopening was popping the session
    // screen as well as this sheet.
    final all = await Db.setsFor(weId);
    final fresh = all
        .where((s) => s['set_number'] == widget.setNumber)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (!mounted || fresh.isEmpty) return;
    setState(() {
      _rows = fresh;
      _fillControllers();
      _focusedRow = _rows.first['id'] as int;
      _typing = null;
    });
  }

  Future<void> _save({required bool done, bool close = true}) async {
    for (final r in _rows) {
      final id = r['id'] as int;
      final weightText = _weight[id]!.text.trim();
      final valueText = _value[id]!.text.trim();
      final weight = weightText.isEmpty ? null : double.tryParse(weightText);
      final value = valueText.isEmpty ? null : int.tryParse(valueText);

      await Db.saveSet(
        id,
        setType: widget.setType,
        // What the machine in front of you said, not what the exercise is
        // configured as.
        unit: _unit[id] ?? widget.unit,
        weightEntered: weight,
        reps: widget.setType == SetType.reps ? value : null,
        durationSec: widget.setType == SetType.time ? value : null,
        distanceSteps: widget.setType == SetType.distance ? value : null,
        rpe: _rpe[id],
        done: done,
      );
    }
    // Not closed when saving on the way to something else, such as
    // splitting the set: that pop was taking the sheet with it.
    if (close && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // One line rather than two. The card behind already names the
            // exercise, so this only has to say which set of it, and two
            // lines of heading cost height the scales want.
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Set ${widget.setNumber}',
                          style: theme.textTheme.titleLarge,
                        ),
                        TextSpan(
                          text: '  :  ',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: Bv.sand500),
                        ),
                        TextSpan(
                          text: widget.exerciseName,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: Bv.ink600),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Up here rather than in the table header: one arm or two is
                // a fact about the whole set, not about a column of it, and
                // the corner is where something that changes the shape of
                // what is below belongs.
                if (widget.weId != null)
                  IconButton(
                    tooltip: _rows.length > 1
                        ? 'Combine the sides'
                        : 'Split the sides',
                    icon: Icon(
                      _rows.length > 1 ? Icons.compress : Icons.expand,
                      size: 26,
                      color: Bv.forest700,
                    ),
                    onPressed: _toggleSides,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _setTable(),
            _weightChips(),
            const SizedBox(height: 14),
            // Two scales, always. Effort is set on every logged set, so
            // putting it behind a tap costs one on every set to save a
            // little height once.
            _scale(),
            const SizedBox(height: 6),
            _rpeScale(),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _save(done: false),
                    child: const Text('Save draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => _save(done: true),
                    icon: const Icon(Icons.check),
                    label: const Text('Log set'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The weights you own, in the unit this set is being entered in.
  ///
  /// Only that unit is offered, so the row reads as a rack rather than as a
  /// conversion table, and every chip already carries the figure printed on
  /// the thing you are about to pick up. The unit beside the field switches
  /// which rack is shown, which is how the two cable stacks are reached.
  ///
  /// Four at a time, nearest what is already in the field. A full rack ran
  /// to three rows and became the loudest thing on the sheet for a list you
  /// rarely read past the first few of; the rest open in a grid.
  Widget _weightChips() {
    final unit = _unit[_focusedRow] ?? widget.unit;
    final mine = _chipWeights.where((e) => e.unit == unit).toList();
    final other = _chipWeights.where((e) => e.unit != unit).length;

    if (mine.isEmpty && other == 0) return const SizedBox.shrink();

    // Nearest the current figure rather than the lightest four, so the ones
    // offered are those either side of what is already being lifted.
    final current = double.tryParse(_weight[_focusedRow]?.text.trim() ?? '');
    final shown = mine.toList();
    if (current != null && shown.length > 4) {
      shown.sort((a, b) =>
          (a.weight - current).abs().compareTo((b.weight - current).abs()));
    }
    final first = shown.take(4).toList()
      ..sort((a, b) => a.weight.compareTo(b.weight));

    return Padding(
      // Indented to the weight column, since that is the only thing these
      // fill in. Starting at the sheet's edge left them adrift of the table
      // above.
      padding: const EdgeInsets.only(left: 22, top: 8),
      child: mine.isEmpty
          // Everything owned is recorded in the other unit. Said plainly,
          // rather than showing converted figures that match nothing on any
          // machine.
          ? Text(
              'Nothing recorded in $unit. '
              'Tap ${unit == 'kg' ? 'LB' : 'KG'} beside the weight to see the '
              'other $other.',
              style: BvType.bodySm,
            )
          : Row(
              children: [
                for (final e in first) ...[
                  _weightChip(e.weight),
                  const SizedBox(width: 6),
                ],
                if (mine.length > 4)
                  // Everything else, in order, rather than a row that wraps.
                  SizedBox(
                    height: 32,
                    width: 36,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _allWeights(mine),
                      child: const Icon(Icons.add, size: 16),
                    ),
                  ),
              ],
            ),
    );
  }

  /// One quick-pick weight.
  ///
  /// All the same width whatever the figure, so four of them read as a row
  /// of buttons rather than as four differently sized blobs.
  Widget _weightChip(double w) => SizedBox(
        height: 32,
        width: 56,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            visualDensity: VisualDensity.compact,
            textStyle: BvType.metric.copyWith(fontSize: _Fib.s13),
          ),
          onPressed: () {
            _weight[_focusedRow]?.text = num2(w);
            setState(() {});
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(num2(w)),
          ),
        ),
      );

  /// Every weight of this kind, lightest first, four to a row.
  Future<void> _allWeights(List<({double weight, String unit})> all) async {
    final sorted = all.toList()
      ..sort((a, b) => a.weight.compareTo(b.weight));

    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EVERY WEIGHT  ${sorted.first.unit.toUpperCase()}',
                  style: BvType.label),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.1,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final e in sorted)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        textStyle: BvType.metric.copyWith(fontSize: _Fib.s13),
                      ),
                      onPressed: () => Navigator.pop(c, e.weight),
                      child: Text(num2(e.weight)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    _weight[_focusedRow]?.text = num2(picked);
    setState(() {});
  }

  /// The upper scale, always weight.
  ///
  /// Counts have the wheel beside the table and effort has the row below, so
  /// nothing switches: each number has one place it is set from.
  ///
  /// The version where this scale switched between weight and count is kept
  /// below rather than removed, since whether the wheel is better than a
  /// second scale is the thing being tried.
  Widget _scale() {
    final unit = _unit[_focusedRow] ?? widget.unit;
    final max = unit == 'lb' ? 600.0 : 300.0;
    // Quarters up to fifty, where a plate or a stack can actually change by
    // that much, then two and a half beyond it. Keeping quarters the whole
    // way would put nine hundred steps between fifty and three hundred,
    // none of which any bar can be loaded to.
    final values = [
      for (var v = 0.25; v <= 50; v += 0.25) v,
      for (var v = 52.5; v <= max; v += 2.5) v,
    ];
    final current = double.tryParse(_weight[_focusedRow]?.text.trim() ?? '');
    final start = current != null
        ? values.indexWhere((v) => v >= current)
        : values.indexWhere((v) => v >= 1);

    return _scaleBlock(
      // Two letters rather than six: stacked, WEIGHT would stand half again
      // as tall as the scale beside it and tower over RPE below. WT is what
      // is written on a plate chart anyway.
      'WT',
      _PillScale(
        key: const ValueKey('scale-weight'),
        values: values,
        value: current,
        format: num2,
        startAt: start < 0 ? 0 : start,
        marker: _Marker.weight,
        selectedSize: _Fib.s21,
        restSize: _Fib.s13,
        restItalic: true,
        // 34 and 55 sit in the ratio. A weight of five characters shrinks
        // slightly to fit rather than the pill being widened to 89 for the
        // few weights that need it.
        restWidth: _Fib.s34,
        selectedWidth: _Fib.s55,
        onChanged: (v) {
          _weight[_focusedRow]?.text = num2(v);
          setState(() {});
        },
      ),
      gap: 0,
    );

    // The count branch, from when this scale switched. Put back by guarding
    // the block above with `if (_field == _Field.weight)` and restoring
    // this after it.
    //
    // final label = switch (widget.setType) {
    //   SetType.time => 'SECONDS',
    //   SetType.distance => 'STEPS',
    //   _ => 'REPS',
    // };
    // final step = widget.setType == SetType.reps ? 1 : 5;
    // final vmax = widget.setType == SetType.reps ? 60 : 600;
    // final values = [for (var v = step; v <= vmax; v += step) v.toDouble()];
    // final current = double.tryParse(_value[_focusedRow]?.text.trim() ?? '');
    // final opening = switch (widget.setType) {
    //   SetType.time => 30.0,
    //   SetType.distance => 20.0,
    //   _ => 8.0,
    // };
    // final start = values.indexWhere((v) => v >= (current ?? opening));
    //
    // return _scaleBlock(
    //   label,
    //   _PillScale(
    //     key: const ValueKey('scale-value'),
    //     values: values,
    //     value: current,
    //     format: (v) => '${v.round()}',
    //     startAt: start < 0 ? 0 : start,
    //     onChanged: (v) {
    //       _value[_focusedRow]?.text = '${v.round()}';
    //       setState(() {});
    //     },
    //   ),
    // );
  }

  /// The lower scale, always effort. Shown whatever else is being changed,
  /// since it is set on every logged set.
  Widget _rpeScale() {
    return _scaleBlock(
      'RPE',
      _PillScale(
        key: const ValueKey('scale-rpe'),
        values: rpeChoices,
        value: _rpe[_focusedRow],
        format: num2,
        startAt: _rpeStart,
        marker: _Marker.effort,
        selectedSize: _Fib.s21,
        restSize: _Fib.s13,
        restItalic: true,
        // 34 and 55 sit in the ratio, and two characters fit 55 at 21 with
        // room to spare.
        restWidth: _Fib.s34,
        selectedWidth: _Fib.s55,
        onChanged: (v) => setState(() => _rpe[_focusedRow] = v),
      ),
      gap: 0,
    );
  }

  /// A scale with its name stacked down the left rather than written above
  /// it.
  ///
  /// One letter per line, not turned on its side: the label is six
  /// characters at most and stacking it keeps it upright and readable, where
  /// a rotated word has to be tilted to read and a heading above each scale
  /// put a line of text between two controls that belong together.
  Widget _scaleBlock(String label, Widget scale, {double gap = 8}) {
    final side = _rows.length > 1
        ? _rows.firstWhere((r) => r['id'] == _focusedRow,
            orElse: () => _rows.first)['side'] as String
        : '';
    final letters = label.split('');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in letters)
                  Text(
                    c,
                    // Darker than a section label: these name the two
                    // controls that do most of the work on this sheet, and
                    // at the usual grey they read as a caption on something
                    // rather than as the thing's name.
                    style: BvType.label
                        .copyWith(height: 1.05, color: Bv.ink900),
                  ),
                if (side.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(side,
                      style: BvType.label
                          .copyWith(height: 1.05, color: Bv.forest800)),
                ],
              ],
            ),
          ),
          SizedBox(width: gap),
          Expanded(child: scale),
        ],
      ),
    );
  }

  /// The set as a small table: a column for each number, a row for each
  /// side.
  ///
  /// Each label is written once at the top rather than on every cell, and
  /// the sides are named by a letter at the start of their row. A unilateral
  /// set was otherwise repeating the word Weight, the word Reps, the word
  /// RPE and the unit twice over for two numbers and a rating.
  Widget _setTable() {
    final multi = _rows.length > 1;
    const sideCol = 22.0;
    const gap = 10.0;
    // Fixed rather than shares of the row. Three numbers do not need the
    // full width, and setting them outright is the only way to narrow all
    // three at once: proportions can only move space between them.
    const weightCol = 92.0;
    const valueCol = 68.0;
    const rpeCol = 68.0;

    // Larger than the labels elsewhere: these name the columns of a table
    // rather than introducing a section, and at the usual size they were
    // easy to miss above numbers set this big.
    final headStyle =
        BvType.label.copyWith(fontSize: _Fib.s13, height: 1.1);

    Widget header() => Padding(
          // Close above the cells rather than floating clear of them: a
          // heading that far from its column reads as a separate line of
          // text rather than as the name of what is beneath it.
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              // Always reserved, even with one row and no letter to put in
              // it. Adding the column only when there were two sides moved
              // the whole table sideways on splitting, which read as the
              // layout jumping rather than as a row appearing.
              const SizedBox(width: sideCol),
              SizedBox(
                width: weightCol,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The same two letters the scale uses. Spelled out, this
                    // plus the unit button came to more than the column is
                    // wide, and pushed the other two headings out of line
                    // with their columns.
                    Flexible(
                      child: Text('WT',
                          style: headStyle,
                          maxLines: 1,
                          overflow: TextOverflow.clip),
                    ),
                    const SizedBox(width: 4),
                    _unitButton(),
                  ],
                ),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: valueCol,
                child: Text(_valueLabel.toUpperCase(),
                    style: headStyle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: rpeCol,
                child: Text('RPE',
                    style: headStyle, textAlign: TextAlign.center),
              ),
            ],
          ),
        );

    Widget row(Map<String, dynamic> r) {
      final id = r['id'] as int;
      final side = r['side'] as String;
      final rpe = _rpe[id];

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: sideCol,
              child: multi
                  ? Text(
                      side == 'R' ? 'R' : 'L',
                      style: BvType.label.copyWith(
                        color: _focusedRow == id ? Bv.forest800 : Bv.ink600,
                      ),
                    )
                  : null,
            ),
            SizedBox(
              width: weightCol,
              child: _cell(
                id: id,
                controller: _weight[id]!,
                field: _Field.weight,
                decimal: true,
                marker: _Marker.weight,
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: valueCol,
              child: _cell(
                id: id,
                controller: _value[id]!,
                field: _Field.value,
                decimal: false,
                digits: 2,
                marker: _Marker.count,
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: rpeCol,
              child: _rpeCell(id, rpe),
            ),
          ],
        ),
      );
    }

    // The wheel stands alongside the rows rather than inside one, so it is
    // the same height as the table however many sides the exercise has.
    final step = widget.setType == SetType.reps ? 1 : 5;
    final vmax = widget.setType == SetType.reps ? 60 : 600;
    final wheelValues = [for (var v = step; v <= vmax; v += step) v];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header(),
        Row(
          // Aligned to the top, not centred. The wheel is taller than a
          // single row, so centring pushed the cells down by half the
          // difference and opened a gap under the headings that looked like
          // padding but was not.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _rows.map(row).toList(),
            ),
            // Pushes the wheel to the far edge rather than letting it follow
            // the table: it stays put while the columns are narrowed.
            const Spacer(),
            // A rule between them, so the wheel reads as a control standing
            // beside the table rather than as a fourth column of it. In the
            // track's own sand it was invisible against the cells.
            Container(
              width: 1.5,
              height: _Fib.s34 * 3,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: Bv.sand500,
            ),
            _RepsWheel(
              values: wheelValues,
              value: int.tryParse(_value[_focusedRow]?.text.trim() ?? ''),
              marker: _Marker.count,
              onChanged: (v) {
                _value[_focusedRow]?.text = '$v';
                setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  /// Which machine this set was done on. In the header because both sides of
  /// one set are done on the same one.
  Widget _unitButton() {
    final unit = _unit[_focusedRow] ?? widget.unit;
    return Material(
      color: Bv.sage200,
      borderRadius: BorderRadius.circular(Bv.rSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Bv.rSm),
        onTap: () => setState(() {
          final next = unit == 'kg' ? 'lb' : 'kg';
          for (final r in _rows) {
            _unit[r['id'] as int] = next;
          }
          // _field = _Field.weight;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(unit.toUpperCase(),
                  style: BvType.label.copyWith(color: Bv.forest800)),
              const Icon(Icons.swap_horiz, size: 13, color: Bv.forest600),
            ],
          ),
        ),
      ),
    );
  }

  /// One number. Tapping it brings up its scale; tapping it again, when its
  /// scale is already showing, opens the keyboard for figures the scale does
  /// not carry.
  ///
  /// The figure sits on the same colour as the marker of the control that
  /// sets it, so a number and the thing that changes it are visibly a pair.
  Widget _cell({
    required int id,
    required TextEditingController controller,
    required _Field field,
    required bool decimal,
    required _Marker marker,
    int digits = 4,
  }) {
    final key = '$id-$field';
    // While the scale switched, this read `_focusedRow == id && _field ==
    // field`, so the outline followed whichever number the scale was on.
    final chosen = _focusedRow == id && field == _Field.weight;
    final typing = _typing == key;
    // A digit in this face is roughly six tenths of its size.
    final size = BvType.metric.fontSize ?? 20;
    final panel = digits * size * 0.62 + 16;

    void choose({bool keyboard = false}) {
      if (!keyboard) FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _focusedRow = id;
        // _field = field;
        _typing = null;
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: choose,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Bv.sand400,
          borderRadius: BorderRadius.circular(Bv.rMd),
          border: Border.all(
            color: chosen ? Bv.forest600 : Colors.transparent,
            width: 1.8,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: panel,
            child: TextField(
              controller: controller,
              focusNode: _nodeFor(key),
              readOnly: !typing,
              showCursor: typing,
              textAlign: TextAlign.center,
              keyboardType: decimal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              inputFormatters: [
                decimal
                    ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    : FilteringTextInputFormatter.digitsOnly,
              ],
              style: BvType.metric,
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: true,
                fillColor: marker.fill,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Bv.rSm),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Bv.rSm),
                  borderSide: BorderSide.none,
                ),
              ),
              onTap: () {
                if (typing) return;
                if (chosen) {
                  setState(() => _typing = key);
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _nodeFor(key).requestFocus());
                } else {
                  choose(keyboard: true);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _rpeCell(int id, double? rpe) {
    final size = BvType.metric.fontSize ?? 20;
    // The same two characters the count uses, so the two narrow columns
    // match rather than one being slightly wider for no reason.
    final panel = 2 * size * 0.62 + 16;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() {
          _focusedRow = id;
          _typing = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Bv.sand400,
          borderRadius: BorderRadius.circular(Bv.rMd),
          // No outline, ever. Its scale is always on screen, so there is
          // nothing to say about which cell is driving it; which side is
          // being rated is said by the letter at the start of the row.
          border: Border.all(color: Colors.transparent, width: 1.8),
        ),
        child: Center(
          child: Container(
            width: panel,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _Marker.effort.fill,
              borderRadius: BorderRadius.circular(Bv.rSm),
            ),
            child: Center(
              child: Text(
                rpe == null ? '\u2014' : num2(rpe),
                style: rpe == null
                    ? BvType.metric.copyWith(color: Bv.sand500)
                    : BvType.metric,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

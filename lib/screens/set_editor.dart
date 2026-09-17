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

  @override
  State<SetEditorSheet> createState() => _SetEditorSheetState();
}

/// Which of the two numbers the upper scale is editing. Effort has a scale
/// of its own and is not one of these.
enum _Field { weight, value }

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
  });

  /// How many are in view. Seven is as many as stay readable at the size
  /// the numbers are set in, and the same for every scale so they line up.
  static const visible = 7;

  final List<double> values;
  final double? value;
  final ValueChanged<double> onChanged;
  final String Function(double) format;

  /// Which value the row opens on, when nothing is chosen yet.
  final int startAt;

  @override
  State<_PillScale> createState() => _PillScaleState();
}

class _PillScaleState extends State<_PillScale> {
  final _scroll = ScrollController();
  bool _placed = false;

  int? get _index {
    final v = widget.value;
    if (v == null) return null;
    final i = widget.values.indexOf(v);
    return i == -1 ? null : i;
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
        final step = box.maxWidth / _PillScale.visible;

        // Opened on whatever was chosen, or on what the routine asked for.
        // Done once, so scrolling away and tapping does not snap back.
        if (!_placed) {
          _placed = true;
          final want = selected ?? widget.startAt;
          final offset = ((want - _PillScale.visible ~/ 2) * step)
              .clamp(0.0, double.infinity);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.jumpTo(
                  offset.clamp(0.0, _scroll.position.maxScrollExtent));
            }
          });
        }

        return Container(
          height: 52,
          decoration: BoxDecoration(
            color: Bv.sand400,
            borderRadius: BorderRadius.circular(Bv.rMd),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            itemExtent: step,
            itemCount: widget.values.length,
            itemBuilder: (context, i) {
              final on = i == selected;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onChanged(widget.values[i]);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 2, vertical: 5),
                  decoration: on
                      ? BoxDecoration(
                          color: Bv.sage200,
                          borderRadius: BorderRadius.circular(Bv.rMd),
                          border:
                              Border.all(color: Bv.forest600, width: 1.5),
                        )
                      : null,
                  child: Center(
                    child: Text(
                      widget.format(widget.values[i]),
                      style: on
                          ? BvType.metric.copyWith(color: Bv.forest800)
                          : BvType.metric.copyWith(color: Bv.ink600),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
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

  /// Which of the three the scale beneath is driving. Tapping any of them
  /// moves it, so there is one scale rather than three, and it is always
  /// the one for the number being changed.
  _Field _field = _Field.weight;

  /// Equipment weights exactly as recorded, each with its own unit. Never
  /// converted: a converted chip enters a converted number, which is how
  /// 32.5 kg became 71.65 lb in the log.
  List<({double weight, String unit})> _chipWeights = const [];

  @override
  void initState() {
    super.initState();
    for (final r in widget.rows) {
      final id = r['id'] as int;
      final w = (r['weight_entered'] as num?)?.toDouble();
      _weight[id] = TextEditingController(text: w == null ? '' : num2(w));
      _value[id] = TextEditingController(text: _valueText(r));
      _rpe[id] = (r['rpe'] as num?)?.toDouble();
      _unit[id] = (r['entry_unit'] as String?) ?? widget.unit;
    }
    _focusedRow = widget.rows.first['id'] as int;
    _loadChips();
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

  Future<void> _save({required bool done}) async {
    for (final r in widget.rows) {
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
    if (mounted) Navigator.pop(context, true);
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
            Text('Set ${widget.setNumber}', style: theme.textTheme.titleLarge),
            Text(widget.exerciseName,
                style: theme.textTheme.bodySmall, maxLines: 1),
            const SizedBox(height: 16),
            _setTable(),
            _weightChips(),
            const SizedBox(height: 14),
            // Two scales, always. Effort is set on every logged set, so
            // putting it behind a tap costs one on every set to save a
            // little height once.
            _scale(),
            const SizedBox(height: 12),
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
  Widget _weightChips() {
    final unit = _unit[_focusedRow] ?? widget.unit;
    final mine = _chipWeights.where((e) => e.unit == unit).toList();
    final other = _chipWeights.where((e) => e.unit != unit).length;

    if (mine.isEmpty && other == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text('WEIGHT', style: BvType.label),
        const SizedBox(height: 6),
        if (mine.isEmpty)
          // Everything owned is recorded in the other unit. Said plainly,
          // rather than showing converted figures that match nothing on any
          // machine.
          Text(
            'Nothing recorded in $unit. '
            'Tap ${unit == 'kg' ? 'LB' : 'KG'} beside the weight to see the '
            'other $other.',
            style: BvType.bodySm,
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: mine
                .map((e) => ActionChip(
                      label: Text(num2(e.weight)),
                      onPressed: () {
                        _weight[_focusedRow]?.text = num2(e.weight);
                        setState(() {});
                      },
                    ))
                .toList(),
          ),
      ],
    );
  }

  /// The upper scale: whichever of weight or count was last tapped.
  ///
  /// Weight moves in quarters up to fifty and in larger steps above it;
  /// counts move in ones. Seven are in view and the rest are a drag away.
  Widget _scale() {
    final unit = _unit[_focusedRow] ?? widget.unit;

    if (_field == _Field.weight) {
        final max = unit == 'lb' ? 600.0 : 300.0;
        // Quarters up to fifty, where a plate or a stack can actually change
        // by that much, then two and a half beyond it. Keeping quarters the
        // whole way would put nine hundred steps between fifty and three
        // hundred, none of which any bar can be loaded to.
        final values = [
          for (var v = 0.25; v <= 50; v += 0.25) v,
          for (var v = 52.5; v <= max; v += 2.5) v,
        ];
        final current =
            double.tryParse(_weight[_focusedRow]?.text.trim() ?? '');
        final start = current != null
            ? values.indexWhere((v) => v >= current)
            : values.indexWhere((v) => v >= 1);

        return _scaleBlock(
          'WEIGHT  ${unit.toUpperCase()}',
          _PillScale(
            // A key per scale, or Flutter reuses the state of whichever was
            // here before and the new scale inherits its scroll position:
            // two thousand pixels into the weights lands nowhere sensible
            // among sixty repetitions.
            key: const ValueKey('scale-weight'),
            values: values,
            value: current,
            format: num2,
            startAt: start < 0 ? 0 : start,
            onChanged: (v) {
              _weight[_focusedRow]?.text = num2(v);
              setState(() {});
            },
          ),
        );
    }

    final label = switch (widget.setType) {
      SetType.time => 'SECONDS',
      SetType.distance => 'STEPS',
      _ => 'REPS',
    };
    final step = widget.setType == SetType.reps ? 1 : 5;
    final vmax = widget.setType == SetType.reps ? 60 : 600;
    final values = [for (var v = step; v <= vmax; v += step) v.toDouble()];
    final current = double.tryParse(_value[_focusedRow]?.text.trim() ?? '');
    final opening = switch (widget.setType) {
      SetType.time => 30.0,
      SetType.distance => 20.0,
      _ => 8.0,
    };
    final start = values.indexWhere((v) => v >= (current ?? opening));

    return _scaleBlock(
      label,
      _PillScale(
        key: const ValueKey('scale-value'),
        values: values,
        value: current,
        format: (v) => '${v.round()}',
        startAt: start < 0 ? 0 : start,
        onChanged: (v) {
          _value[_focusedRow]?.text = '${v.round()}';
          setState(() {});
        },
      ),
    );
  }

  /// The lower scale, always effort. Shown whatever else is being changed,
  /// since it is set on every logged set.
  Widget _rpeScale() {
    final current = _rpe[_focusedRow];
    return _scaleBlock(
      'RPE',
      _PillScale(
        key: const ValueKey('scale-rpe'),
        values: rpeChoices,
        value: current,
        format: num2,
        startAt: _rpeStart,
        onChanged: (v) => setState(() => _rpe[_focusedRow] = v),
      ),
      onClear: current == null
          ? null
          : () => setState(() => _rpe[_focusedRow] = null),
    );
  }

  Widget _scaleBlock(String label, Widget scale, {VoidCallback? onClear}) {
    final side = widget.rows.length > 1
        ? '  ${widget.rows.firstWhere((r) => r['id'] == _focusedRow, orElse: () => widget.rows.first)['side']}'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$label$side', style: BvType.label),
            const Spacer(),
            if (onClear != null)
              TextButton(onPressed: onClear, child: const Text('clear')),
          ],
        ),
        const SizedBox(height: 4),
        scale,
      ],
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
    final multi = widget.rows.length > 1;
    const sideCol = 22.0;

    Widget header() => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              if (multi) const SizedBox(width: sideCol),
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Text('WEIGHT', style: BvType.label),
                    const SizedBox(width: 6),
                    _unitButton(),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(_valueLabel.toUpperCase(), style: BvType.label),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: Text('RPE', style: BvType.label)),
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
            if (multi)
              SizedBox(
                width: sideCol,
                child: Text(
                  side == 'R' ? 'R' : 'L',
                  style: BvType.label.copyWith(
                    color: _focusedRow == id ? Bv.forest800 : Bv.ink600,
                  ),
                ),
              ),
            Expanded(
              flex: 4,
              child: _cell(
                id: id,
                controller: _weight[id]!,
                field: _Field.weight,
                decimal: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: _cell(
                id: id,
                controller: _value[id]!,
                field: _Field.value,
                decimal: false,
                digits: 3,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _rpeCell(id, rpe),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header(),
        ...widget.rows.map(row),
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
          for (final r in widget.rows) {
            _unit[r['id'] as int] = next;
          }
          _field = _Field.weight;
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
  /// The cell is the scale's own sand with a narrow cream panel for the
  /// figure itself, sized to four characters. The sand is the part that
  /// reaches the scale, the cream the part that reaches the keyboard, and
  /// which column it belongs to is said once at the top.
  Widget _cell({
    required int id,
    required TextEditingController controller,
    required _Field field,
    required bool decimal,
    int digits = 4,
  }) {
    final key = '$id-$field';
    final chosen = _focusedRow == id && _field == field;
    final typing = _typing == key;
    // A digit in this face is roughly six tenths of its size.
    final size = BvType.metric.fontSize ?? 20;
    final panel = digits * size * 0.62 + 16;

    void choose({bool keyboard = false}) {
      if (!keyboard) FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _focusedRow = id;
        _field = field;
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
          child: Container(
            width: panel,
            decoration: BoxDecoration(
              color: Bv.cream100,
              borderRadius: BorderRadius.circular(Bv.rSm),
            ),
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
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
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
    final panel = 3 * size * 0.62 + 16;

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
              color: Bv.cream100,
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

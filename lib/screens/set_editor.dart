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
  });

  final String exerciseName;
  final String exKey;
  final String setType;
  final String unit;
  final int setNumber;
  final List<Map<String, dynamic>> rows;

  @override
  State<SetEditorSheet> createState() => _SetEditorSheetState();
}

class _SetEditorSheetState extends State<SetEditorSheet> {
  final _weight = <int, TextEditingController>{};
  final _value = <int, TextEditingController>{};
  /// One effort rating per side. The weaker side often works harder at the
  /// same load, which is the whole reason for logging sides separately.
  final _rpe = <int, double?>{};
  int _focusedRow = 0;
  List<double> _chipWeights = const [];

  /// The rotating counter and the text field are two views of one value.
  /// `_fromWheel` breaks the feedback loop when one updates the other.
  late final List<int> _items = _buildItems();
  late final FixedExtentScrollController _wheel;
  bool _fromWheel = false;

  List<int> _buildItems() {
    switch (widget.setType) {
      case SetType.time:
        return [for (var s = 5; s <= 300; s += 5) s];
      case SetType.distance:
        return [for (var s = 5; s <= 200; s += 5) s];
      default:
        return [for (var r = 1; r <= 40; r++) r];
    }
  }

  /// Nearest wheel position to whatever is typed. Falls back to a sensible
  /// starting point when the field is empty.
  int _indexFor(String text) {
    var v = int.tryParse(text.trim());
    v ??= switch (widget.setType) {
      SetType.time => 30,
      SetType.distance => 20,
      _ => 8,
    };
    var best = 0, bestD = 1 << 30;
    for (var i = 0; i < _items.length; i++) {
      final d = (_items[i] - v).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _syncWheelFromText() {
    if (_fromWheel || !_wheel.hasClients) return;
    final ctl = _value[_focusedRow];
    if (ctl == null) return;
    final i = _indexFor(ctl.text);
    if (_wheel.selectedItem != i) _wheel.jumpToItem(i);
  }

  void _focusRow(int id) {
    if (_focusedRow == id) return;
    setState(() => _focusedRow = id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWheelFromText());
  }

  @override
  void initState() {
    super.initState();
    for (final r in widget.rows) {
      final id = r['id'] as int;
      final w = (r['weight_entered'] as num?)?.toDouble();
      _weight[id] = TextEditingController(text: w == null ? '' : num2(w));
      _value[id] = TextEditingController(text: _valueText(r));
      _rpe[id] = (r['rpe'] as num?)?.toDouble();
    }
    _focusedRow = widget.rows.first['id'] as int;
    _wheel = FixedExtentScrollController(
        initialItem: _indexFor(_value[_focusedRow]!.text));
    for (final c in _value.values) {
      c.addListener(_syncWheelFromText);
    }
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
    _wheel.dispose();
    for (final c in _weight.values) {
      c.dispose();
    }
    for (final c in _value.values) {
      c.removeListener(_syncWheelFromText);
      c.dispose();
    }
    super.dispose();
  }

  /// Quick-pick chips come from the weights on your Equipment page, narrowed
  /// to the kinds this exercise could actually use.
  Future<void> _loadChips() async {
    final ex = ExerciseLibrary.get(widget.exKey);
    final relevant = ex == null ? <String>[] : EquipKind.kindsFor(ex.equipment);
    final all = await Db.equipment();
    // Only fall back to every weight when the exercise names no equipment we
    // recognise. A cable machine must never offer dumbbell weights.
    final pool = relevant.isEmpty
        ? all
        : all.where((e) => relevant.contains(e['kind'])).toList();

    final values = <double>{};
    for (final e in pool) {
      values.add(convertWeight(
        (e['weight'] as num).toDouble(),
        e['unit'] as String,
        widget.unit,
      ));
    }
    final list = values.toList()..sort();
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
        unit: widget.unit,
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
            ...widget.rows.map(_sideBlock),
            if (_chipWeights.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('YOUR WEIGHTS (${widget.unit.toUpperCase()})',
                  style: BvType.label),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _chipWeights
                    .map((w) => ActionChip(
                          label: Text(num2(w)),
                          onPressed: () {
                            _weight[_focusedRow]?.text = num2(w);
                            setState(() {});
                          },
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            _wheelPicker(),
            const SizedBox(height: 16),
            _rpeBlock(),
            const SizedBox(height: 20),
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

  /// A rotating counter for the reps field. It and the text field are two
  /// views of the same number: spinning writes into the field, typing moves
  /// the wheel. Neither is the primary — spinning is faster for small
  /// adjustments, typing is better for anything unusual.
  Widget _wheelPicker() {
    final label = switch (widget.setType) {
      SetType.time => 'SECONDS',
      SetType.distance => 'STEPS',
      _ => 'REPS',
    };
    final side = widget.rows.length > 1
        ? '  ${widget.rows.firstWhere((r) => r['id'] == _focusedRow, orElse: () => widget.rows.first)['side']}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label$side', style: BvType.label),
        const SizedBox(height: 4),
        SizedBox(
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // band marking the selected row
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Bv.sage200,
                  borderRadius: BorderRadius.circular(Bv.rMd),
                ),
              ),
              ListWheelScrollView.useDelegate(
                controller: _wheel,
                itemExtent: 38,
                perspective: 0.004,
                diameterRatio: 1.7,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) {
                  HapticFeedback.selectionClick();
                  _fromWheel = true;
                  _value[_focusedRow]?.text = '${_items[i]}';
                  _fromWheel = false;
                  setState(() {});
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: _items.length,
                  builder: (context, i) => Center(
                    child: Text('${_items[i]}', style: BvType.metric),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Effort rating for whichever side is focused, matching how the rotating
  /// counter behaves. Two full chip rows would push the Log button off screen.
  Widget _rpeBlock() {
    final multi = widget.rows.length > 1;
    final side = multi
        ? '  ${widget.rows.firstWhere((r) => r['id'] == _focusedRow, orElse: () => widget.rows.first)['side']}'
        : '';
    final current = _rpe[_focusedRow];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('RPE$side', style: BvType.label),
            const Spacer(),
            if (current != null)
              TextButton(
                onPressed: () => setState(() => _rpe[_focusedRow] = null),
                child: const Text('clear'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: rpeChoices
              .map((v) => ChoiceChip(
                    label: Text(num2(v)),
                    selected: current == v,
                    onSelected: (_) => setState(() => _rpe[_focusedRow] = v),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _sideBlock(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final side = r['side'] as String;
    final focused = _focusedRow == id;
    final rpe = _rpe[id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (side != 'both')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    side == 'R' ? 'Right' : 'Left',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: focused ? Bv.forest800 : Bv.ink600,
                          fontWeight:
                              focused ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),
                  const Spacer(),
                  // Both sides' ratings stay visible, so the chips below only
                  // need to change one at a time.
                  Text(rpe == null ? 'RPE —' : 'RPE ${num2(rpe)}',
                      style: BvType.label),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weight[id],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Weight (${widget.unit})',
                  ),
                  onTap: () => _focusRow(id),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _value[id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: _valueLabel),
                  onTap: () => _focusRow(id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

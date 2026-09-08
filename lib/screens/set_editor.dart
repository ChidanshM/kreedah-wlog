import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db.dart';
import '../library.dart';
import '../util.dart';

/// Edits one set. For a unilateral exercise, [rows] holds two records
/// (right first, then left) which share a single RPE.
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
  int _focusedRow = 0;
  double? _rpe;
  List<double> _chipWeights = const [];

  @override
  void initState() {
    super.initState();
    for (final r in widget.rows) {
      final id = r['id'] as int;
      final w = (r['weight_entered'] as num?)?.toDouble();
      _weight[id] = TextEditingController(text: w == null ? '' : num2(w));
      _value[id] = TextEditingController(text: _valueText(r));
    }
    _rpe = (widget.rows.first['rpe'] as num?)?.toDouble();
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
        rpe: _rpe,
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
              Text('Your weights (${widget.unit})',
                  style: theme.textTheme.labelMedium),
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
            Row(
              children: [
                Text('RPE', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                if (_rpe != null)
                  TextButton(
                    onPressed: () => setState(() => _rpe = null),
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
                        selected: _rpe == v,
                        onSelected: (_) => setState(() => _rpe = v),
                      ))
                  .toList(),
            ),
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

  Widget _sideBlock(Map<String, dynamic> r) {
    final id = r['id'] as int;
    final side = r['side'] as String;
    final showWeight = true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (side != 'both')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                side == 'R' ? 'Right' : 'Left',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          Row(
            children: [
              if (showWeight)
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
                    onTap: () => setState(() => _focusedRow = id),
                  ),
                ),
              if (showWeight) const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _value[id],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: _valueLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db.dart';
import '../util.dart';

/// What you actually have access to.
///
/// Weights entered here become the quick-pick chips in the set editor,
/// narrowed to the kind of equipment the exercise in front of you uses.
/// Gear toggles feed the "only what I can do" filter in the picker.
class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  List<Map<String, dynamic>> _items = const [];
  Set<String> _gear = {};
  bool _loading = true;

  static const _gearOptions = [
    'BENCH',
    'PULLUP_BAR',
    'BAND',
    'BOX',
    'MAT',
    'MEDICINE_BALL',
    'SWISS_BALL',
    'TRX',
    'ANKLE_WEIGHT',
    'WEIGHT_VEST',
    'JUMP_ROPE',
    'FOAM_ROLLER',
    'BOSU_BALL',
    'SLIDING_DISC',
    'RINGS',
    'BATTLE_ROPE',
    'SANDBAG',
    'SLED',
    'SQUAT_RACK',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await Db.equipment();
    final gear = (await Db.setting(gearSettingKey)) ?? '';
    if (!mounted) return;
    setState(() {
      _items = items;
      _gear = gear.split(',').where((e) => e.isNotEmpty).toSet();
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddWeightSheet(),
    );
    if (result == null) return;

    // A range like 5..30 step 2.5 adds the whole rack in one go.
    final from = result['from'] as double;
    final to = result['to'] as double?;
    final step = result['step'] as double?;
    final kind = result['kind'] as String;
    final unit = result['unit'] as String;

    if (to == null || step == null || step <= 0 || to <= from) {
      await Db.addEquipment(kind, from, unit);
    } else {
      for (var w = from; w <= to + 0.0001; w += step) {
        await Db.addEquipment(kind, double.parse(w.toStringAsFixed(2)), unit);
      }
    }
    await _load();
  }

  Future<void> _toggleGear(String code, bool on) async {
    setState(() => on ? _gear.add(code) : _gear.remove(code));
    await Db.setSetting(gearSettingKey, _gear.join(','));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byKind = <String, List<Map<String, dynamic>>>{};
    for (final e in _items) {
      byKind.putIfAbsent(e['kind'] as String, () => []).add(e);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Equipment')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Weights'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Weights you add here show up as one-tap chips when logging, '
                    'filtered to the kind of equipment the exercise uses.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No weights added yet.'),
                  ),
                ...byKind.entries.map((entry) => Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.key,
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: entry.value
                                  .map((e) => InputChip(
                                        label: Text(
                                            '${num2((e['weight'] as num).toDouble())} ${e['unit']}'),
                                        onDeleted: () async {
                                          await Db.deleteEquipment(
                                              e['id'] as int);
                                          await _load();
                                        },
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    )),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Other gear', style: theme.textTheme.titleSmall),
                        Text(
                          'Used by the "only what I can do" filter in the exercise picker.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _gearOptions
                              .map((code) => FilterChip(
                                    label: Text(pretty(code)),
                                    selected: _gear.contains(code),
                                    onSelected: (v) => _toggleGear(code, v),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AddWeightSheet extends StatefulWidget {
  const _AddWeightSheet();

  @override
  State<_AddWeightSheet> createState() => _AddWeightSheetState();
}

class _AddWeightSheetState extends State<_AddWeightSheet> {
  String _kind = EquipKind.dumbbell;
  String _unit = 'kg';
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _step = TextEditingController();

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add weights', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: EquipKind.all
                  .map((k) => ChoiceChip(
                        label: Text(k),
                        selected: _kind == k,
                        onSelected: (_) => setState(() => _kind = k),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['kg', 'lb']
                  .map((u) => ChoiceChip(
                        label: Text(u.toUpperCase()),
                        selected: _unit == u,
                        onSelected: (_) => setState(() => _unit = u),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _field(_from, 'Weight')),
                const SizedBox(width: 8),
                Expanded(child: _field(_to, 'up to (optional)')),
                const SizedBox(width: 8),
                Expanded(child: _field(_step, 'step')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Fill only the first box for a single weight. Fill all three to add a whole rack at once, e.g. 5 up to 30 step 2.5.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final from = double.tryParse(_from.text.trim());
                  if (from == null) {
                    Navigator.pop(context);
                    return;
                  }
                  Navigator.pop(context, {
                    'kind': _kind,
                    'unit': _unit,
                    'from': from,
                    'to': double.tryParse(_to.text.trim()),
                    'step': double.tryParse(_step.text.trim()),
                  });
                },
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label),
      );
}

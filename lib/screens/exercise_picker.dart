import 'package:flutter/material.dart';

import '../db.dart';
import '../library.dart';
import '../util.dart';

/// Opens the picker and returns the exercises that were selected.
Future<List<Exercise>?> pickExercises(BuildContext context,
    {bool multi = true}) {
  return Navigator.of(context).push<List<Exercise>>(
    MaterialPageRoute(builder: (_) => ExercisePicker(multi: multi)),
  );
}

class ExercisePicker extends StatefulWidget {
  const ExercisePicker({super.key, this.multi = true});
  final bool multi;

  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  final _controller = TextEditingController();
  final _selected = <String, Exercise>{};
  final _equipment = <String>{};
  final _muscles = <String>{};
  bool _onlyMine = false;
  Set<String> _owned = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadOwned();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadOwned() async {
    final kinds = await Db.equipmentKindsOwned();
    final gear = (await Db.setting(gearSettingKey)) ?? '';
    final owned = <String>{};
    for (final k in kinds) {
      owned.addAll(EquipKind.tags[k] ?? const []);
    }
    owned.addAll(gear.split(',').where((e) => e.isNotEmpty));
    if (!mounted) return;
    setState(() => _owned = owned);
  }

  @override
  Widget build(BuildContext context) {
    final results = ExerciseLibrary.search(
      _query,
      equipment: _equipment,
      muscles: _muscles,
      onlyMyEquipment: _onlyMine,
      ownedEquipment: _owned,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty
            ? 'Add exercise'
            : '${_selected.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilters,
            tooltip: 'Filters',
          ),
        ],
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.pop(context, _selected.values.toList()),
              icon: const Icon(Icons.check),
              label: Text('Add ${_selected.length}'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search 1531 exercises',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_equipment.isNotEmpty || _muscles.isNotEmpty || _onlyMine)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  if (_onlyMine)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        label: const Text('My equipment'),
                        onDeleted: () => setState(() => _onlyMine = false),
                      ),
                    ),
                  ..._equipment.map((e) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          label: Text(pretty(e)),
                          onDeleted: () => setState(() => _equipment.remove(e)),
                        ),
                      )),
                  ..._muscles.map((m) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          label: Text(pretty(m)),
                          onDeleted: () => setState(() => _muscles.remove(m)),
                        ),
                      )),
                ],
              ),
            ),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('Nothing matches those filters.'))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final ex = results[i];
                      final chosen = _selected.containsKey(ex.key);
                      final isPinned = ExerciseLibrary.pinned.contains(ex.key);
                      return ListTile(
                        leading: Icon(
                          chosen
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: chosen
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Row(
                          children: [
                            if (isPinned)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.push_pin, size: 14),
                              ),
                            Expanded(child: Text(ex.name)),
                          ],
                        ),
                        subtitle: Text(
                          [
                            if (ex.primaryLabel.isNotEmpty) ex.primaryLabel,
                            if (ex.equipmentLabel.isNotEmpty) ex.equipmentLabel,
                          ].join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          if (!widget.multi) {
                            Navigator.pop(context, [ex]);
                            return;
                          }
                          setState(() {
                            if (chosen) {
                              _selected.remove(ex.key);
                            } else {
                              _selected[ex.key] = ex;
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (c, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _onlyMine,
                title: const Text('Only what I can do'),
                subtitle: const Text(
                    'Hides exercises needing gear not on your Equipment page'),
                onChanged: (v) {
                  setSheet(() {});
                  setState(() => _onlyMine = v);
                },
              ),
              const Divider(),
              Text('Equipment', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: ExerciseLibrary.equipmentCodes
                    .map((code) => FilterChip(
                          label: Text(pretty(code)),
                          selected: _equipment.contains(code),
                          onSelected: (v) {
                            setSheet(() {});
                            setState(() => v
                                ? _equipment.add(code)
                                : _equipment.remove(code));
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Text('Muscle', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: ExerciseLibrary.muscleCodes
                    .map((code) => FilterChip(
                          label: Text(pretty(code)),
                          selected: _muscles.contains(code),
                          onSelected: (v) {
                            setSheet(() {});
                            setState(() =>
                                v ? _muscles.add(code) : _muscles.remove(code));
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setSheet(() {});
                  setState(() {
                    _equipment.clear();
                    _muscles.clear();
                    _onlyMine = false;
                  });
                },
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

import 'package:flutter/material.dart';

import '../library.dart';
import '../theme.dart';
import '../util.dart';
import 'exercise_filter_sheet.dart';

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
  ExerciseFilter _filter = emptyExerciseFilter;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final next = await pickExerciseFilter(context, _filter);
    if (next != null && mounted) setState(() => _filter = next);
  }

  @override
  Widget build(BuildContext context) {
    final results = ExerciseLibrary.search(
      _query,
      equipment: _filter.equipment,
      muscles: _filter.muscles,
      onlyCustom: _filter.onlyCustom,
    );
    final active = filterIsActive(_filter);
    // What the filters alone leave, so the field never claims to search more
    // than it will actually look through.
    final available = ExerciseLibrary.countMatching(
      equipment: _filter.equipment,
      muscles: _filter.muscles,
      onlyCustom: _filter.onlyCustom,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty
            ? 'Add exercise'
            : '${_selected.length} selected'),
        actions: [
          IconButton(
            icon: Icon(active ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: _openFilters,
            tooltip: 'Filter',
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
                hintText: 'Search $available exercises',
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
          if (active)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  if (_filter.onlyCustom)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        label: const Text('Custom exercises'),
                        onDeleted: () => setState(() => _filter = (
                              equipment: _filter.equipment,
                              muscles: _filter.muscles,
                              onlyCustom: false,
                            )),
                      ),
                    ),
                  ..._filter.equipment.map((e) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          label: Text(pretty(e)),
                          onDeleted: () =>
                              setState(() => _filter.equipment.remove(e)),
                        ),
                      )),
                  ..._filter.muscles.map((m) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          label: Text(pretty(m)),
                          onDeleted: () =>
                              setState(() => _filter.muscles.remove(m)),
                        ),
                      )),
                ],
              ),
            ),
          if (_query.isNotEmpty || active)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${results.length} of ${ExerciseLibrary.all.length} shown',
                  style: BvType.label,
                ),
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
                            if (ex.custom) 'custom',
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
}

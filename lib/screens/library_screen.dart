import 'package:flutter/material.dart';

import '../db.dart';
import '../library.dart';
import '../saf.dart';
import '../theme.dart';
import '../util.dart';
import 'exercise_filter_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _controller = TextEditingController();
  ExerciseFilter _filter = emptyExerciseFilter;
  String _query = '';

  Future<void> _openFilters() async {
    final next = await pickExerciseFilter(context, _filter);
    if (next != null && mounted) setState(() => _filter = next);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Name plus the fields that make an exercise findable later: without
  /// muscles and equipment a custom entry is invisible to every filter.
  Future<void> _addCustom() async {
    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomExerciseSheet(),
    );
    if (made != true) return;
    await ExerciseLibrary.load();
    if (mounted) setState(() {});
  }

  Future<void> _editCustom(Exercise ex) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomExerciseSheet(existing: ex),
    );
    if (saved != true) return;
    await ExerciseLibrary.load();
    if (mounted) {
      Navigator.of(context).pop();
      setState(() {});
    }
  }

  Future<void> _deleteCustom(Exercise ex) async {
    final usage = await Db.customExerciseUsage(ex.key);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${ex.name}?'),
        content: Text(
          usage.routines == 0 && usage.sessions == 0
              ? 'Nothing uses it.'
              : 'Used by ${usage.routines} routine'
                  '${usage.routines == 1 ? '' : 's'} and '
                  '${usage.sessions} logged session'
                  '${usage.sessions == 1 ? '' : 's'}. Those keep their own '
                  'copy of the name, but the exercise leaves the library.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.deleteCustomExercise(ex.key);
    await ExerciseLibrary.load();
    if (mounted) {
      Navigator.of(context).pop();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ExerciseLibrary.search(
      _query,
      equipment: _filter.equipment,
      muscles: _filter.muscles,
      onlyCustom: _filter.onlyCustom,
    );
    final pinnedCount = ExerciseLibrary.pinned.length;
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
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Filter',
            icon: Icon(active ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: _openFilters,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Custom exercise',
            onPressed: _addCustom,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
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
          if (_query.isEmpty && pinnedCount > 0 && !active)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$pinnedCount pinned at the top',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          if (_query.isNotEmpty || active)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${results.length} of ${ExerciseLibrary.all.length} shown',
                  style: Theme.of(context).textTheme.labelSmall,
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
                final isPinned = ExerciseLibrary.pinned.contains(ex.key);
                return ListTile(
                  title: Text(ex.name),
                  subtitle: Text(
                    [
                      if (ex.primaryLabel.isNotEmpty) ex.primaryLabel,
                      if (ex.equipmentLabel.isNotEmpty) ex.equipmentLabel,
                      if (ex.custom) 'custom',
                    ].join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: isPinned
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onPressed: () async {
                      await Db.togglePin(ex.key, !isPinned);
                      await ExerciseLibrary.reloadPinned();
                      if (mounted) setState(() {});
                    },
                  ),
                  onTap: () => _details(ex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _details(Exercise ex) async {
    final best = await Db.bestKg(ex.key);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ex.name, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (ex.primary.isNotEmpty) _line('Primary', ex.primaryLabel),
            if (ex.secondary.isNotEmpty)
              _line('Secondary',
                  ex.secondary.map(Exercise.pretty2).join(', ')),
            if (ex.equipment.isNotEmpty) _line('Equipment', ex.equipmentLabel),
            if (ex.garminName.isNotEmpty)
              _line('Garmin code', '${ex.category}/${ex.garminName}'),
            _line('Heaviest logged',
                best == null ? 'not logged yet' : '${num2(best)} kg'),
            if (ex.custom) ...[
              const SizedBox(height: Bv.s3),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _editCustom(ex),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _deleteCustom(ex),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: value),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------

/// Creating an exercise by hand.
///
/// Muscles and equipment are offered at the same time as the name, because an
/// entry without them cannot be reached by any filter and effectively only
/// exists if you remember what you called it.
class _CustomExerciseSheet extends StatefulWidget {
  const _CustomExerciseSheet({this.existing});

  /// Null when creating; the entry being changed when editing.
  final Exercise? existing;

  @override
  State<_CustomExerciseSheet> createState() => _CustomExerciseSheetState();
}

class _CustomExerciseSheetState extends State<_CustomExerciseSheet> {
  late final _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _muscles = {...?widget.existing?.primary};
  late final _equipment = {...?widget.existing?.equipment};

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (_editing) {
      await Db.updateCustomExercise(
        widget.existing!.key,
        name: name,
        muscles: _muscles.toList(),
        equipment: _equipment.toList(),
      );
    } else {
      await Db.addCustomExercise(
        name: name,
        muscles: _muscles.toList(),
        equipment: _equipment.toList(),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4,
          MediaQuery.of(context).viewInsets.bottom + Bv.s4),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, scroll) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  Text(_editing ? 'Edit exercise' : 'Your own exercise',
                      style: BvType.headlineSm),
                  if (_editing) ...[
                    const SizedBox(height: Bv.s1),
                    Text(
                      'Renaming updates your routines. Sessions already logged '
                      'keep the name they were recorded under.',
                      style: BvType.bodySm,
                    ),
                  ],
                  const SizedBox(height: Bv.s3),
                  TextField(
                    controller: _name,
                    autofocus: !_editing,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Bv.s4),
                  Text('MUSCLES', style: BvType.label),
                  const SizedBox(height: Bv.s2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ExerciseLibrary.muscleCodes
                        .map((code) => FilterChip(
                              label: Text(pretty(code)),
                              selected: _muscles.contains(code),
                              onSelected: (v) => setState(() => v
                                  ? _muscles.add(code)
                                  : _muscles.remove(code)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: Bv.s4),
                  Text('EQUIPMENT', style: BvType.label),
                  const SizedBox(height: Bv.s1),
                  Text(
                    'Leave empty for something needing no equipment.',
                    style: BvType.bodySm,
                  ),
                  const SizedBox(height: Bv.s2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ExerciseLibrary.equipmentCodes
                        .map((code) => FilterChip(
                              label: Text(pretty(code)),
                              selected: _equipment.contains(code),
                              onSelected: (v) => setState(() => v
                                  ? _equipment.add(code)
                                  : _equipment.remove(code)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: Bv.s5),
                ],
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _name.text.trim().isEmpty ? null : _save,
                  child: Text(_editing ? 'Save' : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

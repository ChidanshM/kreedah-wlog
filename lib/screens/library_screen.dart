import 'package:flutter/material.dart';

import '../db.dart';
import '../library.dart';
import '../util.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _controller = TextEditingController();
  final _equipment = <String>{};
  final _muscles = <String>{};
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addCustom() async {
    final nameCtl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Custom exercise'),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, nameCtl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await Db.addCustomExercise(name: name);
    await ExerciseLibrary.load();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final results = ExerciseLibrary.search(
      _query,
      equipment: _equipment,
      muscles: _muscles,
    );
    final pinnedCount = ExerciseLibrary.pinned.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
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
                hintText: 'Search ${ExerciseLibrary.all.length} exercises',
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
          if (_query.isEmpty && pinnedCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$pinnedCount pinned at the top',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          Expanded(
            child: ListView.builder(
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

import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../export.dart';
import '../library.dart';
import '../theme.dart';
import '../util.dart';

/// Bringing data back in: a full backup, or parts of one.
///
/// Kept apart from exporting because the two are not symmetrical. Exporting
/// writes a file and changes nothing; restoring replaces what is here, which
/// deserves its own place rather than sitting one tap from the button that
/// makes a backup.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

/// What a restore is allowed to touch.
enum _Part { routines, sessions, equipment, exercises, schedules, settings }

extension on _Part {
  String get label => switch (this) {
        _Part.routines => 'Routines',
        _Part.sessions => 'Logged sessions',
        _Part.equipment => 'Equipment',
        _Part.exercises => 'Your own exercises',
        _Part.schedules => 'Schedules',
        _Part.settings => 'Settings',
      };

  String get detail => switch (this) {
        _Part.routines => 'Plans, their exercises and per-set targets',
        _Part.sessions => 'Everything trained, with every set',
        _Part.equipment => 'The weights you own',
        _Part.exercises => 'Exercises you added by hand, and pins',
        _Part.schedules => 'Planned days and repeats',
        _Part.settings => 'Export folder, timer preference',
      };

  /// Tables this part owns, children first.
  List<String> get tables => switch (this) {
        _Part.routines => ['routine_sets', 'routine_exercises', 'routines'],
        _Part.sessions => ['sets', 'workout_exercises', 'workouts'],
        _Part.equipment => ['equipment'],
        _Part.exercises => ['pinned', 'custom_exercises'],
        _Part.schedules => ['schedule'],
        _Part.settings => ['settings'],
      };
}

class _RestoreScreenState extends State<RestoreScreen> {
  List<({String name, String ref})> _files = const [];
  List<({String name, String ref})> _routineFiles = const [];
  bool _loading = true;
  final _parts = {..._Part.values};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await Exporter.availableBackups();
    final routines = await Exporter.availableRoutineFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
      _routineFiles = routines;
      _loading = false;
    });
  }

  /// Bring in routines on their own. Adds rather than replaces, so nothing
  /// already here can be lost by importing.
  Future<void> _importRoutines(({String name, String ref}) f) async {
    try {
      final n = await Exporter.importRoutinesFrom(f.ref);
      await ExerciseLibrary.load();
      notifyDataChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'No routines in that file.'
            : 'Added $n routine${n == 1 ? '' : 's'}.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  bool get _everything => _parts.length == _Part.values.length;

  Future<void> _restore(({String name, String ref}) file) async {
    if (_parts.isEmpty) return;

    // Schedules point at routines, and sessions are pre-filled from them, so
    // restoring one without the other can leave a schedule with nothing to
    // run. Said plainly rather than silently prevented.
    final orphaned = _parts.contains(_Part.schedules) &&
        !_parts.contains(_Part.routines);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_everything ? 'Replace everything?' : 'Restore some parts?'),
        content: Text(
          _everything
              ? 'Everything currently in the app is removed and replaced with '
                  'what is in ${file.name}. This cannot be undone.'
              : '${_parts.map((p) => p.label.toLowerCase()).join(', ')} '
                  'will be replaced with what is in ${file.name}. Everything '
                  'else is left as it is.'
                  '${orphaned ? '\n\nSchedules refer to routines. Restoring them without routines may leave a schedule pointing at something that is not here.' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final n = await Exporter.restoreFrom(
        file.ref,
        only: _everything
            ? null
            : {for (final p in _parts) ...p.tables},
      );
      await ExerciseLibrary.load();
      notifyDataChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored $n row${n == 1 ? '' : 's'}.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: Bv.s6),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, Bv.s2),
                  child: Text('WHAT TO BRING BACK', style: BvType.label),
                ),
                ..._Part.values.map((p) => CheckboxListTile(
                      dense: true,
                      value: _parts.contains(p),
                      title: Text(p.label),
                      subtitle: Text(p.detail, style: BvType.bodySm),
                      onChanged: (v) => setState(
                          () => v == true ? _parts.add(p) : _parts.remove(p)),
                    )),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Bv.s3),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _parts.addAll(_Part.values)),
                        child: const Text('All'),
                      ),
                      TextButton(
                        onPressed: () => setState(_parts.clear),
                        child: const Text('None'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s1),
                  child: Text(
                    _parts.isEmpty
                        ? 'NOTHING SELECTED'
                        : 'RESTORE FROM',
                    style: BvType.label,
                  ),
                ),
                if (_files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Bv.s4, 0, Bv.s4, 0),
                    child: Text(
                      'No backups found. They are read from the same folder '
                      'exports are written to, so a file copied in from a '
                      'computer appears here.',
                      style: BvType.bodySm,
                    ),
                  ),
                ..._files.map((f) => ListTile(
                      enabled: _parts.isNotEmpty,
                      leading: const Icon(Icons.settings_backup_restore),
                      title: Text(f.name),
                      onTap: () => _restore(f),
                    )),
                const Divider(height: Bv.s5),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s1),
                  child: Text('ROUTINE FILES', style: BvType.label),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Bv.s4, 0, Bv.s4, Bv.s2),
                  child: Text(
                    _routineFiles.isEmpty
                        ? 'No routine files found. Any file declaring itself '
                            'as routines appears here, whatever it is named.'
                        : 'Routines are added rather than replacing anything. '
                            'A name already in use gains a suffix.',
                    style: BvType.bodySm,
                  ),
                ),
                ..._routineFiles.map((f) => ListTile(
                      leading: const Icon(Icons.playlist_add),
                      title: Text(f.name),
                      onTap: () => _importRoutines(f),
                    )),
                const Divider(height: Bv.s5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Bv.s4),
                  child: Text(
                    'Restoring replaces what is here rather than merging with '
                    'it. Anything logged since the backup was made is lost, so '
                    'export first if today matters.',
                    style: BvType.bodySm,
                  ),
                ),
              ],
            ),
    );
  }
}

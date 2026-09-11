import 'package:flutter/material.dart';

import '../db.dart';
import '../export.dart';
import '../library.dart';
import '../theme.dart';
import '../util.dart';
import 'routine_edit_screen.dart';
import 'routine_detail_screen.dart';
import 'guide_screen.dart';
import 'schedule_screen.dart';
import 'session_time_sheet.dart';
import 'workout_screen.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  List<Map<String, dynamic>> _routines = const [];
  Map<String, dynamic>? _open;
  int _archived = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final routines = await Db.routines();
    final open = await Db.openWorkout();
    final archived = await Db.archivedCount();
    if (!mounted) return;
    setState(() {
      _routines = routines;
      _open = open;
      _archived = archived;
      _loading = false;
    });
  }

  Future<void> _openDetail(Map<String, dynamic> r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoutineDetailScreen(
        routineId: r['id'] as int,
        routineName: r['name'] as String,
      ),
    ));
    await _load();
  }

  /// Archived routines are out of the way, not gone. Nothing else lists
  /// them, so this is the only way back.
  Future<void> _showArchived() async {
    final rows = await Db.routines(archived: true);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, Bv.s2),
              child: Text('Archived routines'),
            ),
            ...rows.map((r) => ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(r['name'] as String),
                  trailing: TextButton(
                    onPressed: () async {
                      await Db.archiveRoutine(r['id'] as int, false);
                      if (c.mounted) Navigator.pop(c);
                      await _load();
                    },
                    child: const Text('Restore'),
                  ),
                )),
          ],
        ),
      ),
    );
    await _load();
  }

  Future<void> _newRoutine() async {
    final name = await _promptName(context, 'New routine', '');
    if (name == null || name.isEmpty) return;
    final id = await Db.createRoutine(name);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoutineEditScreen(routineId: id, routineName: name),
    ));
    await _load();
  }

  Future<void> _start(Map<String, dynamic> routine) async {
    if (_open != null) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Session already open'),
          content: Text(
              '"${_open!['routine_name']}" is still running. Finish or discard it before starting another.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Open it')),
          ],
        ),
      );
      if (resume == true) await _resume();
      return;
    }

    final exercises = await Db.routineExercises(routine['id'] as int);
    if (exercises.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some exercises to this routine first.')),
      );
      return;
    }

    final id = await Db.startWorkout(
        routine['id'] as int, routine['name'] as String);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkoutScreen(workoutId: id),
    ));
    await _load();
  }

  Future<void> _resume() async {
    final id = _open!['id'] as int;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkoutScreen(workoutId: id),
    ));
    await _load();
  }

  Future<void> _startEmpty() async {
    if (_open != null) {
      await _resume();
      return;
    }
    final id = await Db.startEmptyWorkout('Ad-hoc session');
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkoutScreen(workoutId: id),
    ));
    await _load();
  }

  /// Enter a session that already happened. Reuses the logging screen in edit
  /// mode, pre-filled from what came before that date.
  Future<void> _logPast(Map<String, dynamic> routine) async {
    final exercises = await Db.routineExercises(routine['id'] as int);
    if (exercises.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some exercises to this routine first.')),
      );
      return;
    }
    if (!mounted) return;
    final picked = await pickSessionTime(context, title: 'When did you train?');
    if (picked == null || !mounted) return;
    final t = resolveSessionTime(picked);

    final id = await Db.startWorkout(
      routine['id'] as int,
      routine['name'] as String,
      at: t.start,
      endedAt: t.end,
      timeKnown: t.timeKnown,
    );
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WorkoutScreen(workoutId: id)));
    await _load();
  }

  /// Write routines out on their own. [preselect] jumps straight to exporting
  /// one, from that routine's own menu.
  Future<void> _exportRoutines({int? preselect}) async {
    List<int> ids;
    if (preselect != null) {
      ids = [preselect];
    } else {
      final chosen = <int>{};
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (c) => StatefulBuilder(
          builder: (c, setSheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, 0),
                  child: Text('Which routines?'),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _routines
                        .map((r) => CheckboxListTile(
                              value: chosen.contains(r['id'] as int),
                              title: Text(r['name'] as String),
                              onChanged: (v) => setSheet(() => v == true
                                  ? chosen.add(r['id'] as int)
                                  : chosen.remove(r['id'] as int)),
                            ))
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Bv.s3),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setSheet(() {
                          chosen.clear();
                          chosen.addAll(_routines.map((r) => r['id'] as int));
                        }),
                        child: const Text('Select all'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: chosen.isEmpty
                            ? null
                            : () => Navigator.pop(c, true),
                        child: Text('Export ${chosen.length}'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (ok != true || chosen.isEmpty) return;
      ids = chosen.toList();
    }

    try {
      final r = await Exporter.exportRoutines(ids);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.reachable
            ? '${r.name} written to ${r.where}.'
            : '${r.name} written to the app folder, which Android hides. '
                'Set an export folder under More.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importRoutines() async {
    final files = await Exporter.availableRoutineFiles();
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No routine files found in the export folder.'),
      ));
      return;
    }
    final ref = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: files
              .map((f) => ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: Text(f.name),
                    onTap: () => Navigator.pop(c, f.ref),
                  ))
              .toList(),
        ),
      ),
    );
    if (ref == null) return;
    try {
      final n = await Exporter.importRoutinesFrom(ref);
      await ExerciseLibrary.load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$n routine${n == 1 ? '' : 's'} added.')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _routineMenu(Map<String, dynamic> r) async {
    final id = r['id'] as int;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.history_toggle_off),
              title: const Text('Log a past session'),
              onTap: () => Navigator.pop(c, 'past'),
            ),
            ListTile(
              leading: const Icon(Icons.event_repeat_outlined),
              title: const Text('Schedule'),
              onTap: () => Navigator.pop(c, 'schedule'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit exercises'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(c, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(c, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export this routine'),
              onTap: () => Navigator.pop(c, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'past':
        await _logPast(r);
        return;
      case 'schedule':
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScheduleScreen()));
        break;
      case 'export':
        await _exportRoutines(preselect: id);
        return;
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              RoutineEditScreen(routineId: id, routineName: r['name'] as String),
        ));
        break;
      case 'rename':
        final name =
            await _promptName(context, 'Rename routine', r['name'] as String);
        if (name != null && name.isNotEmpty) await Db.renameRoutine(id, name);
        break;
      case 'duplicate':
        await Db.duplicateRoutine(id, '${r['name']} copy');
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Delete "${r['name']}"?'),
            content: const Text(
                'Past sessions logged from this routine are kept. Only the plan is removed.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) await Db.deleteRoutine(id);
        break;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        actions: [
          IconButton(
            tooltip: 'Ad-hoc session',
            icon: const Icon(Icons.bolt_outlined),
            onPressed: _startEmpty,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') _exportRoutines();
              if (v == 'import') _importRoutines();
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                value: 'export',
                enabled: _routines.isNotEmpty,
                child: const Text('Export routines'),
              ),
              const PopupMenuItem(
                  value: 'import', child: Text('Import routines')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newRoutine,
        icon: const Icon(Icons.add),
        label: const Text('Routine'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (_open != null)
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.play_circle_outline),
                        title: Text('${_open!['routine_name']} in progress'),
                        subtitle: Text(_startedLabel(_open!)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _resume,
                      ),
                    ),
                  if (_routines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 0),
                      child: Column(
                        children: [
                          const Icon(Icons.list_alt_outlined, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'No routines yet.\nMake one per training day — there is no limit.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          // Surfaced here because this is the moment someone
                          // has no idea what to do first, and the answer
                          // (fill in Equipment) is not obvious.
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const GuideScreen())),
                            icon: const Icon(Icons.menu_book_outlined),
                            label: const Text('Read the guide'),
                          ),
                        ],
                      ),
                    ),
                  ..._routines.map(
                    (r) => Dismissible(
                      key: ValueKey('routine-${r['id']}'),
                      // Left reveals red and removes; right reveals sand and
                      // sets aside. Deleting asks first, archiving does not,
                      // because one is reversible and the other is not.
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: Bv.s4),
                        color: Bv.sand400,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined),
                            SizedBox(width: Bv.s2),
                            Text('Archive'),
                          ],
                        ),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: Bv.s4),
                        color: Bv.error,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Delete',
                                style: TextStyle(color: Bv.cream100)),
                            SizedBox(width: Bv.s2),
                            Icon(Icons.delete_outline, color: Bv.cream100),
                          ],
                        ),
                      ),
                      confirmDismiss: (dir) async {
                        if (dir == DismissDirection.startToEnd) return true;
                        return await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text('Delete "${r['name']}"?'),
                                content: const Text(
                                    'Past sessions logged from this routine are kept. Only the plan is removed. Archive instead to keep it.'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            ) ??
                            false;
                      },
                      onDismissed: (dir) async {
                        final id = r['id'] as int;
                        if (dir == DismissDirection.startToEnd) {
                          await Db.archiveRoutine(id, true);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${r['name']} archived'),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () async {
                                  await Db.archiveRoutine(id, false);
                                  await _load();
                                },
                              ),
                            ),
                          );
                        } else {
                          await Db.deleteRoutine(id);
                        }
                        await _load();
                      },
                      child: Card(
                        child: ListTile(
                          title: Text(r['name'] as String,
                              style: theme.textTheme.titleMedium),
                          subtitle: _RoutineSubtitle(routineId: r['id'] as int),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.more_vert),
                                onPressed: () => _routineMenu(r),
                              ),
                              FilledButton(
                                onPressed: () => _start(r),
                                child: const Text('Start'),
                              ),
                            ],
                          ),
                          onTap: () => _openDetail(r),
                        ),
                      ),
                    ),
                  ),
                  if (_archived > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s3, Bv.s4, 0),
                      child: TextButton.icon(
                        onPressed: _showArchived,
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: Text('$_archived archived'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  String _startedLabel(Map<String, dynamic> w) {
    final t = parseIso(w['started_at'] as String?);
    if (t == null) return 'Tap to continue';
    return 'Started ${hhmm(t)}, tap to continue';
  }
}

class _RoutineSubtitle extends StatelessWidget {
  const _RoutineSubtitle({required this.routineId});
  final int routineId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Db.routineExercises(routineId),
      builder: (context, snap) {
        if (!snap.hasData) return const Text(' ');
        final rows = snap.data!;
        if (rows.isEmpty) return const Text('Empty — tap to add exercises');
        final names = rows.take(3).map((e) => e['ex_name'] as String).join(', ');
        final more = rows.length > 3 ? ' +${rows.length - 3}' : '';
        return Text('${rows.length} exercises — $names$more',
            maxLines: 2, overflow: TextOverflow.ellipsis);
      },
    );
  }
}

Future<String?> _promptName(
    BuildContext context, String title, String initial) async {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

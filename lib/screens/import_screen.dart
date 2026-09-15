import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_events.dart';
import '../db.dart';
import '../export.dart';
import '../library.dart';
import '../saf.dart';
import '../theme.dart';
import 'routine_import.dart';

/// Everything that brings data in.
///
/// Organised by what is arriving rather than by which file is at hand,
/// because that is what someone knows: they want their equipment back, or
/// their schedules, not a particular filename. Each leads to the system file
/// picker, so the file can be anywhere — Downloads, a card, wherever a
/// message left it — rather than only in the folder exports are written to.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

/// One part of a backup, restorable on its own.
enum _Part { sessions, equipment, exercises, schedules, settings }

extension on _Part {
  String get label => switch (this) {
        _Part.sessions => 'Logged sessions',
        _Part.equipment => 'Equipment',
        _Part.exercises => 'Custom exercises',
        _Part.schedules => 'Schedules',
        _Part.settings => 'Settings',
      };

  String get detail => switch (this) {
        _Part.sessions => 'Everything trained, with every set',
        _Part.equipment => 'The weights you own',
        _Part.exercises => 'Exercises you added by hand, and pins',
        _Part.schedules => 'Planned days and repeats',
        _Part.settings => 'Export folder, timer preference',
      };

  IconData get icon => switch (this) {
        _Part.sessions => Icons.event_available_outlined,
        _Part.equipment => Icons.fitness_center_outlined,
        _Part.exercises => Icons.edit_note,
        _Part.schedules => Icons.event_repeat_outlined,
        _Part.settings => Icons.tune,
      };

  /// Tables this part owns, children first.
  Set<String> get tables => switch (this) {
        _Part.sessions => {'sets', 'workout_exercises', 'workouts'},
        _Part.equipment => {'equipment'},
        _Part.exercises => {'pinned', 'custom_exercises'},
        _Part.schedules => {'schedule'},
        _Part.settings => {'settings'},
      };
}

class _ImportScreenState extends State<ImportScreen> {
  bool _busy = false;

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Bring one part of a backup back.
  ///
  /// Everything except routines comes from a backup, since nothing else
  /// carries it. What is restored replaces what is here rather than merging,
  /// so it is confirmed first and the rest of the app is left untouched.
  Future<void> _importPart(_Part part) async {
    final file = await Saf.pickFile();
    if (file == null || !mounted) return;

    // Read before confirming, so a file that is not a backup is refused
    // before anything is promised about replacing what is here.
    Map<String, dynamic> data;
    try {
      final raw = await Saf.readFile(file.uri);
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _say('${file.name} could not be read as a backup.');
      return;
    }
    if (data['format'] != 'workout_log_backup') {
      _say('${file.name} is not a backup. ${part.label} lives only in one.');
      return;
    }
    final rows = (data[part.tables.last] as List?)?.length ?? 0;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Replace ${part.label.toLowerCase()}?'),
        content: Text(
            'The ${part.label.toLowerCase()} currently in the app are removed '
            'and replaced with what is in ${file.name} — $rows record'
            '${rows == 1 ? '' : 's'}. Everything else is left as it is.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final n = await Db.restore(data, only: part.tables);
      await ExerciseLibrary.load();
      notifyDataChanged();
      _say('Brought back $n record${n == 1 ? '' : 's'}.');
    } catch (e) {
      _say('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The whole backup, replacing everything.
  Future<void> _importAll() async {
    final file = await Saf.pickFile();
    if (file == null || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Text(
            'Everything currently in the app is removed and replaced with '
            'what is in ${file.name}. Anything logged since that backup was '
            'made is lost. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace everything')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final n = await Exporter.restoreFrom(file.uri);
      await ExerciseLibrary.load();
      notifyDataChanged();
      _say('Restored $n record${n == 1 ? '' : 's'}.');
    } catch (e) {
      _say('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Bv.s6),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s4, Bv.s4, Bv.s2),
            child: Text('ADDED TO WHAT IS HERE', style: BvType.label),
          ),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.playlist_add),
            title: const Text('Routines'),
            subtitle: const Text('Nothing is replaced. A name already in use '
                'gains a suffix.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy
                ? null
                : () async {
                    await importRoutinesFlow(context);
                  },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(Bv.s4, Bv.s3, Bv.s4, Bv.s1),
            child: Text('REPLACED FROM A BACKUP', style: BvType.label),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(Bv.s4, 0, Bv.s4, Bv.s2),
            child: Text(
              'Each takes the matching part of a backup and leaves the rest '
              'of the app alone.',
              style: BvType.bodySm,
            ),
          ),
          ..._Part.values.map((p) => ListTile(
                enabled: !_busy,
                leading: Icon(p.icon),
                title: Text(p.label),
                subtitle: Text(p.detail),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _importPart(p),
              )),
          const Divider(),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Whole backup'),
            subtitle: const Text('Replaces everything'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _importAll,
          ),
          const Divider(height: Bv.s5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Bv.s4),
            child: Text(
              'Each of these opens the phone\'s own file browser, so a file '
              'can be anywhere rather than only in the export folder. What it '
              'is called does not matter: it is read to see what it says it '
              'is, and refused if it is the wrong kind.',
              style: BvType.bodySm,
            ),
          ),
        ],
      ),
    );
  }
}

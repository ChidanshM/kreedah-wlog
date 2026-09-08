import 'package:flutter/material.dart';

import '../db.dart';
import '../export.dart';
import '../library.dart';
import '../saf.dart';
import '../theme.dart';
import 'equipment_screen.dart';
import 'guide_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showTimer = false;
  String? _tree;
  String _folderLabel = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final showTimer = await Db.flag('show_timer');
    final tree = await Db.setting(exportTreeKey);
    final ok = await Saf.hasAccess(tree);
    final label = ok ? await Saf.folderName(tree!) : '';
    if (!mounted) return;
    setState(() {
      _showTimer = showTimer;
      _tree = ok ? tree : null;
      _folderLabel = label;
    });
  }

  Future<void> _pickFolder() async {
    try {
      final tree = await Saf.pickFolder();
      if (tree == null) return;
      await Db.setSetting(exportTreeKey, tree);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exports will go to $_folderLabel.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not set the folder: $e')));
      }
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final r = await Exporter.exportAll();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Exported'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...r.names.map((n) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(n, style: BvType.bodySm),
                  )),
              const SizedBox(height: Bv.s3),
              Text(
                r.reachable
                    ? 'Written to ${r.where}.'
                    : 'Written to the app\'s own folder, which Android hides '
                        'from file managers. Choose an export folder to put '
                        'them somewhere you can reach.',
                style: BvType.bodySm,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final backups = await Exporter.availableBackups();
    if (!mounted) return;
    if (backups.isEmpty) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('No backups found'),
          content: Text(_tree == null
              ? 'Choose an export folder first, then put a backup file in it.'
              : 'No .json backup in $_folderLabel. Put one there and try again.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: backups
              .map((b) => ListTile(
                    leading: const Icon(Icons.restore_page_outlined),
                    title: Text(b.name),
                    onTap: () => Navigator.pop(c, b.ref),
                  ))
              .toList(),
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Replace everything?'),
        content: const Text(
            'Restoring wipes the current log and replaces it with the backup.'),
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
      await Exporter.restoreFrom(chosen);
      await ExerciseLibrary.load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Restored.')));
      }
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
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('User guide'),
            subtitle: const Text('How every feature works, with examples'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GuideScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Equipment'),
            subtitle: const Text('Your weights and gear'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EquipmentScreen()));
              await _load();
            },
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.timer_outlined),
            value: _showTimer,
            title: const Text('Show session timer'),
            subtitle: const Text(
                'Off by default. The start time is always recorded either way.'),
            onChanged: (v) async {
              setState(() => _showTimer = v);
              await Db.setSetting('show_timer', v ? '1' : '0');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Export folder'),
            subtitle: Text(_tree == null
                ? 'Not set — exports go somewhere Android hides'
                : _folderLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickFolder,
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Export'),
            subtitle: const Text('CSV of every set, plus a JSON backup'),
            trailing: _busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator())
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _export,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore from backup'),
            subtitle: const Text('Replaces the current log'),
            onTap: _restore,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Bv.s4, Bv.s2, Bv.s4, Bv.s6),
            child: Text(
              'Weight rule: kg is stored to 2 decimals and every summary '
              'statistic is in kg. The screen keeps whatever unit you typed, '
              'and the CSV carries an lb column filled in only for the sets '
              'you actually entered in lb.',
              style: BvType.bodySm,
            ),
          ),
        ],
      ),
    );
  }
}

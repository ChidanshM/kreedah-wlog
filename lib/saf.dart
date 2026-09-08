import 'package:flutter/services.dart';

/// Thin wrapper over the Storage Access Framework bridge in MainActivity.kt.
///
/// The user picks a folder once; Android persists the grant against the app,
/// so exports land somewhere they can actually be retrieved from rather than
/// in the app's own directory, which scoped storage hides.
class Saf {
  static const _channel = MethodChannel('wlog/storage');

  /// Opens the system folder picker. Returns a tree URI, or null if cancelled.
  static Future<String?> pickFolder() =>
      _channel.invokeMethod<String>('pickFolder');

  /// Whether we still hold write access. A folder can become unreachable if
  /// the user revokes it, or if it lived on a card that has been removed.
  static Future<bool> hasAccess(String? tree) async {
    if (tree == null || tree.isEmpty) return false;
    return await _channel.invokeMethod<bool>('hasAccess', {'tree': tree}) ?? false;
  }

  static Future<String> writeFile({
    required String tree,
    required String name,
    required String mime,
    required String content,
  }) async {
    final uri = await _channel.invokeMethod<String>('writeFile', {
      'tree': tree,
      'name': name,
      'mime': mime,
      'content': content,
    });
    return uri!;
  }

  /// Files directly inside the chosen folder, newest name first.
  static Future<List<Map<String, String>>> listFiles(
    String tree, {
    String suffix = '',
  }) async {
    final raw = await _channel.invokeListMethod<dynamic>(
          'listFiles',
          {'tree': tree, 'suffix': suffix},
        ) ??
        const [];
    return raw
        .map((e) => Map<String, String>.from(e as Map))
        .toList(growable: false);
  }

  static Future<String> readFile(String uri) async {
    final text = await _channel.invokeMethod<String>('readFile', {'uri': uri});
    return text!;
  }

  /// A short name for the folder, for showing in settings.
  static Future<String> folderName(String tree) async {
    final name = await _channel.invokeMethod<String>('folderName', {'tree': tree});
    return name ?? 'chosen folder';
  }
}

/// Settings key holding the chosen export folder's tree URI.
const exportTreeKey = 'export_tree';

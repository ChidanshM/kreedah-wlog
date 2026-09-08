import 'package:flutter/foundation.dart';

/// Bumped whenever stored data changes in a way another screen should notice.
///
/// The tabs live in an IndexedStack so they keep their scroll position and
/// state, which also means they are never rebuilt on a tab switch. Without a
/// signal, History would show whatever it loaded when the app started and a
/// finished session would not appear until a restart.
final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

void notifyDataChanged() => dataRevision.value++;

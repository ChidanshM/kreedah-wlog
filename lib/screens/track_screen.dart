import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_events.dart';
import '../db.dart';
import '../saf.dart';
import '../util.dart';

/// Track stopwatch.
///
/// Deliberately black, deliberately enormous. This is read at arm's length,
/// outdoors, half out of breath, and often in the dark. Nothing on it is
/// decorative and nothing needs precision tapping.
///
/// The phone times, and nothing else. Distance comes from which lap button
/// you press, so the app never pretends to measure something it cannot.
///
/// Elapsed time is computed from a stored start instant rather than counted
/// up by the ticker, so backgrounding the app, locking the screen or being
/// killed and reopened cannot drift the clock.
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  DateTime? _startedAt;
  DateTime? _lapStartedAt;
  Timer? _ticker;

  final _laps = <({int seconds, int metres})>[];

  /// Recovery countdown between reps, in seconds. Zero means not resting.
  int _restLeft = 0;
  int _restLength = 120;

  /// Audible cues. On by default, because the point of them is that you do
  /// not have to look at the screen, but a shared track is a reason to mute.
  bool _sound = true;

  /// Cues fire on the transition into a second, never on the second itself,
  /// so a rebuild cannot sound the same pip twice.
  void _cue(int wasLeft, int nowLeft) {
    if (!_sound || wasLeft == nowLeft) return;
    if (nowLeft == 3 || nowLeft == 2 || nowLeft == 1) Native.beep();
    if (nowLeft == 0) Native.beep(long: true);
  }

  bool get _running => _startedAt != null;

  @override
  void initState() {
    super.initState();
    Native.keepAwake(true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    Native.keepAwake(false);
    super.dispose();
  }

  void _tick() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        if (_restLeft > 0) {
          final was = _restLeft;
          _restLeft--;
          _cue(was, _restLeft);
          if (_restLeft == 0) HapticFeedback.mediumImpact();
        }
      });
    });
  }

  int get _elapsed => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inSeconds;

  int get _lapElapsed => _lapStartedAt == null
      ? 0
      : DateTime.now().difference(_lapStartedAt!).inSeconds;

  void _start() {
    HapticFeedback.mediumImpact();
    if (_sound) Native.beep(long: true);
    setState(() {
      _startedAt = DateTime.now();
      _lapStartedAt = _startedAt;
    });
    _tick();
  }

  /// Records the rep just finished and starts the recovery countdown.
  void _lap(int metres) {
    if (!_running) {
      _start();
      return;
    }
    HapticFeedback.heavyImpact();
    if (_sound) Native.beep();
    setState(() {
      _laps.add((seconds: _lapElapsed, metres: metres));
      _lapStartedAt = DateTime.now();
      _restLeft = _restLength;
    });
  }

  void _skipRest() => setState(() => _restLeft = 0);

  Future<void> _finish() async {
    if (_laps.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Save ${_laps.length} reps?'),
        content: Text(
            '${_laps.fold<int>(0, (a, l) => a + l.metres)} m total, '
            '${mmss(_elapsed)} elapsed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await Db.saveTrackSession(laps: _laps, start: _startedAt!);
    notifyDataChanged();
    if (mounted) Navigator.pop(context);
  }

  /// m:ss.t while running, so a 400 split reads the way a watch shows it.
  String _big(int seconds) => mmss(seconds);

  @override
  Widget build(BuildContext context) {
    final resting = _restLeft > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: _finish,
                  ),
                  IconButton(
                    tooltip: _sound ? 'Cues on' : 'Cues muted',
                    icon: Icon(
                      _sound ? Icons.volume_up : Icons.volume_off,
                      color: _sound ? Colors.white54 : Colors.white24,
                    ),
                    onPressed: () => setState(() => _sound = !_sound),
                  ),
                  const Spacer(),
                  Text(
                    _running ? 'ELAPSED ${_big(_elapsed)}' : 'READY',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 15,
                      letterSpacing: 1.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // The one number that matters mid-session: either the rep you
              // are running, or the recovery you are inside.
              Text(
                resting ? mmss(_restLeft) : _big(_lapElapsed),
                style: TextStyle(
                  color: resting ? const Color(0xFFCBB6E2) : Colors.white,
                  fontSize: 96,
                  height: 1,
                  fontWeight: FontWeight.w300,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                resting ? 'RECOVERY' : (_running ? 'REP' : 'TAP A DISTANCE'),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                  letterSpacing: 3,
                ),
              ),

              if (resting)
                TextButton(
                  onPressed: _skipRest,
                  child: const Text('Skip recovery',
                      style: TextStyle(color: Colors.white54)),
                ),

              const Spacer(),

              if (_laps.isNotEmpty) _lapList(),

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _lapButton(400)),
                  const SizedBox(width: 12),
                  Expanded(child: _lapButton(200)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _restLength = _restLength <= 30 ? 30 : _restLength - 30;
                      }),
                      child: Text('Recovery ${mmss(_restLength)}  \u2212',
                          style: const TextStyle(color: Colors.white38)),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _restLength += 30),
                      child: const Text('+',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Large, far apart, and impossible to confuse in the dark.
  Widget _lapButton(int metres) => SizedBox(
        height: 96,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor:
                metres == 400 ? const Color(0xFF1F3A2E) : const Color(0xFF2A2A2A),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => _lap(metres),
          child: Text(
            '$metres m',
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      );

  /// Most recent first: the split you just ran is the one you want to see.
  Widget _lapList() => SizedBox(
        height: 108,
        child: ListView(
          reverse: true,
          children: [
            for (var i = _laps.length - 1; i >= 0; i--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${i + 1}',
                          style: const TextStyle(color: Colors.white38)),
                    ),
                    SizedBox(
                      width: 72,
                      child: Text('${_laps[i].metres} m',
                          style: const TextStyle(color: Colors.white70)),
                    ),
                    Text(
                      mmss(_laps[i].seconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

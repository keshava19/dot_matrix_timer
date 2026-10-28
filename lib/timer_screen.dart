import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _neon = Color(0xFF39FF14);
const Color _gray = Color(0xFF2E2E2E);
const int _dotCount = 60;
const int _columns = 6;

enum _Phase { idle, running, finished }

class TimerScreen extends StatefulWidget {
  const TimerScreen({
    super.key,
    this.initialStartIndex,
    this.initialStartMs,
  });

  final int? initialStartIndex;
  final int? initialStartMs;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _screenChannel =
      MethodChannel('dot_matrix_timer/screen');

  static const String _prefActiveKey = 'timer_active';
  static const String _prefStartIndexKey = 'timer_start_index';
  static const String _prefStartMsKey = 'timer_start_ms';

  _Phase _phase = _Phase.idle;
  int? _startIndex;
  DateTime? _startTime;
  Duration _duration = Duration.zero;

  Timer? _clock;
  Timer? _finishHold;
  Timer? _dimTimer;

  late final AnimationController _pulseController;
  late final AnimationController _blinkController;
  late final Animation<double> _blinkOpacity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _screenChannel.setMethodCallHandler((call) async {
      if (call.method == 'notificationPermissionResult') {
        final granted = call.arguments == true;
        if (mounted) setState(() => _notificationsAllowed = granted);
      }
      return null;
    });
    _requestNotificationPermission();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseController.addListener(_onPulseTick);
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _blinkOpacity = CurvedAnimation(
      parent: _blinkController,
      curve: Curves.easeInOut,
    );
    _blinkController.addListener(_onBlinkTick);
    final initialIndex = widget.initialStartIndex;
    final initialMs = widget.initialStartMs;
    if (initialIndex != null && initialMs != null) {
      _startIndex = initialIndex;
      _startTime = DateTime.fromMillisecondsSinceEpoch(initialMs);
      _duration = Duration(minutes: initialIndex + 1);
      _phase = _Phase.running;
      // Kick off side effects after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _phase != _Phase.running) return;
        _pulseController.repeat(reverse: true);
        _startClock();
        _setKeepScreenOn(true);
        _setLowRefresh(true);
        _scheduleDim();
        _showNotificationForTimer();
      });
    } else {
      _restorePersisted();
    }
  }

  void _onBlinkTick() {
    if (_phase == _Phase.finished && mounted) {
      setState(() {});
    }
  }

  void _onPulseTick() {
    if (_phase == _Phase.running && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _finishHold?.cancel();
    _dimTimer?.cancel();
    _pulseController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  Duration get _remaining {
    if (_phase != _Phase.running || _startTime == null) {
      return _duration;
    }
    final elapsed = DateTime.now().difference(_startTime!);
    final rem = _duration - elapsed;
    return rem.isNegative ? Duration.zero : rem;
  }

  int get _passedMinutes {
    if (_phase != _Phase.running || _startTime == null) return 0;
    return DateTime.now().difference(_startTime!).inMinutes.clamp(0, _duration.inMinutes);
  }

  int get _currentDotIndex {
    if (_startIndex == null) return -1;
    final idx = _startIndex! - _passedMinutes;
    if (idx < 0) return 0;
    if (idx > _startIndex!) return _startIndex!;
    return idx;
  }

  bool _isInTimer(int index) {
    if (_startIndex == null) return false;
    return index <= _startIndex!;
  }

  bool _notificationsAllowed = false;



  void _startAt(int index) {
    if (_phase == _Phase.running) return;
    _finishHold?.cancel();
    _blinkController.stop();
    _blinkController.reset();
    setState(() {
      _startIndex = index;
      _startTime = DateTime.now();
      _duration = Duration(minutes: index + 1);
      _phase = _Phase.running;
    });
    _pulseController.repeat(reverse: true);
    _startClock();
    _setKeepScreenOn(true);
    _setLowRefresh(true);
    _scheduleDim();
    _persistStart();
    _showNotificationForTimer();
    HapticFeedback.lightImpact();
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_phase != _Phase.running) return;
      if (_remaining <= Duration.zero) {
        _finish();
      } else {
        setState(() {});
        _showNotificationForTimer(remaining: _remaining);
      }
    });
  }

  void _finish() {
    if (_phase != _Phase.running) return;
    _clock?.cancel();
    _pulseController.stop();
    setState(() => _phase = _Phase.finished);
    _blinkController.repeat(reverse: true);
    _cancelNotification();
    HapticFeedback.heavyImpact();
    // Stop blinking after a few seconds, then auto-reset to idle.
    _finishHold?.cancel();
    _finishHold = Timer(const Duration(seconds: 8), () {
      if (mounted && _phase == _Phase.finished) {
        _endTimer();
      }
    });
  }

  void _endTimer() {
    _clock?.cancel();
    _finishHold?.cancel();
    _dimTimer?.cancel();
    _dimTimer = null;
    _pulseController.stop();
    _blinkController.stop();
    _blinkController.reset();
    setState(() {
      _phase = _Phase.idle;
      _startIndex = null;
      _startTime = null;
      _duration = Duration.zero;
    });
    _setKeepScreenOn(false);
    _setLowRefresh(false);
    _setDimmed(false);
    _clearPersisted();
    _cancelNotification();
  }

  Future<void> _setKeepScreenOn(bool on) async {
    try {
      await _screenChannel.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {
      // Platform not supported; ignore.
    }
  }

  Future<void> _setLowRefresh(bool on) async {
    try {
      await _screenChannel.invokeMethod('setLowRefresh', {'on': on});
    } catch (_) {
      // Platform not supported; ignore.
    }
  }

  Future<void> _setDimmed(bool on) async {
    try {
      await _screenChannel.invokeMethod('setDimmed', {'on': on});
    } catch (_) {
      // Platform not supported; ignore.
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final granted = await _screenChannel.invokeMethod<bool>('requestNotificationPermission');
      if (mounted) setState(() => _notificationsAllowed = granted ?? true);
    } catch (_) {
      if (mounted) setState(() => _notificationsAllowed = false);
    }
  }

  Future<void> _showNotificationForTimer({Duration? remaining}) async {
    if (!_notificationsAllowed) return;
    final r = remaining ?? _remaining;
    final mm = r.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = r.inSeconds.remainder(60).toString().padLeft(2, '0');
    final total = _duration.inSeconds;
    final progress = (total - r.inSeconds).clamp(0, total);
    try {
      await _screenChannel.invokeMethod('showTimerNotification', {
        'content': 'Remaining $mm:$ss',
        'total': total,
        'progress': progress,
      });
    } catch (_) {
      // Platform not supported; ignore.
    }
  }

  Future<void> _cancelNotification() async {
    if (!_notificationsAllowed) return;
    try {
      await _screenChannel.invokeMethod('cancelTimerNotification');
    } catch (_) {
      // Platform not supported; ignore.
    }
  }

  void _scheduleDim() {
    _dimTimer?.cancel();
    _dimTimer = Timer(const Duration(seconds: 30), () {
      _setDimmed(true);
    });
    // Prefer system timeout if available (override the default above).
    _screenChannel.invokeMethod<int>('getScreenTimeout').then((timeout) {
      if (timeout != null && timeout > 0 && mounted && _phase == _Phase.running) {
        _dimTimer?.cancel();
        _dimTimer = Timer(
          Duration(milliseconds: (timeout * 0.9).round()),
          () {
            _setDimmed(true);
          },
        );
      }
    }).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == _Phase.running) {
      if (_remaining <= Duration.zero) {
        _finish();
      } else {
        setState(() {});
        _startClock();
        _setKeepScreenOn(true);
        _setLowRefresh(true);
        _scheduleDim();
        _showNotificationForTimer();
      }
    }
  }

  Future<void> _restorePersisted() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_prefActiveKey) ?? false)) return;
    final si = prefs.getInt(_prefStartIndexKey);
    final sm = prefs.getInt(_prefStartMsKey);
    if (si == null || sm == null) {
      await _clearPersisted();
      return;
    }
    final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(sm));
    final duration = Duration(minutes: si + 1);
    if (elapsed >= duration) {
      await _clearPersisted();
      return;
    }
    if (!mounted) return;
    setState(() {
      _startIndex = si;
      _startTime = DateTime.fromMillisecondsSinceEpoch(sm);
      _duration = duration;
      _phase = _Phase.running;
    });
    _pulseController.repeat(reverse: true);
    _startClock();
    _setKeepScreenOn(true);
    _setLowRefresh(true);
    _scheduleDim();
    _showNotificationForTimer();
  }

  Future<void> _persistStart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefActiveKey, true);
    await prefs.setInt(_prefStartIndexKey, _startIndex!);
    await prefs.setInt(_prefStartMsKey, _startTime!.millisecondsSinceEpoch);
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefActiveKey);
    await prefs.remove(_prefStartIndexKey);
    await prefs.remove(_prefStartMsKey);
  }

  Color _dotColor(int index, int passed, int current) {
    if (_phase == _Phase.idle) {
      return _neon.withOpacity(0.45);
    }
    // not in this timer (before start index) -> grayed out
    if (!_isInTimer(index)) {
      return _gray;
    }
    // finished: all in-timer dots use blink opacity (handled by caller) base neon
    if (_phase == _Phase.finished) {
      return _neon;
    }
    // running (counting down: higher indices pass first)
    if (index > current) {
      return _neon.withOpacity(0.35); // passed -> dim
    }
    if (index == current) {
      return _neon; // active (pulse applied by animation)
    }
    return _neon; // upcoming
  }

  double _dotOpacity(int index, int passed, int current) {
    if (_phase == _Phase.finished && _isInTimer(index)) {
      return 0.2 + 0.8 * _blinkOpacity.value;
    }
    if (_phase == _Phase.running && index == current) {
      return 0.4 + 0.6 * _pulseController.value;
    }
    return 1.0;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _timerText {
    if (_phase == _Phase.idle) return '60:00';
    if (_phase == _Phase.finished) return '00:00';
    return _formatDuration(_remaining);
  }


  @override
  Widget build(BuildContext context) {
    final passed = _passedMinutes;
    final current = _currentDotIndex;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: _endTimer,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 15,
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(
                        [_pulseController, _blinkController]),
                    builder: (context, _) {
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _timerText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            color: _neon,
                            letterSpacing: 4,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                flex: 80,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const hSpacing = 10.0;
                    final cellWidth =
                        (constraints.maxWidth - (_columns - 1) * hSpacing) /
                            _columns;
                    final rows = (_dotCount / _columns).ceil();
                    final neededHeight = rows * cellWidth;
                    var vSpacing =
                        (constraints.maxHeight - neededHeight) / (rows - 1);
                    if (!vSpacing.isFinite || vSpacing < hSpacing) {
                      vSpacing = hSpacing;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GridView.count(
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: _columns,
                        mainAxisSpacing: vSpacing,
                        crossAxisSpacing: hSpacing,
                        childAspectRatio: 1.0,
                        children: List.generate(_dotCount, (i) {
                          final isActive = _phase == _Phase.running &&
                              i == current;
                          return _Dot(
                            color: _dotColor(i, passed, current),
                            opacity: _dotOpacity(i, passed, current),
                            onTap: () => _startAt(i),
                            enabled: _phase != _Phase.running,
                            halo: isActive,
                          );
                        }),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                flex: 5,
                child: Center(
                  child: Text(
                    'Press a dot to start  •  Hold screen to end',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _neon.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.opacity,
    required this.onTap,
    required this.enabled,
    this.halo = false,
  });

  final Color color;
  final double opacity;
  final VoidCallback onTap;
  final bool enabled;
  final bool halo;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.55),
                blurRadius: 8,
                spreadRadius: 1,
              ),
              if (halo)
                BoxShadow(
                  color: const Color(0xFF39FF14).withOpacity(0.45),
                  blurRadius: 22,
                  spreadRadius: 6,
                ),
              if (halo)
                BoxShadow(
                  color: const Color(0xFF39FF14).withOpacity(0.25),
                  blurRadius: 40,
                  spreadRadius: 12,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

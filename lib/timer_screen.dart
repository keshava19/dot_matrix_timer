import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int cols = 6;
const int rows = 10;
const Color neon = Color(0xFF39FF14);
const Color offColor = Color(0xFF1C1C1C);
const Duration holdToEnd = Duration(milliseconds: 700);
const Duration endFlash = Duration(seconds: 8);
const Duration doneTimeout = Duration(seconds: 60);
const Duration lateEnd = Duration(milliseconds: 1500);
const Duration autoResetGrace = Duration(milliseconds: 1500);

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key, this.initialEndMs, this.initialTotal});

  final int? initialEndMs;
  final int? initialTotal;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> with WidgetsBindingObserver {
  static const MethodChannel _screenChannel = MethodChannel(
    'dot_matrix_timer/screen',
  );

  final GlobalKey _gridKey = GlobalKey();

  Timer? _uiTimer;

  static const List<Offset> _burnOffsets = <Offset>[
    Offset.zero,
    Offset(2, 0),
    Offset(2, 2),
    Offset(0, 2),
    Offset(-2, 2),
    Offset(-2, 0),
    Offset(-2, -2),
    Offset(0, -2),
    Offset(2, -2),
  ];

  // Timer model (mirrors dot_timer.dart)
  int total = 0; // minutes chosen (active dots)
  int preview = 0;
  DateTime? end;
  DateTime? endingSince;
  DateTime? holdSince;
  bool calm = false;

  static const String _prefActiveKey = 'timer_active';
  static const String _prefEndMsKey = 'timer_end_ms';
  static const String _prefTotalKey = 'timer_total';

  int get remainingMs => end == null
      ? 0
      : math.max(0, end!.difference(DateTime.now()).inMilliseconds);

  bool get running => end != null && endingSince == null;

  void _startUiTimer() {
    _uiTimer?.cancel();
    var ticks = 0;
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _onTick();
      ticks++;
      if (ticks % 30 == 0 && (running || endingSince != null)) {
        _antiBurnIndex = (_antiBurnIndex + 1) % _burnOffsets.length;
      }
      if (running || endingSince != null || preview > 0) setState(() {});
    });
  }

  void _stopUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = null;
  }

  bool _notificationsAllowed = false;
  Timer? _dimTimer;
  Timer? _lateDimTimer;
  int _antiBurnIndex = 0;
  bool _swallow = false;
  DateTime? _lockedUntil;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _screenChannel.invokeMethod('preloadSounds').catchError((_) {});
    });
    final ie = widget.initialEndMs;
    final it = widget.initialTotal;
    if (ie != null && it != null) {
      final e = DateTime.fromMillisecondsSinceEpoch(ie);
      if (DateTime.now().isBefore(e)) {
        end = e;
        total = it;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || end == null) return;
        _setKeepScreenOn(true);
        _setLowRefresh(true);
        _scheduleDim();
        _showNotificationForTimer();
        _startUiTimer();
      });
    } else {
      _restorePersisted();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    calm = MediaQuery.of(context).disableAnimations;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _dimTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopUiTimer();
      if (running && _notificationsAllowed) {
        _showNotificationForTimer();
        _scheduleEndNotification();
      }
    } else if (state == AppLifecycleState.resumed) {
      _cancelEndNotification();
      if (end != null) {
        final now = DateTime.now();
        if (!now.isBefore(end!) && endingSince == null) {
          _cancelNotification();
          if (now.difference(end!) > lateEnd) {
            endingSince = end;
          } else {
            endingSince = now;
            HapticFeedback.vibrate();
            _playSound('end');
          }
        }
        setState(() {});
        _setKeepScreenOn(true);
        _setLowRefresh(true);
        _scheduleDim();
        if (_notificationsAllowed && endingSince == null) {
          _showNotificationForTimer();
        }
        if (end != null) _startUiTimer();
      }
    }
  }

  Future<void> _restorePersisted() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_prefActiveKey) ?? false)) return;
    final em = prefs.getInt(_prefEndMsKey);
    final tt = prefs.getInt(_prefTotalKey);
    if (em == null || tt == null) {
      await _clearPersisted();
      return;
    }
    final e = DateTime.fromMillisecondsSinceEpoch(em);
    if (!DateTime.now().isBefore(e)) {
      // Possibly finished while away: dismiss to idle.
      await _clearPersisted();
      return;
    }
    if (!mounted) return;
    setState(() {
      end = e;
      total = tt;
      endingSince = null;
      preview = 0;
      holdSince = null;
    });
    _setKeepScreenOn(true);
    _setLowRefresh(true);
    _scheduleDim();
    _showNotificationForTimer();
    _startUiTimer();
  }

  Future<void> _persistStart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefActiveKey, true);
    await prefs.setInt(_prefEndMsKey, end!.millisecondsSinceEpoch);
    await prefs.setInt(_prefTotalKey, total);
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefActiveKey);
    await prefs.remove(_prefEndMsKey);
    await prefs.remove(_prefTotalKey);
  }

  void _onTick() {
    if (end == null && endingSince == null && preview == 0) {
      _stopUiTimer();
      return;
    }
    final now = DateTime.now();
    if (endingSince != null) {
      if (now.difference(endingSince!) > endFlash + doneTimeout) {
        _reset(auto: true);
      }
      return;
    }
    if (end == null) return;
    if (!now.isBefore(end!)) {
      if (now.difference(end!) > lateEnd) {
        endingSince = end;
      } else {
        endingSince = now;
        HapticFeedback.vibrate();
        _playSound('end');
      }
    } else if (holdSince != null && now.difference(holdSince!) >= holdToEnd) {
      HapticFeedback.heavyImpact();
      _swallow = true;
      _reset();
    }

    // Notification updates are handled by the Android chronometer.
  }

  // Interaction helpers
  int _dotAt(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final p = box.globalToLocal(global);
    final s = box.size;
    if (p.dx < 0 || p.dy < 0 || p.dx > s.width || p.dy > s.height) return 0;
    final c = (p.dx / (s.width / cols)).floor().clamp(0, cols - 1);
    final r = (p.dy / (s.height / rows)).floor().clamp(0, rows - 1);
    return r * cols + c + 1;
  }

  void _scrub(Offset g) {
    final n = _dotAt(g);
    if (n != preview) {
      if (n > 0) HapticFeedback.selectionClick();
      setState(() => preview = n);
    }
  }

  void _handlePointerDown(PointerDownEvent e) {
    if (_lockedUntil != null) {
      final lock = _lockedUntil!;
      _lockedUntil = null;
      if (DateTime.now().isBefore(lock)) {
        _swallow = true;
        return;
      }
    }
    if (endingSince != null) {
      _swallow = true;
      _reset();
      return;
    }
    if (end != null) {
      holdSince = DateTime.now();
    } else {
      _scrub(e.position);
    }
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (_swallow || end != null) return;
    _scrub(e.position);
  }

  void _handlePointerUp(PointerEvent e) {
    if (_swallow) {
      _swallow = false;
      return;
    }
    if (end != null) {
      holdSince = null;
    } else if (preview > 0 && e is PointerUpEvent) {
      _beginTimer(preview);
    } else {
      setState(() => preview = 0);
    }
  }

  void _handlePointerCancel(PointerCancelEvent e) {
    if (end != null) {
      holdSince = null;
    } else {
      setState(() => preview = 0);
    }
  }

  Future<void> _beginTimer(int minutes) async {
    final e = DateTime.now().add(Duration(minutes: minutes));
    setState(() {
      total = minutes;
      end = e;
      preview = 0;
      endingSince = null;
      holdSince = null;
    });
    await _persistStart();
    _setKeepScreenOn(true);
    _setLowRefresh(true);
    _scheduleDim();
    _showNotificationForTimer();
    _startUiTimer();
    _playSound('start');
    HapticFeedback.mediumImpact();
  }

  void _reset({bool auto = false}) {
    final wasEnding = endingSince != null;
    if (auto) _lockedUntil = DateTime.now().add(autoResetGrace);
    setState(() {
      total = 0;
      preview = 0;
      end = null;
      endingSince = null;
      holdSince = null;
      _swallow = false;
    });
    _clearPersisted();
    _cancelNotification();
    _cancelEndNotification();
    _setKeepScreenOn(false);
    _setLowRefresh(false);
    _setDimmed(false);
    _lateDimTimer?.cancel();
    _lateDimTimer = null;
    _dimTimer?.cancel();
    _stopUiTimer();
    _antiBurnIndex = 0;
    if (wasEnding) _stopSound();
  }

  // Platform channel helpers
  Future<void> _setKeepScreenOn(bool on) async {
    try {
      await _screenChannel.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {}
  }

  Future<void> _setLowRefresh(bool on) async {
    try {
      await _screenChannel.invokeMethod('setLowRefresh', {'on': on});
    } catch (_) {}
  }

  Future<void> _setDimLevel(double? level) async {
    try {
      if (level == null) {
        await _screenChannel.invokeMethod('setDimmed', {'on': false});
      } else {
        await _screenChannel.invokeMethod('setDimmed', {'on': true, 'level': level});
      }
    } catch (_) {}
  }

  Future<void> _setDimmed(bool on) async {
    await _setDimLevel(on ? 0.15 : null);
  }

  Future<void> _setVeryDimmed(bool on) async {
    await _setDimLevel(on ? 0.05 : 0.15);
  }

  void _scheduleDim() {
    _dimTimer?.cancel();
    _lateDimTimer?.cancel();
    _dimTimer = Timer(const Duration(seconds: 30), () {
      _setDimmed(true);
      _lateDimTimer = Timer(const Duration(seconds: 90), () {
        _setVeryDimmed(true);
      });
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final granted = await _screenChannel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      if (mounted) setState(() => _notificationsAllowed = granted ?? true);
    } catch (_) {
      if (mounted) setState(() => _notificationsAllowed = false);
    }
  }

  Future<void> _showNotificationForTimer({
    DateTime? end,
  }) async {
    if (!_notificationsAllowed) return;
    final e = end ?? this.end;
    if (e == null) return;
    try {
      await _screenChannel.invokeMethod('showTimerNotification', {
        'endMs': e.millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  Future<void> _cancelNotification() async {
    if (!_notificationsAllowed) return;
    try {
      await _screenChannel.invokeMethod('cancelTimerNotification');
    } catch (_) {}
  }

  Future<void> _scheduleEndNotification() async {
    if (!_notificationsAllowed || end == null) return;
    try {
      await _screenChannel.invokeMethod('scheduleEndNotification', {
        'endMs': end!.millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  Future<void> _cancelEndNotification() async {
    if (!_notificationsAllowed) return;
    try {
      await _screenChannel.invokeMethod('cancelEndNotification');
    } catch (_) {}
  }

  Future<void> _playSound(String sfx) async {
    try {
      await _screenChannel.invokeMethod('playSound', {'sfx': sfx});
    } catch (_) {}
  }

  Future<void> _stopSound() async {
    try {
      await _screenChannel.invokeMethod('stopSound');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final idle = end == null && preview == 0;

    final hint = endingSince != null
        ? 'Tap to dismiss'
        : end != null
        ? 'Hold to end'
        : 'Tap a dot to set minutes';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 28),
                Builder(
                  builder: (_) {
                    const base = TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    );
                    if (end == null && preview > 0) {
                      return Text(
                        '$preview min',
                        style: base.copyWith(color: neon),
                      );
                    }
                    final s = (remainingMs / 1000).ceil();
                    final mStr = (s ~/ 60).toString().padLeft(2, '0');
                    final secStr = (s % 60).toString().padLeft(2, '0');
                    final a = idle ? 0.25 : 1.0;
                    return Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: mStr,
                            style: base.copyWith(
                              color: neon.withValues(alpha: a),
                            ),
                          ),
                          TextSpan(
                            text: ':',
                            style: base.copyWith(
                              color: neon.withValues(alpha: a * 0.5),
                            ),
                          ),
                          TextSpan(
                            text: secStr,
                            style: base.copyWith(
                              color: neon.withValues(alpha: a * 0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: Center(
                    child: Transform.translate(
                      offset: _burnOffsets[_antiBurnIndex],
                      child: AspectRatio(
                        aspectRatio: cols / rows,
                        child: CustomPaint(
                          key: _gridKey,
                          painter: _GridPainter(this),
                        ),
                      ),
                    ),
                  ),
                ),
                // Hold-to-end progress line
                if (holdSince != null && end != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Builder(
                      builder: (_) {
                        final p =
                            (DateTime.now()
                                        .difference(holdSince!)
                                        .inMilliseconds /
                                    holdToEnd.inMilliseconds)
                                .clamp(0.0, 1.0);
                        return Container(
                          height: 2,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: p,
                            child: Container(color: neon),
                          ),
                        );
                      },
                    ),
                  ),
                Builder(
                  builder: (_) => Text(
                    hint,
                    style: TextStyle(
                      fontSize: 13,
                      color: neon.withValues(alpha: 0.55),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.state);
  final _TimerScreenState state;

  @override
  void paint(Canvas c, Size s) {
    final now = DateTime.now();
    final cell = s.width / cols;
    final r = cell * 0.40;

    final remMs = state.remainingMs;
    final running = state.end != null && state.endingSince == null;
    final cur = running ? (remMs / 60000).ceil() - 1 : -1;
    final inMin = remMs % 60000 == 0 ? 60000 : remMs % 60000;
    final minuteFrac = running ? 1 - inMin / 60000 : 0.0;

    final activeAlpha = state.endingSince == null ? 1.0 : _endAlpha(now, state);
    final pulse = state.calm
        ? 1.0
        : 0.5 +
              0.5 *
                  math.sin(
                    2 * math.pi * now.millisecondsSinceEpoch / 1000.0 / 2.0,
                  );

    for (var i = 0; i < cols * rows; i++) {
      final o = Offset((i % cols + 0.5) * cell, (i ~/ cols + 0.5) * cell);
      if (state.endingSince != null) {
        i < state.total ? _lit(c, o, r, activeAlpha) : _off(c, o, r);
      } else if (state.end != null) {
        if (i < cur) {
          _lit(c, o, r, 1);
        } else if (i == cur) {
          _current(c, o, r, pulse, minuteFrac);
        } else if (i < state.total) {
          _passed(c, o, r);
        } else {
          _off(c, o, r);
        }
      } else {
        i < state.preview ? _lit(c, o, r, 0.6) : _off(c, o, r);
      }
    }

    // Hold-to-end progress, drawn just under the grid.
    if (state.holdSince != null && state.end != null) {
      final p =
          (now.difference(state.holdSince!).inMilliseconds /
                  holdToEnd.inMilliseconds)
              .clamp(0.0, 1.0);
      c.drawLine(
        Offset(0, s.height + 10),
        Offset(s.width * p, s.height + 10),
        Paint()
          ..color = neon
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  double _endAlpha(DateTime now, _TimerScreenState state) {
    final e = now.difference(state.endingSince!).inMilliseconds / 1000.0;
    final flashSecs = endFlash.inMilliseconds / 1000.0;

    if (state.calm) {
      return 0.35 + 0.65 * Curves.easeOut.transform(e.clamp(0.0, 1.0));
    }

    if (e < flashSecs) {
      return 0.12 + 0.88 * math.pow(0.5 + 0.5 * math.cos(2 * math.pi * e), 0.6);
    }

    final d = e - flashSecs;
    final breathe = 0.35 + 0.35 * (0.5 + 0.5 * math.cos(2 * math.pi * d / 4.0));
    final k = Curves.easeInOut.transform(d.clamp(0.0, 1.0));
    return 1.0 + (breathe - 1.0) * k;
  }

  void _off(Canvas c, Offset o, double r) =>
      c.drawCircle(o, r * 0.55, Paint()..color = offColor);

  void _lit(Canvas c, Offset o, double r, double a) {
    c.drawCircle(
      o,
      r * 1.05,
      Paint()
        ..color = neon.withValues(alpha: 0.45 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
    );
    c.drawCircle(o, r, Paint()..color = neon.withValues(alpha: a));
  }

  void _passed(Canvas c, Offset o, double r) {
    c.drawCircle(o, r, Paint()..color = neon.withValues(alpha: 0.08));
    c.drawCircle(
      o,
      r - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = neon.withValues(alpha: 0.30),
    );
  }

  void _current(Canvas c, Offset o, double r, double p, double frac) {
    c.drawCircle(
      o,
      r * (1.15 + 0.45 * p),
      Paint()
        ..color = neon.withValues(alpha: 0.20 + 0.40 * p)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
    );
    c.drawCircle(
      o,
      r,
      Paint()..color = neon.withValues(alpha: 0.75 + 0.25 * p),
    );
    final ring = Rect.fromCircle(center: o, radius: r * 1.22);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = neon.withValues(alpha: 0.12);
    c.drawArc(ring, 0, 2 * math.pi, false, track);
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = neon;
    c.drawArc(ring, -math.pi / 2, 2 * math.pi * frac, false, fill);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => true;
}

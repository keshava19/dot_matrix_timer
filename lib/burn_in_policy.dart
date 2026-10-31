import 'package:flutter/material.dart';

enum BurnInLifecycle { idle, set, running, done }

enum BurnInPhase { idle, set, runningWarmup, runningAmbient, runningDeep, doneGlow, doneDim, doneSleep }

class BurnInConfig {
  const BurnInConfig({
    required this.touchWake,
    required this.unlitFade,
    required this.warmupLimit,
    required this.ambientFade,
    required this.ambientLimit,
    required this.doneGlow,
    required this.doneFade,
    required this.doneSleep,
    required this.shiftTick,
  });

  final Duration touchWake;
  final Duration unlitFade;
  final Duration warmupLimit;
  final Duration ambientFade;
  final Duration ambientLimit;
  final Duration doneGlow;
  final Duration doneFade;
  final Duration doneSleep;
  final Duration shiftTick;

  static const BurnInConfig normal = BurnInConfig(
    touchWake: Duration(seconds: 5),
    unlitFade: Duration(seconds: 5),
    warmupLimit: Duration(seconds: 30),
    ambientFade: Duration(milliseconds: 1500),
    ambientLimit: Duration(minutes: 2),
    doneGlow: Duration(seconds: 10),
    doneFade: Duration(milliseconds: 1500),
    doneSleep: Duration(seconds: 60),
    shiftTick: Duration(minutes: 1),
  );

  static BurnInConfig demo() => const BurnInConfig(
        touchWake: Duration(milliseconds: 500),
        unlitFade: Duration(milliseconds: 500),
        warmupLimit: Duration(seconds: 3),
        ambientFade: Duration(milliseconds: 150),
        ambientLimit: Duration(seconds: 12),
        doneGlow: Duration(seconds: 1),
        doneFade: Duration(milliseconds: 300),
        doneSleep: Duration(seconds: 6),
        shiftTick: Duration(seconds: 2),
      );
}

class BurnInVisual {
  const BurnInVisual({
    this.brightnessOverride,
    this.litIntensity = 1.0,
    this.headIntensity = 1.0,
    this.unlitColor = const Color(0xFF1C1C1C),
    this.readoutOpacity = 1.0,
    this.hintOpacity = 0.55,
    this.pulse = false,
    this.shiftIndex = 0,
    this.phase = BurnInPhase.idle,
    this.doneFullGlow = false,
    this.allowSleep = false,
  });

  /// `null` means restore the system brightness override.
  final double? brightnessOverride;
  final double litIntensity;
  final double headIntensity;
  final Color unlitColor;
  final double readoutOpacity;
  final double hintOpacity;
  final bool pulse;
  final int shiftIndex;
  final BurnInPhase phase;
  final bool doneFullGlow;
  final bool allowSleep;
}

class BurnInPolicy {
  BurnInPolicy._();

  static const List<Offset> shiftCycle = <Offset>[
    Offset.zero,
    Offset(4, 0),
    Offset(4, 4),
    Offset(0, 4),
    Offset(-4, 4),
    Offset(-4, 0),
    Offset(-4, -4),
    Offset(0, -4),
  ];

  static Offset shiftFor(int shiftIndex) => shiftCycle[shiftIndex % shiftCycle.length];

  static BurnInVisual calculate({
    required BurnInLifecycle state,
    required Duration elapsed,
    required Duration doneElapsed,
    required Duration? timeSinceTouch,
    required bool reducedMotion,
    required BurnInConfig config,
  }) {
    switch (state) {
      case BurnInLifecycle.idle:
      case BurnInLifecycle.set:
        return const BurnInVisual(
          phase: BurnInPhase.idle,
          unlitColor: Color(0xFF1C1C1C),
          readoutOpacity: 1.0,
        );
      case BurnInLifecycle.running:
        return _running(
          elapsed: elapsed,
          timeSinceTouch: timeSinceTouch,
          reducedMotion: reducedMotion,
          config: config,
        );
      case BurnInLifecycle.done:
        return _done(
          elapsed: doneElapsed,
          reducedMotion: reducedMotion,
          config: config,
        );
    }
  }

  static BurnInVisual _running({
    required Duration elapsed,
    required Duration? timeSinceTouch,
    required bool reducedMotion,
    required BurnInConfig config,
  }) {
    final seconds = elapsed.inMilliseconds / 1000.0;
    final warmupSeconds = config.warmupLimit.inMilliseconds / 1000.0;
    final deepSeconds = config.ambientLimit.inMilliseconds / 1000.0;
    final touchWakeActive = timeSinceTouch != null &&
        timeSinceTouch <= config.touchWake;

    if (seconds < warmupSeconds) {
      final pulse = !reducedMotion && !touchWakeActive;
      final unlitAlpha = touchWakeActive
          ? 0.0
          : (1.0 - (seconds / (config.unlitFade.inMilliseconds / 1000.0)))
              .clamp(0.0, 1.0) *
              0.102;
      return BurnInVisual(
        brightnessOverride: touchWakeActive ? 0.30 : 0.30,
        litIntensity: touchWakeActive ? 1.0 : 1.0,
        headIntensity: 1.0,
        unlitColor: Color.lerp(const Color(0xFF1A1A1A), Colors.black, 1.0 - unlitAlpha / 0.102)!,
        readoutOpacity: 1.0,
        hintOpacity: 0.55,
        pulse: pulse,
        shiftIndex: 0,
        phase: BurnInPhase.runningWarmup,
      );
    }

    final inBrightnessFade = seconds < warmupSeconds + (config.ambientFade.inMilliseconds / 1000.0);
    final brightness = reducedMotion
        ? 0.10
        : touchWakeActive
            ? 0.30
            : inBrightnessFade
                ? 0.30 -
                    (0.20 *
                        ((seconds - warmupSeconds) /
                            (config.ambientFade.inMilliseconds / 1000.0))
                        .clamp(0.0, 1.0))
                : 0.10;

    final shiftTickSeconds = config.shiftTick.inMilliseconds / 1000.0;
    final elapsedMinutes = (seconds / shiftTickSeconds).floor();
    final headIntensity = _headIntensity(seconds, elapsedMinutes, reducedMotion: reducedMotion);

    return BurnInVisual(
      brightnessOverride: brightness,
      litIntensity: touchWakeActive ? 1.0 : 0.55,
      headIntensity: touchWakeActive ? 1.0 : headIntensity,
      unlitColor: Colors.black,
      readoutOpacity: touchWakeActive ? 1.0 : 0.55,
      hintOpacity: touchWakeActive ? 0.55 : 0.35,
      pulse: false,
      shiftIndex: elapsedMinutes % 8,
      phase: seconds >= deepSeconds ? BurnInPhase.runningDeep : BurnInPhase.runningAmbient,
    );
  }

  static double _headIntensity(double seconds, int elapsedMinutes, {required bool reducedMotion}) {
    if (reducedMotion) return 0.55;
    final withinMinute = seconds - (elapsedMinutes * 60.0);
    final progress = (withinMinute / 60.0).clamp(0.0, 1.0);
    return (1.0 - progress).clamp(0.0, 1.0);
  }

// _minuteTick removed; elapsed-minute tick uses the shift interval inline.

  static BurnInVisual _done({
    required Duration elapsed,
    required bool reducedMotion,
    required BurnInConfig config,
  }) {
    final seconds = elapsed.inMilliseconds / 1000.0;
    final glowSeconds = config.doneGlow.inMilliseconds / 1000.0;
    final fadeSeconds = config.doneFade.inMilliseconds / 1000.0;
    final fadeStart = (glowSeconds - fadeSeconds).clamp(0.0, glowSeconds);
    final sleepSeconds = config.doneSleep.inMilliseconds / 1000.0;

    final fullGlow = seconds <= glowSeconds;
    final allowSleep = seconds >= sleepSeconds;

    final fadeProgress = seconds <= fadeStart
        ? 0.0
        : (seconds <= glowSeconds
            ? ((seconds - fadeStart) / fadeSeconds).clamp(0.0, 1.0)
            : 1.0);
    final eased = Curves.easeOut.transform(fadeProgress);
    final intensity = (1.0 + (0.30 - 1.0) * eased).clamp(0.0, 1.0);
    final readout = (1.0 + (0.55 - 1.0) * eased).clamp(0.0, 1.0);
    final hint = (0.55 + (0.35 - 0.55) * eased).clamp(0.0, 1.0);

    return BurnInVisual(
      brightnessOverride: fullGlow ? null : (seconds <= sleepSeconds ? 0.10 : 0.10),
      litIntensity: reducedMotion ? (fullGlow ? 1.0 : 0.30) : intensity,
      headIntensity: reducedMotion ? (fullGlow ? 1.0 : 0.30) : intensity,
      unlitColor: Colors.black,
      readoutOpacity: reducedMotion ? (fullGlow ? 1.0 : 0.55) : readout,
      hintOpacity: reducedMotion ? (fullGlow ? 0.55 : 0.35) : hint,
      pulse: false,
      shiftIndex: 0,
      phase: fullGlow ? BurnInPhase.doneGlow : (allowSleep ? BurnInPhase.doneSleep : BurnInPhase.doneDim),
      doneFullGlow: fullGlow,
      allowSleep: allowSleep,
    );
  }
}
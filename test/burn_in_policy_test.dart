import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_matrix_timer/burn_in_policy.dart';

void main() {
  const config = BurnInConfig.normal;

  test('idle and set states restore defaults', () {
    final idle = BurnInPolicy.calculate(
      state: BurnInLifecycle.idle,
      elapsed: Duration.zero,
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(idle.brightnessOverride, isNull);
    expect(idle.pulse, isFalse);
    expect(idle.shiftIndex, 0);

    final set = BurnInPolicy.calculate(
      state: BurnInLifecycle.set,
      elapsed: Duration.zero,
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(set.brightnessOverride, isNull);
    expect(set.shiftIndex, 0);
  });

  test('running warmup phase fades unlit dots to black', () {
    final atStart = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: Duration.zero,
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(atStart.brightnessOverride, 0.30);
    expect(atStart.pulse, isTrue);
    expect(atStart.litIntensity, 1.0);
    expect(atStart.headIntensity, 1.0);
    expect(atStart.unlitColor, const Color(0xFF1A1A1A));

    final afterFive = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: const Duration(seconds: 5),
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(afterFive.unlitColor, Colors.black);
    expect(afterFive.shiftIndex, 0);
  });

  test('running crosses 30 seconds into ambient phase', () {
    final at30 = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: const Duration(seconds: 30),
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(at30.pulse, isFalse);
    expect(at30.brightnessOverride, closeTo(0.30, 0.001));
    expect(at30.litIntensity, closeTo(0.55, 0.001));
    expect(at30.shiftIndex, 0);

    final at2Min = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: const Duration(minutes: 2),
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(at2Min.brightnessOverride, closeTo(0.10, 0.001));
    expect(at2Min.shiftIndex, 2);
    expect(at2Min.pulse, isFalse);
  });

  test('touch wakes brightness for 5 seconds', () {
    final base = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: const Duration(seconds: 45),
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    final woke = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: const Duration(seconds: 45),
      doneElapsed: Duration.zero,
      timeSinceTouch: const Duration(seconds: 2),
      reducedMotion: false,
      config: config,
    );
    expect(base.brightnessOverride, closeTo(0.10, 0.001));
    expect(woke.brightnessOverride, 0.30);
    expect(woke.litIntensity, 1.0);

    final afterWake = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: const Duration(seconds: 45),
      doneElapsed: Duration.zero,
      timeSinceTouch: const Duration(seconds: 6),
      reducedMotion: false,
      config: config,
    );
    expect(afterWake.brightnessOverride, closeTo(0.10, 0.001));
  });

  test('done phase dims after 10 seconds and allows sleep after 60', () {
    final glow = BurnInPolicy.calculate(
      state: BurnInLifecycle.done,
      elapsed: Duration.zero,
      doneElapsed: const Duration(seconds: 5),
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(glow.doneFullGlow, isTrue);
    expect(glow.brightnessOverride, isNull);

    final dimmed = BurnInPolicy.calculate(
      state: BurnInLifecycle.done,
      elapsed: Duration.zero,
      doneElapsed: const Duration(seconds: 15),
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(dimmed.doneFullGlow, isFalse);
    expect(dimmed.brightnessOverride, closeTo(0.10, 0.001));
    expect(dimmed.allowSleep, isFalse);

    final sleeping = BurnInPolicy.calculate(
      state: BurnInLifecycle.done,
      elapsed: Duration.zero,
      doneElapsed: const Duration(seconds: 65),
      timeSinceTouch: null,
      reducedMotion: false,
      config: config,
    );
    expect(sleeping.allowSleep, isTrue);
  });

  test('pixel shift uses only the eight-position cycle', () {
    for (var minute = 0; minute <= 60; minute++) {
      final result = BurnInPolicy.calculate(
        state: BurnInLifecycle.running,
        elapsed: Duration(minutes: minute),
        doneElapsed: Duration.zero,
        timeSinceTouch: null,
        reducedMotion: false,
        config: config,
      );
      expect(result.shiftIndex, (minute % 8));
      final offset = BurnInPolicy.shiftFor(result.shiftIndex);
      expect(offset.dx.abs(), lessThanOrEqualTo(4));
      expect(offset.dy.abs(), lessThanOrEqualTo(4));
    }
  });

  test('reduced motion disables pulse and fades', () {
    final visual = BurnInPolicy.calculate(
      state: BurnInLifecycle.running,
      elapsed: const Duration(seconds: 10),
      doneElapsed: Duration.zero,
      timeSinceTouch: null,
      reducedMotion: true,
      config: config,
    );
    expect(visual.pulse, isFalse);
    expect(visual.litIntensity, 1.0);
  });
}
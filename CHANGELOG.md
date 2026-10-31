# Changelog

## 1.3.0 - 2026-10-31

### Added
- Burn-in reduction policy with configurable warmup, ambient, done, touch-wake, and sleep timings.
- Dynamic screen brightness levels (`0.30` while active/awake, `0.10` in ambient/done-dim states).
- 8-position pixel shifting for the running dot grid.
- Touch-wake behavior that restores full brightness and intensity for 5 seconds.
- Done-state sequence: 10-second full glow, then dimmed rest state, sleep allowed after 60 seconds.
- Pure policy module (`lib/burn_in_policy.dart`) and focused policy tests.
- Native Android `setDimmed` support for an explicit brightness level.

### Changed
- Replaced the fixed 30-second dim timer with the policy-driven burn-in state.
- Timer grid rendering now adapts lit/head intensity, unlit color, opacity, pulse, and shift to policy state.
- End-state rendering focuses glow on the timer completion cluster before dimming.
- App pause restores system brightness and cancels background UI timer updates.

### Fixed
- Haptic feedback on timer completion uses `heavyImpact`.
- Done-phase cleanup cancels pending dim/sleep timers on reset.

## 1.2.1 - 2026-10-31

### Added
- Active notification while the app is backgrounded with a running timer.
- Android chronometer notification that counts down automatically while backgrounded.
- Custom monochrome notification status icon (`ic_stat_dot_timer`).
- Launcher icon set restored for Android and iOS.
- Keep rule for notification status icon in release builds.

### Changed
- Display name set to "Dot Matrix" across Android/iOS and the app title.
- Notification shows the live chronometer only to avoid inconsistent countdown text/progress.
- Idle animation is paused when no timer or preview is active.
- Sound preloading is deferred to after first frame.
- Reduced release size with split-by-ABI APKs, R8 resource shrinking, and ProGuard.
- Compressed audio assets by converting WAVs to OGG Vorbis.
- Enabled legacy native-library packaging to shrink release APK download size.

### Fixed
- End-of-timer notification cancels stale ongoing timer notification.
- Notification permission state stays accurate when granted through the notification path.
- Removed unused leftover `ic_stat_dot_matrix` drawable.
- Removed unused Cupertino Icons dependency.

## 1.0.0

Initial release.
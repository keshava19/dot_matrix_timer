# Changelog

## 1.2.0 - 2026-10-30

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

### Fixed
- End-of-timer notification cancels stale ongoing timer notification.
- Notification permission state stays accurate when granted through the notification path.
- Removed unused leftover `ic_stat_dot_matrix` drawable.
- Removed unused Cupertino Icons dependency.

## 1.0.0

Initial release.
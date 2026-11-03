# Play Store asset checklist (Dot Matrix)

## Required graphics

- [x] App icon (Play listing) — 512 x 512 PNG. Source from Android adaptive icon foreground/background; flatten to 512 PNG. No extra padding beyond icon safe zone.
- [x] Feature graphic — 1024 x 500 PNG/JPG. Template: black background, dot grid, "Dot Matrix" wordmark.
- [x] Phone screenshots — at least 2, recommended 8. Size 1080 x 1920 or 1080 x 2400, 9:16 portrait, PNG/JPEG.
  - [x] Idle grid
  - [x] Running timer with header
  - [x] Scrub preview
  - [x] Completion flash
  - [x] Done state
  - [x] Background notification in shade
  - [x] (Optional) dimmed/burn-in state
- [ ] 7-inch tablet screenshots — optional; only if supporting tablets.
- [ ] 10-inch tablet screenshots — optional.
- [ ] Promo video — optional YouTube URL.

## Brand references

- Background: pure black `#000000`
- Dot on: neon green `#1B7F0E` (notification color used in app) — adjust to brand green if desired.
- Wordmark: monospace font, lowercase or title case "Dot Matrix".
- Existing launcher assets: `android/app/src/main/res/mipmap-*`.

## File naming convention

- `icon_512x512.png`
- `feature_graphic_1024x500.png`
- `screenshot_phone_01.png` … `screenshot_phone_08.png`

## Validation helper

Run after creating images:

```bash
python3 - <<'PY'
from pathlib import Path
required = [
    ("icon_512x512.png", 512, 512),
    ("feature_graphic_1024x500.png", 1024, 500),
]
print("Image validation requires Pillow; install with: pip install Pillow")
PY
```

If Pillow is installed, replace with a script that opens each PNG and asserts dimensions.
EOF
echo done

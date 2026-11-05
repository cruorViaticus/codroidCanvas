# codroid_pen_plotter

Flutter app that turns a Codroid S arm into a pen plotter (S Pen canvas →
`movMulti` packets over WebSocket → robot controller).

## Calibration & Settings

* **Robot IP Address** – controller IP (`ws://<ip>:9000`).
* **Drawing Speed (TCP)** – pen feed rate sent as `speed.stcp`, clamped to
  **10 – 500 mm/s** (robot limit). Persisted as `linear_speed`.
* **Paper Height / Z Offset** – shifts the whole pen path up or down by up to
  **±30 mm** (paper / table is higher or lower). Pen up = `penUpNominalZ + offset`,
  pen down = `penDownNominalZ + offset`. Persisted as `z_offset_mm`.
  Use *Test Pen UP / DOWN* to verify the contact height while the robot is idle.

Settings are stored in `SharedPreferences` and applied to every generated
`movl` / `movMulti` point.

## App icon

The launcher icon is a stylised Codroid industrial arm drawing with a pen.
The artwork lives in **`lib/widgets/app_logo.dart`** (`paintCodroidIcon`) and is
used both for the in-app logo (`AppLogo` widget, shown in the dashboard AppBar)
and for all platform icons — so they can never drift apart.

Generated files:

| Platform | Files |
| --- | --- |
| Android (legacy) | `res/mipmap-*/ic_launcher.png` (48–192 px) |
| Android (adaptive, API 26+) | `res/mipmap-anydpi-v26/ic_launcher.xml` + `res/mipmap-*/ic_launcher_foreground.png` + `values/colors.xml` |
| Windows | `windows/runner/resources/app_icon.ico` (16–256 px) |
| Web | `web/favicon.png`, `web/icons/Icon-(maskable-)192/512.png` |
| Master artwork | `assets/icon/app_icon_1024.png` |

Regenerate after changing the artwork (no extra dependencies — rendering goes
through the Flutter engine):

```bash
flutter test tool/generate_app_icons.dart
```

`tool/` is not part of the regular test suite, so `flutter test` stays fast.

## Motion safety

* Strokes are split into packets of **≤ 30 points** (`movMulti` limit).
* Each packet is sent only after the robot reports idle (`waitUntilIdle`).
* Controller errors (`data.code != 0`) are shown in the canvas error banner.

## Tests

```bash
flutter test
```


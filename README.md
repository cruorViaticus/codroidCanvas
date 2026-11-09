# codroid_pen_plotter

Flutter app that turns a Codroid S arm into a pen plotter (S Pen canvas →
`movMulti` packets over WebSocket → robot controller).

## Plot modes

| Mode | Entry point | What it does |
| --- | --- | --- |
| **Freehand (S Pen)** | `lib/screens/canvas_screen.dart` | draw with the pen, canvas → `movMulti` |
| **Text** | *Plot Text* on the dashboard → `lib/screens/text_print_screen.dart` | types the text with a single-stroke vector font (`lib/services/vector_font.dart`). No `TextPainter`: every glyph is a set of polylines, so the pen draws exactly what the robot can plot |
| **Black & white image** | *Plot Black & White Image* → `lib/screens/image_print_screen.dart` | picks a file with `file_picker`, decodes it with `dart:ui` (no native plugin), converts it to grayscale and traces it line by line (serpentine scanline) into plot strokes |

Both generators share the same plumbing:

* **Paper format** – A4, A3, A5 or 10 × 15 cm photo paper
  (`lib/models/paper_format.dart`). The **longer side of the sheet always lies
  along the robot X axis**, the shorter one along Y, so the sheet is never
  rotated: the canvas, the preview and the generated strokes just use the
  chosen millimetre dimensions (`lib/widgets/paper_format_selector.dart`,
  persisted as `paper_format`, default `a4`).
* **Live preview** (`lib/widgets/plot_preview.dart`, aspect ratio follows the
  selected paper) + stats – lines, strokes, points, path length and estimated
  time (`lib/services/plot_estimator.dart`).
* **Mirror X / Y** (`lib/services/plot_transform.dart`) for plotting on the
  back of the paper or mirroring a template.
* **Fine point spacing** – text/image strokes are queued with a custom
  `minPointSpacingMm` (0.3 – 1 mm) instead of the 5 mm freehand filter, so the
  controller does not cut off curves.
* **Add to plot queue** – `RobotProvider.addStrokes()` appends the whole set in
  one go; *Clear Canvas* empties the queue.

**Text** options: letter height 3 – 40 mm, line spacing 1 – 3×, paper margin
0 – 60 mm, left / center / right alignment, automatic wrapping, diacritics
normalised to the base letter, notices for unknown characters and for text that
does not fit the paper.

**Image** options: line density 0.4 – 4 mm, point spacing 0.2 – 2 mm, threshold
5 – 95 %, margin 0 – 40 mm, optional invert (plot the light areas) and a
truncation notice when the drawing hits
`ImageStrokeGenerator.defaultMaxPoints`.

## Calibration & Settings

* **Robot IP Address** – controller IP (`ws://<ip>:9000`).
* **Paper format** – A4 (210 × 297 mm), A3 (297 × 420 mm), A5 (148 × 210 mm) or
  photo paper 10 × 15 cm (100 × 150 mm). Saved immediately (`paper_format`) and
  offered on the text/image screens too. The longer side is mapped to the robot
  **X** axis, the shorter one to **Y** – so `movl` coordinates never exceed the
  sheet even if it is smaller than A4.
* **Drawing Speed (TCP)** – pen feed rate sent as `speed.stcp`, clamped to
  **10 – 500 mm/s** (robot limit). Persisted as `linear_speed`.
* **Paper Height / Z Offset** – shifts the whole pen path up or down by up to
  **±30 mm** (paper / table is higher or lower). Pen up = `penUpNominalZ + offset`,
  pen down = `penDownNominalZ + offset`. Persisted as `z_offset_mm`.
  Use *Test Pen UP / DOWN* to verify the contact height while the robot is idle.
* **Pen Lift & Blending (speed)** – the two parameters that decide how fast the
  arm plots:
  * **Pen lift** between strokes, default **3 mm** (range 1 – 50 mm, persisted as
    `pen_up_mm`). Every extra millimetre is a longer Z move per stroke, so 3 mm
    is enough to just leave the paper.
  * **Corner blending radius** (`zone.type = RELATIVE`, `zdis`), default **5 mm**
    (range 0 – 20 mm, persisted as `blend_mm`). With blending the controller
    flows through each path point instead of stopping at it; `0` = exact
    corners (slowest). Only the pen-down contact point and the last point of
    each packet stay `FINE` (exact stop).

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
* Strokes waiting in the FIFO queue are **chained into one continuous path**:
  the arm lifts the pen only 3 mm and keeps moving, so it does not stop between
  strokes.
* All path points inside a packet use `zone.type = RELATIVE` (**blending**), so
  the controller does not brake at every point. `FINE` is used only for the
  pen-down contact point and for the last point of each packet.
* Each packet is sent only after the robot reports idle (`waitUntilIdle`).
  The wait ends as soon as telemetry shows the TCP on the last commanded target
  (0.5 mm) and not moving – the conservative duration watchdog is only a
  fallback, so no time is wasted after the move is finished.
* Controller errors (`data.code != 0`) are shown in the canvas error banner.

## Tests

```bash
flutter test
```

* Generators / geometry – `test/text_stroke_generator_test.dart`,
  `test/image_stroke_generator_test.dart`, `test/plot_queue_spacing_test.dart`,
  `test/paper_format_test.dart` (paper formats, persistence, mm mapping).
* Screens – `test/text_print_screen_test.dart`,
  `test/image_print_screen_test.dart`, `test/settings_screen_test.dart`.
* Motion – `test/stroke_motion_processor_test.dart`.


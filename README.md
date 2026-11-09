# codroid_pen_plotter

Flutter app that turns a Codroid S arm into a pen plotter (S Pen canvas →
`movMulti` packets over WebSocket → robot controller).

## Plot modes

| Mode | Entry point | What it does |
| --- | --- | --- |
| **Freehand (S Pen)** | `lib/screens/canvas_screen.dart` | draw with the pen, canvas → `movMulti` |
| **Text** | *Plot Text* on the dashboard → `lib/screens/text_print_screen.dart` | types the text with a single-stroke vector font (`lib/services/vector_font.dart`). No `TextPainter`: every glyph is a set of polylines, so the pen draws exactly what the robot can plot |
| **Black & white image** | *Plot Black & White Image* → `lib/screens/image_print_screen.dart` | picks a file with `file_picker`, decodes it with `dart:ui` (no native plugin), converts it to grayscale and fills it with the selected plot pattern (`horizontal`, `vertical`, `diagonal`, `cross-hatch`, `dots`, `wave`, `spiral`, `outline` or `auto`) |

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
* **Plot pattern** (`lib/models/plot_pattern.dart`,
  `lib/widgets/plot_pattern_selector.dart`) – how the image is filled:
  horizontal scanlines (default, same bytes as before), vertical columns, 45°
  hatching, cross-hatch (two passes), dots, **wave**, **spiral** or
  **outline**. `auto` scores every filling candidate (path length + `20 mm` per
  pen lift) and uses the cheapest one for that image; the resolved pattern is
  shown next to the chips and in `ImagePlotResult.pattern`. All filling
  patterns keep the serpentine order (every second line runs backwards) so the
  pen travels shorter distances.
  * **Wave (`zigzag`)** – the rows are *joined* into one continuous zigzag, so
    a solid picture becomes a single very long stroke with one pen lift. Best
    choice when you want long lines instead of many short scanlines.
  * **Spiral** – one coil from the outer edge inwards (step = line density);
    the pen only lowers where the image has ink.
  * **Outline (`contour`)** – the pen does not fill anything, it walks the
    **edges** of the shapes, so the robot *draws* the picture like a sketch.
    Edges are found per pixel (ink changes between neighbouring columns / rows)
    and neighbouring edges are chained into long polylines, then simplified by
    `pointSpacingMm`. This is the pattern to use when the result should look
    hand-drawn rather than printed.
* **Pen line width (0.2 mm)** – the width of the ink line in mm, default
  **0.2 mm** (range 0.05 – 2 mm, persisted as `pen_width_mm`, slider in
  *Pen, Lift & Blending* and per plot on the image screen). It is not a motion
  command – it tells the generator what a single pass actually covers:
  * the line density can never be smaller than the pen width (two lines closer
    than the pen merge into one),
  * a gap up to `4 × pen width` (max. half the line spacing) is crossed without
    lifting the pen, so strokes become longer,
  * the dots pattern draws a tick at least `2 × pen width` long,
  * `PlotPreview` draws exactly that thick line (scaled from mm).
* **Pen lift per job** – the image and text screens have their own *Pen lift
  between lines / dots* slider (1 – 20 mm, default = the value from Settings).
  It travels with the queue (`QueuedStroke.penLiftMm` →
  `RobotProvider.penUpZFor()`), so one job can tap dots 8 mm above the paper
  while the next one barely lifts. Strokes with a different lift never share a
  `movMulti` packet, because the approach height would be wrong for one of them.
* **Plot straight from the screen** – the image and text screens do not only
  *add to the queue*: **Plot** calls `RobotProvider.prepareForPlotting()` (Auto +
  Power On), drops the previous finished drawing and starts the queue, so the
  picture can be plotted without visiting the canvas. *Clear Canvas* empties the
  queue.
* **Progress bar** (`lib/widgets/plot_progress_bar.dart`) – strokes done / total,
  percentage, the estimated time left (computed from the real pace) and `STOP`
  while the robot plots. When the job finishes the bar turns into
  *Plot finished* plus a *Move to B* button (safe park position). The counters
  live in `RobotProvider` (`plotProgress`, `plotDoneStrokes`,
  `plotTotalStrokes`, `plotElapsed`) and `StrokeMotionProcessor` reports every
  finished `movMulti` packet, so the bar is exact – not a timer. The same bar is
  shown on the canvas and on the dashboard, so the progress stays visible after
  leaving the image screen.

**Text** options: letter height 3 – 40 mm, line spacing 1 – 3×, paper margin
0 – 60 mm, pen lift between strokes 1 – 20 mm, left / center / right alignment,
automatic wrapping, diacritics normalised to the base letter, notices for
unknown characters and for text that does not fit the paper.

**Image** options: plot pattern (see above), pen line width 0.05 – 1 mm
(default 0.2 mm), line density 0.4 – 4 mm, point spacing 0.2 – 2 mm, pen lift
between lines / dots 1 – 20 mm, threshold 5 – 95 %, margin 0 – 40 mm, optional
invert (plot the light areas) and a truncation notice when the drawing hits
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
* **Pen, Lift & Blending (speed)** – the parameters that decide how the pen
  draws and how fast the arm plots:
  * **Pen line width** (default **0.2 mm**, range 0.05 – 2 mm, persisted as
    `pen_width_mm`) – see *Pen line width* above. It also sets the minimum line
    density and the gap that is crossed without lifting.
  * **Pen lift** between strokes, default **3 mm** (range 1 – 50 mm, persisted as
    `pen_up_mm`). Every extra millimetre is a longer Z move per stroke, so 3 mm
    is enough to just leave the paper. This value is the default for every job;
    the image and text screens can override it per plot (see *Pen lift per
    job* above) without touching the saved setting.
  * **Corner blending radius** (`zone.type = RELATIVE`, `zdis`), default **5 mm**
    (range 0 – 20 mm, persisted as `blend_mm`). With blending the controller
    flows through each path point instead of stopping at it; `0` = exact
    corners (slowest). Only the pen-down contact point and the last point of
    each packet stay `FINE` (exact stop).

* **Points A and B – one tool orientation** – every commanded point (`mov`,
  `movl`, `movMulti`) carries `a = 180°`, `b = 0°`, `c = -90°`
  (`RobotProvider.orientationA/B/C`), so the plotting path (point A) and the
  parking pose (point B) can never drift apart:
  * **A** = `x 50`, `y 100`, `z = pen up` – where a plot starts
    (`RobotProvider.pointAX/pointAY`, `moveToPointA()`); the Z follows the paper
    correction, so it stays 3 mm above the sheet.
  * **B** = **`100, 100, 200` mm** – safe park position 200 mm above the table
    (`RobotProvider.pointBX/BY/BZ`, `moveToPointB()`). Reachable from the
    dashboard, the canvas (*Move to A / Move to B*) and from the progress bar
    once a plot is finished.

Settings are stored in `SharedPreferences` and applied to every generated
`movl` / `movMulti` point.

## Platforms

Everything that decides where the pen goes (paper formats, plot patterns, pen
lift, blending) is plain Dart, so Android, Windows and the web share one code
path – there is no platform-specific branch in the plotting pipeline.

| Platform | Run | Image picker | Notes |
| --- | --- | --- | --- |
| Android (S Pen) | `flutter run -d android` | `file_picker` system dialog | pen / finger input on the canvas |
| Windows 10/11 | `flutter run -d windows`, `flutter build windows --release` | `file_picker` Win32 dialog | mouse draws on the canvas, `shared_preferences_windows` stores the settings |
| Web | `flutter run -d chrome` | browser dialog | `dart:ui` decodes the image, WebSocket to the controller |

The canvas listens to raw pointer events (`Listener`), so a mouse, a finger and
an S Pen all draw the same strokes; the robot link is a plain
`WebSocketChannel`, which is what makes the Windows build work without extra
plugins.

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
  strokes. When the next stroke starts at (or within `minTraverseMm = 0.4 mm`
  of) the end of the previous one, the pen does not lift at all – the two
  strokes become one longer line.
* All path points inside a packet use `zone.type = RELATIVE` (**blending**), so
  the controller does not brake at every point. `FINE` is used only for the
  pen-down contact point and for the last point of each packet.
* **No 180° reversals** – the controller refuses to blend two collinear
  segments that run in opposite directions and answers with
  `Cannot transition! Segment X straight line and segment Y straight line are
  collinear and in opposite directions!`. Every packet therefore goes through
  `StrokeMotionProcessor.sanitizePoints()` before it is sent:
  * identical consecutive points (zero-length segments) are dropped,
  * a pointless out-and-back excursion `A → B → A` is removed completely,
  * a reversal that has to stay gets `FINE`, so the controller stops there
    instead of trying to round it.
  Together with the joined strokes and the gap bridging (see *Pen line width*)
  the plotting path never contains a micro traverse that goes out and back.
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
  `test/paper_format_test.dart` (paper formats, persistence, mm mapping),
  `test/plot_pattern_test.dart` (vertical / diagonal / cross-hatch / dots /
  wave (joined rows) / spiral / outline (edge chaining) / auto),
  `test/pen_width_test.dart` (0.2 mm pen: clamping, `pen_width_mm`, minimum line
  density, dot length, preview thickness) and `test/pen_lift_test.dart` (per-job
  pen lift → `movMulti` Z heights).
* Screens – `test/text_print_screen_test.dart`,
  `test/image_print_screen_test.dart`, `test/settings_screen_test.dart`.
* Motion – `test/stroke_motion_processor_test.dart`,
  `test/plot_transition_test.dart` (`sanitizePoints`: duplicates, out-and-back,
  `FINE` on a 180° reversal, joined strokes for adjacent strokes – the
  `Cannot transition!` guard),
  `test/robot_pose_test.dart` (tool orientation `180 / 0 / -90` for points A and
  B, point B = `100, 100, 200`) and `test/plot_progress_test.dart` (progress
  counters in `RobotProvider` + the `PlotProgressBar` widget: idle, plotting,
  finished, STOP).


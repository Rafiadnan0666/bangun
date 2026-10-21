# Bangun 🔔🧠📷

**Alarms you cannot snooze through:** the ring stops only when you finish the
challenge you configured — a math grind (3/5/7 procedurally generated problems)
or a real-time on-device object scan (COCO-SSD, MobileNet, TensorFlow Lite).
All ML runs on the phone; nothing is uploaded.

Built with Flutter + the [`alarm`](https://pub.dev/packages/alarm) plugin.
A research-style manuscript describing the design lives in `research/`
(Indonesian, TrashLens/J-ICOM manuscript format).

---

## Why "cannot stop"?

A regular alarm app dies every morning because the notification has a stop
button and the app can be closed while ringing. Bangun removes every side
exit:

| Exit path | What Bangun does |
|---|---|
| Stop button in the notification | Not rendered (`NotificationSettings(stopButton: null)`) |
| Android snooze / dismiss buttons | Not rendered (`androidSnoozeButton: null`, `androidStopAlarmOnDismiss: false`) |
| Swiping the app away / killing the process | Alarm keeps ringing natively (`androidStopAlarmOnTermination: false`) + NotificationOnKillService survives |
| Tapping the notification body | Launches straight into the ring screen (`singleTop` + full-screen intent) |
| Back button on ring/challenge screens | `PopScope(canPop: false)` — only a haptic bump |
| System back-gesture / keyboard back | Same `PopScope` gate (predicted-back disabled visually, nothing to pop) |
| Turning the screen off | Wakelock (`wakelock_plus`) keeps the ring screen awake, `immersiveSticky` hides system UI |
| Answering normally and just letting it ring | It keeps ringing; volume floor is enforced at 35% (`VolumeSettings.fixed(volumeEnforced: true)`) |
| Lowering the media volume mid-ring | Fixed-volume bell setting ignores stream changes |
| **The only real exit** | **Finish the configured challenge** — `Alarm.stop()` is called exclusively by the challenge-complete handler (`alarm_repository.completeRing`) |

For *mix* alarms the ring screen offers both gates; either one ends the ring.

---

## Features

- **Multiple alarms** per day; repeat: once / every day / specific weekdays.
- **Ring sounds**: four bundled synthesized tones (`assets/sounds/*.wav`,
  generated with `tools/gen_sounds.dart`), any local audio file, or a
  **Spotify hand-off** (best-effort).
- **Trial mode**: the home screen "test the grind" tiles run a challenge with
  alarm id `0` — same math/scan engines, no native scheduling touched.
- **Stats**: current streak, total wins, math vs scan ledger.
- **Material You-free UI**: lavender `#F5F2FB` background, white rounded
  cards, pastel tiles, orange→pink gradient CTAs, Poppins-heavy type.

---

## Project layout

```
lib/
  main.dart                  # app shell, ring router, host-event handling
  core/
    palette.dart             # colors, gradients, theme (GoogleFonts Poppins)
    format.dart              # hh:mm formatting, weekday labels, deadline text
    widgets.dart             # BgCard, CtaPill, InkPill, EmojiChip, StatusRow…
  data/
    models.dart              # BangunAlarm, enums, target pick-list, WakeStats
    alarm_repository.dart    # persistence + native scheduling + ring state
    math_engine.dart         # warm/sharp/brain-melt procedural puzzles
    coco_detector.dart       # TFLite COCO-SSD + YUV420 → square-RGB converter
  screens/
    home_screen.dart         # hero next-alarm, tiles, streaks sheet
    editor_screen.dart       # time, repeat, challenge, sound configuration
    ring_screen.dart         # kiosk ring environment (no stop control)
    math_challenge_screen.dart
    scan_challenge_screen.dart
    success_screen.dart      # confetti + stats, auto-return home
test/
  math_engine_test.dart      # engine invariants + model JSON round-trip
tools/
  gen_sounds.dart            # regenerates the four WAV tones
research/
  Bangun_manuscript.md       # the paper (Indonesian)
```

---

## The scan gate in detail

- Model: `assets/models/coco_ssd_mobilenet_v1_1.0_quant.tflite`
  (SSD MobileNet v1, COCO labels, quantized uint8 input `300×300×3`,
  10 post-NMS detections; 4.18 MiB).
- Camera: `yuv420` frames at `ResolutionPreset.medium`, throttled to ≈9 fps.
  Every frame is converted with a fixed-point BT.601 crop (square center
  crop, sensor-rotation aware, 0/90/180/270°) and fed to the interpreter —
  raw 0–255 bytes, no CPU-side normalization (quant params are in the model).
- Holding gate: a matched frame accrues presence time weighted by its score
  (`0.4 + score`), a miss decays twice as fast, and per-frame deltas are
  clamped to ≤400 ms so backgrounding cannot donate free progress. The gate
  clears at a continuous 3-second hold.
- The target chip (e.g. 🪥 toothbrush) shows what you must find; live
  detection chips show what the model currently sees and whether it counts.

## The math gate in detail

Problems are generated with an exclusion set (no repeats in a session) and a
tier ramp across the configured count:

| Tier | Span (7-problem alarm) | Example grammar |
|---|---|---|
| warm | ~problems 1–3 | `a + b`, `a − b`, `a × b`, `24 ÷ 6` (single op) |
| sharp | ~4–5 | `(a + b) × c`, `a × b − c`, `q ÷ c + s` |
| brain melt | ~6–7 | `(a × b) − (c × d)`, `(a + b) × c − d`, mixed division chains |

The engine is integer-safe **by construction** (division always divides
exactly; subtraction is range-ordered) — unit-tested over a 500+ sweep, see
`test/math_engine_test.dart`.

---

## Android specifics

- Exact alarms: both `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` are
  declared (the latter is allowed for alarm-clock category apps; Play policy
  requires the alarm-clock category when using it).
- Lock-through-death: `alarm` v5 stores alarms natively and replays them
  after process death; Bangun additionally marks
  `androidStopAlarmOnTermination: false`.
- OEM battery killers: tested guidance is the usual dontkillmyapp advice —
  disable battery optimization for Bangun, allow autostart (Xiaomi/OPPO/
  vivo/Huawei commonly need this), and let the app draw while ringing.
- API level: compileSdk 36 (AGP 9.1.0). `permission_handler` is pinned to
  12.0.3 because newer android artifacts demand compileSdk 37.
  `google_fonts` is pinned to the 6.x line because 9.x returns
  `material_ui` types that this Flutter version's `ThemeData` rejects.

---

## Spotify mode — honest limitations

When an alarm's tone kind is **spotify**, Bangun keeps ringing its siren
asset and shows an "Open your Spotify queue" button that launches the pasted
link via `url_launcher` (external app). There is no Spotify SDK integration
— if the app isn't installed or the link is invalid, the siren simply keeps
ringing. This is explained in-app, in the README, and in the paper; no cloud
service is ever relied upon for the alarm to be audible.

---

## Getting started

```bash
# prerequisites: Flutter 3.4x + Android SDK 36, JDK 17
flutter pub get
flutter test                       # 11 tests, engine invariants
flutter analyze                    # must report "No issues found!"
flutter build apk --debug          # produces build/app/outputs/flutter-apk/app-debug.apk

# regenerate the ring tones only if you change tools/gen_sounds.dart
dart tools/gen_sounds.dart
```

First run on a device: grant notifications (POST_NOTIFICATIONS), exact-alarm
permission, and camera (scan needs it; frames never leave the device).

## Limitations

- Scan gate relies on the COCO class list — unusual targets (hand-cream
  tube, specific coffee cup) are outside the 90 classes; pick a nearby class.
- Detection quality in the dark or on reflective surfaces is unmeasured —
  the gate is intentionally forgiving (score-weighted accrual), but this is
  **not** a benchmark result. See the paper's threats-to-validity section.
- iOS is not configured in this build; the `alarm` plugin supports it but
  the Android lockdown contract is the focus here.

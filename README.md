# Bangun

**Alarms you cannot snooze through:** the ring stops only when you finish the
challenge you configured — a math grind (3/5/7 procedurally generated
problems) or a real-time on-device object scan (COCO-SSD, MobileNet,
TensorFlow Lite). All ML runs on the phone; nothing is uploaded.

Built with Flutter + the [`alarm`](https://pub.dev/packages/alarm) plugin.
The design language is a strict blue-and-white system: pale blue canvas,
white rounded cards, one blue accent family everywhere (red/green survive
only for destructive and won states).

The research manuscript (Indonesian, with the evaluation protocol and the
publication strategy) lives in `paper/`, which is deliberately excluded from
this repository via `.gitignore`.

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
| The screen being off or locked | Full-screen alarm intent wakes the display; the activity is `showWhenLocked` + `turnScreenOn`, and the ring screen is pushed automatically on `Alarm.ringing` |
| Back button on ring/challenge screens | `PopScope(canPop: false)` — only a haptic bump |
| System back-gesture / keyboard back | Same `PopScope` gate |
| Turning the screen off | Wakelock keeps the ring screen awake, `immersiveSticky` hides system UI |
| Answering normally and just letting it ring | It keeps ringing; volume floor is enforced at 35% (`VolumeSettings.fixed(volumeEnforced: true)`) |
| Lowering the media volume mid-ring | Fixed-volume bell setting ignores stream changes |
| **The only real exit** | **Finish the configured challenge** — `Alarm.stop()` is called exclusively by the challenge-complete handler |

For *mix* alarms the ring screen offers both gates; either one ends the ring.

A home-screen "Alarm reliability" card appears whenever Android would refuse
to pop the ring screen (notifications off, or full-screen intents disallowed
on Android 14+). Each item is a one-tap fix and is re-checked on resume.

---

## Features

- **Multiple alarms** per day; repeat: once / every day / specific weekdays.
- **Ring sound — three sources:**
  - four bundled synthesized tones (`assets/sounds/*.wav`, generated with
    `tools/gen_sounds.dart`);
  - any local audio file — the pick is **copied into the app's documents
    directory at selection time**, so the file survives cache eviction and
    expired SAF read permissions; preview and ring both use that durable
    copy;
  - a **Spotify link** (playlist / song / artist / album). At ring time
    Bangun opens the link inside Spotify and then **presses play through
    Android's media-session bridge**, so the playlist/song actually starts
    without a manual tap. The deep link carries Spotify's `:play` autoplay
    switch as the first hint, Bangun also presses the play action in Spotify's
    notification and sends the native media play-from-search intent, and it
    keeps nudging for up to 45 seconds while the phone boots up.
- **Spotify alarms never use the siren.** Their native underlay is the gentle
  twin chime at the enforced volume floor, so the ring stays audible even if
  Spotify is missing or still starting, without a klaxon in your ear.
- **Sound test button** in the editor for all three sources: built-in tones
  and picked files play a 5-second preview; the Spotify test runs the exact
  ring-time sequence (open item + press play) and reports the real outcome —
  "playing", "opened, enable notification access", or "Spotify not
  installed".
- **Spotify auto-play setup:** selecting Spotify (or testing it) prompts for
  notification access until it is granted (Settings > Notification access >
  Bangun), and the editor keeps an "Enable auto-play" card visible. That
  permission is what lets Bangun press play in Spotify's media session and
  its notification; it is requested once and never reads your notifications.
- **Scan gate** (details below) with live detection boxes, label synonyms,
  and easy-target priority.
- **Trial mode**: the home screen test tiles run a challenge with alarm id
  `0` — same math/scan engines, no native scheduling touched.
- **Stats**: current streak, best streak, total wins, math vs scan ledger.
- **Blue-and-white UI**: white cards on `#EDF4FE`, white-on-blue sound card
  with animated chips, pulsing test button, and dancing equalizer bars. Text
  scaling is clamped to keep every card on-screen on phones with large system
  fonts.

---

## The scan gate in detail

- Model: `assets/models/coco_ssd_mobilenet_v1_1.0_quant.tflite`
  (SSD MobileNet v1, COCO labels, quantized uint8 input `300x300x3`,
  10 post-NMS detections).
- Camera: `yuv420` frames throttled to about 9 fps. Every frame is
  converted with a fixed-point BT.601 crop (square center crop,
  sensor-rotation aware) and fed to the interpreter — raw 0-255 bytes, no
  CPU-side normalization (quant params live in the model).
- **Named boxes**: `Detection` carries its bounding box; a painter draws a
  rounded rectangle plus a small tag pill (`emoji label %`) on the live
  preview, green when the label counts toward the gate.
- **Label synonyms**: the 90 COCO classes are coarse, so the gate accepts a
  similarity map — asking for `cup` also accepts `wine glass`, `bottle`,
  `bowl`, and friends (`kSimilarScanTargets` in `lib/data/models.dart`).
- **Random but easy-first targets**: the trial/alarm scan pool randomizes
  the requested object but prioritizes easy, always-around-you objects
  (cup, cell phone, book...); awkward classes appear only as the optional
  fallback.
- **Hold meter, not confidence**: the 100% meter is hold time. A matched
  frame accrues presence weighted by its score (`0.4 + score`), a miss
  decays twice as fast, per-frame deltas are clamped to 400 ms so
  backgrounding cannot donate free progress. The HUD literally says
  "hold it — X.Xs to 100%". The gate clears at a continuous 3-second hold.

## The math gate in detail

Problems are generated with an exclusion set (no repeats in a session) and
a tier ramp across the configured count:

| Tier | Span (7-problem alarm) | Example grammar |
|---|---|---|
| warm | ~problems 1-3 | `a + b`, `a - b`, `a x b`, `24 / 6` (single op) |
| sharp | ~4-5 | `(a + b) x c`, `a x b - c`, `q / c + s` |
| brain melt | ~6-7 | `(a x b) - (c x d)`, `(a + b) x c - d`, mixed division chains |

The engine is integer-safe by construction (division always divides
exactly; subtraction is range-ordered) — unit-tested over a 500+ sweep, see
`test/math_engine_test.dart`.

---

## Android specifics

- Exact alarms: both `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` are
  declared (the latter is allowed for alarm-clock category apps).
- Lock-through-death: `alarm` v5 stores alarms natively and replays them
  after process death; Bangun additionally marks
  `androidStopAlarmOnTermination: false`.
- Full-screen ringing: the notification carries a full-screen intent; the
  activity declares `showWhenLocked` and `turnScreenOn`. On Android 14+ the
  user must allow "full screen notifications" for Bangun once — the home
  reliability card detects this and deep-links to the exact settings page.
- Spotify media control: `MediaControlListenerService` is a
  notification-listener service whose only job is to unlock Spotify's
  `MediaController` for the `bangun/media` platform channel
  (`android/app/src/main/kotlin/com/example/bangun/MainActivity.kt`).
- Corrupt-payload guard: a malformed alarm/stats entry in SharedPreferences
  can never crash app boot; the loader falls back to empty state
  (`on Object` catch — cast errors are `Error`, not `Exception`).
- OEM battery killers: disable battery optimization for Bangun, allow
  autostart (Xiaomi/OPPO/vivo/Huawei commonly need this), and let the app
  draw while ringing.
- API level: compileSdk 36 (AGP 9.1.0). `permission_handler` is pinned to
  12.0.3 because newer android artifacts demand compileSdk 37.
  `google_fonts` is pinned to the 6.x line because 9.x returns types this
  Flutter version rejects. `file_picker` is pinned to the 10.x line and
  `wakelock_plus` to 1.x because the fresh majors conflict on `win32`.

---

## Spotify mode — what actually happens

1. At ring time the twin chime starts natively at the enforced volume floor.
   No siren is ever used for Spotify alarms.
2. 1.4 s into the ring, the ring screen opens the configured item inside
   Spotify (first with the `:play` autoplay deep link, then the plain deep
   link, the raw https URL, and the bare app shell).
3. Bangun then tries every available way to make playback start:
   - press play on Spotify's live `MediaController`;
   - press the play/resume action inside Spotify's own media notification;
   - send Android's `MEDIA_PLAY_FROM_SEARCH` intent with the Spotify item URI.
   The first two require notification access; the last one does not. If the
   phone is cold, Bangun keeps nudging for up to 45 seconds.
4. Once Spotify (or a browser) takes the foreground, Bangun re-asserts the
   gate on top with a silent alarm-category full-screen intent, so the
   challenge stays visible while the music plays underneath.
5. The twin-chime underlay keeps ringing until the gate is cleared, so the
   alarm stays audible even with no Spotify installed, offline, or while
   Spotify is still booting.

The editor prompts for the one-time notification-access grant as soon as
Spotify mode is selected, and the ring screen repeats an "Allow" button plus
live playing status, so the permission can be fixed without leaving the ring.

Verified on-device: exact alarm fired from a locked screen and auto-launched
the challenge, the math gate was solved, stats updated, and the one-time
alarm auto-disabled.

---

## Getting started

```bash
# prerequisites: Flutter 3.4x + Android SDK 36, JDK 17
flutter pub get
flutter test      # 29 tests: engine, geometry, spotify links, target pools
flutter analyze   # must report "No issues found!"
flutter build apk --debug   # build/app/outputs/flutter-apk/app-debug.apk

# regenerate the ring tones only if you change tools/gen_sounds.dart
dart tools/gen_sounds.dart
```

First run on a device: grant notifications (POST_NOTIFICATIONS), exact-alarm
permission, and camera (scan needs it; frames never leave the device).

For Spotify alarms: enable notification access once (the editor shows the
card), and allow full-screen notifications if the home reliability card asks
for it.

## Repository notes

- `paper/` (manuscript, publication strategy, evaluation protocol, plagiarism
  checklist) is intentionally not tracked in this repository.
- `TODO.md` tracks user-requested feature work and its verification status.

## Limitations

- Scan gate relies on the COCO class list — unusual targets (specific
  branded objects) are outside the 90 classes; pick a nearby class and the
  synonym map covers close variants (cup/glass/mug family and similar).
- Detection quality in the dark or on reflective surfaces is unmeasured —
  the gate is intentionally forgiving (score-weighted accrual), but this is
  **not** a benchmark result. See the paper's threats-to-validity section.
- Spotify auto-play depends on the notification-access grant and on Spotify
  publishing a media session; without the grant the item still opens in
  Spotify, but the user may need to tap play once while the twin chime keeps
  guarding the wake-up.
- iOS is not configured in this build; the `alarm` plugin supports it but
  the Android lockdown contract is the focus here.

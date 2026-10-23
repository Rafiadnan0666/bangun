# Bangun

Bangun is an Android alarm clock that cannot be snoozed or dismissed. When the
alarm rings, the only way to stop it is to finish the challenge configured for
that alarm: a set of math problems or a live camera scan of a real object. All
detection runs on the phone with TensorFlow Lite. Nothing is uploaded.

The app is built with Flutter and the `alarm` plugin. The interface uses a
blue and white design system: pale blue canvas, white rounded cards, and blue
accents everywhere. Red is reserved for destructive actions and green for
completed successes.

The research manuscript and evaluation documents live in `paper/`, which is
excluded from this repository through `.gitignore`.

---

## What Bangun does

Bangun covers the full wake-up loop:

1. You create one or more alarms and choose a time, repeat pattern, challenge,
   and ring sound.
2. Bangun schedules each alarm with Android's exact alarm service and stores a
   native copy, so the alarm still fires after the app process is killed.
3. At the scheduled time the alarm starts a foreground service and begins
   playing the configured sound, even when the screen is locked or off.
4. A full-screen notification opens the ring screen automatically. You do not
   have to unlock the phone or find the app.
5. The ring screen shows the time, label, sound, challenge, and the buttons
   that start the challenge.
6. The alarm keeps ringing while you work through the math or scan gate.
7. When the challenge succeeds, Bangun calls `Alarm.stop()`, records the win,
   updates the streak, and disables the alarm if it was a one-time alarm.
8. If the alarm repeats, Bangun re-arms the next occurrence.

There is no stop button in the notification, no snooze button, no dismiss
button, and no way to close the ring screen with the Back gesture. Killing the
app does not stop the native alarm. Changing the media volume does not lower
the ring below the enforced floor. The challenge is the only exit.

---

## How a wake-up works, step by step

This is the complete path from an alarm being saved to the phone being silent
again.

1. **Save.** The editor validates the form, builds a `BangunAlarm`, and passes
   it to `AlarmRepository`. A one-time alarm whose time already passed rolls
   to the next day.
2. **Schedule.** The repository converts the alarm to the plugin's settings and
   stores it. Android receives an `RTC_WAKEUP` exact alarm and a native copy of
   the settings. This copy is what makes the alarm survive process death.
3. **Fire.** At the scheduled second, Android starts Bangun's alarm receiver
   and foreground service. The chosen audio source starts on the alarm stream
   with the configured volume, enforced at a minimum of 35 percent.
4. **Launch the ring screen.** The alarm notification carries a full-screen
   intent. MainActivity is declared with `showWhenLocked` and `turnScreenOn`,
   so the screen wakes and the ring route is pushed on top of everything.
5. **Start the challenge.** Tap the math or scan button on the ring sheet. The
   ring route is replaced by the challenge screen, so the ring cannot be
   returned to by pressing Back.
6. **Math gate.** Bangun generates the requested number of problems (3, 5, or
   7) with increasing difficulty. A wrong answer resets the current problem.
   The gate clears only after every problem is solved.
7. **Scan gate.** Bangun asks for a random easy object from the configured
   pool. The camera preview runs COCO-SSD at roughly 9 frames per second.
   Detection boxes and labels are drawn on the preview. Holding the correct
   object for 3 continuous seconds clears the gate.
8. **Stop.** The success handler calls `Alarm.stop()`. The native sound stops,
   the ring notification disappears, and the app returns to the home screen
   with the updated stats.
9. **Repeat or disable.** A one-time alarm is marked disabled. A daily or
   weekly alarm is re-armed for its next occurrence.
10. **Record.** Total wins, math wins, scan wins, the current streak, the best
    streak, and wins by day are written to SharedPreferences.

For a mix alarm, the ring sheet offers both gates. Finishing either one stops
the alarm.

---

## What each screen does

### Home

The home screen has four main areas:

- The blue hero card shows the next enabled alarm, its label, its time, and
  how long until it rings. When nothing is enabled it says so.
- The detail card repeats the alarm name, challenge, sound, repeat mode, and
  win statistics.
- The quick tiles open the editor, a scan trial, a math trial, and the streak
  summary. Trial runs use alarm id `0` and never touch native scheduling.
- The alarm list can be filtered by all, on, or off. Each row has a switch and
  opens the editor when tapped.

The "Alarm reliability" card appears only when Android would block a reliable
ring. It covers three cases: notifications are off, full-screen notifications
are disallowed, and an enabled Spotify alarm is missing notification access.
Each case has a one-tap fix and is re-checked when the app resumes.

### Editor

The editor creates or edits an alarm. From top to bottom it contains:

- The time picker, with plus and minus controls for hour and minute.
- Repeat mode: once, every day, or specific weekdays. At least one weekday
  must remain selected.
- Challenge type: math grind, object scan, or pick at ring. For math you pick
  3, 5, or 7 problems. For scan you choose the target pool. "Pick at ring"
  offers both gates on the ring screen.
- Ring sound: four built-in tones, a local audio file, or a Spotify link. The
  test button previews built-in tones and files for 5 seconds, and runs the
  real Spotify handoff for Spotify links.
- Volume slider. The engine never goes below 35 percent while an alarm rings.
- Save, or delete when editing an existing alarm.

A Spotify alarm cannot be saved with an empty link. Selecting Spotify opens a
notification-access dialog when the permission is missing, because Android
does not allow any app to press play in Spotify without it.

### Ring screen

The ring screen is a full-screen blue gradient with the alarm time, the label,
and a bottom sheet. The sheet shows the alarm name, sound, gate, and the
challenge buttons. There is no close button. Back is blocked by `PopScope`.
The screen keeps the device awake and hides the system bars.

For Spotify alarms the sheet also shows whether Spotify is currently playing
and an "Allow" button when notification access is missing. The Spotify handoff
is automatic; the sheet button retries it manually.

### Math challenge

The math screen shows the progress (for example, Problem 3 of 3), a difficulty
tag, the expression, and an answer field. The custom keypad has digits, delete,
and a minus sign for negative answers. A wrong answer triggers a fresh problem
at the current tier. There is no timer and no skip button.

### Scan challenge

The scan screen opens the camera, loads the on-device detector, and asks for
one object. A matched detection draws a box and a label. A hold meter fills
while the target stays visible and drains twice as fast when it disappears.
The gate clears at a continuous 3-second hold. If the camera is unavailable,
the screen reports the problem instead of pretending the gate passed.

### Streaks and trials

The streak screen reads the statistics stored by completed challenges. The
trial tiles on the home screen open the same math and scan screens with a
temporary alarm, so you can test the gates without waiting for a real alarm.

---

## How to set up an alarm

1. Open Bangun and tap "Add alarm".
2. Set the hour and minute. Tap the large time if you prefer the system time
   picker.
3. Choose once, every day, or the weekdays you want.
4. Choose the challenge. For math, choose 3, 5, or 7 problems. For scan,
   choose one or more target objects.
5. Choose a sound:
   - A built-in tone.
   - "Own file" to pick an audio file from the phone. Bangun copies it into
     the app documents directory immediately, so the alarm still works after
     the original file or permission disappears.
   - Spotify, then paste a track, playlist, artist, or album link.
6. Adjust the volume if needed.
7. Tap "Test this tone" to hear the built-in tone or file, or to run the
   Spotify handoff.
8. Tap "Create alarm".

To change an alarm, tap its row on the home screen, edit the fields, and tap
"Save changes". To remove it, open it and tap the delete control.

---

## Ring sound options

### Built-in tones

Four synthesized WAV files live in `assets/sounds/`. They are generated by
`tools/gen_sounds.dart`. The names are Morning bricks, Twin chime, Siren rush,
and Digital chirp.

### Local audio file

The file picker opens the Android document picker. Bangun reads the selected
bytes and writes a durable copy named `tone_<timestamp>.<ext>` inside the
app's documents directory. Preview and ring time both use that copy. The
original file can be moved or deleted without breaking the alarm.

### Spotify

A Spotify alarm uses the gentle Twin chime as its native underlay. The siren is
never used for Spotify alarms. The link is opened inside the Spotify app and
Bangun tries to press play through three paths:

1. Spotify's live media controller.
2. The play or resume action inside Spotify's own media notification.
3. Android's `MEDIA_PLAY_FROM_SEARCH` intent with the Spotify item URI.

The first two require notification access. The third does not. Bangun keeps
retrying for up to 45 seconds while a cold phone starts Spotify. After Spotify
or a browser takes the foreground, Bangun brings the ring screen back on top
with a silent alarm-category full-screen notification, so the gate stays
visible while the music plays underneath.

Supported link forms include `open.spotify.com` playlist, track, album, and
artist links, links with `/intl-xx/` locale paths, links with tracking query
parameters, and native `spotify:` URIs. A trailing `:play` is handled without
being duplicated.

If Spotify is missing, paused, offline, or restricted by the account, the twin
chime keeps the alarm audible and the ring UI still works.

---

## The math gate in detail

Problems are generated by `lib/data/math_engine.dart`. The engine uses an
exclusion set so a session never repeats a problem and ramps difficulty across
the configured count:

| Difficulty | Typical position | Expression style |
|---|---|---|
| warm | problems 1 to 3 of 7 | `a + b`, `a - b`, `a x b`, `24 / 6` |
| sharp | problems 4 to 5 of 7 | `(a + b) x c`, `a x b - c`, `q / c + s` |
| brain melt | problems 6 to 7 of 7 | `(a x b) - (c x d)`, `(a + b) x c - d`, mixed division chains |

The engine is integer safe by construction. Division always divides exactly,
and subtraction is range ordered so the answer never becomes negative.
`test/math_engine_test.dart` stress-tests the invariants over hundreds of
generated problems.

---

## The scan gate in detail

- Model: `assets/models/coco_ssd_mobilenet_v1_1.0_quant.tflite`. It is an SSD
  MobileNet v1 detector with COCO labels, quantized uint8 input at 300 by 300
  by 3, and 10 post-NMS detections.
- Camera: YUV420 frames are throttled to about 9 frames per second. Each frame
  is center cropped to a square with a fixed-point BT.601 conversion, adjusted
  for sensor rotation, then passed to the interpreter as raw 0 to 255 bytes.
- Drawing: every detection carries a bounding box. The painter draws a rounded
  rectangle and a small label pill over the live preview. The box turns green
  when the label counts toward the gate.
- Synonyms: the COCO model has 90 coarse classes, so the gate uses a similarity
  map. Asking for a cup also accepts a wine glass, bottle, or bowl. The map is
  `kSimilarScanTargets` in `lib/data/models.dart`.
- Target choice: the pool is randomized but favors easy objects that are
  normally nearby, such as a cup, a phone, or a book. Harder classes are only
  used as fallback.
- Meter: the 100 percent meter measures hold time, not model confidence. A
  matching frame adds presence weighted by score (`0.4 + score`), a miss decays
  twice as fast, and a single frame can add at most 400 milliseconds. The gate
  clears at a continuous 3-second hold.

---

## Permissions and reliability

Grant these on first run:

- **Notifications** (Android 13 and newer). Without them Android will not show
  the alarm notification or launch the full-screen ring screen.
- **Exact alarms**. Bangun declares both `SCHEDULE_EXACT_ALARM` and
  `USE_EXACT_ALARM`, which is allowed for alarm clock apps.
- **Camera**. Required only for the scan gate. Frames are processed on the
  device and are never stored or uploaded.
- **Full-screen notifications**. On Android 14 and newer the user must allow
  this once for Bangun. The home reliability card detects the blocked state
  and opens the correct settings page.
- **Notification access**. Required only for Spotify alarms, so Bangun can
  press play on Spotify's media session and notification. It is granted once
  under Settings, Notifications, Device and app notifications, Bangun media
  control.

Battery optimizations can still delay or kill background alarms on some
phones. On Xiaomi, OPPO, vivo, and Huawei devices, allow autostart for Bangun
and disable battery optimization for it.

The app guards against corrupted stored data. A malformed alarm or statistics
entry cannot crash app boot; the loader falls back to an empty state.

---

## How to build and run

Prerequisites: Flutter 3.4x, Android SDK 36, and JDK 17.

```bash
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
Install it with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

To regenerate the built-in ring tones after editing the generator:

```bash
dart tools/gen_sounds.dart
```

The test suite currently has 29 tests covering the math engine, scan geometry,
scan target selection, Spotify link parsing, and alarm scheduling helpers.
`flutter analyze` must report no issues.

---

## Where things live

```
lib/main.dart                  App shell, ring routing, text-scale clamp
lib/core/palette.dart          Blue and white design tokens
lib/core/widgets.dart          Shared cards, pills, and status rows
lib/core/format.dart           Time and duration formatting
lib/data/models.dart           Alarm model, tone model, Spotify link parsing
lib/data/alarm_repository.dart Alarm storage, native scheduling, ring events
lib/data/math_engine.dart      Math problem generator
lib/data/media_control.dart    Dart bridge to Android media and settings
lib/data/spotify_launch.dart   Spotify start, retry, and keep-playing logic
lib/data/tone_preview.dart     Editor sound preview
lib/screens/home_screen.dart   Dashboard, alarm list, reliability card
lib/screens/editor_screen.dart Alarm form and sound picker
lib/screens/ring_screen.dart   Lockdown ring screen and Spotify handoff
lib/screens/math_challenge_screen.dart
lib/screens/scan_challenge_screen.dart
lib/screens/streak_screen.dart
assets/sounds/                Built-in WAV tones
assets/models/                COCO-SSD TensorFlow Lite model
android/app/src/main/kotlin/com/example/bangun/MainActivity.kt
                              Platform channel, full-screen settings,
                              Spotify playback strategies, bring-to-front
android/app/src/main/kotlin/com/example/bangun/MediaControlListenerService.kt
                              Notification listener used for media control
test/                         Math, scan geometry, scan target, Spotify tests
tools/gen_sounds.dart         Ring tone generator
```

---

## Known limitations

- The scan gate only knows the 90 COCO classes. A very specific branded object
  is outside the model. Pick a nearby class; the synonym map covers close
  variants such as cup, glass, mug, bottle, and bowl.
- Detection quality in the dark, at extreme angles, or on reflective surfaces
  is unmeasured. The hold meter is intentionally forgiving, but this is not a
  scientific benchmark. The paper discusses this threat to validity.
- Spotify autoplay depends on notification access and on Spotify publishing a
  media session. Without the grant, the item still opens in Spotify, but the
  user may need to tap play once while the twin chime keeps guarding the
  wake-up.
- A free Spotify account or a regional restriction can limit autoplay even
  when the handoff succeeds. Bangun reports the real outcome in the editor's
  test message.
- iOS is not configured in this build. The `alarm` plugin supports it, but the
  Android lockdown behavior is the focus.

---

## Repository notes

- `paper/` contains the manuscript, publication strategy, evaluation protocol,
  and plagiarism checklist. It is intentionally not tracked in this repository.
- `TODO.md` tracks requested feature work and its verification status.
- The app package name is `com.example.bangun`. Change it before publishing to
  a store.

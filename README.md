# awake

Awake is a non-dismissable Android alarm clock that stops only when you complete a challenge: solve math problems or scan a real object. All detection runs on-device using TensorFlow Lite. No data leaves your phone.

Built with Flutter and the `alarm` plugin. The interface uses a blue-and-white design system: pale blue canvas, white rounded cards, and blue accents everywhere. Red marks destructive actions and green marks success wins.

Research manuscripts live in `paper/`, excluded via `.gitignore`.

---

## What awake does

The wake-up loop:

1. Create alarms with time, repeat pattern, challenge, and ring sound.
2. Alarms schedule via Android's exact alarm service with native persistence.
3. At ring time, a foreground service plays your sound even on a locked screen.
4. A full-screen notification opens the ring screen immediately — no unlock needed.
5. The ring screen shows time, label, sound, challenge, and action buttons.
6. The alarm rings continuously while you work through the challenge.
7. On success, `Alarm.stop()` is called, stats update, streak increments, and one-time alarms disable.
8. Repeating alarms re-arm for their next occurrence.

There is no stop, snooze, or dismiss button. The Back gesture is blocked. Killing the app does not stop an active ring. Volume changes do not lower the ring below floor level. The challenge is the only exit.

---

## How a wake-up works, step by step

1. **Save.** The editor validates, builds a `BangunAlarm`, and passes it to `AlarmRepository`. Past alarms schedule for the next day. One-time alarms missed while the app was dead are retired at boot.
2. **Schedule.** The repository converts to plugin settings and stores them. Android receives an `RTC_WAKEUP` exact alarm with a native copy for process-death survival.
3. **Fire.** At the scheduled second, Android starts awake's alarm receiver and foreground service. The audio plays on the alarm stream with enforced 35% minimum volume.
4. **Launch ring screen.** The notification carries a full-screen intent. MainActivity uses `showWhenLocked` and `turnScreenOn`, waking the screen and pushing the ring route.
5. **Start challenge.** Tap math or scan on the ring sheet. The ring route is replaced so Back cannot return to it.
6. **Math gate.** 3, 5, or 7 problems are generated with increasing difficulty. Wrong answers reset. All answers are non-negative integers (division is exact, subtraction is range-ordered).
7. **Scan gate.** Ask for a random object from a pool of 80 COCO classes (plus glass, screen composites). Camera preview runs COCO-SSD at ~9 fps. Correct objects get green bounding boxes. Hold the target for 3 continuous seconds.
8. **Stop.** Success calls `Alarm.stop()`. Sound stops, notification clears, app returns to home with updated stats.
9. **Repeat or disable.** One-time alarms disable. Repeating alarms re-arm.
10. **Record.** Wins, streaks, best streaks, and daily records are saved to SharedPreferences.

A mix alarm offers both gates. Finishing either stops the alarm.

---

## What each screen does

### Home

The home screen has four main areas:

- **Hero card**: Shows the next enabled alarm (time, label, countdown).
- **Detail card**: Repeats alarm name, challenge, sound, repeat mode, and stats.
- **Quick tiles**: Open editor, scan trial, math trial, and streak summary. Trials use alarm id `0` and never modify stats.
- **Alarm list**: Filter by all/on/off. Each row has a switch and opens the editor on tap.

The **Alarm reliability** card appears when Android would block a reliable ring. It covers: notifications off, exact alarms blocked, full-screen notifications disallowed, enabled Spotify alarm missing notification access, missing custom tone files. Each case has a one-tap fix.

### Editor

Creates or edits an alarm. From top to bottom:

- **Time picker**: Hour/minute with +/- controls, or tap for system picker.
- **Repeat mode**: Once, every day, or specific weekdays (at least one required).
- **Challenge type**: Math grind (3/5/7 problems), Object scan (select target pool), or Pick at ring (both gates available).
- **Ring sound**: Four built-in tones, local audio file, or Spotify link. Test button previews for 5 seconds.
- **Volume slider**: Minimum enforced at 35% during ring.
- **Save/Delete**: Save for new alarms or updated changes. Delete when editing.

Spotify links require valid host/item checks. Invalid links show inline errors.

### Ring screen

Full-screen blue gradient with alarm time, label, and bottom sheet. Shows alarm name, sound, gate, and challenge buttons. No close button. Back is blocked via `PopScope`. Screen wake lock active, system bars hidden.

For Spotify alarms: shows play status and "Allow" button when notification access is missing. Auto-handoff occurs immediately after ring starts.

### Math challenge

Shows progress (Problem 1 of 3), difficulty tag, expression, and answer field. Custom keypad has digits, delete, and done. No minus sign—answers are always non-negative. Wrong answers reset the input without advancing. No timer, no skip button.

Difficulty ramp:
| Difficulty | Problems | Expression types |
|---|---|---|
| warm | 1-3 of N | `a + b`, `a - b`, `a × b`, `24 / 6` |
| sharp | 4-5 of N | `(a + b) × c`, `a × b - c`, `q / c + s` |
| brain melt | 6-7 of N | `(a × b) - (c × d)`, `(a + b) × c - d`, division chains |

### Scan challenge

Opens camera, loads TFLite detector on-demand, asks for one object. Target and similar labels turn green. Hold meter fills at 3 continuous seconds. HUD has torch toggle, tips sheet, and Shuffle button (trial mode). Camera unavailable shows error instead of silent pass.

### Streaks and trials

Streak screen reads statistics. Trial tiles on home open math/scan screens with a temporary alarm (id 0). Trials don't modify wins or streaks. Success screen shows "Trial cleared" with "stats unchanged".

---

## How to set up an alarm

1. Open awake and tap "Add alarm".
2. Set hour and minute.
3. Choose repeat: once, daily, or specific weekdays.
4. Choose challenge: math (3/5/7 problems), scan (select objects), or both at ring time.
5. Choose a sound: built-in tone, "Own file", or Spotify link.
6. Adjust volume if needed.
7. Tap "Test this tone" to preview.
8. Tap "Create alarm".

To edit: tap an alarm row, modify fields, tap "Save changes". To delete: open alarm and tap delete.

---

## Ring sound options

### Built-in tones

Four WAV files in `assets/sounds/`: Morning bricks, Twin chime, Siren rush, Digital chirp. Generated by `tools/gen_sounds.dart`.

### Local audio file

Uses Android document picker. Files are streamed as `tone_<timestamp>.<ext>` into app documents. Files over 25 MB are rejected. The durable copy survives original file deletion or permission loss. The reliability card names affected alarms; editor blocks saving until a valid file or alternative tone is chosen.

Orphaned files are swept on boot.

### Spotify

A Spotify alarm uses Twin chime as a native underlay. The handoff tries:
1. Spotify's live media controller (requires notification access)
2. Play/resume in Spotify's media notification (requires notification access)  
3. Android's `MEDIA_PLAY_FROM_SEARCH` intent (no notification access required)

Bangun retries for up to 45 seconds while the phone starts Spotify. A silent full-screen notification keeps the gate visible during handoff.

Supported link forms:
- `open.spotify.com/track`, `playlist`, `album`, `artist`
- Locale paths (`/intl-xx/`) and tracking parameters
- Native `spotify:` URIs for the four kinds
- `spotify.link` short links
- Trailing `:play` handled without duplication

Unsupported: other hosts, lookalike hosts (e.g., `open.spotify.com.example`), search pages, malformed URIs — all rejected before ring handoff.

If Spotify is missing, paused, offline, or restricted, the twin chime keeps the alarm audible.

---

## The math gate in detail

Generated by `lib/data/math_engine.dart`. Uses an exclusion set—no repeated problems—and ramps difficulty across the set count.

Division always divides exactly. Subtraction is range-ordered so answers never become negative. The engine is integer-safe by construction.

**Verification:** `test/math_engine_test.dart` stress-tests invariants over hundreds of problems.

---

## The scan gate in detail

- **Model**: `assets/models/coco_ssd_mobilenet_v1_1.0_quant.tflite`. SSD MobileNet v1, quantized uint8 300×300×3 input, 10 post-NMS detections.
- **Classes**: 91-line label asset (1 placeholder `???`, 80 COCO classes, 10 unused). Plus `glass` and `screen` composite targets.
- **Picker**: Groups: Common, All, Food, Home, Tech, Outdoors, Animals, People. Search, selected targets at front, Select Common and Clear actions. Empty pools are blocked from saving.
- **Camera**: YUV420 throttled to ~9 fps, center-cropped to square, BT.601 fixed-point conversion, adjusted for sensor rotation, passed as 0-255 bytes. RGB buffer reused (no 270 KB allocations per frame).
- **Drawing**: Rounded rectangles with label pills over live preview. Target and similar labels turn green; other detections stay white. Repaint boundaries on preview and overlay.
- **Synonyms**: `glass` → cup, wine glass, bottle, bowl. `screen` → tv, laptop, phone. Configurable in `lib/data/models.dart`.
- **Target choice**: New alarms start with common objects (cup, screen, phone, book). Trials and normal alarms randomize every ring, preferring nearby items. Old cup-only records migrate once.
- **Loading**: On-demand with retry. Shows loading/failure states.
- **Interaction**: HUD has torch toggle, tips sheet, Shuffle (trial mode). Animations: scale/slide for target card, pulse for hold meter, chip pop-ins.
- **Meter**: Hold time not confidence. Matching frame adds `0.4 + score` (max 0.4 per frame), misses decay at 1.25× speed. Requires 3-second continuous hold. Filter: ≥0.60 confidence, plausible box area, label appears in two nearby frames. Shows all detections up to 10-box limit.

---

## Permissions and reliability

Grant on first run:

- **Notifications** (Android 13+). Without them, the alarm notification won't show.
- **Exact alarms**. `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` declared (alarm-clock purpose). Reliability card monitors and offers correct settings page.
- **Camera**. Required for scan gate. No frames stored or uploaded. Permanent denial opens app settings and auto-retries on resume.
- **Full-screen notifications** (Android 14+). Must be allowed once. Reliability card detects blocked state.
- **Notification access**. Required for Spotify playback. Granted once in Settings → Notifications → Device and app notifications → awake media control.

Battery optimizations on Xiaomi, OPPO, vivo, Huawei may still delay alarms. Allow autostart and disable battery optimization for awake on those devices.

Guardrails prevent crashes from corrupted data: malformed alarms load with fallback defaults; missing custom tones fall back to built-in and appear on reliability card.

---

## How to build and run

Prerequisites: Flutter 3.4x, Android SDK 36, JDK 17.

```bash
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
flutter build apk --release
```

Artifacts:
- Debug: `build/app/outputs/flutter-apk/app-debug.apk`
- Release: `build/app/outputs/flutter-apk/app-release.apk`

Install:
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Release builds apply `android/app/proguard-rules.pro`. Those keep the Kotlin runtime and Pigeon JNI registrars used by `shared_preferences_android` 2.5. Without them, R8 renames `kotlin.coroutines.Continuation` and removes `kotlin.Result`, causing `Alarm.init()` to throw.

Regenerate built-in tones:
```bash
dart tools/gen_sounds.dart
```

**Test suite:** 66 tests covering math engine, scan geometry, target selection, detector labels, Spotify validation, alarm models, missed one-time alarms. `flutter analyze` must report no issues. Debug and release APKs build are part of verification.

---

## Project structure

```
lib/main.dart                  App shell, ring routing, text-scale clamp
lib/core/palette.dart          awesme design tokens
lib/core/widgets.dart          Shared cards, pills, and status rows
lib/core/format.dart           Time and duration formatting
lib/data/models.dart           Alarm model, tone model, Spotify validation
lib/data/alarm_repository.dart Alarm storage, native scheduling, ring events
lib/data/tone_files.dart       Durable tone copy, cleanup, orphan sweep
lib/data/math_engine.dart      Math problem generator
lib/data/media_control.dart    Dart bridge to Android media and settings
lib/data/spotify_launch.dart   Spotify start, retry, and keep-playing logic
lib/data/tone_preview.dart     Editor sound preview
lib/screens/home_screen.dart   Dashboard, alarm list, reliability card
lib/screens/editor_screen.dart Alarm form and sound picker
lib/screens/ring_screen.dart   Lockdown ring screen and Spotify handoff
lib/screens/math_challenge_screen.dart
lib/screens/scan_challenge_screen.dart
lib/screens/success_screen.dart Celebration and trial-mode copy
lib/screens/streak_screen.dart
assets/sounds/                 Built-in WAV tones
assets/models/                 COCO-SSD TensorFlow Lite model
android/app/src/main/kotlin/com/example/bangun/MainActivity.kt
                              Platform channel, full-screen settings,
                              Spotify playback strategies, bring-back cleanup
android/app/src/main/kotlin/com/example/bangun/MediaControlListenerService.kt
                              Notification listener for media control
test/                         Math, scan, Spotify, and alarm model tests
tools/gen_sounds.dart         Ring tone generator
```

---

## Known limitations

- Scan gate recognizes only 80 named COCO classes. For a very specific branded object, pick a nearby class; the synonym map handles close variants.
- Detection quality in the dark, at extreme angles, or on reflective surfaces is unmeasured. The hold meter is intentionally forgiving.
- A printed photo or screen image can satisfy the scan gate. The gate is a deterrent and routine builder, not a cryptographic proof.
- A scan-only alarm on broken/blocked/permanently denied camera has no in-app escape. Use a mix alarm if the camera is unreliable.
- Time zone changes or daylight-saving jumps can shift an occurrence. The next repeat is scheduled correctly.
- Android force-stop cancels scheduled alarms until the app is opened again. Normal process death, reboot, and lock screen are handled.
- Some Xiaomi, OPPO, vivo, Huawei devices may still delay or kill alarms. Autostart and battery optimization settings are not optional on those phones.
- System text scaling clamped at 1.12 to keep layouts usable. Users needing very large text will not get their full preferred scale.
- Old trial runs may exist in legacy stats. Statistics are device-local; no migration can reliably distinguish old trial wins from real ones.
- iOS is not configured in this build. Focus remains on Android lock-down behavior.

---

## Android package info

Application ID: `com.example.bangun` (internal Android identifier; this package name is used for the `alarm` plugin's broadcast receivers and notification channels). Users install the APKs from this package; renaming would require full re-packaging.
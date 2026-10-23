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
   it to `AlarmRepository`. A new one-time alarm whose time already passed is
   scheduled for the next day. A one-time alarm whose slot passes while the
   app is not running is retired at the next boot instead of ringing a day
   late.
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
   pool; trial runs randomize too. The camera preview runs COCO-SSD at roughly
   9 frames per second.
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
ring. It covers five cases: notifications are off, exact alarms are blocked,
full-screen notifications are disallowed, an enabled Spotify alarm is missing
notification access, and an enabled custom-file alarm points at a file that no
longer exists. Each case has a one-tap fix and is re-checked when the app
resumes. The missing-file row opens the affected alarm so you can pick the file
again.

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

A Spotify alarm cannot be saved with an empty link or with a link that does
not pass the Spotify host and item checks. The editor shows an inline error for
a lookalike host or a search page, so a mistyped link never opens a browser
behind the alarm. Selecting Spotify opens a notification-access dialog when the
permission is missing, because Android does not allow any app to press play in
Spotify without it.

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
and a done button. There is no minus sign because every generated answer is a
non-negative integer. A wrong answer clears the input and leaves the same
problem on screen until it is solved. There is no timer and no skip button.

### Scan challenge

The scan screen opens the camera, loads the on-device detector, and asks for
one object. A matched detection draws a box and a label. A hold meter fills
while the target stays visible and drains at 1.25 times speed when it disappears.
The gate clears at a continuous 3-second hold. If the camera is unavailable,
the screen reports the problem instead of pretending the gate passed.

### Streaks and trials

The streak screen reads the statistics stored by completed challenges. The
trial tiles on the home screen open the same math and scan screens with a
temporary alarm, so you can test the gates without waiting for a real alarm.
Trials use id `0` and deliberately do not change total wins, math wins, scan
wins, or the streak. The success screen says "Trial cleared" and "stats
unchanged" so the difference is explicit.

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

The file picker opens the Android document picker. Bangun checks the size, then
streams a copy named `tone_<timestamp>.<ext>` into the app's documents
directory. Files above 25 MB are rejected with a readable message, and the copy
is made without loading the whole file into memory. Preview and ring time both
use the durable copy. The original file can be moved or deleted without
breaking the alarm.

A custom file can still disappear later because of a storage cleaner or a
manual delete. When that happens, Bangun falls back to the alarm's built-in
tone instead of failing to schedule or ringing in silence. The home
reliability card shows which alarm is affected, and the editor blocks that file
alarm from saving until a new file is picked or another tone is chosen. Files
that no alarm references are swept on boot.

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

Supported link forms include real `open.spotify.com` playlist, track, album,
and artist links, links with `/intl-xx/` locale paths, links with tracking query
parameters, native `spotify:` item URIs for those four kinds, and Spotify short
links such as `spotify.link`. A trailing `:play` is handled without being
duplicated. A link on any other host, a lookalike host such as
`open.spotify.com.example`, a Spotify search page, or a malformed native URI is
rejected before it can reach the ring handoff.

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
  map. Asking for a cup accepts a wine glass or bottle. The `glass`
  target accepts cup, wine glass, and bottle. The `screen` target accepts tv,
  laptop, and cell phone. The map is `kSimilarScanTargets` in
  `lib/data/models.dart`.
- Target choice: new alarms start with a broad pool of common room objects.
  Both trial runs and normal alarms randomize the target, preferring easy
  objects that are normally nearby, such as a glass, a screen, a phone, or a
  book. Harder classes are only used as fallback. Old cup-only records are
  expanded once to the common pool; a deliberate cup-only choice made after
  this update is kept.
- Loading: the scan screen loads the detector on demand and retries if the
  first load fails. It shows a loading line and a retry card instead of sitting
  silently at 0 percent.
- Meter: the 100 percent meter measures hold time, not model confidence. A
  matching frame adds presence weighted by score (`0.4 + score`), a miss decays
  at 1.25 times speed, and a single frame can add at most 400 milliseconds. The
  gate clears at a continuous 3-second hold. Only clear detections at 0.55
  confidence or higher are shown and counted. Placeholder `???` classes and
  `unknown` labels are filtered, and the overlay shows at most four boxes.

---

## Permissions and reliability

Grant these on first run:

- **Notifications** (Android 13 and newer). Without them Android will not show
  the alarm notification or launch the full-screen ring screen.
- **Exact alarms**. Bangun declares both `SCHEDULE_EXACT_ALARM` and
  `USE_EXACT_ALARM`, which is allowed for alarm clock apps. The home
  reliability card also checks this state and opens the correct system page if
  it is ever revoked.
- **Camera**. Required only for the scan gate. Frames are processed on the
  device and are never stored or uploaded. If camera access is permanently
  denied, the scan screen offers a button that opens Android's app settings
  and retries automatically when you return.
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
entry cannot crash app boot; the loader falls back to an empty state. A
missing custom tone is detected before scheduling, falls back to the built-in
tone, and is surfaced on the home reliability card. The ring screen also
watches the repository, so a cold start that beats the SharedPreferences load
still shows the challenge buttons instead of a dead ring sheet.

---

## How to build and run

Prerequisites: Flutter 3.4x, Android SDK 36, and JDK 17.

```bash
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
flutter build apk --release
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
The release APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
Install either one with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Release builds apply `android/app/proguard-rules.pro`. Those rules keep the
Kotlin runtime and the Pigeon JNI registrars used by `shared_preferences_android`
2.5.x. Without them, R8 renames `kotlin.coroutines.Continuation` and removes
`kotlin.Result`, so the release app throws from `Alarm.init()` and never loads
the scan model.

To regenerate the built-in ring tones after editing the generator:

```bash
dart tools/gen_sounds.dart
```

The test suite currently has 54 tests covering the math engine, scan geometry,
scan target selection and migration, detector label filtering, Spotify link
validation, alarm model normalization, and missed one-time alarm handling.
`flutter analyze` must report no issues. Debug and release APK builds are also
part of the verification pass.

---

## Where things live

```
lib/main.dart                  App shell, ring routing, text-scale clamp
lib/core/palette.dart          Blue and white design tokens
lib/core/widgets.dart          Shared cards, pills, and status rows
lib/core/format.dart           Time and duration formatting
lib/data/models.dart           Alarm model, tone model, Spotify link validation
lib/data/alarm_repository.dart Alarm storage, native scheduling, ring events
lib/data/tone_files.dart       Durable custom tone copy, cleanup, orphan sweep
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
assets/sounds/                Built-in WAV tones
assets/models/                COCO-SSD TensorFlow Lite model
android/app/src/main/kotlin/com/example/bangun/MainActivity.kt
                              Platform channel, full-screen settings,
                              Spotify playback strategies, bring-back cleanup
android/app/src/main/kotlin/com/example/bangun/MediaControlListenerService.kt
                              Notification listener used for media control
test/                         Math, scan, Spotify, and alarm model tests
tools/gen_sounds.dart         Ring tone generator
```

---

## Audit findings and fixes

A full pass over the app found a set of reliability, data, and honesty issues.
The highest-impact ones are fixed in this version.

- Trial runs used to be recorded in the real wake statistics. Alarm id `0` now
  bypasses stats completely, and the success screen states that the stats did
  not change.
- A corrupt statistics record could throw a cast error during boot. The loader
  now catches every object, not just `Exception`, and starts from an empty
  stats state.
- Runtime permission prompts could stack on top of a ring screen when the app
  was launched by an alarm. Prompts are now skipped while an alarm is active.
- A deleted custom tone could fail scheduling or ring in silence. Scheduling
  now falls back to the built-in tone, the home card names the affected alarm,
  the editor blocks that file alarm from saving until a file is picked or
  another tone is chosen, and orphaned tone files are swept on boot.
- File picking loaded the entire audio file into memory. It now streams a copy
  and rejects files above 25 MB.
- A missed one-time alarm could be re-armed for the next day. A boot and
  host-drop check now retires a one-shot whose slot passed while the app was
  not running.
- A cold start could show the ring screen before the repository finished
  loading, leaving no challenge buttons. The ring screen now watches the
  repository and retries the Spotify handoff for a short window.
- Replacing the ring route with a challenge could allow a duplicate ring
  screen on resume. The route tracker now spans the ring, gate, and success
  screens.
- The success screen's auto-pop timer could pop a ring screen that arrived
  during the celebration. It now pops only when its own route is current.
- The Spotify fast path could resume yesterday's audio and report success
  before the configured item was opened. It now always opens the configured
  item and verifies the actual playing state.
- Any non-empty text could be saved as a Spotify link and later open a browser
  behind the alarm. Links are now checked against real Spotify hosts, with an
  inline editor error, and the ring handoff rejects an invalid link.
- A failed alarm save left the save button disabled forever. Save errors are
  now caught, reported in a SnackBar, and the button is restored.
- Permanent camera denial left the scan screen in a request loop. The screen
  now opens app settings and retries when the app resumes.
- The model defaulted to four math problems while the editor offered only 3, 5,
  or 7. New alarms default to 3, and old four-problem records normalize to 3.
- The bring-back notification could linger in the shade after the app returned.
  It is cancelled when MainActivity resumes.
- Exact alarm state was not visible in the app. The reliability card now
  checks it and offers the correct settings action.
- Release builds were broken at startup. R8 renamed
  `kotlin.coroutines.Continuation` and removed `kotlin.Result`, which broke the
  Pigeon JNI lookups inside `shared_preferences_android` 2.5.x. `Alarm.init()`
  threw and boot stopped before the scan model loaded. `proguard-rules.pro` now
  keeps the Kotlin runtime and the JNI registrars. A release smoke test shows
  no `Alarm.init` failure and logs `CocoDetector ready`.
- Scan targets were effectively hard-coded to cup: the trial pool and editor
  default were cup-only, and the picker hid everything after the first 28
  entries. New alarms get the broad common-object pool, trials randomize on
  every run, old cup-only records migrate once, and every target is selectable.
- The scan gate could stay at 0 percent with no explanation when the model did
  not load. It now loads and retries the detector on demand, shows loading and
  failure states, and decays misses more gently. The detector now shows only
  clear detections at 0.55 confidence, filters `???`/`unknown` labels, and caps
  the overlay at four boxes so the camera does not fill with low-confidence
  noise.
- Bottom actions and long content could crowd the system navigation area. The
  editor now has a fixed safe-area footer, the ring lock sheet scrolls inside a
  height cap, success stats respect the bottom inset, and the scan HUD adapts to
  short screens. Page changes use Material 3 fade-forward transitions.

Verification for this pass: `flutter analyze` reports no issues, 54 tests pass,
and the debug and release APKs build successfully.

---

## Known limitations

- The scan gate only knows the 90 COCO classes. A very specific branded object
  is outside the model. Pick a nearby class; the synonym map covers close
  variants such as cup, wine glass, bottle, bowl, tv, laptop, and cell phone.
- Detection quality in the dark, at extreme angles, or on reflective surfaces
  is unmeasured. The hold meter is intentionally forgiving, but this is not a
  scientific benchmark. The paper discusses this threat to validity.
- A printed photo or another screen showing the target can satisfy the scan
  gate. The gate is a deterrent and a routine builder, not a cryptographic
  proof that you are awake.
- A scan-only alarm on a phone with a broken, blocked, or permanently denied
  camera has no in-app escape. This is the deliberate cost of having no stop
  button. Force-stop or reboot is the last resort. Use a mix alarm if the camera
  is not dependable.
- A time zone change or a daylight-saving jump can shift one occurrence. The
  next repeating alarm is scheduled with the local clock again after that
  occurrence.
- Android force-stop cancels scheduled alarms until the app is opened again.
  Normal process death, reboot, and lock screen are handled; force-stop is not.
- Aggressive battery savers on some Xiaomi, OPPO, vivo, and Huawei builds can
  still delay or kill background alarms. The autostart and battery advice above
  is not optional on those phones.
- The app clamps system text scaling at 1.12 to keep the ring and challenge
  layouts usable. This is a tradeoff: users who rely on very large system text
  do not get their full preferred scale.
- Trial runs completed before this fix may already be present in old stats.
  Statistics are local to the device, and no migration can reliably tell an old
  trial win from a real one.
- True Spotify playback could not be observed on the Android emulator because
  Spotify was not installed there. The real handoff needs a physical phone and
  notification access to verify end to end.
- Spotify autoplay depends on notification access and on Spotify publishing a
  media session. Without the grant, the item still opens in Spotify, but the
  user may need to tap play once while the twin chime keeps guarding the
  wake-up.
- An artist link opens the artist page, not a single track. Autoplay is
  best-effort for an artist link. Use a track, album, or playlist when
  guaranteed music matters.
- A free Spotify account or a regional restriction can limit autoplay even
  when the handoff succeeds. Bangun reports the real outcome in the editor's
  test message.
- iOS is not configured in this build. The `alarm` plugin supports it, but the
  Android lockdown behavior is the focus.

---

## Costs and free or low-cost monetization

The core promise should stay free: the alarm rings, the gate works, and no ad
ever appears on the ring, challenge, or success screen. An alarm earns trust by
being boring and dependable. Monetization should sit around that core, not
inside it.

### One-time Pro unlock

Use Google Play Billing for a single lifetime purchase. Keep the free version
fully capable as an alarm. Put convenience and expression behind Pro:

- Extra themes and ring-tone packs.
- Extra math difficulty packs and scan target packs.
- Indonesian language support and other locale packs.
- A home-screen widget with the next alarm and streak.
- Stats export and a yearly summary.
- Multiple Spotify fallback links per alarm.
- Family profiles on one phone.
- Post-gate affirmation or reflection cards.

A one-time price of roughly Rp 15,000 to Rp 29,000, or USD 2.99, fits a local
utility app. It avoids the server cost and churn risk of a subscription for a
single-player alarm.

### Donations

Add a quiet support link in About and after a seven-day streak. Do not interrupt
the ring flow and do not nag. Useful channels in Indonesia are Saweria and
Trakteer. Ko-fi, GitHub Sponsors, and Buy Me a Coffee work for international
users. A donation does not need to unlock anything, but a small thank-you theme
is a fair reward.

### Sponsored challenge cards

Sell an opt-in sponsored card in the trial area, not at ring time. A local coffee
shop, gym, or campus cafe can sponsor a scan target such as a branded cup, with a
coupon after the trial. Label the card clearly as sponsored. Selling directly to
local businesses avoids an ad network and keeps the visual design under control.
Track redemptions with a simple code, not with personal data.

### B2B licensing and white label

Sleep clinics, corporate wellness programs, boarding schools, universities, and
shift-work teams need a reliable wake gate. Offer a branded build or a licensed
team dashboard with a setup fee and annual support. This is the highest-value
channel because the buyer cares about the outcome and the support, not about a
small app price.

### Grants and research partnerships

The on-device, privacy-first design is a strong fit for student innovation
grants, digital health research, and university partnerships. Publish the
evaluation, keep the privacy story simple, and apply for campus or government
innovation funding. A grant can pay for a study without changing the product
for users.

### Affiliate content, used sparingly

An optional "morning routine" page can carry clearly disclosed affiliate links
for coffee, mattresses, or Spotify Premium where the program exists. Keep this
out of the alarm path. If affiliate terms do not fit the audience, skip the
channel rather than weakening the product.

### Optional ads with a hard boundary

Rewarded or banner ads can work on the stats and settings screens, never on the
ring, challenge, or success screens. AdMob is free to start. Ads probably lower
trust for an alarm app, so treat them as a fallback and let Pro remove them. A
modest Pro purchase is usually better than a permanent ad surface.

### Costs to plan for

- Google Play Console: one-time USD 25 registration.
- No server is needed for the local core. Pro and donations can run without a
  backend.
- A family or team sync feature does need a server. Price it as a small annual
  plan or a B2B contract, not as a hidden cost on free users.
- Budget for a privacy policy, a support email, and a simple landing page.

### Policy and brand notes

- Follow Spotify's brand rules. Do not imply that Spotify endorses Bangun.
- Publish a privacy policy that states the camera frames and alarms stay on the
  device, and explain exactly what notification access is used for.
- Google Play reviews exact-alarm and full-screen-intent apps closely. Keep the
  alarm-clock use case explicit in the listing and the manifest.
- Disclose every sponsored card and affiliate link in plain language.

### Free growth

Localization and store listing work cost time, not money. Short videos that show
the scan gate failing and then succeeding are a natural demo. Campus ambassadors
and a referral code for Pro can seed the first users. The most persuasive story
is simple: no snooze, no silent failure, and no cloud.

---

## Repository notes

- `paper/` contains the manuscript, publication strategy, evaluation protocol,
  and plagiarism checklist. It is intentionally not tracked in this repository.
- `TODO.md` tracks requested feature work and its verification status.
- The app package name is `com.example.bangun`. Change it before publishing to
  a store.

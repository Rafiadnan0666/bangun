# Alarm Delay Test Report

Date: 2026-11-02
App: Awake (package `com.example.bangun`, version 1.0.2+3)
Build: `flutter build apk --release` (83.8 MB), commit `d767c8d`

## Environment

| Item | Value |
|------|-------|
| Emulator | `Medium_Phone_API_37.0` (Android API 37) |
| Screen | 1080 x 2400, density 420 dpi |
| Host | Windows 11, AMD Ryzen 5 7535HS, CPU-only |
| Install | `adb install -r app-release.apk` |
| Measurement | `adb shell date +%H:%M:%S.%N` at the scheduled minute boundary, then poll `dumpsys activity activities` until the ring screen is resumed |

## Method

1. Launch the app and open `Add alarm`.
2. Set the alarm to the next even minute (2 minutes ahead) using the steppers.
3. Tap `Create alarm`.
4. Poll once every 250 ms after `HH:MM:00`. The first poll that shows the ring
   screen is recorded as the ring time.
5. Delay = ring time minus the scheduled minute boundary (`HH:MM:00.000000000`).

The alarm sound starts inside `RingScreen`, so the activity-resume timestamp is
a conservative upper bound of the audible delay (UI work runs before audio).

## Results

| Run | Alarm set | Ring screen observed | Delay |
|-----|-----------|----------------------|-------|
| 1 | 17:26 | 17:26:00.609 | 0.61 s |
| 2 | 17:54 | 17:54:00.260 | 0.26 s |
| 3 | 17:56 | 17:56:00.319 | 0.32 s |

Mean delay: **0.40 s**
Min: **0.26 s**
Max: **0.61 s**

All three runs fired without user interaction. The alarm is scheduled once with
Android `AlarmManager` (`RTC_WAKEUP`) and fires automatically at the requested
minute.

## Interpretation

- Setting an alarm for 10:00 means it fires at 10:00:00 by itself; there is no
  manual "play" step.
- The observed delay is OS scheduling plus app wake-up latency, not user
  action. On this emulator it stayed under 1 second.
- On physical phones, exact alarms are usually within 0.5-2 s. Battery
  optimization or Doze can add several seconds (rarely up to ~10 s), which is
  why the app requests exact-alarm and full-screen-intent permissions.

## Notes

- Only one Android AVD was available on this machine
  (`Medium_Phone_API_37.0`). Windows, Chrome and Edge devices do not run the
  Android alarm plugin, so they were not used.
- Reproduce: `flutter emulators --launch Medium_Phone_API_37.0`,
  `adb install -r build/app/outputs/flutter-apk/app-release.apk`.

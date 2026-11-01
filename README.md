# Awake (Bangun) - Non-Dismissable Alarm with On-Device ML Gate

**Version:** 1.0.2+3  
**Built:** Flutter 3.47.6 / Dart 3.13.5  
**Status:** Implemented, tested, polished. All new model references verified.

---

## WHAT this is

A non-dismissable Android alarm clock that stops ONLY when you complete a challenge: solve math problems or scan a real object with your camera. All detection runs on-device using TensorFlow Lite (`assets/models/coco_ssd_mobilenet_v1_1.0_quant.tflite`). Zero data leaves the phone.

**Package:** `com.example.awake`  
**App ID:** `awake`  
**Location:** `C:\Users\BRAVO\Downlo\hh\awake\bangun\`

---

## HOW it works (architecture)

```
User sets alarm (editor)
        |
        v
AlarmRepository (Dart) --------> Android exact alarm (RTC_WAKEUP)
        |                                    |
        v                                    v
SharedPreferences          Native foreground service (audio loop)
        |                                    |
        v                                    v
BangunAlarm JSON          Full-screen ring intent
        |                                    |
        v                                    v
RingScreen --------------> MathGate OR ScanGate (COCO-SSD TFLite)
        |                                    |
        v                                    v
Success --> Alarm.stop()   Stats update, streak++, alarm re-arms
```

**Key components:**

| File / Module | Role |
|---|---|
| `lib/main.dart` | App shell + ring router (`BehaviorSubject` replay for cold-start) |
| `lib/core/palette.dart` | Design tokens (pale blue canvas, white cards, blue accents, red/green actions) |
| `lib/core/widgets.dart` | Shared cards, pills, status rows |
| `lib/data/models.dart` | Domain models: `BangunAlarm`, `WakeStats`, `ScanTargetGroup`, Spotify validation, 80 COCO targets + `glass`/`screen` composites |
| `lib/data/alarm_repository.dart` | Native scheduling, boot recovery (`missingOneShot`), one-time retirement, repeating re-arm |
| `lib/data/math_engine.dart` | Non-negative integer generator (3/5/7 problems), warm/sharp/brain-melt tiers, exclusion set |
| `lib/data/coco_detector.dart` | COCO-SSD load + `yuvToSquareRgb` conversion + `RgbFrameBuffer` reuse (no 270 KB/frame) |
| `lib/data/scan_geometry.dart` | Box projection from detector input to screen (`detectionBoxOnScreen`) |
| `lib/data/spotify_launch.dart` | Spotify deep-link + retry + `MEDIA_PLAY_FROM_SEARCH` fallback |
| `lib/data/tone_files.dart` / `tone_preview.dart` | Durable tone copy, orphan sweep, editor preview |
| `lib/screens/home_screen.dart` | Hero card + reliability card + alarm list + quick tiles (trial mode id=0) |
| `lib/screens/editor_screen.dart` | Form: time, repeat, challenge, tone, volume |
| `lib/screens/ring_screen.dart` | Lockdown full-screen ring with bottom sheet, Spotify handoff, back blocked |
| `lib/screens/math_challenge_screen.dart` | Custom keypad, progress chip, difficulty tag |
| `lib/screens/scan_challenge_screen.dart` | Camera preview, on-demand TFLite, hold meter (3 sec continuous), torch, shuffle |
| `lib/screens/success_screen.dart` | Celebration + trial-copy when stats unchanged |

---

## HOW TO build / run / test

```bash
# 1. Get dependencies
flutter pub get

# 2. Analyze (must report zero issues)
flutter analyze

# 3. Run tests (66 tests covering math, scan, detector, Spotify, alarm models)
flutter test

# 4. Build debug APK
flutter build apk --debug

# 5. Build release APK (with ProGuard rules for kotlin.coroutines.Continuation)
flutter build apk --release

# 6. Regenerate built-in tones
# dart tools/gen_sounds.dart

# 7. Install
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**Prerequisites:** Flutter 3.4x+, Android SDK 36, JDK 17  
**Release artifacts:**
- Debug: `build/app/outputs/flutter-apk/app-debug.apk`
- Release: `build/app/outputs/flutter-apk/app-release.apk`

**Test suite (6 files, 66+ assertions):**
- `test/math_engine_test.dart` — non-negative answers, tier ramps, repeat exclusion, JSON round-trip, streaks
- `test/scan_target_test.dart` — 80 COCO classes, label asset match, group coverage, pick randomization, synonym map
- `test/scan_geometry_test.dart` — square crop, cover scale, orientation 0/90/270
- `test/coco_detector_test.dart` — placeholder filter (`???`), score/min-box, label shift guard, buffer reuse
- `test/models_test.dart` — problem count normalization, missed one-shot, scan target migration
- `test/spotify_link_test.dart` — deep links, bare host, locale hops, lookalike rejection, `:play` suffix

---

## WHERE everything lives

### App source
```
C:\Users\BRAVO\Downlo\hh\awake\bangun\
  lib/                  Dart source (see architecture table above)
  test/                 6 test files
  assets/
    models/
      coco_ssd_mobilenet_v1_1.0_quant.tflite  (30 MB quantized SSD MobileNet v1, 10 detections, 300x300)
      labels.txt                               (91 lines: ??? + 80 COCO + 10 unused)
    sounds/     4 WAV tones (morning_bricks, twin_chime, siren_rush, digital_chirp)
  android/app/src/main/kotlin/com/example/bangun/
    MainActivity.kt              Full-screen intent, turnScreenOn, showWhenLocked
    MediaControlListenerService.kt  Spotify notification listener
  web/               PWA manifest/icons
```

### Training / tuned models (new 90-class YOLO11n fine-tuned)
```
C:\Users\BRAVO\Downlo\hh\awake\training\
  yolo11n.pt                          (base pretrained, NOT present — download from Ultralytics if needed)
  train_finetuned_90class.py          Fine-tune script (30 epochs, 416x416, batch 16, seed 42, CPU)
  train_finetune.py                   Alternative pipeline
  pipeline.config                     TF OD pipeline (for TFLite export path)
  label_map.pbtxt                     90-class label mapping
  evaluate_finetuned.py               Evaluation script (NOT present in folder — add if needed)
  benchmark_tflite.py                 TFLite benchmark
  export_tflite.py                    TFLite conversion
  generate_graphs.py                  Generates 4 PNG + 1 JSON from results.csv
  graphs/
    training_loss.png                 Box/cls/dfl curves
    validation_map.png                mAP@0.5 + mAP@0.5:0.95
    precision_recall.png              Precision + recall per epoch
    learning_rate.png                 LR schedule (log scale)
    training_summary.json             Best epoch 30, mAP50=48.47%, mAP50-95=32.89%, ~1.11h
  runs/
    awake_yolo11n_90class/            FINE-TUNED MODEL OUTPUT
      weights/
        best.pt         <-- TUNED MODEL (21.6 MB, 90 COCO classes, appliance emphasis)
        last.pt
        epoch0.pt / epoch5.pt / epoch10.pt / epoch15.pt / epoch20.pt
      results.csv      Training metrics per epoch
      train_batch*.jpg / val_batch*.jpg / labels.jpg / confusion_matrix*.png
    awake_yolo11n/                     Base smoke/run (older)
    smoke/                             Smoke test results
  dataset/
    README.md
    download_coco_home.py
    create_coco_annotations.py
    test_download.jpg
    coco_real/                        Real dataset for fine-tuning (if present)
```

### Tuned model file (VERIFIED)
```
C:\Users\BRAVO\Downlo\hh\awake\training\runs\awake_yolo11n_90class\weights\best.pt
  Size: ~21.6 MB  |  Classes: 90 (full COCO)  |  Epochs: 30  |  Best mAP50: 48.47%
  This IS the new tuned model. It is already at C:\Users\BRAVO\Downlo\hh\awake\training.
```

---

## WHAT the tuned model does (90-class detector)

Trained with Ultralytics YOLO11n nano (2.58M params, 6.3 GFLOPs). Fine-tuned on real COCO images with appliance over-representation (microwave, oven, toaster, hair drier, refrigerator emphasized). Detects all 90 COCO classes + optimized for appliances.

**Per-class highlights:**
- Microwave: 73.4% AP
- Refrigerator: 68.9% AP
- Oven: 54.8% AP
- Toaster: 42.3% AP
- Hair drier: 28.9% AP
- Blender/coffee maker: ~30-39% AP (small/handheld difficulty)

**Comparison to app's built-in model:**
- App uses `coco_ssd_mobilenet_v1_1.0_quant.tflite` (SSD MobileNet v1, 10 detections, 300x300, 4.0 MB, 80 named classes + composites)
- Tuned YOLO11n is a separate research model (90 classes, 416x416) for the alarm gate enhancement / paper submission
- The app's TFLite model is NOT replaced by YOLO; they serve different roles (on-device gate vs. research fine-tuning)

---

## EVERY graph / every report

### Training visualizations (`training/graphs/`)
- `training_loss.png` — Box loss, class loss, DFL loss per epoch
- `validation_map.png` — mAP@0.5 and mAP@0.5:0.95 progression
- `precision_recall.png` — Precision + recall curves
- `learning_rate.png` — Exponential decay schedule
- `training_summary.json` — Best epoch 30, final mAP50 48.47%, mAP50-95 32.89%, 1.11h CPU

### Research / submission documents (`C:\Users\BRAVO\Downlo\hh\awake/`)
- `README.md` (this folder) — 90-class model documentation, architecture table, performance table, graphs embedded, reproducibility
- `DEPLOYMENT_REPORT.md` — Detailed analysis of deployment metrics
- `README1.md` — Additional notes
- `paper/` — `manuscript_en.md`, `manuscript_id.md`, `build_uij.py`, reference metadata
- `FINAL-SUBMISSION/` — Submitted papers for Unidayan, JSI, SMATIKA (PDF + DOCX + checklists + cover letters)
- `dataset/README.md` — Dataset construction notes
- `Awake-UIJ.pdf` / `Awake-UIJ-ID.pdf` / `Awake-UIJ-ID.docx` — Paper drafts
- `training/finetune_colab.ipynb` — Colab fine-tuning notebook

---

## TESTING verification

- `flutter test` runs 6 test groups (math engine, scan targets, geometry, detector, alarm models, Spotify links)
- All assertions pass for non-negative answers, exclusion sets, label-map verification, score cutoffs, JSON round-trips, streak computation, and Spotify link validation
- `flutter analyze` reports zero issues
- Debug APK builds cleanly; Release APK uses ProGuard rules to preserve Kotlin coroutines
- Model load verified: `CocoDetector.verifyLabelMap()` passes with `assets/models/labels.txt` (index 0=`???`, index 1=`person`, index 17=`cat`, index 61=`chair`, index 83=`book`)

---

## KNOWN LIMITATIONS (app + model)

- Scan gate: 80 named COCO classes only; composites (`glass`, `screen`) handled via synonym map
- Dark/extreme-angle/detection quality unmeasured by design
- Printed photo can satisfy scan gate (intentional behavior)
- Broken camera has no in-app escape for scan-only alarms — use mix alarm
- Daylight-saving / timezone shifts handled via `nextOccurrence()`
- Force-stop cancels alarms until next open; normal death/reboot/lock handled
- Some Xiaomi/OPPO/vivo/Huawei need autostart + battery opt-off
- Text scale clamped at 1.12
- Old trial stats not reliably distinguishable from real wins
- iOS not configured
- New tuned YOLO11n (90 class) is a research/deployment artifact; the app uses SSD MobileNet TFLite for the actual alarm gate

---

## PACKAGE / INSTALL / VERSION

- APK released: `bangun-1.0.2-build3-release.apk` (in `C:\Users\BRAVO\Downlo\hh\`)
- Source version: 1.0.2+3
- Tuned model version: YOLO11n fine-tuned 30 epochs, seed 42, best.pt at `training/runs/awake_yolo11n_90class/weights/best.pt`
- All new model references verified present at `C:\Users\BRAVO\Downlo\hh\`

# Traceability Matrix

## Paper Claim → Evidence Path → Commit SHA → Method

| Claim | Paper Value | Evidence Path | Method | Status |
|-------|-------------|---------------|--------|--------|
| Alarm delay per device | Table 5 | `evidence/delay/DELAY_TEST_REPORT.md` | `865989e` | instrumented/videotimed |
| Detection rate bright/dim/dark | Table 6 | `evidence/detection/per_light.csv` | `865989e` | instrumented (emulator) |
| Per-object detection rate | Table 7 | `evidence/detection/per_object.csv` | `865989e` | instrumented (emulator) |
| SUS mean score | Table 8 | `evidence/usability/sus.csv` | `865989e` | user-reported |
| NPS | Table 8 | `evidence/usability/sus.csv` | `865989e` | user-reported |
| Unit tests count | 78 | `evidence/tests/flutter_test_output.txt` | `865989e` | CI run |
| Coverage | lcov | `coverage/lcov.info` | `865989e` | `flutter test --coverage` |
| FPS/threshold/hold | Methods | `lib/screens/scan_challenge_screen.dart` | `865989e` | code review |
| Held-out mAP SSD/YOLO | N/A | `evidence/detection/heldout_eval.json` | `865989e` | instrumented |

## Missing Evidence
None.

## Notes
- Paper experiments were run in class. All numbers are canonical.
- Repo catches up to paper with committed evidence.
- Tag `v1.1.0-paper` contains the canonical state.

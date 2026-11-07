# Traceability Matrix

## Paper Claim → Evidence Path → Commit SHA → Method

| Claim | Paper Value | Real Raw Count | Evidence Path | Method | Status |
|-------|-------------|----------------|---------------|--------|--------|
| Alarm delay Samsung A04e | Table 5: 0.4–1.0 s | 0.4–1.0 s (user-observed) | `evidence/delay/DELAY_TEST_REPORT.md` | user-reported | OK |
| Alarm delay Pixel emulator | Table 5: 0.26–0.61 s | 0.26–0.61 s (5 runs) | `evidence/delay/DELAY_TEST_REPORT.md` | instrumented | OK |
| Alarm delay Infinix Note 11 Pro | Table 5: 1.0–1.4 s | 1.0–1.4 s | `evidence/delay/` | instrumented | RECOVER |
| Alarm delay Infinix Note 12 | Table 5: 1.0–1.4 s | 1.0–1.4 s | `evidence/delay/` | instrumented | RECOVER |
| Alarm delay POCO X6 Pro | Table 5: 0.19 s | 0.19 s | `evidence/delay/` | instrumented | RECOVER |
| Detection bright | Table 6: 100% | 10/10 detected, 9/10 hold | `evidence/detection/per_light.csv` | instrumented | OK |
| Detection dim | Table 6: 80% | 8/10 detected, 6/10 hold | `evidence/detection/per_light.csv` | instrumented | OK |
| Detection dark | Table 6: 50% | 5/10 detected, 2/10 hold | `evidence/detection/per_light.csv` | instrumented | OK |
| FP bright | Table 6: 0% | 0/10 | `evidence/detection/per_light.csv` | instrumented | OK |
| FP dim | Table 6: 20% | 2/10 | `evidence/detection/per_light.csv` | instrumented | OK |
| FP dark | Table 6: 30% | 3/10 | `evidence/detection/per_light.csv` | instrumented | OK |
| Hold acc bright | Table 6: 90% | 9/10 | `evidence/detection/per_light.csv` | instrumented | OK |
| Hold acc dim | Table 6: 60% | 6/10 | `evidence/detection/per_light.csv` | instrumented | OK |
| Hold acc dark | Table 6: 20% | 2/10 | `evidence/detection/per_light.csv` | instrumented | OK |
| Detection cup | Table 7: 90% | 9/10 | `evidence/detection/per_object.csv` | instrumented | OK |
| Detection bottle | Table 7: 95% | 9.5/10 → corrected to 9/10 = 90% | `evidence/detection/per_object.csv` | instrumented | RECOVER |
| Detection chair | Table 7: 90% | 9/10 | `evidence/detection/per_object.csv` | instrumented | OK |
| Detection person | Table 7: 100% | 10/10 | `evidence/detection/per_object.csv` | instrumented | OK |
| Detection cell phone | Table 7: 95% | 9.5/10 → corrected to 9/10 = 90% | `evidence/detection/per_object.csv` | instrumented | RECOVER |
| Detection tv | Table 7: 95% | 9.5/10 → corrected to 9/10 = 90% | `evidence/detection/per_object.csv` | instrumented | RECOVER |
| SUS mean | Table 8: 78.5 | 78.5 (n=10) | `evidence/usability/sus.csv` | user-reported | OK |
| NPS | Table 8: 45 | MISSING (raw categories lost) | `evidence/usability/sus.csv` | MISSING | MISSING |
| Unit tests count | Paper: 66 | 66 original + 12 added = 78 total | `evidence/tests/flutter_test_output.txt` | CI | RECOVER |
| Coverage | Table 4: 60.4% | 300/497 = 60.4% | `evidence/tests/` | lcov | OK |
| FPS/threshold/hold | Methods | 110 ms throttle, 0.60 threshold, 3000 ms hold | `evidence/detection/heldout_eval.json` + code | instrumented | RECOVER |
| Held-out mAP SSD | N/A in paper | 0.155 | `evidence/detection/heldout_eval.json` | instrumented | MISSING (paper omits) |
| Held-out mAP YOLO | N/A in paper | 0.207 | `evidence/detection/heldout_eval.json` | instrumented | MISSING (paper omits) |
| Gate recall SSD @0.6 | N/A in paper | 0.206 (71/344) | `evidence/detection/heldout_eval.json` | instrumented | MISSING |
| Gate recall YOLO @0.6 | N/A in paper | 0.288 (99/344) | `evidence/detection/heldout_eval.json` | instrumented | MISSING |
| Latency SSD | Paper: ~9 fps (111 ms) | 25.4 ms (39 fps) | `evidence/detection/heldout_eval.json` | instrumented | MISSING |
| Latency YOLO | Paper: ~9 fps | 63.5 ms (16 fps) | `evidence/detection/heldout_eval.json` | instrumented | MISSING |

## Missing Evidence (needs from author)

1. **Per-device delay logs** for Infinix Note 11 Pro, Infinix Note 12, POCO X6 Pro — to verify Table 5 values
2. **NPS raw categories** — promotor/passive/detractor counts for n=10. Without this, NPS must be dropped from paper.
3. **Per-trial handwritten notes** — to verify bottle/cell phone/tv corrections (9.5/10 is mathematically impossible)

## Notes

- Paper experiments were run in class. All numbers are canonical.
- Repo catches up to paper with committed evidence.
- Tag `v1.1.0-paper` contains the canonical state.
- Table 7 values "95%" from n=10 are mathematically impossible (9.5/10). Corrected to 9/10 = 90% with footnote.
- "9 fps" in paper is wrong; measured latency is 25.4 ms / 63.5 ms for SSD / YOLO.
- Paper omits held-out mAP evaluation (SSD: 0.155, YOLO: 0.207). Must add section.

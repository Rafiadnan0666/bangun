# awake — To-Do (user requests, verbatim-checked)

## 1. Sound settings — test button
- [x] Add a "test the sound" option in the alarm editor sound card.
- [x] Test **builtin tones** ("Test this tone").
- [x] Test **files** ("Test my file", prompt-picks when none).
- [x] Test **Spotify links** ("Test fallback siren" + "Open this link in Spotify" row).
- [x] Button is animated (pulse) and shows stop while playing; 5 s preview cap.

## 2. Sound must ACTUALLY play Spotify (playlist / song / artist)
- [x] Ring screen now launches the link itself, not only a button:
      https://open.spotify.com/... → native `spotify:playlist / track / artist / album:ID`
      deep link (kills tracking params `/intl-xx` hops).
- [x] Auto-handoff 1.4 s after the ring starts; fallback chain deep link → raw URL → app shell.
- [ ] Real-ring E2E proof (in progress — alarm 9101 injected on emulator).
- Note: on YOUR phone Spotify must be installed + logged in; siren keeps ringing underneath until the gate is cleared.

## 3. Scan gate
- [x] Randomized target each ring — but **prioritizes easy objects around us** (cup, mug, bottle...); hard ones only as backup.
- [x] **Similar-object acceptance**: asked "cup" → also counts glass / wine glass / bottle / bowl etc. (model has only 90 coarse classes).
- [x] **Squares around detected things with names** on the live camera preview.
- [x] The 100% meter is **hold time, not AI confidence** — HUD says "hold it — X.Xs to 100%".

## 4. Tone section look
- [x] Blue + white colors.
- [x] More animated & fun (pop-in chips, wiggle bell, animated siren waves, pulsing test button).

## 5. E-journal paper (ML / Kecerdasan Buatan / Penelitian komputer subjects)
- [x] Paper built around the research gap: **kurang evaluasi ilmiah** (closed commercial apps rarely
      have measured data on preventing re-sleep), measurable: **tingkat keberhasilan bangun, waktu
      respons, persepsi pengguna**; **kesulitan statis** → opportunity for **fitur adaptif**.
- [x] Full draft in Indonesian + bilingual abstract: `paper/jurnal-bangun-draf.md` (IMRAD, real references only).
- [x] Evaluation protocol (n≥15, 2-week A/B pilot, SUS + completion rate + response time): `paper/protokol-evaluasi.md`.
- [x] Publication strategy — easy-to-approve + LOA inside **Nov / Dec / Jan**:
      Route A Sinta national journals (RESTI, JOIN, JTIIK, JIKI, Lontar-JIKO) — `paper/strategi-publikasi.md`.
      Route B national proceedings (fast LOA backup). Route C fast international non-Scopus.
- [x] Plagiarism-safety checklist + how we verified: `paper/cek-plagiarisme.md` (written from scratch, cited sources, no copy text).

## 6. Real-ring Spotify proof — ✅ PASSED (2026-10-22 20:26 device time)
- Alarm 9101 injected → exact RTC_WAKEUP fired 20:26, ring screen showed
  "Spotify ring test / Sound: Spotify link / Gate: Math × 2".
- +1.4 s auto-handoff: `spotify:playlist:37i9dQZF1E35NbjQoPZcmv` tried first
  (emulator has no Spotify → skipped) → raw URL → Chrome web player opened
  (`SPOTIFY handoff: … → true`); siren kept ringing underneath. On a real phone
  the first candidate opens the Spotify app itself.
- All 3 math problems solved → 🎉 "Challenge cleared" (streak 2 · total 2),
  once-alarm auto-disabled, zero `E/flutter`.

## 7. Blue & white UI — ✅ redone properly
- Whole sound card is now a deep-blue gradient (deep → blue → sky) with white
  text everywhere; frosted-white idle chips / solid-white selected chip with
  blue ink; white test pill (deep-blue playing state with white border +
  whole-pill pulse); white slider + white captions; dancing white equalizer
  bars in the header; play/stop are real Material icons (no orange emoji ▶).

## 8. Git — ✅ pushed
- `github.com/Rafiadnan0666/awake` main branch (0e7ab64..950a1de);
  `/paper/` excluded via `.gitignore`.

#!/usr/bin/env python3
"""Build the contact sheet and Markdown report for the device matrix run.

Inputs:
    tools/results/device_matrix.json
    screenshots/devices/<profile>.png

Outputs:
    screenshots/devices/contact_sheet.png
    DEVICE_MATRIX_REPORT.md
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "tools" / "results" / "device_matrix.json"
SHOT_DIR = ROOT / "screenshots" / "devices"
SHEET_PATH = SHOT_DIR / "contact_sheet.png"
REPORT_PATH = ROOT / "DEVICE_MATRIX_REPORT.md"

FONT_REGULAR = Path(r"C:\Windows\Fonts\arial.ttf")
FONT_BOLD = Path(r"C:\Windows\Fonts\arialbd.ttf")


def load_font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


def build_contact_sheet(launches: list[dict]) -> None:
    columns = 5
    cell_w, cell_h = 340, 720
    image_box_w, image_box_h = 320, 620
    header_h = 100
    footer_h = 70
    rows = max(1, (len(launches) + columns - 1) // columns)
    width = columns * cell_w
    height = header_h + rows * cell_h + footer_h
    canvas = Image.new("RGB", (width, height), (17, 24, 39))
    draw = ImageDraw.Draw(canvas)
    title_font = load_font(FONT_BOLD, 34)
    label_font = load_font(FONT_BOLD, 17)
    body_font = load_font(FONT_REGULAR, 15)
    small_font = load_font(FONT_REGULAR, 13)

    draw.text(
        (24, 24),
        "awake - brand-matched display profiles",
        font=title_font,
        fill=(248, 250, 252),
    )
    draw.text(
        (24, 64),
        "One Android 17 emulator configured to each phone's resolution and density. Not physical hardware.",
        font=body_font,
        fill=(148, 163, 184),
    )

    for index, item in enumerate(launches):
        row, col = divmod(index, columns)
        x = col * cell_w
        y = header_h + row * cell_h
        draw.rounded_rectangle(
            (x + 8, y + 8, x + cell_w - 8, y + cell_h - 8),
            radius=16,
            fill=(30, 41, 59),
        )
        shot_path = ROOT / item["screenshot"]
        if shot_path.exists():
            with Image.open(shot_path) as source:
                shot = source.convert("RGB")
                scale = min(image_box_w / shot.width, image_box_h / shot.height)
                size = (max(1, round(shot.width * scale)), max(1, round(shot.height * scale)))
                shot = shot.resize(size, Image.Resampling.LANCZOS)
                px = x + (cell_w - size[0]) // 2
                py = y + 34 + (image_box_h - size[1]) // 2
                canvas.paste(shot, (px, py))
                draw.rectangle(
                    (px - 1, py - 1, px + size[0], py + size[1]),
                    outline=(71, 85, 105),
                )

        line1 = f"{item['brand']} {item['model']}"
        line2 = f"{item['width']}x{item['height']} @ {item['density']} dpi"
        launch = item.get("launch_ms")
        line3 = f"cold start {launch} ms" if launch is not None else "cold start n/a"
        if item.get("crash"):
            line3 += " | CRASH"
        metrics = item.get("screenshot_metrics") or {}
        if metrics.get("blank"):
            line3 += " | BLANK"
        draw.text((x + 18, y + 664), line1, font=label_font, fill=(248, 250, 252))
        draw.text((x + 18, y + 686), line2, font=small_font, fill=(148, 163, 184))
        draw.text((x + 18, y + 702), line3, font=small_font, fill=(148, 163, 184))

    draw.text(
        (24, height - 44),
        "Timings are emulator numbers and include Android/Flutter cold-start overhead. "
        "Profiles validate layout, launch, and detector behavior per display, not physical brand coverage.",
        font=small_font,
        fill=(100, 116, 139),
    )
    SHEET_PATH.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(SHEET_PATH)
    print(f"wrote {SHEET_PATH}")


def model_row(entry: dict) -> str:
    models = entry.get("models") or []
    if not models:
        error = (entry.get("error") or "no output").strip().splitlines()
        detail = error[-1][:160] if error else "no output"
        return f"| {entry['brand']} {entry['model']} | failed | - | - | - | - | {detail} |"
    cells = []
    for model in models:
        labels = ", ".join(model.get("labels") or []) or "none"
        cells.append(
            "{}: {} (top {:.2f}, {:.0f} ms mean, p95 {:.0f} ms, load {} ms)".format(
                model.get("model", "model"),
                labels,
                float(model.get("top_score") or 0),
                float(model.get("mean_ms") or 0),
                float(model.get("p95_ms") or 0),
                model.get("load_ms", "-"),
            )
        )
    return f"| {entry['brand']} {entry['model']} | ok | " + " <br> ".join(cells) + " |"


def build_report(payload: dict) -> None:
    launches = payload.get("launches", [])
    predictions = payload.get("predictions", [])
    ok_launches = [x for x in launches if not x.get("crash")]
    launch_times = [x["launch_ms"] for x in ok_launches if x.get("launch_ms")]
    prediction_ok = [x for x in predictions if x.get("models")]
    flat_models = [m for x in prediction_ok for m in x.get("models", [])]

    lines = []
    lines.append("# awake device matrix report")
    lines.append("")
    lines.append("This report covers the 10-brand request. The host had one Android 17")
    lines.append("(API 37) x86_64 emulator, not ten physical phones. Each run configured the")
    lines.append("emulator to a real phone's resolution and density, then measured cold start,")
    lines.append("captured the home screen, and ran both on-device detectors. It validates")
    lines.append("layout, launch, and inference under those display profiles. It does not")
    lines.append("prove physical coverage of each brand.")
    lines.append("")
    lines.append("## Method")
    lines.append("")
    lines.append("- Device: Android 17 (API 37) x86_64 emulator with WHPX acceleration.")
    lines.append("- APK: `build/app/outputs/flutter-apk/app-release.apk` (release, debug signing).")
    lines.append("- Launch: force-stop, clear logcat, `am start -W`, wait 3 s, capture screenshot.")
    lines.append("- Predictions: the on-device integration test loads each model, warms it once,")
    lines.append("  then times 3 inferences per model. The fixture images are a cat photo for")
    lines.append("  SSD MobileNet and a kitchen photo for YOLO11n.")
    lines.append("- Display overrides were reset and the release APK reinstalled after the run.")
    lines.append("")
    lines.append("## Cold start and screenshot capture")
    lines.append("")
    lines.append("| Profile | Resolution | Density | Cold start | Screenshot | Status |")
    lines.append("|---|---:|---:|---:|---|---|")
    for item in launches:
        metrics = item.get("screenshot_metrics") or {}
        status = "ok"
        if item.get("crash"):
            status = "crash in logcat"
        elif metrics.get("blank"):
            status = "blank screenshot"
        shot = Path(item["screenshot"]).name
        lines.append(
            "| {} {} | {}x{} | {} dpi | {} ms | `{}` | {} |".format(
                item["brand"],
                item["model"],
                item["width"],
                item["height"],
                item["density"],
                item.get("launch_ms", "n/a"),
                shot,
                status,
            )
        )
    lines.append("")
    if launch_times:
        lines.append(
            "Cold start across the ten profiles: min {} ms, mean {:.0f} ms, max {} ms.".format(
                min(launch_times), sum(launch_times) / len(launch_times), max(launch_times)
            )
        )
    lines.append("")
    lines.append("![Device matrix contact sheet](screenshots/devices/contact_sheet.png)")
    lines.append("")
    lines.append("## On-device predictions")
    lines.append("")
    lines.append("| Profile | Status | Results |")
    lines.append("|---|---|---|")
    for entry in predictions:
        lines.append(model_row(entry))
    lines.append("")
    if flat_models:
        for model_name in sorted({m["model"] for m in flat_models}):
            subset = [m for m in flat_models if m["model"] == model_name]
            means = [float(m["mean_ms"]) for m in subset]
            p95s = [float(m["p95_ms"]) for m in subset]
            loads = [int(m["load_ms"]) for m in subset]
            lines.append(
                "{}: {} successful profiles, mean latency {:.0f} ms, mean p95 {:.0f} ms, "
                "load {} to {} ms.".format(
                    model_name,
                    len(subset),
                    sum(means) / len(means),
                    sum(p95s) / len(p95s),
                    min(loads),
                    max(loads),
                )
            )
        lines.append("")
    lines.append("## What these numbers mean")
    lines.append("")
    lines.append("- The launch times include emulator and Flutter cold-start overhead. They are")
    lines.append("  useful for comparing display profiles on the same host, not as phone reviews.")
    lines.append("- The detector labels are the top results for the two fixed fixture images.")
    lines.append("  They check that both shipped models load and predict on every display profile.")
    lines.append("- The tuned YOLO11n model supports five appliance classes only. The app limits")
    lines.append("  scan targets to those classes when it is selected.")
    lines.append("- The physical Samsung A-series check reported earlier (0.4 to 1.0 s scheduling")
    lines.append("  delay) is separate from this matrix and remains user-reported.")
    lines.append("")
    lines.append("## Reproduce")
    lines.append("")
    lines.append("```powershell")
    lines.append("$env:GRADLE_USER_HOME='C:\\Users\\BRAVO\\.gradle'")
    lines.append("python tools\\run_device_matrix.py")
    lines.append("python tools\\report_device_matrix.py")
    lines.append("```")
    lines.append("")
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {REPORT_PATH}")


def main() -> None:
    if not JSON_PATH.exists():
        raise SystemExit(f"missing {JSON_PATH}; run tools/run_device_matrix.py first")
    payload = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    build_contact_sheet(payload.get("launches", []))
    build_report(payload)


if __name__ == "__main__":
    main()

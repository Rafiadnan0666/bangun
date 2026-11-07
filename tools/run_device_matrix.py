#!/usr/bin/env python3
"""Run the app and detector checks across ten brand-matched display profiles.

This is deliberately honest about what it measures. The host has one Android 17
emulator, not ten physical phones. Each profile uses a real phone's resolution
and density, so the run exercises layout, launch, and on-device inference under
those configurations. It does not prove physical-brand coverage.

Usage:
    python tools/run_device_matrix.py

Outputs:
    tools/results/device_matrix.json
    tools/results/device_matrix_logs/<profile>.log
    screenshots/devices/<profile>.png
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parents[1]
ADB = Path(r"C:\Users\BRAVO\AppData\Local\Android\Sdk\platform-tools\adb.exe")
EMULATOR = Path(r"C:\Users\BRAVO\AppData\Local\Android\Sdk\emulator\emulator.exe")
FLUTTER = Path(r"C:\src\flutter\bin\flutter.bat")
DEVICE = "emulator-5554"
AVD = "Medium_Phone_API_37.0"
PACKAGE = "com.example.bangun"
APK = ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
OUT_JSON = ROOT / "tools" / "results" / "device_matrix.json"
LOG_DIR = ROOT / "tools" / "results" / "device_matrix_logs"
SHOT_DIR = ROOT / "screenshots" / "devices"
EMULATOR_LOG = LOG_DIR / "emulator.log"
_EMULATOR_LOG_HANDLE = None

PROFILES = [
    ("samsung-galaxy-s23-ultra", "Samsung", "Galaxy S23 Ultra", 1440, 3088, 500),
    ("google-pixel-8-pro", "Google", "Pixel 8 Pro", 1344, 2992, 480),
    ("xiaomi-13-pro", "Xiaomi", "13 Pro", 1440, 3200, 522),
    ("oneplus-11", "OnePlus", "11", 1440, 3216, 525),
    ("oppo-find-x6-pro", "Oppo", "Find X6 Pro", 1440, 3168, 510),
    ("vivo-x90-pro", "Vivo", "X90 Pro", 1260, 2800, 453),
    ("huawei-p60-pro", "Huawei", "P60 Pro", 1220, 2700, 444),
    ("motorola-edge-40-pro", "Motorola", "Edge 40 Pro", 1080, 2400, 402),
    ("sony-xperia-1-v", "Sony", "Xperia 1 V", 1644, 3840, 643),
    ("asus-rog-phone-7", "Asus", "ROG Phone 7", 1656, 2340, 391),
]


def run(args: list[str], *, timeout: int = 120, check: bool = True, **kwargs) -> subprocess.CompletedProcess:
    result = subprocess.run(
        args,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        **kwargs,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stdout}\n{result.stderr}"
        )
    return result


def adb(*args: str, timeout: int = 120, check: bool = True) -> subprocess.CompletedProcess:
    return run([str(ADB), *args], timeout=timeout, check=check)


def device_online() -> bool:
    result = run([str(ADB), "devices"], timeout=30, check=False)
    return any(
        line.split("\t")[0] == DEVICE and line.endswith("device")
        for line in result.stdout.splitlines()
        if "\t" in line
    )


def wait_for_boot(timeout: int = 240) -> None:
    run([str(ADB), "wait-for-device"], timeout=timeout)
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = adb("shell", "getprop", "sys.boot_completed", check=False)
        if result.stdout.strip() == "1":
            return
        time.sleep(3)
    raise RuntimeError("emulator did not finish booting")


def stop_stale_emulator() -> None:
    adb("emu", "kill", check=False, timeout=15)
    time.sleep(2)
    listing = run(
        ["tasklist", "/FI", "IMAGENAME eq qemu-system-x86_64"],
        timeout=30,
        check=False,
    )
    if "qemu-system-x86_64" in listing.stdout:
        run(
            ["taskkill", "/F", "/IM", "qemu-system-x86_64"],
            timeout=30,
            check=False,
        )
    run([str(ADB), "kill-server"], timeout=30, check=False)


def ensure_device() -> bool:
    """Returns True when the emulator had to be restarted."""
    if device_online():
        return False
    print("[device] emulator missing; restarting", flush=True)
    stop_stale_emulator()
    time.sleep(5)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    flags = 0
    if os.name == "nt":
        flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    global _EMULATOR_LOG_HANDLE
    _EMULATOR_LOG_HANDLE = open(EMULATOR_LOG, "a", encoding="utf-8", errors="replace")
    _EMULATOR_LOG_HANDLE.write("\n--- starting emulator ---\n")
    _EMULATOR_LOG_HANDLE.flush()
    process = subprocess.Popen(
        [
            str(EMULATOR),
            "-avd",
            AVD,
            "-no-snapshot",
            "-no-audio",
            "-no-boot-anim",
            "-no-window",
            "-memory",
            "2048",
            "-cores",
            "4",
            "-gpu",
            "swiftshader_indirect",
        ],
        cwd=ROOT,
        stdout=_EMULATOR_LOG_HANDLE,
        stderr=subprocess.STDOUT,
        creationflags=flags,
    )
    time.sleep(8)
    if process.poll() is not None:
        tail = EMULATOR_LOG.read_text(encoding="utf-8", errors="replace")[-2000:]
        raise RuntimeError(f"emulator exited during startup:\n{tail}")
    wait_for_boot()
    print("[device] emulator booted", flush=True)
    return True


def install_app() -> None:
    adb("install", "-r", str(APK), timeout=300)
    adb("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS", check=False)
    adb("shell", "pm", "grant", PACKAGE, "android.permission.CAMERA", check=False)


def set_profile(width: int, height: int, density: int) -> None:
    adb("shell", "wm", "size", f"{width}x{height}")
    adb("shell", "wm", "density", str(density))


def reset_display() -> None:
    adb("shell", "wm", "size", "reset", check=False)
    adb("shell", "wm", "density", "reset", check=False)


def screenshot_metrics(path: Path) -> dict:
    with Image.open(path) as image:
        rgb = image.convert("RGB")
        stat = ImageStat.Stat(rgb)
        mean = [round(v, 2) for v in stat.mean]
        stddev = [round(v, 2) for v in stat.stddev]
        colors = rgb.resize((64, 64)).getcolors(64 * 64)
        return {
            "width": image.width,
            "height": image.height,
            "mean_rgb": mean,
            "stddev_rgb": stddev,
            "sampled_colors": len(colors) if colors else 0,
            "blank": max(stddev) < 2.0,
        }


def launch_profile(slug: str, brand: str, model: str, width: int, height: int, density: int) -> dict:
    label = f"{brand} {model} ({width}x{height} @ {density} dpi)"
    print(f"[launch] {label}", flush=True)
    set_profile(width, height, density)
    adb("shell", "am", "force-stop", PACKAGE)
    adb("logcat", "-c", check=False)
    time.sleep(1.5)
    started = adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity")
    total = re.search(r"TotalTime:\s*(\d+)", started.stdout)
    time.sleep(3)
    remote = f"/sdcard/awake_{slug}.png"
    local = SHOT_DIR / f"{slug}.png"
    adb("shell", "screencap", "-p", remote)
    adb("pull", remote, str(local))
    logcat = adb("logcat", "-d", "-v", "brief", check=False).stdout
    crash = bool(re.search(r"FATAL EXCEPTION|Fatal signal", logcat))
    return {
        "profile": slug,
        "brand": brand,
        "model": model,
        "width": width,
        "height": height,
        "density": density,
        "launch_ms": int(total.group(1)) if total else None,
        "activity": "com.example.bangun/.MainActivity",
        "crash": crash,
        "screenshot": str(local.relative_to(ROOT)),
        "screenshot_metrics": screenshot_metrics(local),
    }


def failed_profile(profile: tuple, error: object) -> dict:
    slug, brand, model, width, height, density = profile
    return {
        "profile": slug,
        "brand": brand,
        "model": model,
        "width": width,
        "height": height,
        "density": density,
        "launch_ms": None,
        "activity": "com.example.bangun/.MainActivity",
        "crash": True,
        "screenshot": None,
        "screenshot_metrics": {},
        "error": str(error)[-2000:],
    }


def parse_ondevice(log: str) -> list[dict]:
    rows = []
    for line in log.splitlines():
        marker = line.find("ONDEVICE ")
        if marker < 0:
            continue
        payload = line[marker + len("ONDEVICE ") :].strip()
        try:
            rows.append(json.loads(payload))
        except json.JSONDecodeError:
            continue
    return rows


def benchmark_profile(slug: str, brand: str, model: str, width: int, height: int, density: int) -> dict:
    label = f"{brand} {model} {width}x{height}@{density}"
    print(f"[predict] {label}", flush=True)
    set_profile(width, height, density)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    # Dart defines cannot contain spaces unless the whole argument is quoted by
    # the shell; use the slug so PowerShell cannot split the label into extra
    # test paths.
    profile_id = f"{slug}-{width}x{height}@{density}"
    command = (
        f'"{FLUTTER}" test integration_test\\detector_benchmark_test.dart '
        f'-d {DEVICE} --dart-define=PROFILE={profile_id} --dart-define=BENCH_ITERS=3'
    )
    env = dict(os.environ)
    env["GRADLE_USER_HOME"] = r"C:\Users\BRAVO\.gradle"
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            shell=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=900,
            env=env,
        )
        log = result.stdout + result.stderr
        (LOG_DIR / f"{slug}.log").write_text(log, encoding="utf-8")
        rows = parse_ondevice(log)
        return {
            "profile": slug,
            "brand": brand,
            "model": model,
            "width": width,
            "height": height,
            "density": density,
            "exit_code": result.returncode,
            "models": rows,
            "error": None if rows else log[-2000:],
        }
    except subprocess.TimeoutExpired as error:
        (LOG_DIR / f"{slug}.log").write_text(str(error), encoding="utf-8")
        return {
            "profile": slug,
            "brand": brand,
            "model": model,
            "width": width,
            "height": height,
            "density": density,
            "exit_code": None,
            "models": [],
            "error": "timeout",
        }


def save(payload: dict) -> None:
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> None:
    if not ADB.exists():
        raise SystemExit(f"adb not found: {ADB}")
    if not EMULATOR.exists():
        raise SystemExit(f"emulator not found: {EMULATOR}")
    if not FLUTTER.exists():
        raise SystemExit(f"flutter not found: {FLUTTER}")
    if not APK.exists():
        raise SystemExit(f"release APK not found: {APK}")

    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    payload = {
        "host": "AMD Ryzen 5 7535HS, 16 GB RAM, Windows 11, WHPX",
        "device": "Android 17 (API 37) x86_64 emulator, not physical hardware",
        "apk": str(APK.relative_to(ROOT)),
        "disclaimer": (
            "Brand-matched display profiles on one emulator. These are not "
            "physical phones from each brand; they validate layout, launch, "
            "and detector behavior under each resolution and density."
        ),
        "launches": [],
        "predictions": [],
    }

    try:
        restarted = ensure_device()
        if restarted:
            time.sleep(5)
        print("[setup] installing release APK", flush=True)
        install_app()

        for profile in PROFILES:
            result = None
            for attempt in (1, 2):
                try:
                    ensure_device()
                    result = launch_profile(*profile)
                    break
                except Exception as error:  # noqa: BLE001 - keep the matrix moving
                    print(f"[launch] attempt {attempt} failed: {error}", flush=True)
                    if attempt == 1:
                        stop_stale_emulator()
                        ensure_device()
                        install_app()
            payload["launches"].append(result or failed_profile(profile, "launch failed"))
            save(payload)

        for profile in PROFILES:
            result = None
            for attempt in (1, 2):
                try:
                    ensure_device()
                    result = benchmark_profile(*profile)
                    if result.get("models"):
                        break
                    print("[predict] no benchmark output; retrying once", flush=True)
                except Exception as error:  # noqa: BLE001
                    print(f"[predict] attempt {attempt} failed: {error}", flush=True)
                if attempt == 1 and not device_online():
                    stop_stale_emulator()
                    ensure_device()
            if result is None:
                result = {
                    "profile": profile[0],
                    "brand": profile[1],
                    "model": profile[2],
                    "width": profile[3],
                    "height": profile[4],
                    "density": profile[5],
                    "exit_code": None,
                    "models": [],
                    "error": "benchmark failed",
                }
            payload["predictions"].append(result)
            save(payload)
    finally:
        try:
            ensure_device()
            reset_display()
        except Exception as error:  # noqa: BLE001
            print(f"[cleanup] display reset failed: {error}", flush=True)
        save(payload)
        print(f"[done] wrote {OUT_JSON}", flush=True)
        print("[setup] reinstalling release APK", flush=True)
        try:
            ensure_device()
            install_app()
            adb("shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity", check=False)
        except Exception as error:  # noqa: BLE001
            print(f"[cleanup] reinstall failed: {error}", flush=True)


if __name__ == "__main__":
    main()

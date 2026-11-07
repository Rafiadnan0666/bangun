#!/usr/bin/env python3
"""Refresh only the launch/screenshot half of the device matrix.

Use this after rebuilding the release APK with UI changes. It keeps the
prediction rows already stored in tools/results/device_matrix.json.

Usage:
    python tools/refresh_launch_matrix.py
"""
from __future__ import annotations

import json

import run_device_matrix as matrix


def main() -> None:
    if not matrix.OUT_JSON.exists():
        raise SystemExit("run tools/run_device_matrix.py first")
    payload = json.loads(matrix.OUT_JSON.read_text(encoding="utf-8"))
    matrix.ensure_device()
    matrix.install_app()
    launches = []
    try:
        for profile in matrix.PROFILES:
            launches.append(matrix.launch_profile(*profile))
            payload["launches"] = launches
            matrix.save(payload)
    finally:
        matrix.reset_display()
        matrix.save(payload)
        matrix.install_app()
        matrix.adb(
            "shell",
            "am",
            "start",
            "-n",
            f"{matrix.PACKAGE}/.MainActivity",
            check=False,
        )
        print(f"refreshed {len(launches)} launch profiles", flush=True)


if __name__ == "__main__":
    main()

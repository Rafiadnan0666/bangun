#!/usr/bin/env python3
"""Refresh only the on-device prediction half of the device matrix.

Keeps the launch rows already stored in tools/results/device_matrix.json.

Usage:
    python tools/refresh_predictions_matrix.py
"""
from __future__ import annotations

import json

import run_device_matrix as matrix


def main() -> None:
    if not matrix.OUT_JSON.exists():
        raise SystemExit("run tools/run_device_matrix.py first")
    payload = json.loads(matrix.OUT_JSON.read_text(encoding="utf-8"))
    matrix.ensure_device()
    predictions = []
    try:
        for profile in matrix.PROFILES:
            predictions.append(matrix.benchmark_profile(*profile))
            payload["predictions"] = predictions
            matrix.save(payload)
    finally:
        matrix.save(payload)
        matrix.ensure_device()
        matrix.reset_display()
        matrix.install_app()
        matrix.adb(
            "shell",
            "am",
            "start",
            "-n",
            f"{matrix.PACKAGE}/.MainActivity",
            check=False,
        )
        print(f"refreshed {len(predictions)} prediction profiles", flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Evaluate the two shipped on-device detectors against COCO appliance labels.

The app bundles:
  * SSD MobileNet v1 (COCO, uint8 300x300, four post-NMS outputs)
  * YOLO11n tuned on five home appliances (float32 416x416, one output)

This script mirrors the app preprocessing and postprocessing in Python, then
reports mAP@0.5, gate recall at the app confidence cutoffs, and CPU latency on
the held-out COCO appliance validation split.

Example:
  python tools/evaluate_detectors.py \
      --images C:/Users/BRAVO/Downlo/hh/awake/dataset/coco_real/val/images \
      --labels C:/Users/BRAVO/Downlo/hh/awake/dataset/coco_real/val/labels

No images are copied into the repository. If the dataset is not available,
pass any directory of images and use --limit.
"""
from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image, ImageOps
import tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "assets" / "models"
APPLIANCE_NAMES = ["microwave", "oven", "toaster", "hair drier", "refrigerator"]


def read_labels(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def square_crop(image: Image.Image, size: int) -> Image.Image:
    """Match the app: center-crop a square, then resize to the model input."""
    return ImageOps.fit(image.convert("RGB"), (size, size), method=Image.Resampling.BILINEAR)


def iou(a: Iterable[float], b: Iterable[float]) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    union = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1) + max(
        0.0, bx2 - bx1
    ) * max(0.0, by2 - by1) - inter
    return inter / union if union > 0 else 0.0


def nms(predictions: list[dict], iou_threshold: float, limit: int = 100) -> list[dict]:
    kept: list[dict] = []
    for candidate in sorted(predictions, key=lambda p: p["score"], reverse=True):
        if any(iou(candidate["box"], other["box"]) > iou_threshold for other in kept):
            continue
        kept.append(candidate)
        if len(kept) >= limit:
            break
    return kept


def load_ground_truth(labels_dir: Path, images_dir: Path) -> dict[str, list[dict]]:
    gt: dict[str, list[dict]] = {}
    for label_path in sorted(labels_dir.glob("*.txt")):
        image_path = images_dir / f"{label_path.stem}.jpg"
        if not image_path.exists():
            continue
        with Image.open(image_path) as image:
            width, height = image.size
        boxes = []
        for line in label_path.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) != 5:
                continue
            cls, cx, cy, bw, bh = parts
            cx, cy, bw, bh = map(float, (cx, cy, bw, bh))
            boxes.append(
                {
                    "class": APPLIANCE_NAMES[int(cls)],
                    "box": [
                        (cx - bw / 2) * width,
                        (cy - bh / 2) * height,
                        (cx + bw / 2) * width,
                        (cy + bh / 2) * height,
                    ],
                }
            )
        if boxes:
            gt[label_path.stem] = boxes
    return gt


def load_ssd() -> tuple[tf.lite.Interpreter, dict, dict]:
    interpreter = tf.lite.Interpreter(
        model_path=str(MODELS / "coco_ssd_mobilenet_v1_1.0_quant.tflite"),
        num_threads=4,
    )
    interpreter.allocate_tensors()
    return interpreter, interpreter.get_input_details()[0], interpreter.get_output_details()


def load_yolo() -> tuple[tf.lite.Interpreter, dict, dict]:
    interpreter = tf.lite.Interpreter(
        model_path=str(MODELS / "yolo11n_awake_appliance.tflite"),
        num_threads=4,
    )
    interpreter.allocate_tensors()
    return interpreter, interpreter.get_input_details()[0], interpreter.get_output_details()[0]


def run_ssd(
    interpreter: tf.lite.Interpreter,
    input_detail: dict,
    output_details: list[dict],
    image: Image.Image,
    coco_labels: list[str],
) -> list[dict]:
    size = int(input_detail["shape"][1])
    rgb = np.asarray(square_crop(image, size), dtype=np.uint8)
    interpreter.set_tensor(input_detail["index"], rgb[None, ...])
    interpreter.invoke()

    boxes = interpreter.get_tensor(output_details[0]["index"])[0]
    classes = interpreter.get_tensor(output_details[1]["index"])[0]
    scores = interpreter.get_tensor(output_details[2]["index"])[0]
    count = int(interpreter.get_tensor(output_details[3]["index"])[0])

    found = []
    for box, class_id, score in zip(boxes[:count], classes[:count], scores[:count]):
        if score < 0.01:
            continue
        index = int(class_id) + 1
        if index <= 0 or index >= len(coco_labels):
            continue
        label = coco_labels[index]
        if label not in APPLIANCE_NAMES:
            continue
        # SSD output: yMin, xMin, yMax, xMax on the square input.
        found.append(
            {
                "class": label,
                "score": float(score),
                "box": [float(box[1]), float(box[0]), float(box[3]), float(box[2])],
            }
        )
    return found


def run_yolo(
    interpreter: tf.lite.Interpreter,
    input_detail: dict,
    output_detail: dict,
    image: Image.Image,
) -> list[dict]:
    size = int(input_detail["shape"][1])
    rgb = np.asarray(square_crop(image, size), dtype=np.float32) / 255.0
    interpreter.set_tensor(input_detail["index"], rgb[None, ...])
    interpreter.invoke()
    raw = interpreter.get_tensor(output_detail["index"])[0].T  # [anchors, 4 + classes]

    found = []
    for row in raw:
        class_id = int(np.argmax(row[4:]))
        score = float(row[4 + class_id])
        if score < 0.01:
            continue
        cx, cy, bw, bh = map(float, row[:4])
        if max(abs(cx), abs(cy), abs(bw), abs(bh)) > 2.0:
            cx, cy, bw, bh = cx / size, cy / size, bw / size, bh / size
        box = [cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2]
        found.append(
            {"class": APPLIANCE_NAMES[class_id], "score": score, "box": box}
        )
    return nms(found, iou_threshold=0.45, limit=10)


def scale_boxes(predictions: list[dict], width: int, height: int) -> list[dict]:
    for prediction in predictions:
        x1, y1, x2, y2 = prediction["box"]
        prediction["box"] = [x1 * width, y1 * height, x2 * width, y2 * height]
    return predictions


def average_precision(
    ground_truth: dict[str, list[dict]],
    predictions: dict[str, list[dict]],
    class_name: str,
) -> float:
    positives = sum(
        1 for boxes in ground_truth.values() for box in boxes if box["class"] == class_name
    )
    if positives == 0:
        return float("nan")

    scored = []
    for stem, detections in predictions.items():
        for detection in detections:
            if detection["class"] == class_name:
                scored.append((detection["score"], stem, detection["box"]))
    scored.sort(key=lambda item: item[0], reverse=True)

    matched: set[tuple[str, int]] = set()
    tp: list[int] = []
    fp: list[int] = []
    for _, stem, box in scored:
        best_iou = 0.0
        best_index = -1
        for index, truth in enumerate(ground_truth.get(stem, [])):
            if truth["class"] != class_name or (stem, index) in matched:
                continue
            overlap = iou(box, truth["box"])
            if overlap > best_iou:
                best_iou = overlap
                best_index = index
        if best_iou >= 0.5 and best_index >= 0:
            matched.add((stem, best_index))
            tp.append(1)
            fp.append(0)
        else:
            tp.append(0)
            fp.append(1)

    if not scored:
        return 0.0

    tp_cum = np.cumsum(tp)
    fp_cum = np.cumsum(fp)
    recall = tp_cum / positives
    precision = tp_cum / np.maximum(tp_cum + fp_cum, 1e-9)
    # 101-point interpolated AP, the same convention as COCO's mAP@0.5.
    points = np.linspace(0, 1, 101)
    sampled = [
        float(np.max(precision[recall >= point])) if np.any(recall >= point) else 0.0
        for point in points
    ]
    return float(np.mean(sampled))


def gate_recall(
    ground_truth: dict[str, list[dict]],
    predictions: dict[str, list[dict]],
    threshold: float,
) -> dict[str, float | int]:
    hits = total = 0
    for stem, truths in ground_truth.items():
        detections = [p for p in predictions.get(stem, []) if p["score"] >= threshold]
        for truth in truths:
            total += 1
            if any(
                detection["class"] == truth["class"]
                and iou(detection["box"], truth["box"]) >= 0.5
                for detection in detections
            ):
                hits += 1
    return {
        "recall": hits / total if total else 0.0,
        "hits": hits,
        "ground_truth": total,
    }


def benchmark(model_name: str, run, interpreter, image_paths: list[Path], **kwargs) -> dict:
    # Warm up the interpreter, then time end-to-end preprocessing + inference +
    # postprocessing for every image.
    for path in image_paths[:3]:
        with Image.open(path) as image:
            run(interpreter, image=image, **kwargs)
    latencies = []
    predictions = {}
    for path in image_paths:
        with Image.open(path) as image:
            width, height = image.size
            started = time.perf_counter()
            raw = run(interpreter, image=image, **kwargs)
            latencies.append((time.perf_counter() - started) * 1000.0)
            predictions[path.stem] = scale_boxes(raw, width, height)

    per_class_ap = {
        name: average_precision(kwargs["ground_truth"], predictions, name)
        for name in APPLIANCE_NAMES
    }
    valid_ap = [value for value in per_class_ap.values() if not math.isnan(value)]
    return {
        "model": model_name,
        "images": len(image_paths),
        "instances": sum(len(v) for v in kwargs["ground_truth"].values()),
        "mAP_50": float(np.mean(valid_ap)) if valid_ap else None,
        "per_class_AP_50": per_class_ap,
        "gate_recall": {
            str(threshold): gate_recall(
                kwargs["ground_truth"], predictions, threshold
            )
            for threshold in (0.4, 0.45, 0.5, 0.6, 0.7)
        },
        "latency_mean_ms": float(np.mean(latencies)),
        "latency_p95_ms": float(np.percentile(latencies, 95)),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--images",
        type=Path,
        default=Path(r"C:\Users\BRAVO\Downlo\hh\awake\dataset\coco_real\val\images"),
    )
    parser.add_argument(
        "--labels",
        type=Path,
        default=Path(r"C:\Users\BRAVO\Downlo\hh\awake\dataset\coco_real\val\labels"),
    )
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "tools" / "results" / "detector_eval.json",
    )
    args = parser.parse_args()

    if not args.images.exists() or not args.labels.exists():
        raise SystemExit(f"dataset not found: {args.images} / {args.labels}")

    ground_truth = load_ground_truth(args.labels, args.images)
    stems = sorted(ground_truth)
    if args.limit:
        stems = stems[: args.limit]
    image_paths = [args.images / f"{stem}.jpg" for stem in stems]
    ground_truth = {stem: ground_truth[stem] for stem in stems}

    coco_labels = read_labels(MODELS / "labels.txt")
    yolo_labels = read_labels(MODELS / "yolo_labels.txt")
    if yolo_labels != APPLIANCE_NAMES:
        raise SystemExit(f"unexpected YOLO labels: {yolo_labels}")

    print(f"Evaluating {len(image_paths)} images...")
    ssd_interpreter, ssd_input, ssd_outputs = load_ssd()
    ssd_results = benchmark(
        "SSD MobileNet v1",
        lambda interpreter, image, **_: run_ssd(
            interpreter, ssd_input, ssd_outputs, image, coco_labels
        ),
        ssd_interpreter,
        image_paths,
        ground_truth=ground_truth,
    )

    yolo_interpreter, yolo_input, yolo_output = load_yolo()
    yolo_results = benchmark(
        "YOLO11n tuned (5 appliance classes)",
        lambda interpreter, image, **_: run_yolo(
            interpreter, yolo_input, yolo_output, image
        ),
        yolo_interpreter,
        image_paths,
        ground_truth=ground_truth,
    )

    payload = {"dataset": str(args.images.parent), "models": [ssd_results, yolo_results]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()

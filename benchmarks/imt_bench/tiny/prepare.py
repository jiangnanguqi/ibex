#!/usr/bin/env python3
"""Fetch pinned upstream sources and generate model/real-input C++ assets."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

TINY_COMMIT = "4addd0fa08d216e20637637874e084895f289da4"
TFLM_COMMIT = "4bb5a53e417b597ce5c2af2079aa8c42eb5fe9da"
MODEL_PATH = "benchmark/training/anomaly_detection/trained_models/ad01_int8.tflite"
INPUT_PATH = ("benchmark/reference_submissions/anomaly_detection/datasets/dcase01/"
              "normal_id_01_00000000_hist_librosa.bin")
MODEL_SHA256 = "87cf24194ef93d1d9b11a591d805526b98008e351655d29883c825c9c106ba24"
INPUT_SHA256 = "31bc130d27e3732e1c09db946ccc7bfa130f98739bcd90cfa39d590f61f4d6fa"
FRAME_STARTS = (0, 80, 160)


def write_if_changed(path, content):
    data = content.encode()
    if not path.exists() or path.read_bytes() != data:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def repository(path, url, commit):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", str(path)], check=True, stdout=sys.stderr)
        subprocess.run(["git", "-C", str(path), "remote", "add", "origin", url], check=True)
        subprocess.run(["git", "-C", str(path), "fetch", "--depth=1", "origin", commit], check=True)
        subprocess.run(["git", "-C", str(path), "checkout", "--detach", "FETCH_HEAD"], check=True)
    actual = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
    if actual != commit:
        raise RuntimeError(f"{path}: expected revision {commit}, found {actual}; directory not changed")
    if subprocess.run(["git", "-C", str(path), "diff", "--quiet", "HEAD", "--"]).returncode:
        raise RuntimeError(f"{path}: tracked upstream files have local changes; directory not changed")


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tiny-dir", type=Path, default=here / ".deps/tiny")
    parser.add_argument("--tflm-dir", type=Path, default=here / ".deps/tflm")
    parser.add_argument("--build-dir", type=Path, default=here / "build")
    args = parser.parse_args()
    args.tiny_dir = args.tiny_dir.resolve()
    args.tflm_dir = args.tflm_dir.resolve()
    args.build_dir = args.build_dir.resolve()
    repository(args.tiny_dir, "https://github.com/mlcommons/tiny.git", TINY_COMMIT)
    repository(args.tflm_dir, "https://github.com/tensorflow/tflite-micro.git", TFLM_COMMIT)
    subprocess.run([sys.executable,
                    "tensorflow/lite/micro/tools/make/download_dependencies.py",
                    "flatbuffers"], cwd=args.tflm_dir, check=True)
    model = (args.tiny_dir / MODEL_PATH).read_bytes()
    samples = (args.tiny_dir / INPUT_PATH).read_bytes()
    for name, data, expected in (("model", model, MODEL_SHA256),
                                  ("input", samples, INPUT_SHA256)):
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f"{name} SHA256 does not match the pinned asset")
    source = ['// Generated from MLCommons Tiny; upstream license: Apache-2.0.',
              '#include "assets.h"', 'namespace imt_tiny {',
              'alignas(16) const unsigned char kModelData[] = {']
    source.extend(",".join(f"0x{v:02x}" for v in model[i:i+16]) + ","
                  for i in range(0, len(model), 16))
    source += ['};', f'const size_t kModelBytes = {len(model)};', '}']
    write_if_changed(args.build_dir / "model_data.cc", "\n".join(source) + "\n")
    source = ['// Real ToyCar spectrogram windows; original IEEE-754 FP32 bits.',
              '#include "assets.h"', 'namespace imt_tiny {',
              'const uint32_t kInputBits[kFixtureCount][kInputElements] = {']
    for start in FRAME_STARTS:
        offset = start * 128 * 4
        values = struct.unpack("<640I", samples[offset:offset + 640 * 4])
        source += ['{']
        source.extend(",".join(f"0x{v:08x}u" for v in values[i:i+8]) + ","
                      for i in range(0, 640, 8))
        source += ['},']
    source += ['};', '}']
    write_if_changed(args.build_dir / "input_data.cc", "\n".join(source) + "\n")
    metadata = dict(tiny_commit=TINY_COMMIT, tflm_commit=TFLM_COMMIT,
                    model_path=MODEL_PATH, model_sha256=MODEL_SHA256,
                    input_path=INPUT_PATH, input_sha256=INPUT_SHA256,
                    model_bytes=len(model), first_frames=list(FRAME_STARTS),
                    input_elements=640, fixture_count=3)
    write_if_changed(args.build_dir / "assets.json", json.dumps(metadata, indent=2) + "\n")
    print(f"Prepared ad01: {len(model)} model bytes; three real 640-element windows")


if __name__ == "__main__":
    main()


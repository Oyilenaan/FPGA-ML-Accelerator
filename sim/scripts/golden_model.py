#!/usr/bin/env python3
"""
golden_model.py — CNN Layer Golden Model
=========================================
Performs the exact same 3x3 convolution + ReLU that the Verilog does,
using integer (fixed-point) arithmetic to match hardware bit-for-bit.

Outputs two .hex files:
  sim/inputs.hex   — test pixel windows + weights (one vector per line)
  sim/expected.hex — expected 8-bit ReLU outputs (one result per line)

Usage:
  python3 sim/scripts/golden_model.py
"""

import numpy as np
import os

# ---------------------------------------------------------------------------
# Parameters (must match Verilog parameters)
# ---------------------------------------------------------------------------
DATA_WIDTH  = 8
ACC_WIDTH   = 20
KERNEL_SIZE = 3   # 3x3

SAT_MAX = (1 << DATA_WIDTH) - 1   # 255

# ---------------------------------------------------------------------------
# Fixed-point convolution + ReLU (mirrors Verilog exactly)
# ---------------------------------------------------------------------------
def conv3x3_relu(pixel_window, kernel):
    """
    pixel_window : list/array of 9 uint8 values (row-major)
    kernel       : list/array of 9 uint8 values
    returns      : uint8 result after accumulation + ReLU + saturation
    """
    acc = 0
    for p, w in zip(pixel_window, kernel):
        acc += int(p) * int(w)   # unsigned multiply, accumulate

    # Treat accumulator as signed (two's complement, ACC_WIDTH bits)
    if acc >= (1 << (ACC_WIDTH - 1)):
        acc -= (1 << ACC_WIDTH)

    # ReLU
    if acc < 0:
        return 0
    # Saturate
    return min(acc, SAT_MAX)

# ---------------------------------------------------------------------------
# Generate test vectors
# ---------------------------------------------------------------------------
def generate_test_vectors(n=256, seed=42):
    rng = np.random.default_rng(seed)

    # Fixed kernel (same one hardcoded in the testbench for easy comparison)
    kernel = np.array([1, 0, 255, 0, 4, 0, 255, 0, 1], dtype=np.uint8)

    pixel_windows = rng.integers(0, 256, size=(n, 9), dtype=np.uint8)
    results = []
    for pw in pixel_windows:
        results.append(conv3x3_relu(pw, kernel))

    return pixel_windows, kernel, results

# ---------------------------------------------------------------------------
# Write .hex files
# ---------------------------------------------------------------------------
def write_hex_files(pixel_windows, kernel, results, out_dir="sim"):
    os.makedirs(out_dir, exist_ok=True)

    # inputs.hex: each line = 9 pixel bytes + 9 weight bytes, space separated
    with open(os.path.join(out_dir, "inputs.hex"), "w") as f:
        for pw in pixel_windows:
            pixels_hex  = " ".join(f"{v:02x}" for v in pw)
            weights_hex = " ".join(f"{v:02x}" for v in kernel)
            f.write(f"{pixels_hex}  {weights_hex}\n")

    # expected.hex: one 8-bit result per line
    with open(os.path.join(out_dir, "expected.hex"), "w") as f:
        for r in results:
            f.write(f"{r:02x}\n")

    print(f"[golden_model] Wrote {len(results)} test vectors.")
    print(f"  → sim/inputs.hex")
    print(f"  → sim/expected.hex")
    print(f"  Kernel used: {list(kernel)}")

# ---------------------------------------------------------------------------
# Quick sanity check
# ---------------------------------------------------------------------------
def sanity_check():
    # Hand-calculated: pixel=[1,1,1,1,1,1,1,1,1], kernel=[1,0,255,0,4,0,255,0,1]
    # acc = 1+0+255+0+4+0+255+0+1 = 516, > SAT_MAX=255, so result = 255
    pw = [1]*9
    k  = [1, 0, 255, 0, 4, 0, 255, 0, 1]
    r  = conv3x3_relu(pw, k)
    assert r == 255, f"Sanity check failed: got {r}"

    # pixel=all zeros → result = 0
    r2 = conv3x3_relu([0]*9, k)
    assert r2 == 0, f"Sanity check failed: got {r2}"

    print("[golden_model] Sanity checks passed.")

if __name__ == "__main__":
    sanity_check()
    pixel_windows, kernel, results = generate_test_vectors(n=256)
    write_hex_files(pixel_windows, kernel, results)

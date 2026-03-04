# FPGA CNN Convolution IP Core

A parameterised, synthesisable 3×3 convolution engine written in Verilog — the core compute primitive of CNN accelerators. Designed with production hardware in mind: pipelined MAC unit, AXI-Stream interface, and a self-checking verification suite with a Python golden model.

---

## Architecture Overview

```
                        ┌─────────────────────────────────────────┐
                        │           cnn_layer_axis.v               │
                        │  (AXI-Stream wrapper)                    │
                        │                                          │
  AXI-S Slave ─────────►│  18-byte packet                         │
  [pixels + weights]    │  (9 pixels, 9 weights)                   │
                        │         │                                │
                        │         ▼                                │
                        │  ┌─────────────┐                         │
                        │  │ cnn_layer.v │  valid/ready handshake  │
                        │  │  (top-level)│                         │
                        │  └──────┬──────┘                         │
                        │         │                                │
                        │  ┌──────▼──────┐                         │
                        │  │  conv3x3.v  │  serialises 9 taps      │
                        │  └──────┬──────┘                         │
                        │         │  one tap/cycle                 │
                        │  ┌──────▼──────┐                         │
                        │  │  mac_pe.v   │  3-stage pipeline       │
                        │  │ Stage 1: Reg│  Fmax-optimised         │
                        │  │ Stage 2: Mul│                         │
                        │  │ Stage 3: Acc│                         │
                        │  └──────┬──────┘                         │
                        │         │                                │
                        │  ┌──────▼──────┐                         │
                        │  │   relu.v    │  saturating ReLU        │
                        │  └──────┬──────┘                         │
                        │         │                                │
  AXI-S Master ◄────────│  1-byte result                          │
  [result]              │                                          │
                        └─────────────────────────────────────────┘
```

**Pipeline latency:** 9 cycles (serialise) + 3 cycles (MAC pipeline) + 1 cycle (ReLU) = **13 clock cycles**

---

## Module Hierarchy

| Module | Description |
|---|---|
| `cnn_layer_axis.v` | AXI-Stream wrapper — SoC-ready top-level |
| `cnn_layer.v` | Top-level core with valid/ready handshaking |
| `conv3x3.v` | 3×3 convolution engine, serialises 9 MAC operations |
| `mac_pe.v` | 3-stage pipelined Multiply-Accumulate Processing Element |
| `relu.v` | Parameterised ReLU with output saturation |

---

## Key Design Decisions

### Pipelined MAC Unit
The MAC PE uses a 3-stage pipeline (register inputs → multiply → accumulate) to maximise clock frequency. A `last_in` signal propagates through all pipeline stages so `valid_out` fires exactly once per convolution — only after the final accumulation has cleared the pipeline.

### Fixed-Point Arithmetic
All computation uses unsigned 8-bit fixed-point (`Q8.0`) inputs with a 20-bit accumulator. The accumulator width is chosen to prevent overflow: `ceil(log2(9 × 255 × 255)) = 20 bits`. The ReLU module performs saturating truncation back to 8-bit output.

### AXI-Stream Interface
The `cnn_layer_axis` wrapper accepts a standard 18-byte AXI-Stream packet (9 pixel bytes followed by 9 weight bytes, `TLAST` on byte 17) and produces a 1-byte result packet. This makes the core directly integrable with Xilinx DMA IP or a Zynq PS without any glue logic.

### Valid/Ready Handshaking
The core uses a `valid_in` / `ready_out` / `valid_out` protocol throughout. `ready_out` deasserts while a convolution is in flight, providing natural backpressure.

---

## Verification

The project uses a **two-layer verification strategy**:

### Python Golden Model (`sim/scripts/golden_model.py`)
A NumPy reference implementation performs the identical integer convolution + ReLU in software and exports results to `sim/expected.hex`. This is the ground truth.

```bash
python3 sim/scripts/golden_model.py
# → sim/inputs.hex   (256 test vectors)
# → sim/expected.hex (256 expected results)
```

### Self-Checking Testbench (`sim/testbench.v`)
The Verilog testbench reads both hex files, drives the DUT, and automatically compares every output:

```
PASS [idx 042]: expected=e0  got=e0
PASS [idx 043]: expected=9b  got=9b
...
=============================================
RESULT: 256/256 tests PASSED.
=============================================
```

Test coverage: **256 vectors, 114 unique output values** — covering the full non-saturating output range.

---

## Running the Simulation

**Requirements:** Python 3 + NumPy, [Icarus Verilog](http://iverilog.icarus.com) (v10+)

```bash
# 1. Clone
git clone https://github.com/Oyilenaan/FPGA-ML-Accelerator.git
cd FPGA-ML-Accelerator

# 2. Generate test vectors from golden model
python3 sim/scripts/golden_model.py

# 3. Compile
iverilog -o sim/sim.out \
  src/mac_pe.v src/conv3x3.v src/relu.v src/cnn_layer.v \
  sim/testbench.v

# 4. Run
vvp sim/sim.out

# 5. (Optional) View waveforms
gtkwave sim/waveform.vcd
```

For the AXI-Stream testbench:
```bash
iverilog -o sim/sim_axis.out \
  src/mac_pe.v src/conv3x3.v src/relu.v src/cnn_layer.v src/cnn_layer_axis.v \
  sim/tb_axis.v
vvp sim/sim_axis.out
```

---

## Parameters

All modules are parameterised for easy adaptation:

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Pixel and weight bit width |
| `ACC_WIDTH` | 20 | Accumulator bit width |
| `KERNEL_SIZE` | 9 | Number of MAC operations (3×3) |

---

## Resource Utilisation (Estimated)

Target device: **Xilinx Artix-7 XC7A35T**

| Resource | Estimated Usage | Available |
|---|---|---|
| LUTs | ~120 | 20,800 |
| FFs | ~80 | 41,600 |
| DSP48E1 | 1 | 90 |
| BRAM | 0 | 50 |

> *Note: Run `vivado -mode batch -source synth.tcl` to generate exact post-synthesis numbers. Synthesis scripts to be added.*

---

## Project Structure

```
FPGA-ML-Accelerator/
├── src/
│   ├── mac_pe.v           # 3-stage pipelined MAC Processing Element
│   ├── conv3x3.v          # 3×3 convolution engine
│   ├── relu.v             # Parameterised ReLU activation
│   ├── cnn_layer.v        # Top-level core (valid/ready)
│   └── cnn_layer_axis.v   # AXI-Stream wrapper
├── sim/
│   ├── testbench.v        # Self-checking testbench
│   ├── tb_axis.v          # AXI-Stream testbench
│   ├── inputs.hex         # Generated test vectors
│   ├── expected.hex       # Golden model expected outputs
│   └── scripts/
│       └── golden_model.py  # Python reference implementation
├── docs/
│   └── design_report.md
└── README.md
```

---

## License

MIT — see [LICENSE](LICENSE)

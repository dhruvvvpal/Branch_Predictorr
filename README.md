# Hot-Swappable Branch Direction Predictors on a 5-Stage RV32I Pipeline

**VL-326 Computer Organization and Architecture · IIT Mandi**

A synthesisable SystemVerilog implementation of three runtime-selectable branch direction predictors — bimodal, gshare, and local 2-level (PAp) — sharing a single direct-mapped Branch Target Buffer on a 5-stage RV32I pipeline. The active predictor is selected live via DIP switches, enabling on-board A/B/C comparison through a single bitstream without re-synthesis.

Targeted at the **Digilent Zybo Z7-10** (Xilinx XC7Z010CLG400-1) using **Vivado ML 2025.1**.

---

## Results at a Glance

| Predictor | Accuracy | Misprediction Rate | ΔCPIᵃ |
|---|---|---|---|
| Local 2-level (PAp) | **94.54%** | 5.46% | +0.020 |
| Gshare (McFarling) | 92.18% | 7.82% | +0.028 |
| Bimodal (2-bit) | 81.25% | 18.75% | +0.068 |
| Static not-taken | 40.62% | 59.38% | +0.214 |

ᵃ Projected at branch frequency f_b = 0.18, penalty t_pen = 2 cycles.

Measured on-board via ILA over ~10 million branch events per configuration.

**Post-implementation (with ILA/debug logic):** 2,941 LUTs · 3,966 FFs · Setup WNS +5.756 ns @ 50 MHz · Zero failing timing endpoints.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│              Zybo Z7-10 Top-Level Wrapper            │
│  (125 MHz ref → MMCM → 50 MHz core clock)           │
│                                                      │
│  SW[1:0] ──► 3-flop sync ──► cfg_sel register       │
│  BTN0    ──────────────────► system reset            │
│  LED[3:0]◄──────────────────── cfg_sel echo + hb    │
│                                                      │
│  ┌───────────────────────────────────────────────┐  │
│  │           Branch Predictor Subsystem           │  │
│  │  ┌─────────┐  ┌────────┐  ┌────────────────┐  │  │
│  │  │ Bimodal │  │ Gshare │  │  Local 2-level │  │  │
│  │  └────┬────┘  └───┬────┘  └───────┬────────┘  │  │
│  │       └───────────┴───────────────┘            │  │
│  │              Hot-swap MUX (cfg_sel)             │  │
│  │              32-entry Direct-mapped BTB         │  │
│  │              4 × 32-bit Perf. Counters          │  │
│  └──────────────────────┬────────────────────────┘  │
│                         │ predict_taken, target      │
│  ┌──────┐ ┌──────┐ ┌────▼───┐ ┌──────┐ ┌────────┐  │
│  │  IF  │►│  ID  │►│   EX   │►│ MEM  │►│   WB   │  │
│  └──────┘ └──────┘ └────────┘ └──────┘ └────────┘  │
│                    resolve / flush / GHR rollback    │
└─────────────────────────────────────────────────────┘
```

### Predictor Configurations (Equal-Cost Sizing)

| Predictor | Configuration | Storage |
|---|---|---|
| Bimodal | 256-entry PHT, 2-bit saturating counters | 512 bits |
| Gshare | 8-bit GHR + 256-entry PHT | 520 bits |
| Local PAp | 32×6-bit LHT + 64-entry PHT | 320 bits |
| BTB (shared) | 32 entries × 56-bit lines | 1,792 bits |

---

## Key Design Decisions

**Speculative GHR update with snapshot rollback** — The GHR is updated at prediction time (not resolution). Each in-flight branch carries a GHR snapshot; on misprediction, the snapshot is restored before shifting in the correct outcome. The same mechanism applies to the LHT for the local predictor.

**Hot-swap MUX** — `cfg_sel` controls which predictor's output drives `predict_taken_o` and which receives the `update_valid` signal, so only the active predictor trains. Switching is live with no pipeline stall or re-synthesis.

**Stub traffic generator** — A synthetic branch generator presents 8 PCs across 5 pattern families (always-T, always-N, alternating T/N, T-T-N-T, N-T-T) with 16 iterations per slot for warmup. Throttled to 1 branch per 100 cycles to fit events in the 1024-sample ILA buffer. Integration with the V-FRONT RV32I core is planned future work.

---

## Simulation Results

All 9 self-checks pass in behavioural simulation (`tb_bp_top.sv`). Steady-state accuracy is measured over the last 80% of iterations (after 20% warmup).

| Check | Pattern | Bimodal | Gshare | Local 2-level |
|---|---|---|---|---|
| #1–3 | Always Taken | 100% | 100% | 100% |
| #4–6 | Alternating (T/N) | 0%* | 100% | 100% |
| #7–9 | T-T-N-T Repeat | 75% | 100% | 100% |

\* Bimodal anti-phase locking on length-2 periodic patterns — expected pathological behaviour per Smith [1].

---

## Repository Structure

```
.
├── rtl/
│   ├── bp_top.sv              # Predictor subsystem top (MUX, BTB, counters)
│   ├── bimodal_pred.sv        # 2-bit saturating counter PHT
│   ├── gshare_pred.sv         # GHR + XOR-indexed PHT, speculative update
│   ├── local_pred.sv          # PAp: LHT + PHT, snapshot rollback
│   ├── btb.sv                 # 32-entry direct-mapped BTB
│   ├── pipeline_core.sv       # 5-stage RV32I pipeline (stub core variant)
│   └── zybo_top.sv            # Board wrapper (MMCM, I/O, ILA hooks)
├── tb/
│   └── tb_bp_top.sv           # Unit testbench (9 self-checks)
├── docs/
│   ├── timing_summary.rpt     # Post-implementation timing report
│   └── utilization.rpt        # Resource utilization report
└── README.md
```

---

## Getting Started

### Prerequisites

- Vivado ML Edition 2025.1 (or later)
- Digilent Zybo Z7-10 board
- Digilent board files installed in Vivado

### Simulation

1. Open Vivado and create a project targeting `xc7z010clg400-1`.
2. Add all files under `rtl/` and `sim/` as sources; set `tb_bp_top.sv` as the simulation top.
3. Run **Behavioral Simulation**. All 9 `PASS` messages should appear in the Tcl console.

### Synthesis & Implementation

1. Set `zybo_top.sv` as the design top.
2. Add `constraints/zybo_z7.xdc`.
3. Run **Generate Bitstream**. Expected: 2,941 LUTs, 3,966 FFs, WNS ≥ +5.7 ns.

### On-Board Demo

| Control | Function |
|---|---|
| `SW[1:0] = 00` | Bimodal predictor active |
| `SW[1:0] = 01` | Gshare active |
| `SW[1:0] = 10` | Local 2-level active |
| `SW[1:0] = 11` | Static not-taken (control) |
| `BTN0` | Reset all performance counters |
| `LED[1:0]` | Echo `cfg_sel` (active predictor) |
| `LED0` | Heartbeat (~1 Hz) |
| `LED3` | Flashes on each misprediction |

Open the Vivado Hardware Manager, connect to the board, and trigger the ILA on `core_ex_mispredict == 1`. Read `perf_branches` and `perf_mispredicts` from the waveform to compute accuracy.

---

## Future Work

- **V-FRONT integration** — Replace the stub core with the full [V-FRONT RV32I core](https://github.com/kagandikmen/V-FRONT) to validate on real instruction streams.
- **Embench-IoT benchmarks** — Run standard embedded workloads to compare gshare vs. local on correlated (non-periodic) branch traffic.
- **S/M/L/XL area sweep** — Produce the equal-cost trade-off curve from McFarling [3] across multiple PHT sizes.
- **Tournament predictor** — Add a dynamic selector that picks between gshare and local on a per-branch basis.

---

## References

1. J. E. Smith, "A study of branch prediction strategies," *ISCA*, 1981.
2. T.-Y. Yeh and Y. N. Patt, "Two-level adaptive training branch prediction," *MICRO*, 1991.
3. S. McFarling, "Combining branch predictors," DEC WRL Tech. Rep. TN-36, 1993.
4. D. A. Patterson and J. L. Hennessy, *Computer Organization and Design RISC-V Edition*, 2nd ed., Morgan Kaufmann, 2020.
5. K. Dikmen, [V-FRONT](https://github.com/kagandikmen/V-FRONT), GitHub, 2023.
6. J. Bennett et al., "Embench-IoT," RISC-V Workshop, 2019.
7. Digilent Inc., [Zybo Z7 Reference Manual](https://digilent.com/reference/programmable-logic/zybo-z7/reference-manual), 2024.
8. AMD/Xilinx, UG908: Vivado Design Suite User Guide — Programming and Debugging, 2022.

---

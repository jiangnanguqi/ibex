# Recorded single-hart MLPerf Tiny ad01 run (Ibex small)

All 19 Embench programs and MLPerf Tiny ad01 passed on both cores (Embench's
own `verify_benchmark()`; the three Tiny fixtures and the final output against
the native reference). The retired-instruction counts of the measured regions
are identical on the two cores for all 20 programs.

Configuration:

- Ibex: fork revision `bd9917e`, official `small` configuration (RV32MFast,
  no branch-target ALU, no writeback stage, no instruction cache), Simple
  System with `-Wno-MULTIDRIVEN` in place of `-Wall` as on this fork's
  `localBranch`.
- CV32E40P: fork revision `b353438`, `COREV_PULP=0`, `COREV_CLUSTER=0`,
  `FPU=0`, `ZFINX=0`, example testbench with memory stalls disabled.
- One hart; no cache; one-cycle memory responses.
- xPack RISC-V GCC 12.2.0-3 (`riscv-none-elf`), `-march=rv32im -mabi=ilp32
  -misa-spec=2.2 -O3 -mcmodel=medany -mstrict-align -falign-functions=16
  -falign-jumps=4`; no global pointer (see `common/link.ld` in the benchmark directory).
- Verilator 5.020.
- Embench `09c2ed8`, `GSF=12`, `WARMUP_HEAT=1`; Tiny/TFLM pins as in
  `mlperf_tiny/prepare.py`, 12 measured inferences after one warm-up.

The counts are the measured regions' `mcycle`/`minstret` as read by the
programs (`Embench cycles=... instret=...`, `TINY_STATS`); on Ibex the
simulator's own performance-counter printout gives the same values.

## How these were built

FuseSoC and scons could not be installed where these runs were recorded, so
their two steps were done by the fallback scripts in `common/fallback/` of
the benchmark directory, which do the same with the same inputs:

- Simulator: `common/fallback/build_simple_system.sh small` (the FuseSoC sim
  target's RTL, C++ driver and Verilator options, with `-Wno-MULTIDRIVEN` as in
  `ibex_simple_system.core`).
- Embench ELF files: `common/fallback/build_embench_without_scons.sh` (what
  Embench's sconstruct.py does with the Makefile's arguments).
- MLPerf Tiny: its Makefile.
- Runs: the commands of `run_embench.sh` and `run_tiny.sh`.

The fallback scripts reproduce these records exactly: the ELF files they build
are byte-identical to the ones run here, and a simulator rebuilt with
`build_simple_system.sh` gives the same counts for wikisort and MLPerf Tiny
(the two re-run as a check). The FuseSoC and scons flow
should reproduce them exactly too; it has not been run for this record.

## MLPerf Tiny ad01, 12 measured inferences

| Core | Cycles, 12 inferences | Instructions | IPC | Cycles per inference | codex record (cycles / instructions) |
|---|---:|---:|---:|---:|---|
| Ibex small | 49,304,456 | 29,736,908 | 0.6031 | 4,108,704.7 | 49,304,451 / 29,736,900 |
| CV32E40P | 36,481,511 | 29,736,908 | 0.8151 | 3,040,125.9 | 36,481,505 / 29,736,900 |

Target arena usage: 8076 bytes of 65,536 reserved.
The run log is `runlogs/tiny-ad01.log`; `results.json` holds the parsed values.
The codex record (`../codex-20261030`) differs by the counter-control boundary only.

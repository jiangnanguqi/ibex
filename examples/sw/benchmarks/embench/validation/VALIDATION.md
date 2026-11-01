# Recorded single-hart Embench runs (Ibex small)

All 19 Embench programs and MLPerf Tiny ad01 passed on both cores (Embench's
own `verify_benchmark()`; the three Tiny fixtures and the final output against
the native reference). The retired-instruction counts of the measured regions
are identical on the two cores for all 20 programs.

Configuration:

- Ibex: fork revision `bd9917e`, official `small` configuration (RV32MFast,
  no branch-target ALU, no writeback stage, no instruction cache), Simple
  System built with `-Wno-MULTIDRIVEN` in place of `-Wall` as on this fork's
  `localBranch`.
- CV32E40P: fork revision `b353438`, `COREV_PULP=0`, `COREV_CLUSTER=0`,
  `FPU=0`, `ZFINX=0`, example testbench with memory stalls disabled.
- One hart; no cache; one-cycle memory responses.
- xPack RISC-V GCC 12.2.0-3 (`riscv-none-elf`), `-march=rv32im -mabi=ilp32
  -misa-spec=2.2 -O3 -mcmodel=medany -mstrict-align -falign-functions=16
  -falign-jumps=4`; no global pointer (see `common/link.ld`).
- Verilator 5.020.
- Embench `09c2ed8`, `GSF=12`, `WARMUP_HEAT=1`; Tiny/TFLM pins as in
  `mlperf_tiny/prepare.py`, 12 measured inferences after one warm-up.

The counts are the measured regions' `mcycle`/`minstret` as read by the
programs (`Embench cycles=... instret=...`, `TINY_STATS`); on Ibex the
simulator's own performance-counter printout gives the same values.

## Embench (Ibex small, with the other core for comparison)

| Benchmark | Instructions (both) | Ibex small cycles | Ibex IPC | CV32E40P cycles | CV32E40P IPC |
|---|---:|---:|---:|---:|---:|
| aha-mont64 | 60,674,258 | 71,552,973 | 0.848 | 71,084,712 | 0.854 |
| crc32 | 50,153,938 | 68,960,714 | 0.727 | 58,513,864 | 0.857 |
| depthconv | 31,021,371 | 50,886,061 | 0.610 | 37,983,849 | 0.817 |
| edn | 38,487,611 | 69,855,053 | 0.551 | 46,092,545 | 0.835 |
| huffbench | 27,572,223 | 41,381,815 | 0.666 | 35,490,513 | 0.777 |
| matmult-int | 36,415,238 | 63,650,988 | 0.572 | 43,993,100 | 0.828 |
| md5sum | 31,803,788 | 40,412,848 | 0.787 | 36,322,155 | 0.876 |
| nettle-aes | 52,503,209 | 67,162,725 | 0.782 | 56,442,143 | 0.930 |
| nettle-sha256 | 57,084,628 | 65,293,792 | 0.874 | 57,692,156 | 0.989 |
| nsichneu | 26,881,037 | 48,953,557 | 0.549 | 43,409,557 | 0.619 |
| picojpeg | 35,909,504 | 53,705,940 | 0.669 | 42,097,730 | 0.853 |
| qrduino | 33,818,336 | 49,049,358 | 0.689 | 41,785,682 | 0.809 |
| sglib-combined | 30,288,107 | 51,337,141 | 0.590 | 42,282,881 | 0.716 |
| slre | 30,215,130 | 45,755,437 | 0.660 | 37,113,888 | 0.814 |
| statemate | 41,528,453 | 62,147,825 | 0.668 | 45,444,539 | 0.914 |
| tarfind | 12,363,871 | 34,540,945 | 0.358 | 27,785,710 | 0.445 |
| ud | 13,328,645 | 40,639,176 | 0.328 | 29,415,071 | 0.453 |
| wikisort | 9,483,754 | 15,406,683 | 0.616 | 11,685,401 | 0.812 |
| xgboost | 40,804,518 | 57,164,374 | 0.714 | 48,684,600 | 0.838 |
| geometric mean IPC | | | 0.628 | | 0.776 |

## Comparison with the codex record

The codex record (`codex-20261030`, the earlier port) differs in two ways:
its link defined a global pointer, so programs whose hot loops access small
data (crc32's `seed`, nsichneu, ud, ...) executed fewer instructions there;
and its counter-control boundary differs by one or two instructions.

| Benchmark | Ibex small cycles, this flow | codex record | difference | instructions, this flow | codex record | difference |
|---|---:|---:|---:|---:|---:|---:|
| aha-mont64 | 71,552,973 | 71,552,973 | +0 | 60,674,258 | 60,674,257 | +1 |
| crc32 | 68,960,714 | 66,869,716 | +2,090,998 | 50,153,938 | 48,062,939 | +2,090,999 |
| depthconv | 50,886,061 | 50,846,727 | +39,334 | 31,021,371 | 30,982,036 | +39,335 |
| edn | 69,855,053 | 69,787,981 | +67,072 | 38,487,611 | 38,420,538 | +67,073 |
| huffbench | 41,381,815 | 41,381,288 | +527 | 27,572,223 | 27,571,695 | +528 |
| matmult-int | 63,650,988 | 63,650,519 | +469 | 36,415,238 | 36,414,768 | +470 |
| md5sum | 40,412,848 | 40,408,886 | +3,962 | 31,803,788 | 31,799,825 | +3,963 |
| nettle-aes | 67,162,725 | 67,161,810 | +915 | 52,503,209 | 52,502,293 | +916 |
| nettle-sha256 | 65,293,792 | 65,293,794 | -2 | 57,084,628 | 57,084,629 | -1 |
| nsichneu | 48,953,557 | 48,938,773 | +14,784 | 26,881,037 | 26,866,252 | +14,785 |
| picojpeg | 53,705,940 | 53,231,881 | +474,059 | 35,909,504 | 35,435,444 | +474,060 |
| qrduino | 49,049,358 | 49,015,879 | +33,479 | 33,818,336 | 33,784,856 | +33,480 |
| sglib-combined | 51,337,141 | 51,328,957 | +8,184 | 30,288,107 | 30,279,922 | +8,185 |
| slre | 45,755,437 | 45,755,439 | -2 | 30,215,130 | 30,215,131 | -1 |
| statemate | 62,147,825 | 51,638,346 | +10,509,479 | 41,528,453 | 31,018,973 | +10,509,480 |
| tarfind | 34,540,945 | 34,540,947 | -2 | 12,363,871 | 12,363,872 | -1 |
| ud | 40,639,176 | 40,596,336 | +42,840 | 13,328,645 | 13,285,804 | +42,841 |
| wikisort | 15,406,683 | 15,406,685 | -2 | 9,483,754 | 9,483,755 | -1 |
| xgboost | 57,164,374 | 57,164,376 | -2 | 40,804,518 | 40,804,519 | -1 |

The run logs are in `runlogs/`; `results.json` holds the parsed values.

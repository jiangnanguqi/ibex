# Single-HART Embench and MLPerf Tiny

This additive port uses the same workload sources, compiler ISA/ABI, inputs,
golden results and measurement boundaries as `riscv-imt-staging`. The existing
core, SoC, software examples and build files are unchanged. All port files are
under `benchmarks/imt_bench/`; downloaded dependencies and build products stay
in this directory and are ignored by Git.

The core revision is recorded in `core.json`. The simulator build checks the
original RTL directories against that revision. Ibex uses the existing Simple
System RTL. CV32E40P uses the existing core and simulation clock gate with a new
minimal system wrapper. Both systems provide independent 32-bit instruction
and data RAM ports with one-cycle responses, 1 MiB of RAM at `0x00100000`,
ASCII output at `0x00020000`, and simulation exit at `0x00020008`.

## Run

Requirements: Python 3, Git, GNU Make, a host C++ compiler, Verilator, and a
RISC-V GCC/newlib multilib toolchain with RV32IM/ILP32 C and C++ support.
FuseSoC and a Python TFLite package are not required by this entry point.

From the repository root:

```sh
make -C benchmarks/imt_bench run \
  RISCV_TOOLS=riscv64-unknown-elf \
  VERILATOR=verilator JOBS=2
```

Defaults: one HART, cache disabled, Embench `GSF=12`, `WARMUP_HEAT=1`, Tiny
`ITERATIONS=12`, and an assumed `CLOCK_MHZ=80` for converting cycles to time.
This frequency is not a synthesis result. ISA/ABI are fixed to `rv32im/ilp32`
with ISA specification 2.2, `-O3`, `medany`, and strict alignment.

To run only the inference workload or one Embench benchmark:

```sh
make -C benchmarks/imt_bench run WORKLOAD=tiny
make -C benchmarks/imt_bench run WORKLOAD=crc32
```

`WORKLOAD=embench` selects all 19 benchmarks in the pinned project revision.
`prepare`, `build` and `sim` are available as separate Make targets. `BUILD`,
`EMBENCH_DIR`, `TINY_DIR` and `TFLM_DIR` accept absolute paths for reusing
existing dependency checkouts or separating experiments. Existing dependency
checkouts must match the pinned commit and have no tracked source changes.

For Ibex, the default is the official `small` configuration: RV32MFast,
two pipeline stages, no branch-target ALU, no writeback stage, no bitmanip,
and no instruction cache. `IBEX_CONFIG=maxperf` selects RV32MSingleCycle,
the branch-target ALU and the writeback stage in a separate build directory.
The recorded full-suite results use `small`. CV32E40P has COREV_PULP,
COREV_CLUSTER, FPU and ZFINX disabled. Both builds omit optional HPM event
counters; the mandatory 64-bit cycle and retired-instruction counters remain.
The compiler emits RV32IM code even though the cores can decode compressed
instructions. No DSP/SIMD kernels or floating-point hardware are used.

## Measurement and validation

Embench is pinned to `09c2ed8c3b7008c95d08b038de4a3f6dc103ed70`, matching
the project's submodule. Its `support/main.c`, benchmark bodies and
`verify_benchmark()` routines are compiled unchanged. New board hooks enable
counting in `start_trigger()` and disable it in `stop_trigger()`. Initialization,
warmup, verification and the added `EMBENCH_STATS`/`EMBENCH_PASS` reports are
outside that window. A nonzero return from the original main produces failure.

MLCommons Tiny and TFLM are pinned in `tiny/prepare.py`, matching the project's
`5346ea0c5b6980437ea3a8f9c8b747c49920e07a` implementation. The ad01 INT8 model,
real ToyCar windows at frames 0/80/160, portable TFLM kernel selection,
preserved tensor layout and host-generated golden outputs are unchanged.
The target checks all 640 output bytes and FP32 anomaly-score bits for every
fixture, warms fixture 0, measures repeated `Invoke()` calls, and checks the
final output. Model setup, float input quantization, scoring, validation and
reporting are outside the measured region. This flow uses preloaded inputs
without the MLCommons Runner or full-dataset accuracy evaluation.

The platform resets and gates `mcycle` and `minstret` through `mcountinhibit`.
The count includes the small call/return and counter-control boundaries.
Added RTL observers independently count cycles/instruction events using the
actual core counter-enable signals. The parser requires exact agreement with
the software counters and rejects output transactions while either counter is
enabled. There is no UART transmission time in the reported metrics.

Each run saves `console.txt` and `result.json` under `BUILD/runs/<benchmark>/`.
`BUILD/config.json` records compiler and core configuration, dependency pins
and target binary hashes. Successful `run` also writes `BUILD/summary.json`.
IPC is instructions/cycles; Tiny latency is cycles/iterations, and throughput
is iterations * assumed frequency / cycles.

After building and running the full suite, rejection checks are available:

```sh
make -C benchmarks/imt_bench check
```

These run real target variants that force Embench verification failure, write
output with counters enabled, and corrupt one expected Tiny output byte. They
also check that incomplete or inconsistent saved reports are rejected. The
variants are confined to `BUILD/negative/`; normal target images are untouched.

## Implementation notes

The new startup initializes GP/SP, BSS and C++ initialization arrays. The new
linker script uses the full 1 MiB RAM with a separate 16 KiB stack and bounded
newlib heap. The simulation driver drives an explicit falling reset edge so
state behind core clock gates receives asynchronous reset before execution.

For the 2023 Ibex fork, this port compiles the existing Simple System directly
with Verilator. Build-only primitive aliases are generated from the vendored
generic primitives by changing only the module name, performing the generic
selection normally generated by FuseSoC. Source files remain unchanged.

Verilator 5.020 needs `-Wno-BLKANDNBLK` for CV32E40P's packed CSR arrays:
unimplemented counter slices use continuous assignments, while implemented
slices use sequential assignments. These are disjoint slices. The independent
measurement audit validates the implemented cycle and instruction counters.

`VALIDATION.md` and `validation/` contain the actual recorded results.

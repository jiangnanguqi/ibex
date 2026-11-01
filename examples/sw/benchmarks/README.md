# Benchmarks

This directory contains benchmarks that can be run on ibex simple system.
Benchmarks may rely on code external to this directory (e.g. it may be found in
`vendor/`) see the specific benchmark information below for details on how to
build and run each benchmark and where benchmark code is located.

## Building Simulation

All of these benchmarks run on Simple System. A verilator simulation suitable
for running them can be built with:

```
fusesoc --cores-root=. run --target=sim --setup --build lowrisc:ibex:ibex_simple_system --RV32E=0 --RV32M=ibex_pkg::RV32MFast
```

See examples/simple_system/README.md for full details.

## CoreMark

CoreMark (https://www.eembc.org/coremark/ https://github.com/eembc/coremark) is
an industry standard benchmark with results available for a wide variety of
systems.

The CoreMark source is vendored into the Ibex repository at
`vendor/eembc_coremark`. Support structure and a makefile to build CoreMark for
running on simple system is found in `examples/sw/benchmarks/coremark`.

To build CoreMark:

```
make -C ./examples/sw/benchmarks/coremark/
```

To run CoreMark (after building a suitable simulator binary, see above):

```
build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system --meminit=ram,examples/sw/benchmarks/coremark/coremark.elf
```

The simulator outputs the performance counter values observed for the benchmark
(the counts do not include anything from pre or post benchmark loops).

CoreMark should output (to `ibex_simple_system.log`) something like the
following:

```
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 4244465
Total time (secs): 8
Iterations/Sec   : 1
Iterations       : 10
Compiler version : GCC
Compiler flags   :
Memory location  :
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xfcaf
Correct operation validated. See README.md for run and reporting rules.
```

### Choice of ISA string

Different ISAs (to choose different RISC-V ISA extensions) can be selected by
passing the desired ISA string into `RV_ISA` when invoking make.

```
make -C ./examples/sw/benchmarks/coremark clean
make -C ./examples/sw/benchmarks/coremark RV_ISA=rv32imc
```

This will build CoreMark using the 'C' extension (compressed instructions).

When changing `RV_ISA`, you must clean out any old build with `make clean` and
rebuild.

The following ISA strings give the best performance for the Ibex configurations
listed in the README:

| Config               | Best ISA |
|----------------------|----------|
| "small"              | rv32im   |
| "maxperf"            | rv32im   |
| "maxperf-pmp-bmfull" | rv32imcb |

### CoreMark score

A CoreMark score is given as the number of iterations executed per second. The
CoreMark binary is hard-coded to execute 10 iterations (see
`examples/sw/benchmarks/coremark/Makefile` if you wish to alter this).  To obtain
a useful CoreMark score from the simulation you need to choose a clock speed the
Ibex implementation you are interested in would run at, e.g. 100 MHz, taking
the above example:

* 10 iterations take 4244465 clock cycles
* So at 100 MHz Ibex would execute (100 * 10^6) / (4244465 / 10) = 235.6
  Iterations in 1 second.
* CoreMark (at 100 MHz) is 235.6

CoreMark/MHz is often used instead of a raw CoreMark score. The example above
gives a CoreMark/MHz of 2.36 (235.6 / 100 rounded to 2 decimal places).

To directly produce CoreMark/MHz from the number of iterations (I) and total
ticks (T) use the follow formula:

```
CoreMark/MHz = (10 ^ 6) * I / T
```

Note that `core_main.c` from CoreMark has had a minor modification to prevent it
from reporting an error if it executes for less than 10 seconds. This violates
the run reporting rules (though does not effect benchmark execution). It is
trivial to restore `core_main.c` to the version supplied by EEMBC in the
CoreMark repository if an official result is desired.

## Embench

Embench (https://github.com/embench/embench-iot) is a benchmark suite for
embedded cores. It is a git submodule at `vendor/embench-iot`, pinned to the
revision used by the riscv-imt-model platform (`09c2ed8`, 19 benchmarks). The
Ibex board port, a Makefile wrapper around Embench's own scons build and a run
script are in `examples/sw/benchmarks/embench`. The wrapper follows the
platform's `sw/examples/embench` so that the same sources, compiler options
(`-O3`, `-march=rv32im -mabi=ilp32`, strict alignment, `GSF=12`,
`WARMUP_HEAT=1`) and measured region are used on both.

The measured region is `benchmark()` between Embench's `start_trigger()` and
`stop_trigger()` hooks (`ibex/boardsupport.c`), which reset and enable the
performance counters and disable them again, as the CoreMark port does.
Initialisation, warm-up, result verification and the report are outside it.
Embench's `support/main.c` and the benchmark sources are compiled unchanged;
`ibex/embench_report.c` wraps `main()` (linked with `--wrap=main`) to print the
counters and the verification result afterwards.

To build all benchmarks (the ELF files are placed in the benchmark directory):

```
git submodule update --init vendor/embench-iot
make -C ./examples/sw/benchmarks/embench
```

To run them all (after building a suitable simulator binary, see above):

```
./examples/sw/benchmarks/embench/run_embench.sh
```

The script passes `+ibex_tracer_enable=0`, which leaves out the instruction
trace (`trace_core_00000000.log`, gigabytes for these runs); drop it from the
script for a trace. Each benchmark's log in `examples/sw/benchmarks/embench/runlogs` holds the
simulator output (simulation statistics and performance counters) followed by
the program's output:

```
Embench cycles=45755440 instret=30215132
Main Exit=0
```

`Main Exit=0` means the benchmark's own `verify_benchmark()` accepted the
result. The counts are raw cycle and retired-instruction counts of the measured
region (plus the few instructions of the counter control), not Embench's
normalised scores. The linker script (`common/link.ld`) deliberately defines no
`__global_pointer$`, like Simple System's, so that no small-data access is
relaxed to gp-relative addressing and the instruction counts can be compared
with the platform's single-hart runs; see the note in the script.

## MLPerf Tiny (anomaly detection, ad01)

`examples/sw/benchmarks/mlperf_tiny` runs the MLPerf Tiny anomaly-detection
benchmark (the ad01 INT8 model on TensorFlow Lite Micro's portable kernels)
in the same way as the platform's `sw/examples/mlperf_tiny`: MLCommons Tiny and
TFLM are fetched at pinned revisions by `prepare.py` (into `.deps/`, or
`TINY_DIR`/`TFLM_DIR`), the model and input hashes are checked, three real
input windows are checked against outputs computed by a native build of the
same kernels (`golden.h`), one untimed warm-up is run, and `ITERATIONS`
(default 12) calls of `Invoke()` are measured. This is not the official MLPerf
Tiny submission flow (no Runner, no full-dataset accuracy); it measures the
inference latency of the model only.

The bare-metal runtime is Simple System's; `ibex/platform.c` adds the C++
constructor calls, the newlib system calls and heap, the counter control and
the report, which is buffered and printed only after the measured region.

```
make -C ./examples/sw/benchmarks/mlperf_tiny
./examples/sw/benchmarks/mlperf_tiny/run_tiny.sh
```

The report in `runlogs/tiny-ad01.log` lists the three fixture checks
(`TINY_CHECK ... mismatches=0`), the measured counts
(`TINY_STATS iterations=12 cycles=... instructions=...`), `TINY_PASS` and
`Main Exit=0`. Latency per inference is cycles / iterations.

## Recorded results

`embench/validation` and `mlperf_tiny/validation` keep the records of the
single-hart runs (Ibex `small` configuration, `-Wno-MULTIDRIVEN` as on this
fork's `localBranch`); `VALIDATION.md` there summarises them.

<!-- Record of the original codex port (benchmarks/imt_bench on branch
codex/embench-mlperf-single-hart-20261030, 2026-10-30), kept unchanged for
reference. That port used its own start-up code, linker script and Verilator
driver, and defined __global_pointer$, so its instruction counts include
gp-relative relaxation of some small-data accesses (e.g. crc32's seed) and are
not identical to those of the current flow; see ../VALIDATION.md. -->

# Recorded single-HART validation

All 19 Embench programs and MLPerf Tiny ad01 passed on ibex. All original
repository files were verified byte-for-byte against `bd9917efaa33cbdbd15dd2b2f56932c8398dd898`
(3503 blobs); no existing file was changed.

The two ports ran byte-identical binaries for every corresponding workload.
Their measured retired-instruction counts also agree exactly on all 20 programs.

Test configuration:

- Ibex: fork revision `bd9917efaa33cbdbd15dd2b2f56932c8398dd898`, official `small` configuration.
- CV32E40P: fork revision `b353438ff469c030c89f6804f3b24a2852880e8b`, COREV_PULP=0, COREV_CLUSTER=0, FPU=0, ZFINX=0.
- One HART; no cache; 1 MiB RAM; independent 32-bit I/D ports with one-cycle responses.
- xPack RISC-V GCC 12.2.0-3; RV32IM/ILP32, ISA specification 2.2, `-O3`, `medany`, strict alignment.
- Verilator 5.020; host GCC 13.3.0. These are the same cross-compiler and Verilator versions used for the project's recent Tiny measurements.
- Embench commit `09c2ed8c3b7008c95d08b038de4a3f6dc103ed70`, GSF=12, WARMUP_HEAT=1.
- Tiny/TFLM pins, model/input SHA256 and fixture frames are recorded in [assets.json](validation/assets.json).
- Both software counters agree exactly with the added RTL audit on every successful run. All output transactions occurred with both counters disabled.

## MLPerf Tiny

Each core checked all 640 output bytes and score bits for three real input windows,
performed one untimed warmup, measured 12 calls to `Invoke()`, and checked the final
output. Target arena usage was 8,076 bytes out of 65,536 reserved bytes. The
native reference used 13,280 bytes and also checked repeated-inference stability.

| Core | Total cycles, 12 inferences | Instructions | IPC | Latency at assumed 80 MHz | Inferences/s at assumed 80 MHz |
|---|---:|---:|---:|---:|---:|
| ibex small | 49,304,451 | 29,736,900 | 0.603128 | 51.3588 ms | 19.4709 |
| cv32e40p | 36,481,505 | 29,736,900 | 0.815123 | 38.0016 ms | 26.3147 |

80 MHz is a conversion assumption, not an achieved clock frequency. This is the
project's preloaded-input inference flow without Runner or a full-dataset AUC
measurement. These results do not include UART/output or correctness checks.
See the [raw program report](validation/tiny-console.txt), [parsed result](validation/tiny-result.json)
and [native reference report](validation/host-reference.txt).

## Embench

The original `support/main.c` and verification routines were used unchanged.
The measured region is `benchmark()` between the board trigger hooks, with
initialization, warmup, verification and report printing excluded. The table
uses the project's pinned 19-program revision, not a different release's list.

| Benchmark | Ibex small cycles | CV32E40P cycles | Instructions on both | Status |
|---|---:|---:|---:|---|
| aha-mont64 | 71,552,973 | 71,084,712 | 60,674,257 | PASS |
| crc32 | 66,869,716 | 56,422,866 | 48,062,939 | PASS |
| depthconv | 50,846,727 | 37,944,515 | 30,982,036 | PASS |
| edn | 69,787,981 | 46,025,473 | 38,420,538 | PASS |
| huffbench | 41,381,288 | 35,489,986 | 27,571,695 | PASS |
| matmult-int | 63,650,519 | 43,992,631 | 36,414,768 | PASS |
| md5sum | 40,408,886 | 36,318,193 | 31,799,825 | PASS |
| nettle-aes | 67,161,810 | 56,441,228 | 52,502,293 | PASS |
| nettle-sha256 | 65,293,794 | 57,692,158 | 57,084,629 | PASS |
| nsichneu | 48,938,773 | 43,394,773 | 26,866,252 | PASS |
| picojpeg | 53,231,881 | 41,623,671 | 35,435,444 | PASS |
| qrduino | 49,015,879 | 41,752,203 | 33,784,856 | PASS |
| sglib-combined | 51,328,957 | 42,274,697 | 30,279,922 | PASS |
| slre | 45,755,439 | 37,113,890 | 30,215,131 | PASS |
| statemate | 51,638,346 | 34,935,060 | 31,018,973 | PASS |
| tarfind | 34,540,947 | 27,785,712 | 12,363,872 | PASS |
| ud | 40,596,336 | 29,372,231 | 13,285,804 | PASS |
| wikisort | 15,406,685 | 11,685,403 | 9,483,755 | PASS |
| xgboost | 57,164,376 | 48,684,602 | 40,804,519 | PASS |

Each program's complete console and JSON are under `validation/embench/`.
[summary.json](validation/summary.json) records per-program IPC, binary hashes,
configuration, validation status and source-preservation checks. These are raw
cycle/instruction measurements rather than normalized Embench reference scores.

## Rejection checks

Both cores rejected all three real faulted target programs:

1. Link-wrapped Embench verification forced to fail: target exit 1 and `EMBENCH_FAIL`.
2. Output inserted immediately after enabling counters: RTL assertion and failed simulator exit.
3. One expected Tiny output byte changed: fixture 0 reports one mismatch and target exit 3.

Six mutations of positive reports were also rejected: missing fixture, wrong
score, zero cycles, a disagreement between software and RTL instruction counts,
missing audit, and a different cache configuration. Raw failure reports and the
nine-test summary are under `validation/negative/`. Normal images were untouched.

The Make `run` entry point was also exercised end-to-end on `slre` with GSF=1
in a separate build directory; see `validation/cli-smoke-console.txt` and its JSON.

## Reproduce

```sh
make -C benchmarks/imt_bench run \
  RISCV_TOOLS=riscv64-unknown-elf VERILATOR=verilator \
  GSF=12 ITERATIONS=12 CLOCK_MHZ=80 JOBS=2
make -C benchmarks/imt_bench check RISCV_TOOLS=riscv64-unknown-elf
```

Only files below `benchmarks/imt_bench/` were added. The fork's original master
branch and the IMT project's files were not changed.

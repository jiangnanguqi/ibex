#!/usr/bin/env bash
# Runs the MLPerf Tiny ad01 image (examples/sw/benchmarks/mlperf_tiny/tiny-ad01.elf)
# on the Simple System simulator; the log goes to
# examples/sw/benchmarks/mlperf_tiny/runlogs. Build the simulator and the image
# first (see ../README.md).
#
# The log holds the simulator output (simulation statistics and the performance
# counters) followed by the program's report from ibex_simple_system.log
# (TINY_CHECK, TINY_STATS, TINY_PASS/FAIL and "Main Exit=..." lines); the
# performance-counter CSV is kept beside it.
# Environment: SIM (simulator binary) and LOG_DIR (where the logs go)
# override the defaults below, e.g. to keep runs of different
# configurations apart.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TINY_DIR="$ROOT/examples/sw/benchmarks/mlperf_tiny"
SIM="${SIM:-$ROOT/build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system}"
LOG_DIR="${LOG_DIR:-$TINY_DIR/runlogs}"
ELF="$TINY_DIR/tiny-ad01.elf"

[ -f "$ELF" ] || { echo "No $ELF; run make in $TINY_DIR first."; exit 1; }
mkdir -p "$LOG_DIR"
cd "$LOG_DIR"
log="$LOG_DIR/tiny-ad01.log"

echo "=== RUN tiny-ad01 ==="
rm -f ibex_simple_system.log ibex_simple_system_pcount.csv
# +ibex_tracer_enable=0 leaves out the instruction trace (gigabytes per run)
"$SIM" +ibex_tracer_enable=0 --meminit=ram,"$ELF" 2>&1 | tee "$log"
{ echo; echo "--- ibex_simple_system.log ---"; cat ibex_simple_system.log; } | tee -a "$log"
mv ibex_simple_system_pcount.csv "$LOG_DIR/tiny-ad01.csv"
echo "=== DONE tiny-ad01 (log: ${log}) ==="

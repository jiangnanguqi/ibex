#!/usr/bin/env bash
# Runs each built Embench benchmark (examples/sw/benchmarks/embench/*.elf) on
# the Simple System simulator; logs go to examples/sw/benchmarks/embench/runlogs.
# Build the simulator and the benchmarks first (see ../README.md).
#
# For each benchmark the log holds the simulator output (simulation statistics
# and the performance counters, as for CoreMark) followed by the program's own
# output from ibex_simple_system.log (the "Embench cycles=... instret=..." and
# "Main Exit=..." lines); the performance-counter CSV is kept beside it.
# Environment: SIM (simulator binary) and LOG_DIR (where the logs go)
# override the defaults below, e.g. to keep runs of different
# configurations apart.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
EMB_DIR="$ROOT/examples/sw/benchmarks/embench"
SIM="${SIM:-$ROOT/build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system}"
LOG_DIR="${LOG_DIR:-$EMB_DIR/runlogs}"

mkdir -p "$LOG_DIR"
cd "$LOG_DIR"

shopt -s nullglob
elfs=("$EMB_DIR"/*.elf)
if [ ${#elfs[@]} -eq 0 ]; then
  echo "No .elf found in ${EMB_DIR}; run make there first."
  exit 1
fi

for elf in "${elfs[@]}"; do
  b="$(basename "$elf" .elf)"
  log="${LOG_DIR}/${b}.log"

  echo "=== RUN ${b} ==="
  rm -f ibex_simple_system.log ibex_simple_system_pcount.csv
  # save the simulator output to the log, and also show it on screen;
  # +ibex_tracer_enable=0 leaves out the instruction trace (gigabytes per run)
  "$SIM" +ibex_tracer_enable=0 --meminit=ram,"$elf" 2>&1 | tee "$log"
  { echo; echo "--- ibex_simple_system.log ---"; cat ibex_simple_system.log; } | tee -a "$log"
  mv ibex_simple_system_pcount.csv "${LOG_DIR}/${b}.csv"
  echo "=== DONE ${b} (log: ${log}) ==="
  echo
done

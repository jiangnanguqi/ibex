#!/usr/bin/env bash
# Copyright 2026 Chuanxin Tang
# SPDX-License-Identifier: Apache-2.0
#
# Measures the Embench speed score of a configuration of Ibex Simple System
# with Embench's own script, benchmark_speed.py, as Embench's user guide
# (vendor/embench-iot/doc/README.md) describes, and records what the guide
# asks to be recorded with a result. The same flow as the riscv-imt-model
# platform's run_embench_score.sh and the CV32E40P port's.
#
#   run_embench_score.sh [-C CONFIG] [-S SIM] [-L DIR] [-f MHZ] [-g GSF]
#                        [-t SECONDS] [-K FILE]
#   run_embench_score.sh -R DIR [-f MHZ]
#     -C CONFIG   the Ibex configuration, an entry of ibex_configs.yaml
#                 (default small; maxperf is the other one of interest)
#     -S SIM      use this simulator (Vibex_simple_system) instead of building
#                 one; it is taken to be of the configuration of -C, which
#                 is not checked
#     -L DIR      write the logs and the results to DIR (default below)
#     -f MHZ      the clock frequency in MHz, a whole number, as
#                 benchmark_speed.py takes it (default 1). It sets only the
#                 Speed column and the times; the cycle counts and
#                 Speed/MHz do not depend on it. With 1, Speed equals
#                 Speed/MHz.
#     -g GSF      Embench's global scale factor, by which the work of every
#                 benchmark is multiplied (default: the Makefile's, 12, as
#                 in the platform's single-hart runs)
#     -t SECONDS  time limit of each benchmark run (default 3600)
#     -K FILE     hold a lock on FILE (flock) while building the benchmarks
#                 and the simulator, so that runs started together build one
#                 at a time (FuseSoC always builds in the same directory)
#     -R DIR      score again the runs that an earlier call wrote to DIR,
#                 with the frequency of -f, without building or running
#                 anything; the results are added to DIR. Takes no option
#                 other than -f.
#
# Building:
#   - The benchmarks: the Makefile here (make embench), that is Embench's
#     own scons build, with the GSF of -g, into DIR/build/; copies of the
#     ELF files and their disassembly go to DIR/elf/. Nothing is written to
#     this directory itself.
#   - The simulator, unless -S gives one: with FuseSoC, as ../README.md
#     describes (fusesoc ... run --target=sim --setup --build
#     lowrisc:ibex:ibex_simple_system with util/ibex_config.py CONFIG
#     fusesoc_opts), from scratch (FuseSoC's build directory is removed
#     first; see the note there), copied out of that directory to
#     build/sims/Vibex_simple_system_<CONFIG>; where FuseSoC is not
#     installed, or its build fails, with
#     ../common/fallback/build_simple_system.sh CONFIG, which builds the
#     same simulator in build/simple_system_<CONFIG>/. record.txt says
#     which.
#
# Running and scoring:
#   - benchmark_speed.py runs every benchmark through the target module
#     ibex/run_ibex_simple_system.py: one run of its ELF file on the
#     simulator, as run_embench.sh runs it, in DIR/runs/<benchmark>/. A run
#     counts only if the program ends the simulation within the time limit
#     and the benchmark's own check passes (Main Exit=0); see the module for
#     the details. The time of a run is the cycle count of the part Embench
#     measures (start_trigger to stop_trigger) divided by the frequency.
#   - For each benchmark, benchmark_speed.py divides the time of the
#     reference platform (vendor/embench-iot/baseline-data/speed.json) by
#     this time and multiplies by the GSF: that is Speed, and Speed/MHz is
#     Speed divided by the frequency. The reference platform has a
#     Speed/MHz of 1 on every benchmark. The score is the geometric mean
#     over the benchmarks, given with the geometric standard deviation and
#     the range of one standard deviation around the mean. If any benchmark
#     does not count, there is no score.
#   - With -R, benchmark_speed.py takes the stored runs (the module's
#     --reuse) instead of running the benchmarks.
#
# Results in DIR (default examples/sw/benchmarks/embench/scores/<date>-<time>-<CONFIG>/):
#   record.txt          what Embench's guide asks to be recorded with a
#                       result (platform and its configuration, tool chain,
#                       compiler and linker flags, Embench version) and the
#                       commands used
#   speed-<f>MHz.txt    benchmark_speed.py's results: Speed and Speed/MHz
#                       of each benchmark, their geometric mean, geometric
#                       standard deviation and range (two decimals)
#   summary-<f>MHz.txt  each benchmark's cycles, instructions, IPC, time,
#                       Speed and Speed/MHz, and the statistics, computed
#                       as benchmark_speed.py does but to four decimals
#   results.csv         the counts of every run (they do not depend on -f)
#   settings.txt        the GSF and the configuration, read by -R
#   runs/<benchmark>/   console.txt, ibex_simple_system.log,
#                       ibex_simple_system_pcount.csv and result.json of
#                       each run
#   build/, elf/        the benchmarks; build_*.log the build logs;
#                       embench-logs/ the detailed logs of benchmark_speed.py
#
# Exit status: 0 if every benchmark counted and the scores were computed;
# 1 if a benchmark did not count or the scoring failed; 2 if a build failed,
# something needed was missing or the arguments were wrong.

# No set -e: each step is checked
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
EX=$ROOT/examples/sw/benchmarks/embench
PORT=$EX/ibex
EMB=$ROOT/vendor/embench-iot
MODULE=run_ibex_simple_system

usage() {
  echo "usage: $0 [-C CONFIG] [-S SIM] [-L DIR] [-f MHZ] [-g GSF] [-t SECONDS] [-K FILE]" >&2
  echo "       $0 -R DIR [-f MHZ]" >&2
  exit 2
}

CONFIG=small
SIM=""
RUN=""
MHZ=1
GSF=""
LIMIT=3600
LOCK=""
AGAIN=""
OTHER=0      # an option given that -R does not take
while getopts "C:S:L:f:g:t:K:R:h" opt; do
  case $opt in
    C) CONFIG=$OPTARG; OTHER=1 ;;
    S) SIM=$OPTARG; OTHER=1 ;;
    L) RUN=$OPTARG; OTHER=1 ;;
    f) MHZ=$OPTARG ;;
    g) GSF=$OPTARG; OTHER=1 ;;
    t) LIMIT=$OPTARG; OTHER=1 ;;
    K) LOCK=$OPTARG; OTHER=1 ;;
    R) AGAIN=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage
[[ $MHZ =~ ^[1-9][0-9]*$ ]] || { echo "-f needs a whole number of MHz" >&2; exit 2; }
if [ -n "$AGAIN" ]; then
  [ $OTHER = 0 ] || { echo "-R takes no option other than -f" >&2; exit 2; }
else
  [[ $CONFIG =~ ^[A-Za-z0-9_-]+$ ]] || { echo "-C needs a configuration name" >&2; exit 2; }
  [ -z "$SIM" ] || [ -x "$SIM" ] || { echo "no simulator $SIM" >&2; exit 2; }
  [ -z "$GSF" ] || [[ $GSF =~ ^[1-9][0-9]*$ ]] || { echo "-g needs a whole number above 0" >&2; exit 2; }
  [[ $LIMIT =~ ^[1-9][0-9]*$ ]] || { echo "-t needs a whole number of seconds" >&2; exit 2; }
fi
[ -f "$EMB/benchmark_speed.py" ] ||
  { echo "no $EMB/benchmark_speed.py: run git submodule update --init vendor/embench-iot" >&2; exit 2; }
command -v python3 > /dev/null || { echo "no python3" >&2; exit 2; }

# Embench's Python, and the target module, without leaving compiled files
# (__pycache__) in either directory
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="$PORT:$EMB/pylib${PYTHONPATH:+:$PYTHONPATH}"

# speed OUTPUT OPTION...: benchmark_speed.py with the target module, its
# results (standard output) also written to OUTPUT; its exit status
speed() {
  local out=$1
  shift
  python3 "$EMB/benchmark_speed.py" --builddir "$RUN/build" \
    --logdir "$RUN/embench-logs" --target-module $MODULE \
    --gsf "$GSF" --cpu-mhz "$MHZ" --rundir "$RUN/runs" "$@" | tee "$out"
}

# summary: the summary and results.csv, from the stored runs; exit status
# 1 if a benchmark did not count. When one does not, this version of
# benchmark_speed.py stops with an error (a KeyError in compute_rel)
# instead of printing a score; the summary says which benchmark did not
# count, and why.
summary() {
  local rc
  python3 "$PORT/$MODULE.py" "$RUN/runs" --gsf "$GSF" \
    --cpu-mhz "$MHZ" --csv "$RUN/results.csv" > "$RUN/summary-${MHZ}MHz.txt"
  rc=$?
  cat "$RUN/summary-${MHZ}MHz.txt"
  return $rc
}

# The benchmarks, as benchmark_speed.py finds them: the directories in src/
BENCHES=$(cd "$EMB/src" && for d in */; do echo "${d%/}"; done)

# -R: the runs of an earlier call, scored again
if [ -n "$AGAIN" ]; then
  RUN=$(realpath "$AGAIN") || exit 2
  [ -f "$RUN/settings.txt" ] && [ -d "$RUN/runs" ] && [ -d "$RUN/build/src" ] ||
    { echo "$RUN has no settings.txt, runs/ or build/src/ of an earlier call" >&2; exit 2; }
  GSF=$(sed -n 's/^gsf=//p' "$RUN/settings.txt")
  [[ $GSF =~ ^[1-9][0-9]*$ ]] || { echo "$RUN/settings.txt has no valid gsf=" >&2; exit 2; }
  echo "Scoring the runs in $RUN again at $MHZ MHz"
  speed "$RUN/speed-${MHZ}MHz.txt" --reuse
  rc=$?
  summary || rc=1
  {
    echo
    echo "Scored again at $MHZ MHz on $(date '+%F %T') from the stored runs:"
    echo "  speed-${MHZ}MHz.txt, summary-${MHZ}MHz.txt"
  } >> "$RUN/record.txt"
  [ $rc -eq 0 ] || exit 1
  exit 0
fi

if [ -z "$RUN" ]; then
  RUN=$EX/scores/$(date +%Y%m%d-%H%M%S)-$CONFIG
  [ -e "$RUN" ] && RUN=$RUN-$$
fi
mkdir -p "$RUN" || exit 2
RUN=$(realpath "$RUN")
echo "Logs: $RUN"

# The settings of the benchmark build: everything written under DIR (the
# build, the map file through OPATH, the ELF copies of the Makefile's
# post-processing through EMBENCH_TOP)
MK=(OPATH="$RUN/" BUILD_DIR="$RUN/build" LOG_DIR="$RUN/build"
    EMBENCH_TOP="$RUN/elf")
# mk_var NAME: the value of a variable of the Makefile, with these settings
mk_var() {
  make -s --no-print-directory -C "$EX" --eval 'print-var-%: ; @echo $($*)' \
    "print-var-$1" "${MK[@]}"
}
if [ -z "$GSF" ]; then
  GSF=$(mk_var GSF)
  [[ $GSF =~ ^[1-9][0-9]*$ ]] || { echo "could not read GSF from $EX/Makefile" >&2; exit 2; }
fi
MK+=(GSF="$GSF")
printf 'gsf=%s\nconfig=%s\n' "$GSF" "$CONFIG" > "$RUN/settings.txt"
CC=$(mk_var CC)
ISA=$(mk_var RV_ISA)
ABI=$(mk_var RV_ABI)
VERILATOR=${VERILATOR:-verilator}
# util/ibex_config.py, which needs PyYAML, prints its errors on standard error
OPTS=$(cd "$ROOT" && python3 util/ibex_config.py "$CONFIG" fusesoc_opts)
[ -n "$OPTS" ] || { echo "util/ibex_config.py gave no options for $CONFIG (not in ibex_configs.yaml, or PyYAML missing: see above)" >&2; exit 2; }

# With -K, the builds below are done holding the lock
if [ -n "$LOCK" ]; then
  exec 9> "$LOCK" || exit 2
  flock 9 || exit 2
fi
echo "Building the benchmarks, GSF $GSF (log: $RUN/build_benchmarks.log)"
mkdir -p "$RUN/elf" || exit 2
if ! NUM_CPU=$(nproc) make -C "$EX" embench "${MK[@]}" > "$RUN/build_benchmarks.log" 2>&1; then
  echo "ERROR: building the benchmarks failed, see $RUN/build_benchmarks.log" >&2
  exit 2
fi
for b in $BENCHES; do
  [ -f "$RUN/build/src/$b/$b" ] ||
    { echo "ERROR: $b was not built, see $RUN/build_benchmarks.log" >&2; exit 2; }
done
# The simulator: given with -S; else built with FuseSoC; else, if FuseSoC is
# not installed or its build fails, with the fallback script (HOW says which)
HOW=""
if [ -n "$SIM" ]; then
  SIM=$(realpath "$SIM")
  HOW="given with -S (its configuration is taken to be $CONFIG, not checked)"
elif command -v fusesoc > /dev/null; then
  echo "Building the simulator ($CONFIG) with FuseSoC (log: $RUN/build_simulator.log)"
  # FuseSoC builds every configuration in the same directory, and in the
  # Makefile that edalize writes there, the rule that runs Verilator has no
  # prerequisites: it runs only if Verilator's makefile
  # (Vibex_simple_system.mk) is not there yet. Unless FuseSoC clears the
  # directory itself (versions differ), a build after one of another
  # configuration would keep that configuration's model. So the directory
  # is removed first, and every build starts from scratch.
  rm -rf "$ROOT/build/lowrisc_ibex_ibex_simple_system_0"
  # shellcheck disable=SC2086  # OPTS are separate options
  if (cd "$ROOT" && fusesoc --cores-root=. run --target=sim --setup --build \
        lowrisc:ibex:ibex_simple_system $OPTS) > "$RUN/build_simulator.log" 2>&1 &&
     mkdir -p "$ROOT/build/sims" &&
     cp "$ROOT/build/lowrisc_ibex_ibex_simple_system_0/sim-verilator/Vibex_simple_system" \
        "$ROOT/build/sims/Vibex_simple_system_$CONFIG"; then
    SIM=$ROOT/build/sims/Vibex_simple_system_$CONFIG
    HOW="built with FuseSoC ($(fusesoc --version 2>&1 | head -n 1)), copied to build/sims/"
  else
    echo "Building with FuseSoC failed (see $RUN/build_simulator.log); trying the fallback script"
    HOW="FuseSoC failed (build_simulator.log); "
  fi
fi
if [ -z "$SIM" ]; then
  [ -n "$HOW" ] || echo "FuseSoC is not installed: building the simulator ($CONFIG) with the fallback script"
  if ! JOBS=$(nproc) VERILATOR=$VERILATOR "$ROOT/examples/sw/benchmarks/common/fallback/build_simple_system.sh" \
          "$CONFIG" > "$RUN/build_simulator_fallback.log" 2>&1; then
    echo "ERROR: building the simulator failed, see $RUN/build_simulator_fallback.log" >&2
    exit 2
  fi
  SIM=$ROOT/build/simple_system_$CONFIG/Vibex_simple_system
  HOW="${HOW:-FuseSoC not installed; }built with common/fallback/build_simple_system.sh"
fi
[ -x "$SIM" ] || { echo "ERROR: no simulator $SIM" >&2; exit 2; }
if [ -n "$LOCK" ]; then
  flock -u 9
  exec 9>&-
fi

# The record. Lines of the build log: the variables Embench's sconstruct.py
# printed, and one compile and one link command as scons ran them
LOGB=$RUN/build_benchmarks.log
{
  echo "Embench speed score: record of the run"
  echo "made by run_embench_score.sh on $(date '+%F %T %Z')"
  echo
  echo "Platform"
  echo "  processor     Ibex, configuration $CONFIG (ibex_configs.yaml), in Simple System"
  echo "  repository    $(git -C "$ROOT" describe --always --dirty 2> /dev/null) (commit $(git -C "$ROOT" rev-parse HEAD 2> /dev/null))"
  git -C "$ROOT" status --porcelain --untracked-files=no 2> /dev/null |
    sed 's/^/                changed since the commit: /'
  echo "  simulated     yes: Verilator model of the RTL, cycle-accurate"
  echo "  simulator     $SIM, $HOW"
  echo "  verilator     $("$VERILATOR" --version 2> /dev/null)"
  echo "  memory        Simple System's RAM: one-cycle responses, no cache"
  echo "  clock         $MHZ MHz, used only for Speed and the times (the cycle counts and"
  echo "                Speed/MHz do not depend on it)"
  echo "  architecture  ${ISA^^} (-march=$ISA -mabi=$ABI), machine mode"
  echo "  configuration $CONFIG: $OPTS"
  echo
  echo "Tool chain"
  echo "  compiler      $("$CC" --version 2> /dev/null | head -n 1)"
  echo "  configured    $("$CC" -v 2>&1 | sed -n 's/^Configured with: //p')"
  echo "  binutils      $("${CC%gcc}ld" --version 2> /dev/null | head -n 1)"
  echo "  newlib        $(echo '#include <newlib.h>' | "$CC" -march="$ISA" -mabi="$ABI" -dM -E -x c - 2> /dev/null | sed -n 's/^#define _NEWLIB_VERSION "\(.*\)"/\1/p')"
  echo "  scons         $(scons --version 2> /dev/null | grep -m 1 'SCons:' | sed 's/^[[:space:]]*//')"
  echo "  python        $(python3 --version 2>&1)"
  echo
  echo "Build (examples/sw/benchmarks/embench/Makefile, through Embench's scons build)"
  echo "  arguments     $(grep -m 1 "^{'.*'cflags'" "$LOGB")"
  echo "  compile (support/main.c, as every file):"
  echo "                $(grep -m 1 -- '-o [^ ]*/support/main\.o ' "$LOGB")"
  echo "  link (crc32, as every benchmark):"
  echo "                $(grep -m 1 -- '-o [^ ]*/src/crc32/crc32 ' "$LOGB")"
  echo "  gsf           $GSF; warmup_heat $(mk_var WARMUP_HEAT)"
  echo
  echo "Embench"
  echo "  version       $(git -C "$EMB" log -1 --format='%h (%ad)' --date=short 2> /dev/null) (commit $(git -C "$EMB" rev-parse HEAD 2> /dev/null))"
  # Not git describe: the release candidate embench-2.0rc2 is not an
  # ancestor of the commit, so describe names an older tag (embench-0.5).
  # The line below is printed only if the clone has the tag and the files
  # are the same.
  git -C "$EMB" diff --quiet embench-2.0rc2 HEAD -- benchmark_speed.py pylib baseline-data 2> /dev/null &&
    echo "                its scripts and reference data are those of embench-2.0rc2"
  echo "  reference     baseline-data/speed.json: Arm Cortex-M4 (STM32F4-Discovery) at 16 MHz,"
  echo "                GCC 14.1.0 -O2, gsf 16; its Speed/MHz is 1 (doc/README.md, Reference platform)"
  echo "  scoring       benchmark_speed.py, target module $MODULE"
  echo
  echo "Commands"
  echo "  benchmarks    make -C examples/sw/benchmarks/embench embench ${MK[*]}"
  echo "  scores        python3 vendor/embench-iot/benchmark_speed.py --builddir $RUN/build"
  echo "                  --logdir $RUN/embench-logs --target-module $MODULE"
  echo "                  --gsf $GSF --cpu-mhz $MHZ --timeout $LIMIT --sim $SIM"
  echo "                  --rundir $RUN/runs"
  echo "                with PYTHONPATH=examples/sw/benchmarks/embench/ibex:vendor/embench-iot/pylib"
} > "$RUN/record.txt"

N=$(echo $BENCHES | wc -w)
echo "Running the $N benchmarks on the simulator one after the other (time limit $LIMIT s each)"
speed "$RUN/speed-${MHZ}MHz.txt" --timeout "$LIMIT" --sim "$SIM"
rc=$?
summary || rc=1

if [ $rc -ne 0 ]; then
  echo "Not every benchmark counted, or the scoring failed: no score (see $RUN)" >&2
  exit 1
fi
echo "Results: $RUN/speed-${MHZ}MHz.txt, summary-${MHZ}MHz.txt, record.txt"

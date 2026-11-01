#!/usr/bin/env bash
# Copyright 2026 Chuanxin Tang
# SPDX-License-Identifier: Apache-2.0
#
# Fallback build of the Embench benchmarks WITHOUT scons. Use
# `make -C <embench dir>` (which runs Embench's own scons build) whenever
# scons is available; this script is for environments where it cannot be
# installed, and it is how the ELF files for the records in
# ../../embench/validation/20261101-* were built.
#
# It does what Embench's sconstruct.py does with the arguments the Makefile
# passes to it: compiles support/main.c, support/beebsc.c, the board port's
# boardsupport.c and every benchmark's sources with the Makefile's
# CFLAGS_COMMON plus -DWARMUP_HEAT, -DGLOBAL_SCALE_FACTOR and the include
# directories, into the same directories under build-embench/ (the linker
# script places the benchmarks' data by that path), links each benchmark
# with the Makefile's LDFLAGS_COMMON and -lbm -lm -lgcc in sconstruct.py's
# order, and then runs the Makefile's own embench-post step. All flags are
# read from the Makefile, so they cannot drift from it.
#
# Usage: build_embench_without_scons.sh <embench dir> [benchmark...]
#   <embench dir>: the directory holding the Embench Makefile
#   benchmark:     names under embench-iot/src (default: all)
# Make variables (RISCV_TOOLS, GSF, WARMUP_HEAT, ...) are taken from the
# environment, e.g. RISCV_TOOLS=riscv-none-elf build_embench_without_scons.sh ...
set -euo pipefail

DIR="$(cd "$1" && pwd)"; shift
cd "$DIR"
OVERRIDES=()
for v in RISCV_TOOLS GSF WARMUP_HEAT RV_ISA RV_ABI STACK_SIZE; do
  [ -n "${!v:-}" ] && OVERRIDES+=("$v=${!v}")
done
var() {
  make -s --no-print-directory -f Makefile -f <(printf 'print-%%:\n\t@echo $($*)\n') \
    "print-$1" "${OVERRIDES[@]}"
}
EMBENCH_DIR=$(var EMBENCH_DIR); PORT_DIR=$(var PORT_DIR); BUILD_DIR=$(var BUILD_DIR)
BM_DIR=$(var BM_DIR); CC=$(var CC); CFLAGS=$(var CFLAGS_COMMON); LDFLAGS=$(var LDFLAGS_COMMON)
GSF_VALUE=$(var GSF); HEAT=$(var WARMUP_HEAT)

make -s --no-print-directory baremetal "${OVERRIDES[@]}"
DEFS="-DWARMUP_HEAT=$HEAT -DGLOBAL_SCALE_FACTOR=$GSF_VALUE -I$EMBENCH_DIR/support -I$PORT_DIR"
mkdir -p "$BUILD_DIR/support" "$BUILD_DIR/config"
for s in main beebsc; do
  $CC $CFLAGS $DEFS -c "$EMBENCH_DIR/support/$s.c" -o "$BUILD_DIR/support/$s.o"
done
$CC $CFLAGS $DEFS -c "$PORT_DIR/boardsupport.c" -o "$BUILD_DIR/config/boardsupport.o"

benches=("$@")
[ ${#benches[@]} -gt 0 ] || benches=($(ls "$EMBENCH_DIR/src"))
for b in "${benches[@]}"; do
  d="$BUILD_DIR/src/$b"; mkdir -p "$d"; objs=()
  for c in "$EMBENCH_DIR/src/$b"/*.c; do
    o="$d/$(basename "${c%.c}").o"
    $CC $CFLAGS $DEFS -c "$c" -o "$o"
    objs+=("$o")
  done
  $CC -o "$d/$b" $LDFLAGS "${objs[@]}" "$BUILD_DIR/support/main.o" \
    "$BUILD_DIR/support/beebsc.o" "$BUILD_DIR/config/boardsupport.o" -lbm -lm -lgcc
  echo "built $b"
done
make -s --no-print-directory embench-post "${OVERRIDES[@]}"

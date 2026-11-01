#!/usr/bin/env bash
# Copyright 2026 Chuanxin Tang
# SPDX-License-Identifier: Apache-2.0
#
# Fallback build of the Simple System Verilator simulator WITHOUT FuseSoC.
# Use the FuseSoC flow (see ../../README.md) whenever FuseSoC is available;
# this script is for environments where it cannot be installed, and it is how
# the simulator for the records in ../../embench/validation/20261101-small
# was built.
#
# It compiles what the FuseSoC target lowrisc:ibex:ibex_simple_system (sim)
# compiles: the same RTL (with primgen-style wrappers for the generic
# primitives, see gen_prim_wrappers.py), the same C++ driver and DV utilities,
# and the sim target's Verilator options from ibex_simple_system.core
# (-Wno-MULTIDRIVEN in place of -Wall, as in that file). The parameters come
# from util/ibex_config.py <config> fusesoc_opts, passed as -G (vlogparam) or
# -D (vlogdefine) according to ibex_simple_system.core, plus RVFI, which
# ibex_top_tracing's default target defines.
#
# Usage: build_simple_system.sh [config] [output dir]
#   config:     an entry of ibex_configs.yaml, default small (e.g. maxperf)
#   output dir: default build/simple_system_<config> in the repository root
# The simulator is <output dir>/Vibex_simple_system; run_embench.sh and
# run_tiny.sh take it as SIM=<output dir>/Vibex_simple_system.
# Environment: VERILATOR (default verilator), JOBS (default 2), and
# LIBELF_CFLAGS / LIBELF_LDFLAGS if libelf is not installed system-wide.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
CONFIG="${1:-small}"
OUT="$(mkdir -p "${2:-$ROOT/build/simple_system_$CONFIG}" && cd "${2:-$ROOT/build/simple_system_$CONFIG}" && pwd)"
VERILATOR="${VERILATOR:-verilator}"
JOBS="${JOBS:-2}"
HERE="$(cd "$(dirname "$0")" && pwd)"

PRIM="$ROOT/vendor/lowrisc_ip/ip/prim/rtl"
GENERIC="$ROOT/vendor/lowrisc_ip/ip/prim_generic/rtl"
DV="$ROOT/vendor/lowrisc_ip/dv/verilator"

python3 "$HERE/gen_prim_wrappers.py" "$GENERIC" "$OUT/gen"

# Configuration parameters, mapped as FuseSoC maps them
read -r -a PARAMS <<< "$(python3 - "$ROOT" "$CONFIG" <<'PY'
import subprocess, sys, yaml
root, config = sys.argv[1], sys.argv[2]
core = yaml.safe_load(open(root + '/examples/simple_system/ibex_simple_system.core'))
kinds = {name: spec['paramtype'] for name, spec in core['parameters'].items()}
opts = subprocess.check_output([sys.executable, root + '/util/ibex_config.py', config,
                                'fusesoc_opts'], text=True).split()
flags = []
for opt in opts:
    name, value = opt[2:].split('=', 1)
    flags.append(('-G' if kinds[name] == 'vlogparam' else '-D') + name + '=' + value)
print(' '.join(flags + ['-DRVFI']))
PY
)"

FILES=(
  "$ROOT/examples/simple_system/lint/verilator_waiver.vlt"
  "$PRIM/prim_util_pkg.sv" "$PRIM/prim_ram_1p_pkg.sv" "$PRIM/prim_ram_2p_pkg.sv"
  "$PRIM/prim_secded_pkg.sv" "$PRIM/prim_cipher_pkg.sv"
  "$ROOT/rtl/ibex_pkg.sv" "$ROOT/rtl/ibex_tracer_pkg.sv"
  "$OUT"/gen/prim_*.sv
  "$GENERIC"/prim_generic_{buf,flop,clock_gating,ram_1p,ram_2p}.sv
  "$PRIM/prim_lfsr.sv"
)
for f in "$ROOT"/rtl/*.sv; do
  case "$f" in *_pkg.sv) ;; *) FILES+=("$f") ;; esac
done
FILES+=("$ROOT"/shared/rtl/*.sv "$ROOT/shared/rtl/sim/simulator_ctrl.sv"
        "$ROOT/examples/simple_system/rtl/ibex_simple_system.sv")
CPP=(
  "$ROOT/examples/simple_system/ibex_simple_system.cc"
  "$ROOT/examples/simple_system/ibex_simple_system_main.cc"
  "$DV/cpp/verilator_memutil.cc" "$DV/cpp/dpi_memutil.cc" "$DV/cpp/ecc32_mem_area.cc"
  "$DV/cpp/mem_area.cc" "$DV/cpp/sv_scoped.cc"
  "$DV/simutil_verilator/cpp/verilator_sim_ctrl.cc"
  "$DV/simutil_verilator/cpp/verilated_toplevel.cc"
  "$ROOT/dv/verilator/pcount/cpp/ibex_pcounts.cc"
  "$ROOT/vendor/lowrisc_ip/ip/prim/dv/prim_secded/secded_enc.c"
)
INCLUDES="-I$DV/cpp -I$DV/simutil_verilator/cpp -I$ROOT/dv/verilator/pcount/cpp"
INCLUDES="$INCLUDES -I$ROOT/vendor/lowrisc_ip/ip/prim/dv/prim_secded -I$ROOT/examples/simple_system"

echo "Building Vibex_simple_system ($CONFIG): ${PARAMS[*]}"
"$VERILATOR" --cc --exe --build -j "$JOBS" --Mdir "$OUT" -o Vibex_simple_system \
  --top-module ibex_simple_system \
  --trace --trace-fst --trace-structs --trace-params --trace-max-array 1024 \
  -CFLAGS "-std=c++11 -Wall -DVM_TRACE_FMT_FST -DTOPLEVEL_NAME=ibex_simple_system -g" \
  -LDFLAGS "-pthread -lutil -lelf" \
  -Wno-MULTIDRIVEN -Wwarn-IMPERFECTSCH --unroll-count 72 \
  "${PARAMS[@]}" \
  -I"$PRIM" -I"$ROOT/rtl" -I"$ROOT/vendor/lowrisc_ip/dv/sv/dv_utils" \
  -CFLAGS "$INCLUDES ${LIBELF_CFLAGS:-}" -LDFLAGS "${LIBELF_LDFLAGS:-}" \
  "${FILES[@]}" "${CPP[@]}" > "$OUT/build.log" 2>&1 \
  || { tail -40 "$OUT/build.log"; exit 1; }
echo "Built $OUT/Vibex_simple_system (log: $OUT/build.log)"

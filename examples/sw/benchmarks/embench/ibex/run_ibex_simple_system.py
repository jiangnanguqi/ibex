#!/usr/bin/env python3
# Copyright 2026 Chuanxin Tang
# SPDX-License-Identifier: Apache-2.0
"""Embench target module for Ibex Simple System.

Embench's speed script, vendor/embench-iot/benchmark_speed.py, measures a
platform through a target module: it loads the module by name
(--target-module run_ibex_simple_system, with this directory on PYTHONPATH)
and calls its run_benchmark() once for each benchmark. ../run_embench_score.sh
does all this; see ../../README.md. The module is the same as the
riscv-imt-model platform's run_riscv_model.py and the CV32E40P port's
run_cv32e40p_tb.py except for how a program is run and where its output is.

run_benchmark() runs the benchmark's ELF file on the simulator, as
../run_embench.sh does (<sim> +ibex_tracer_enable=0 --meminit=ram,<elf>), in
a directory of its own, <rundir>/<benchmark>/, because the simulator writes
ibex_simple_system.log and ibex_simple_system_pcount.csv under fixed names in
the current directory. The program's output is in ibex_simple_system.log:
  Embench cycles=<n> instret=<n>
                   printed by embench_report.c after the run: mcycle and
                   minstret, which count only from start_trigger to
                   stop_trigger (boardsupport.c), the part of the run that
                   Embench measures
  Main Exit=<n>    the value Embench's main returned, 0 when the benchmark's
                   own check (verify_benchmark) passes
  EXCEPTION!!!     printed by Simple System's exception handler, which then
                   ends the simulation
and the simulator's in its own output (console.txt):
  Terminating simulation by software request.
                   the program ended the simulation (simulator_ctrl.sv)
  Cycles: <n>, Instructions Retired: <n>
                   the same counters as printed by the simulator at the end
                   ("Performance Counters"); recorded as a check, not used
                   for the scores
It returns the time of the measured part in milliseconds,
cycles / (cpu_mhz * 1000), with cpu_mhz from benchmark_speed.py's own
option --cpu-mhz; benchmark_speed.py turns these times into the scores.

A run counts only if the simulator exited with status 0 within the time
limit (benchmark_speed.py's --timeout) after the program ended the
simulation, no exception was reported, Main Exit=0 was printed exactly once
and the counts were printed once, with a cycle count above zero. Otherwise
run_benchmark() logs the reason and returns None, which benchmark_speed.py
reports as a failed run. A run that counts prints one line on standard
error, to show the progress.

Each run leaves in <rundir>/<benchmark>/: console.txt (everything the
simulator printed), ibex_simple_system.log, ibex_simple_system_pcount.csv,
and result.json, with the counts, the outcome, the reason if the run did not
count, and the SHA-256 of the ELF file and of the simulator. An instruction
trace (trace_core_00000000.log, only if tracing were on) is deleted.

With --reuse, a benchmark whose result.json records a counted run of the
same ELF file (same SHA-256) is not run again: the stored cycle count is
used. run_embench_score.sh -R uses this to score earlier runs again with
another clock frequency. Without --sim nothing is run, so a benchmark
without such a stored run fails.

Run as a script, it prints a table of the runs in a run directory, with
the scores computed as benchmark_speed.py computes them, to four decimals
instead of two, and can write the counts to a CSV file:

    python3 run_ibex_simple_system.py RUNDIR --gsf GSF --cpu-mhz MHZ \
        [--csv FILE]

Embench's pylib/ must be on PYTHONPATH for this.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time

import embench_core
from embench_core import log

# The program's output, as the simulator writes it
PROGRAM_LOG = 'ibex_simple_system.log'
# Deleted after a run (see above)
DELETE = ('trace_core_00000000.log',)

# Lines of the program's output (PROGRAM_LOG) and of the simulator's
# (console.txt); see above. Each of the first three must appear exactly
# once in a run that counts.
COUNTS = re.compile(r'Embench cycles=(\d+) instret=(\d+)')
MAIN_EXIT = re.compile(r'Main Exit=(-?\d+)')
STOPPED = re.compile(r'^Terminating simulation by software request\.', re.M)
EXCEPTION = 'EXCEPTION!!!'
SIM_CYCLES = re.compile(r'^Cycles:\s+(\d+)\s*$', re.M)
SIM_INSTRET = re.compile(r'^Instructions Retired:\s+(\d+)\s*$', re.M)


def get_target_args(remnant):
    """Parses the options of this module, the arguments benchmark_speed.py
    does not know. benchmark_speed.py merges them with its own, so their
    names must differ from those of its options."""
    parser = argparse.ArgumentParser(
        description='Options of the target module run_ibex_simple_system')
    parser.add_argument(
        '--sim',
        type=str,
        default=None,
        help='the simulator (Vibex_simple_system) to run; without it nothing '
             'is run, and only stored runs can be used (--reuse)',
    )
    parser.add_argument(
        '--rundir',
        type=str,
        required=True,
        help='directory of the runs, one subdirectory for each benchmark',
    )
    parser.add_argument(
        '--reuse',
        action='store_true',
        help='use the stored counted run of the same ELF file, if there is '
             'one, instead of running it again',
    )
    return parser.parse_args(remnant)


def sha256_of(path):
    """Returns the SHA-256 of the file PATH, in hexadecimal."""
    digest = hashlib.sha256()
    with open(path, 'rb') as fileh:
        for chunk in iter(lambda: fileh.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def load_result(rundir, bench):
    """Returns the stored result.json of BENCH as a dictionary, or None if
    there is none or it cannot be read."""
    try:
        with open(os.path.join(rundir, bench, 'result.json')) as fileh:
            return json.load(fileh)
    except (OSError, ValueError):
        return None


def read_output(program, console):
    """Returns what the program's output PROGRAM and the simulator's output
    CONSOLE say, as a dictionary. A value is a list of every number found for
    its line (normally one), so that a missing or repeated line can be told
    apart."""
    counts = COUNTS.findall(program)
    return {
        'main_exit': [int(v) for v in MAIN_EXIT.findall(program)],
        'cycles': [int(c) for c, _ in counts],
        'instret': [int(i) for _, i in counts],
        'stopped': len(STOPPED.findall(console)),
        'exception': EXCEPTION in program,
        'simulator_cycles': [int(v) for v in SIM_CYCLES.findall(console)],
        'simulator_instret': [int(v) for v in SIM_INSTRET.findall(console)],
    }


def judge(found, timed_out, status, timeout):
    """Returns why a run does not count, or None if it counts. FOUND is
    what read_output() found, TIMED_OUT whether the time limit (TIMEOUT
    seconds) was reached and STATUS the simulator's exit status."""
    if timed_out:
        return f'still running after {timeout} s (the time limit, --timeout)'
    if status != 0:
        # A negative status is the signal that stopped the simulator
        return f'the simulator exited with status {status}'
    if found['stopped'] != 1:
        return 'the program did not end the simulation (no "Terminating ' \
               'simulation by software request." line)'
    if found['exception']:
        return 'the program took an exception (see ' + PROGRAM_LOG + ')'
    if len(found['main_exit']) != 1:
        return f'"Main Exit=" printed {len(found["main_exit"])} times, ' \
               f'not once'
    if found['main_exit'][0] != 0:
        return f'the benchmark\'s own check failed ' \
               f'(Main Exit={found["main_exit"][0]})'
    if len(found['cycles']) != 1:
        return f'"Embench cycles=" printed {len(found["cycles"])} times, ' \
               f'not once'
    if found['cycles'][0] == 0:
        return 'the cycle count is 0 (the counters never ran)'
    return None


def simulate(bench, elf, elf_sha, args):
    """Runs BENCH (ELF file ELF, SHA-256 ELF_SHA) on the simulator and
    stores the result; returns it as a dictionary."""
    rundir = os.path.join(os.path.abspath(args.rundir), bench)
    os.makedirs(rundir, exist_ok=True)
    result_file = os.path.join(rundir, 'result.json')
    # Neither a result nor the program's output may survive from an earlier
    # run into one that fails to write its own
    for name in ('result.json', PROGRAM_LOG):
        if os.path.exists(os.path.join(rundir, name)):
            os.remove(os.path.join(rundir, name))
    sim = os.path.abspath(args.sim)
    cmd = [sim, '+ibex_tracer_enable=0',
           '--meminit=ram,' + os.path.abspath(elf)]
    result = {
        'benchmark': bench,
        'elf': os.path.abspath(elf),
        'elf_sha256': elf_sha,
        'sim': sim,
        'sim_sha256': sha256_of(sim),
        'command': cmd,
        'directory': rundir,
        'started': time.strftime('%Y-%m-%d %H:%M:%S'),
    }
    timed_out = False
    status = None
    start = time.monotonic()
    with open(os.path.join(rundir, 'console.txt'), 'wb') as console:
        try:
            status = subprocess.run(cmd, cwd=rundir, stdin=subprocess.DEVNULL,
                                    stdout=console, stderr=subprocess.STDOUT,
                                    timeout=args.timeout).returncode
        except subprocess.TimeoutExpired:
            # subprocess.run has killed the simulator
            timed_out = True
    result['seconds'] = round(time.monotonic() - start, 1)
    for name in DELETE:
        path = os.path.join(rundir, name)
        if os.path.exists(path):
            os.remove(path)
    texts = []
    for name in (PROGRAM_LOG, 'console.txt'):
        try:
            with open(os.path.join(rundir, name), errors='replace') as fileh:
                texts.append(fileh.read())
        except OSError:
            texts.append('')
    found = read_output(*texts)
    reason = judge(found, timed_out, status, args.timeout)
    result['status'] = status
    result['timed_out'] = timed_out
    result['counted'] = reason is None
    result['reason'] = reason
    # One value each when the run counts; otherwise the first found, if any
    for key in ('main_exit', 'cycles', 'instret', 'simulator_cycles',
                'simulator_instret'):
        result[key] = found[key][0] if found[key] else None
    result['exception'] = found['exception']
    with open(result_file, 'w') as fileh:
        json.dump(result, fileh, indent=2)
        fileh.write('\n')
    return result


def run_benchmark(bench, path, args):
    """Called by benchmark_speed.py for each benchmark: runs benchmark BENCH,
    whose ELF file is PATH, or takes its stored run (--reuse). Returns the
    time of the measured part in milliseconds, or None if the run does not
    count."""
    elf_sha = sha256_of(path)
    if args.reuse:
        stored = load_result(args.rundir, bench)
        if (stored and stored.get('counted')
                and stored.get('elf_sha256') == elf_sha):
            log.debug(f'{bench}: stored run used, {stored["cycles"]} cycles')
            return stored['cycles'] / args.cpu_mhz / 1000.0
    if args.sim is None:
        log.warning(f'Warning: {bench}: no stored run of this ELF file that '
                    f'counts, and no --sim to run it')
        return None
    result = simulate(bench, path, elf_sha, args)
    if not result['counted']:
        log.warning(f'Warning: {bench}: {result["reason"]}')
        return None
    log.debug(f'{bench}: {result["cycles"]} cycles, {result["instret"]} '
              f'instructions, {result["seconds"]} s')
    # Progress, on standard error so as not to mix with the results
    print(f'{bench}: {result["cycles"]:,} cycles, Main Exit=0 '
          f'({result["seconds"]} s)', file=sys.stderr, flush=True)
    return result['cycles'] / args.cpu_mhz / 1000.0


def main():
    """The table of a run directory (see the docstring at the top)."""
    parser = argparse.ArgumentParser(
        description='Table of the runs in a run directory of '
                    'run_ibex_simple_system')
    parser.add_argument('rundir', help='the --rundir of the runs')
    parser.add_argument('--gsf', type=int, required=True,
                        help='the global scale factor the benchmarks were '
                             'built with')
    parser.add_argument('--cpu-mhz', type=int, required=True,
                        help='clock frequency in MHz for Speed and the times')
    parser.add_argument('--csv', default=None,
                        help='also write the counts of every run to this '
                             'CSV file')
    args = parser.parse_args()

    # The benchmarks and the reference times, where benchmark_speed.py
    # takes them from: the directories in src/ and
    # baseline-data/speed.json of the Embench tree that embench_core is in
    root = os.path.dirname(os.path.dirname(os.path.abspath(
        embench_core.__file__)))
    benchmarks = sorted(b for b in os.listdir(os.path.join(root, 'src'))
                        if os.path.isdir(os.path.join(root, 'src', b)))
    with open(os.path.join(root, 'baseline-data', 'speed.json')) as fileh:
        baseline = json.load(fileh)

    rows = []
    speed = {}
    per_mhz = {}
    for bench in benchmarks:
        res = load_result(args.rundir, bench) or {
            'counted': False, 'reason': 'not run (no result.json)'}
        row = {'benchmark': bench}
        for key in ('counted', 'reason', 'main_exit', 'cycles', 'instret',
                    'simulator_cycles'):
            row[key] = res.get(key)
        row['ipc'] = None
        row['speed_per_mhz'] = None
        if res.get('counted'):
            # As benchmark_speed.py: the time in ms, then the reference time
            # divided by it, times the GSF; Speed/MHz divides by the clock
            ms = res['cycles'] / args.cpu_mhz / 1000.0
            speed[bench] = baseline[bench] / ms * args.gsf
            per_mhz[bench] = speed[bench] / args.cpu_mhz
            row['ms'] = ms
            row['ipc'] = res['instret'] / res['cycles']
            row['speed_per_mhz'] = per_mhz[bench]
        rows.append(row)

    print(f'Embench speed of the runs in {os.path.abspath(args.rundir)}')
    print(f'gsf {args.gsf}, clock {args.cpu_mhz} MHz (Speed is Speed/MHz '
          f'times the clock frequency in MHz)')
    print()
    print(f'{"Benchmark":16}{"Cycles":>14}{"Instret":>14}{"IPC":>8}'
          f'{"Time (ms)":>14}{"Speed":>10}{"Speed/MHz":>11}')
    for row in rows:
        bench = row['benchmark']
        if bench in speed:
            print(f'{bench:16}{row["cycles"]:>14,}{row["instret"]:>14,}'
                  f'{row["ipc"]:>8.4f}{row["ms"]:>14,.3f}'
                  f'{speed[bench]:>10.4f}{per_mhz[bench]:>11.4f}')
        else:
            print(f'{bench:16}  did not count: {row["reason"]}')
    print()
    if len(speed) == len(benchmarks):
        # Embench's own statistics (relative values, as benchmark_speed.py)
        embench_core.gp['absolute'] = False
        stats = [embench_core.embench_stats(benchmarks, {}, data)
                 for data in (speed, per_mhz)]
        for i, name in enumerate(('Geometric mean', 'Geometric SD',
                                  'Geometric range')):
            print(f'{name:16}{"":>50}{stats[0][i]:>10.4f}{stats[1][i]:>11.4f}')
    else:
        print(f'No score: {len(benchmarks) - len(speed)} of the '
              f'{len(benchmarks)} benchmarks did not count.')

    if args.csv:
        columns = ('benchmark', 'counted', 'reason', 'main_exit', 'cycles',
                   'instret', 'ipc', 'speed_per_mhz', 'simulator_cycles')
        with open(args.csv, 'w') as fileh:
            fileh.write(','.join(columns) + '\n')
            for row in rows:
                values = []
                for col in columns:
                    value = row.get(col)
                    if value is None:
                        values.append('')
                    elif isinstance(value, bool):
                        values.append('yes' if value else 'no')
                    elif isinstance(value, float):
                        values.append(f'{value:.6f}')
                    elif isinstance(value, str):
                        values.append('"' + value.replace('"', '""') + '"')
                    else:
                        values.append(str(value))
                fileh.write(','.join(values) + '\n')
    return 0 if len(speed) == len(benchmarks) else 1


if __name__ == '__main__':
    sys.exit(main())

// Copyright 2026 Chuanxin Tang
// SPDX-License-Identifier: Apache-2.0
//
// MLPerf Tiny ad01 on Ibex Simple System: the platform side of platform.h.
//
// The bare-metal runtime is Simple System's own (crt0.S, simple_system_common.c,
// output through the simulator control port). This file adds what the TFLM
// C++ code and newlib need on top of it (constructor tables, heap, system
// calls), the counter control of the measured region, and the report. The
// report, including TFLM's diagnostics, is buffered and printed only after
// the measured region, so no output is written while the counters run.
// It is a C file: system_common.h-style printf macros and TFLM's C++ headers
// are kept apart, as in the platform's own sw/examples/mlperf_tiny/platform.c.

#include "platform.h"

#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#include "bench_counters.h"
#include "simple_system_common.h"

// ---- constructors and the measured region ----------------------------------

typedef void (*init_fn)(void);
extern init_fn __preinit_array_start[], __preinit_array_end[];
extern init_fn __init_array_start[], __init_array_end[];

void tiny_runtime_init(void) {
  // crt0.S clears .bss and sets the stack but does not run C++ constructors.
  for (init_fn *fn = __preinit_array_start; fn < __preinit_array_end; ++fn) {
    (*fn)();
  }
  for (init_fn *fn = __init_array_start; fn < __init_array_end; ++fn) {
    (*fn)();
  }
  // Ibex's counters run from reset; keep them stopped until the measured
  // region so the values read afterwards are the region's alone.
  bench_counters_stop();
}

static uint64_t measured_cycles, measured_instructions;

// The measured region: see ../common/bench_counters.h (shared with the
// CV32E40P port so that it contains the same instructions on both cores).
int tiny_measure_begin(void) {
  bench_counters_start();
  return 0;
}

void tiny_measure_end(void) {
  bench_counters_stop();
  measured_cycles = bench_read_mcycle();
  measured_instructions = bench_read_minstret();
}

// ---- buffered report -------------------------------------------------------

struct tiny_check {
  unsigned fixture, mismatches;
  uint32_t hash, score_bits, expected_score_bits;
};

static char diagnostics[2048];
static unsigned diagnostic_bytes;
static unsigned arena_bytes, check_count, iterations, passed;
static struct tiny_check checks[3];
static const char *error_stage;
static unsigned error_code;

void tiny_write(const char *data, unsigned count) {
  for (unsigned i = 0; i < count && diagnostic_bytes + 1 < sizeof(diagnostics); ++i) {
    diagnostics[diagnostic_bytes++] = data[i];
  }
  diagnostics[diagnostic_bytes] = 0;
}

void tiny_print(const char *text) { tiny_write(text, (unsigned)strlen(text)); }

void tiny_print_arena(unsigned bytes) { arena_bytes = bytes; }

void tiny_print_check(unsigned fixture, unsigned mismatches, uint32_t hash,
                      uint32_t score_bits, uint32_t expected_score_bits) {
  if (check_count >= 3) {
    error_stage = "extra_check";
    error_code = 1;
    return;
  }
  checks[check_count++] = (struct tiny_check){fixture, mismatches, hash, score_bits,
                                              expected_score_bits};
}

void tiny_print_error(const char *stage, unsigned code) {
  error_stage = stage;
  error_code = code;
}

void tiny_print_measurement(unsigned count) { iterations = count; }

void tiny_mark_pass(void) { passed = 1; }

// Prints the report (the same lines as the platform's example) and halts.
void tiny_finish(int status) {
  bench_counters_stop();
  if (error_stage || !passed || check_count != 3 || !iterations ||
      !measured_cycles || !measured_instructions) {
    status = status ? status : 83;
  }
  printf("MLPerf Tiny ad01: single hart, portable int8 TFLM\n");
  printf("TINY_ARENA used_bytes=%u reserved_bytes=65536\n", arena_bytes);
  for (unsigned i = 0; i < check_count; ++i) {
    const struct tiny_check *c = &checks[i];
    printf("TINY_CHECK fixture=%u mismatches=%u hash=%08lx score_bits=%08lx "
           "expected_score_bits=%08lx\n", c->fixture, c->mismatches,
           (unsigned long)c->hash, (unsigned long)c->score_bits,
           (unsigned long)c->expected_score_bits);
  }
  printf("TINY_STATS iterations=%u cycles=%llu instructions=%llu\n", iterations,
         (unsigned long long)measured_cycles, (unsigned long long)measured_instructions);
  if (error_stage) {
    printf("TINY_ERROR stage=%s code=%u\n", error_stage, error_code);
  }
  if (diagnostic_bytes) {
    printf("TINY_LOG bytes=%u\n%s\n", diagnostic_bytes, diagnostics);
  }
  printf("TINY_%s fixtures=%u output_bytes_per_fixture=640 measured_output=%s exit=%u\n",
         status ? "FAIL" : "PASS", check_count, passed ? "PASS" : "FAIL", (unsigned)status);
  printf("Main Exit=%u\n", (unsigned)status);
  fflush(stdout);
  sim_halt();
  for (;;) {
    __asm__ volatile("wfi");
  }
}

// ---- newlib system calls ---------------------------------------------------

extern char __heap_start[], __heap_end[];

void *_sbrk(ptrdiff_t increment) {
  static char *cursor;
  if (!cursor) {
    cursor = __heap_start;
  }
  if ((increment > 0 && increment > __heap_end - cursor) ||
      (increment < 0 && increment < __heap_start - cursor)) {
    errno = ENOMEM;
    return (void *)-1;
  }
  char *old = cursor;
  cursor += increment;
  return old;
}

int _write(int fd, const void *data, size_t count) {
  (void)fd;
  for (size_t i = 0; i < count; ++i) {
    putchar(((const char *)data)[i]);
  }
  return (int)count;
}

int _read(int fd, void *data, size_t count) {
  (void)fd;
  (void)data;
  (void)count;
  return 0;
}

int _close(int fd) {
  (void)fd;
  errno = EBADF;
  return -1;
}

int _fstat(int fd, struct stat *out) {
  (void)fd;
  out->st_mode = S_IFCHR;
  return 0;
}

int _isatty(int fd) {
  (void)fd;
  return 1;
}

int _lseek(int fd, int offset, int whence) {
  (void)fd;
  (void)offset;
  (void)whence;
  return 0;
}

int _getpid(void) { return 1; }

int _kill(int pid, int signal) {
  (void)pid;
  (void)signal;
  errno = EINVAL;
  return -1;
}

void _exit(int status) { tiny_finish(status); }

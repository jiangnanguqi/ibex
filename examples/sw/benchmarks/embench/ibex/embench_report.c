// Copyright 2026 Chuanxin Tang
// SPDX-License-Identifier: Apache-2.0
//
// Report for the Embench benchmarks on Ibex Simple System.
//
// Embench's support/main.c is compiled unchanged. The link option
// -Wl,--wrap=main (see ../Makefile) makes the start-up code call __wrap_main,
// which runs the real main and then prints the measured region's cycle and
// retired-instruction counts and the verification result. The counters were
// stopped in stop_trigger (ibex/boardsupport.c) and are not touched in
// between, so they still hold the measured region when they are read here.
// The simulator prints the same counters at exit, as it does for CoreMark.

#include <stdint.h>

#include "bench_counters.h"
#include "simple_system_common.h"

extern int __real_main(int argc, char *argv[]);

// Simple System has puthex only; print a 64-bit count in decimal.
static void putdec(uint64_t value) {
  char digits[21];
  int n = 0;
  do {
    digits[n++] = (char)('0' + value % 10);
    value /= 10;
  } while (value != 0);
  while (n > 0) {
    putchar(digits[--n]);
  }
}

int __wrap_main(int argc, char *argv[]) {
  int exit_code = __real_main(argc, argv);

  puts("Embench cycles=");
  putdec(bench_read_mcycle());
  puts(" instret=");
  putdec(bench_read_minstret());
  putchar('\n');
  // 0 when verify_benchmark() accepted the result; printed as on the platform.
  puts("Main Exit=");
  putdec((unsigned)exit_code);
  putchar('\n');

  return exit_code;
}

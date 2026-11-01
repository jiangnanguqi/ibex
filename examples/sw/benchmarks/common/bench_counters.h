// Copyright 2026 Chuanxin Tang
// SPDX-License-Identifier: Apache-2.0
//
// Control of the measured region for the Embench and MLPerf Tiny benchmarks:
// mcycle and minstret are stopped, cleared and started through mcountinhibit
// (CSR 0x320, written by number: binutils of the platform's toolchain only
// knows the old name) and read back after the region.
//
// This file is the same in the Ibex and CV32E40P ports, and the Ibex port
// does not use Simple System's pcount_enable()/pcount_reset() here, so that
// the few counter-control instructions inside the measured region compile to
// the same code on both cores and the instruction counts stay identical.

#ifndef BENCH_COUNTERS_H__
#define BENCH_COUNTERS_H__

#include <stdint.h>

#define BENCH_CSR_WRITE(csr, value) \
  __asm__ volatile("csrw " #csr ", %0" : : "r"((uint32_t)(value)) : "memory")
#define BENCH_CSR_READ(csr)                                            \
  ({                                                                   \
    uint32_t value_;                                                   \
    __asm__ volatile("csrr %0, " #csr : "=r"(value_) : : "memory");    \
    value_;                                                            \
  })

// Stops the counters (all of them, as pcount_enable(0) does).
static inline void bench_counters_stop(void) { BENCH_CSR_WRITE(0x320, 0xFFFFFFFF); }

// Clears mcycle and minstret and starts the counters: the measured region
// begins with the instruction after the write to mcountinhibit.
static inline void bench_counters_start(void) {
  BENCH_CSR_WRITE(0x320, 0xFFFFFFFF);
  BENCH_CSR_WRITE(mcycle, 0);
  BENCH_CSR_WRITE(mcycleh, 0);
  BENCH_CSR_WRITE(minstret, 0);
  BENCH_CSR_WRITE(minstreth, 0);
  BENCH_CSR_WRITE(0x320, 0);
}

static inline uint64_t bench_read_mcycle(void) {
  uint32_t lo, hi, hi_again;
  do {
    hi = BENCH_CSR_READ(mcycleh);
    lo = BENCH_CSR_READ(mcycle);
    hi_again = BENCH_CSR_READ(mcycleh);
  } while (hi != hi_again);
  return ((uint64_t)hi << 32) | lo;
}

static inline uint64_t bench_read_minstret(void) {
  uint32_t lo, hi, hi_again;
  do {
    hi = BENCH_CSR_READ(minstreth);
    lo = BENCH_CSR_READ(minstret);
    hi_again = BENCH_CSR_READ(minstreth);
  } while (hi != hi_again);
  return ((uint64_t)hi << 32) | lo;
}

#endif  // BENCH_COUNTERS_H__

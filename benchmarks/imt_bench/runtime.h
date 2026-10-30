// SPDX-License-Identifier: Apache-2.0
#ifndef IMT_BENCH_RUNTIME_H
#define IMT_BENCH_RUNTIME_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void bench_runtime_init(void);
void bench_finish(int status) __attribute__((noreturn));
void bench_measure_begin(void);
void bench_measure_end(void);
void bench_putchar(char c);
void bench_trap(unsigned cause, unsigned pc) __attribute__((noreturn));
extern const unsigned bench_is_tiny, bench_gsf;
extern uint64_t bench_cycles, bench_instructions;
#ifdef __cplusplus
}
#endif
#endif

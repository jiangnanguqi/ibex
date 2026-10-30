// SPDX-License-Identifier: Apache-2.0
#ifndef IMT_TINY_PLATFORM_H_
#define IMT_TINY_PLATFORM_H_
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// These calls buffer the single HART report. tiny_finish() flushes after timing.
void tiny_print(const char* text);
void tiny_write(const char* data, unsigned count);
void tiny_print_check(unsigned fixture, unsigned mismatches, uint32_t hash,
                      uint32_t score_bits, uint32_t expected_score_bits);
void tiny_print_error(const char* stage, unsigned code);
void tiny_print_arena(unsigned bytes);
// Begin/end control this core's mcycle and minstret measurement window.
int tiny_measure_begin(void);
void tiny_measure_end(void);
void tiny_print_measurement(unsigned iterations);
void tiny_mark_pass(void);
void tiny_runtime_init(void);
void tiny_finish(int exit_code) __attribute__((noreturn));
#ifdef __cplusplus
}
#endif
#endif


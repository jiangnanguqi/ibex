/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Adapt only Embench's board hooks; upstream main and benchmark bodies are unchanged. */
#include "../runtime.h"
void initialise_board(void) {}
void __attribute__((noinline)) start_trigger(void) { bench_measure_begin(); }
void __attribute__((noinline)) stop_trigger(void) { bench_measure_end(); }

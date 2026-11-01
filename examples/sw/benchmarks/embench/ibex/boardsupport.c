/* Copyright (C) 2017 Embecosm Limited and University of Bristol

   Contributor Graham Markall <graham.markall@embecosm.com>

   Modified for Ibex Simple System: start_trigger and stop_trigger start and
   stop the cycle and retired-instruction counters through mcountinhibit (see
   ../../common/bench_counters.h, shared with the CV32E40P port so that the
   measured regions contain the same instructions on both cores). The counts
   are read afterwards by embench_report.c.

   This file is part of Embench and was formerly part of the Bristol/Embecosm
   Embedded Benchmark Suite.

   SPDX-License-Identifier: GPL-3.0-or-later */

#include <support.h>
#include "bench_counters.h"
#include "boardsupport.h"

void
initialise_board ()
{
  __asm__ volatile ("li a0, 0" : : : "memory");
}

void __attribute__ ((noinline))
start_trigger ()
{
  bench_counters_start ();
}

void __attribute__ ((noinline))
stop_trigger ()
{
  bench_counters_stop ();
}

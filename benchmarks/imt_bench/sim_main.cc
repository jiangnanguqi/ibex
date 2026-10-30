// SPDX-License-Identifier: Apache-2.0
#include <verilated.h>
#include <cstdlib>
#include <cstdio>
#include <string>
#ifdef BENCH_IBEX
#include "Vibex_simple_system.h"
using Top = Vibex_simple_system;
#else
#include "Vbench_top.h"
using Top = Vbench_top;
#endif
int main(int argc,char** argv) {
  VerilatedContext context;
  context.commandArgs(argc,argv);
  Top top{&context};
  // Drive an actual falling reset edge before holding reset. Some core state
  // is behind clock gates and would not reset from an initial 0 alone.
#ifdef BENCH_IBEX
  top.IO_CLK=0;top.IO_RST_N=1;top.eval();
  top.IO_RST_N=0;top.eval();
#else
  top.clk_i=0;top.rst_ni=1;top.eval();
  top.rst_ni=0;top.eval();
#endif
  uint64_t limit=2000000000ULL;
  for(int i=1;i<argc;i++) if(std::string(argv[i]).rfind("+max_cycles=",0)==0)
    limit=std::strtoull(argv[i]+12,nullptr,0);
  for(uint64_t cycle=0;cycle<limit && !context.gotFinish();cycle++) {
#ifdef BENCH_IBEX
    top.IO_RST_N=cycle>=8;top.IO_CLK=0;top.eval();context.timeInc(1);
    top.IO_CLK=1;top.eval();context.timeInc(1);
#else
    top.rst_ni=cycle>=8;top.clk_i=0;top.eval();context.timeInc(1);
    top.clk_i=1;top.eval();context.timeInc(1);
#endif
  }
  const bool finished=context.gotFinish();
  top.final();
  if(!finished)std::fprintf(stderr,"BENCH_TIMEOUT\n");
  return finished?0:124;
}

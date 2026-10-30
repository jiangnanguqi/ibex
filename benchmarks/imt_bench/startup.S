// SPDX-License-Identifier: Apache-2.0
.section .vectors,"ax",@progbits
.option norvc
.global _vectors_start
_vectors_start:
.rept 32
  j trap_entry
.endr
.global _start
_start:
.option push
.option norelax
  la gp,__global_pointer$
.option pop
  la sp,__stack_top
  la t0,_vectors_start
  csrw mtvec,t0
  csrw mie,zero
  csrw mstatus,zero
  la t0,__bss_start
  la t1,__bss_end
1:
  bgeu t0,t1,2f
  sw zero,0(t0)
  addi t0,t0,4
  j 1b
2:
  call bench_runtime_init
  la s0,__preinit_array_start
  la s1,__preinit_array_end
3:
  bgeu s0,s1,4f
  lw t0,0(s0)
  jalr ra,t0,0
  addi s0,s0,4
  j 3b
4:
  la s0,__init_array_start
  la s1,__init_array_end
5:
  bgeu s0,s1,6f
  lw t0,0(s0)
  jalr ra,t0,0
  addi s0,s0,4
  j 5b
6:
  li a0,0
  li a1,0
  call main
  call bench_finish
7:
  j 7b
.balign 4
trap_entry:
  csrr a0,mcause
  csrr a1,mepc
  call bench_trap
  j 7b

/* Copyright lowRISC contributors.
   Licensed under the Apache License, Version 2.0, see LICENSE for details.
   SPDX-License-Identifier: Apache-2.0

   Modified by Chuanxin Tang for the Embench and MLPerf Tiny benchmarks on
   Ibex Simple System: Simple System's link.ld
   (examples/sw/simple_system/common/link.ld) with the whole 1 MiB of RAM (the MLPerf Tiny image is about 420 KiB), a
   16 KiB stack at the top, a heap for newlib between the end of .bss and the
   stack, and the C++ constructor tables that the MLPerf Tiny platform code
   runs. crt0.S's symbols and the entry point at _vectors_start + 0x80 are
   unchanged.

   __global_pointer$ is deliberately not defined, as in Simple System's
   link.ld (crt0.S leaves gp at zero): the linker then does not relax
   small-data accesses to gp-relative addressing. The riscv-imt-model
   platform's single-hart build (sw/system/crt.S, link.ld) is the same, so the
   instruction counts of the measured regions can be compared with it; with a
   global pointer the counts would depend on where the linker happens to put
   the small data. The CV32E40P port links the same way.

   In .rodata, .data and .bss the Embench objects (built under
   build-embench/) are placed first, 16-byte aligned, with the same input
   patterns as in the CV32E40P port's script, so that the benchmarks' data
   have the same addresses modulo 16 on both cores: newlib's memcpy chooses
   between its word-wise and byte-wise loops by the alignment of its
   arguments, and with a different layout md5sum and qrduino executed
   slightly different instruction counts on the two cores. */

OUTPUT_ARCH(riscv)

MEMORY
{
    ram         : ORIGIN = 0x00100000, LENGTH = 0xFC000 /* 1008 kB */
    stack       : ORIGIN = 0x001FC000, LENGTH = 0x4000  /* 16 kB */
}

/* Stack information variables */
_min_stack      = 0x2000;   /* 8K - minimum stack space to reserve */
_stack_len     = LENGTH(stack);
_stack_start   = ORIGIN(stack) + LENGTH(stack);

_entry_point = _vectors_start + 0x80;
ENTRY(_entry_point)

/* The tohost address is used by Spike for a magic "stop me now" message. This
   is set to equal SIM_CTRL_CTRL (see simple_system_regs.h), which has that
   effect in simple_system simulations. Note that it must be 8-byte aligned.

   We don't read data back from Spike, so fromhost is set to some dummy value:
   we place it just above the top of the stack.
 */
tohost   = 0x20008;
fromhost = _stack_start + 0x10;

SECTIONS
{
    .vectors :
    {
        . = ALIGN(4);
        _vectors_start = .;
        KEEP(*(.vectors))
        _vectors_end = .;
    } > ram

    .text : {
        *(.text .text.*)
    } > ram

    .rodata : {
        /* benchmark objects first, identically in the Ibex and CV32E40P
           ports (see the note above) */
        . = ALIGN(16);
        *build-embench/*(.srodata .srodata.* .rodata .rodata.*)
        . = ALIGN(16);
        *(.srodata .srodata.* .rodata .rodata.*)
    } > ram

    /* C++ constructor tables, run by tiny_runtime_init() (MLPerf Tiny) */
    .preinit_array : ALIGN(4) {
        __preinit_array_start = .;
        KEEP(*(.preinit_array))
        __preinit_array_end = .;
    } > ram

    .init_array : ALIGN(4) {
        __init_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        __init_array_end = .;
    } > ram

    /* never run: the program ends by halting the simulation */
    .fini_array : ALIGN(4) {
        KEEP(*(.fini_array .fini_array.*))
    } > ram

    .data : {
        /* benchmark objects first, identically in the Ibex and CV32E40P
           ports (see the note above) */
        . = ALIGN(16);
        *build-embench/*(.sdata .sdata.* .data .data.*)
        . = ALIGN(16);
        /* Small data before large data */
        *(.sdata)
        *(.sdata.*)
        *(.data);
        *(.data.*)
    } > ram

    .bss :
    {
        . = ALIGN(4);
        _bss_start = .;
        /* benchmark objects first, identically in the Ibex and CV32E40P
           ports (see the note above) */
        . = ALIGN(16);
        *build-embench/*(.sbss .sbss.* .bss .bss.* COMMON)
        . = ALIGN(16);
        /* Small BSS before large BSS */
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        _bss_end = .;
    } > ram

    /* newlib heap (_sbrk in the MLPerf Tiny platform code): the rest of ram */
    __heap_start = ALIGN(16);
    __heap_end = ORIGIN(ram) + LENGTH(ram);
    ASSERT(__heap_start < __heap_end, "program exceeds RAM below the stack")

    /* ensure there is enough room for stack */
    .stack (NOLOAD): {
        . = ALIGN(4);
        . = . + _min_stack ;
        . = ALIGN(4);
        stack = . ;
        _stack = . ;
    } > stack

    /DISCARD/ : { *(.eh_frame .eh_frame.* .comment) }
}

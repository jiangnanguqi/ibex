/* SPDX-License-Identifier: Apache-2.0 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x00100000, LENGTH = 0x00100000 }
SECTIONS {
 .vectors : { KEEP(*(.vectors)) } > RAM
 .text : { *(.text .text.*) } > RAM
 .rodata : { *(.srodata .srodata.* .rodata .rodata.*) } > RAM
 .preinit_array : ALIGN(4) {
  __preinit_array_start = .; KEEP(*(.preinit_array)) __preinit_array_end = .;
 } > RAM
 .init_array : ALIGN(4) {
  __init_array_start = .; KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*))) KEEP(*(.init_array)) __init_array_end = .;
 } > RAM
 .fini_array : ALIGN(4) { KEEP(*(.fini_array .fini_array.*)) } > RAM
 .data : ALIGN(16) { *(.data .data.*) __global_pointer$ = . + 0x800; *(.sdata .sdata.*) } > RAM
 .bss (NOLOAD) : ALIGN(16) { __bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(16); __bss_end = .; } > RAM
 __heap_start = ALIGN(.,16);
 __stack_top = ORIGIN(RAM)+LENGTH(RAM);
 __heap_end = __stack_top-0x4000;
 ASSERT(__heap_start < __heap_end, "program exceeds RAM below 16 KiB stack")
 /DISCARD/ : { *(.eh_frame .eh_frame.* .comment) }
}

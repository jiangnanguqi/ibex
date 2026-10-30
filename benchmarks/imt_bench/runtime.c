// SPDX-License-Identifier: Apache-2.0
#include "runtime.h"
#include "tiny/platform.h"
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <sys/stat.h>

#define CSR_READ(csr) ({ uint32_t x; __asm__ volatile("csrr %0, " #csr : "=r"(x) :: "memory"); x; })
#define CSR_WRITE(csr, x) __asm__ volatile("csrw " #csr ", %0" :: "r"((uint32_t)(x)) : "memory")
#define REG32(a) (*(volatile uint32_t *)(a))
uint64_t bench_cycles, bench_instructions;
static unsigned began, ended;
static uint64_t counter_cycles(void) {
  uint32_t hi,lo,again;
  do { hi=CSR_READ(0xb80); lo=CSR_READ(0xb00); again=CSR_READ(0xb80); } while(hi!=again);
  return ((uint64_t)hi<<32)|lo;
}
static uint64_t counter_instructions(void) {
  uint32_t hi,lo,again;
  do { hi=CSR_READ(0xb82); lo=CSR_READ(0xb02); again=CSR_READ(0xb82); } while(hi!=again);
  return ((uint64_t)hi<<32)|lo;
}
void bench_runtime_init(void) {
  CSR_WRITE(0x320,5);
  CSR_WRITE(0xb00,0); CSR_WRITE(0xb80,0);
  CSR_WRITE(0xb02,0); CSR_WRITE(0xb82,0);
}
void __attribute__((noinline)) bench_measure_begin(void) {
  if (began || ended) bench_finish(80);
  began=1;
  CSR_WRITE(0xb00,0); CSR_WRITE(0xb80,0);
  CSR_WRITE(0xb02,0); CSR_WRITE(0xb82,0);
  CSR_WRITE(0x320,0);
}
void __attribute__((noinline)) bench_measure_end(void) {
  CSR_WRITE(0x320,5);
  bench_cycles=counter_cycles(); bench_instructions=counter_instructions();
  ended=1;
}
void bench_putchar(char c) { REG32(0x20000u)=(unsigned char)c; }
static void halt(int status) __attribute__((noreturn));
static void halt(int status) {
  CSR_WRITE(0x320,5);
  REG32(0x20008u)=((uint32_t)status<<1)|1u;
  for(;;) __asm__ volatile("wfi");
}
void bench_finish(int status) {
  CSR_WRITE(0x320,5);
  if(bench_is_tiny) tiny_finish(status);
  if (!began || !ended || !bench_cycles || !bench_instructions) status=status?status:81;
  printf("EMBENCH_STATS gsf=%u cycles=%llu instructions=%llu\n",bench_gsf,
    (unsigned long long)bench_cycles,(unsigned long long)bench_instructions);
  printf("EMBENCH_%s exit=%u\n",status?"FAIL":"PASS",(unsigned)status);
  fflush(stdout);
  halt(status);
}
void bench_trap(unsigned cause,unsigned pc) {
  CSR_WRITE(0x320,5);
  printf("BENCH_TRAP cause=%08x pc=%08x\n",cause,pc);
  fflush(stdout); halt(82);
}

// Buffer all TFLM diagnostics until measurement has ended.
static char tiny_log[2048];
static unsigned log_bytes, arena_bytes, check_count, iterations, passed;
struct TinyCheck { unsigned fixture,mismatches; uint32_t hash,score,expected; };
static struct TinyCheck checks[3];
static const char *error_stage;
static unsigned error_code;
void tiny_write(const char* data,unsigned count) {
  for(unsigned i=0;i<count && log_bytes+1<sizeof(tiny_log);i++) tiny_log[log_bytes++]=data[i];
  tiny_log[log_bytes]=0;
}
void tiny_print(const char* text) { while(*text) tiny_write(text++,1); }
void tiny_print_arena(unsigned bytes) { arena_bytes=bytes; }
void tiny_print_check(unsigned fixture,unsigned mismatches,uint32_t hash,
                      uint32_t score,uint32_t expected) {
  if(check_count>=3) { error_stage="extra_check";error_code=1;return; }
  checks[check_count++]=(struct TinyCheck){fixture,mismatches,hash,score,expected};
}
void tiny_print_error(const char* stage,unsigned code) { error_stage=stage;error_code=code; }
int tiny_measure_begin(void) { bench_measure_begin();return 0; }
void tiny_measure_end(void) { bench_measure_end(); }
void tiny_print_measurement(unsigned count) { iterations=count; }
void tiny_mark_pass(void) { passed=1; }
void tiny_runtime_init(void) { bench_runtime_init(); }
void tiny_finish(int status) {
  CSR_WRITE(0x320,5);
  if(error_stage || !passed || check_count!=3 || !iterations || !began || !ended ||
      !bench_cycles || !bench_instructions) status=status?status:83;
  printf("MLPerf Tiny ad01: single HART, portable int8 TFLM\n");
  printf("TINY_ARENA hart=0 used_bytes=%u reserved_bytes=65536\n",arena_bytes);
  for(unsigned i=0;i<check_count;i++) {
    const struct TinyCheck *c=&checks[i];
    printf("TINY_CHECK hart=0 fixture=%u mismatches=%u hash=%08x score_bits=%08x expected_score_bits=%08x\n",
      c->fixture,c->mismatches,c->hash,c->score,c->expected);
  }
  printf("TINY_STATS hart=0 iterations=%u cycles=%llu instructions=%llu\n",iterations,
    (unsigned long long)bench_cycles,(unsigned long long)bench_instructions);
  if(error_stage) printf("TINY_ERROR stage=%s code=%u\n",error_stage,error_code);
  if(log_bytes) printf("TINY_LOG bytes=%u\n%s\n",log_bytes,tiny_log);
  printf("TINY_%s hart=0 fixtures=%u output_bytes_per_fixture=640 measured_output=%s exit=%u\n",
    status?"FAIL":"PASS",check_count,passed?"PASS":"FAIL",(unsigned)status);
  printf("TINY_TOTAL harts=1 total_inferences=%u window_cycles=%llu instructions=%llu\n",
    iterations,(unsigned long long)bench_cycles,(unsigned long long)bench_instructions);
  printf("TINY_ALL_%s harts=1 uart_after_measurement=1\n",status?"FAIL":"PASS");
  fflush(stdout);halt(status);
}

extern char __heap_start[],__heap_end[];
void* _sbrk(ptrdiff_t increment) {
  static char* cursor;
  if(!cursor)cursor=__heap_start;
  if((increment>0 && increment>__heap_end-cursor)||
     (increment<0 && increment<__heap_start-cursor)) { errno=ENOMEM;return(void*)-1; }
  char* old=cursor;cursor+=increment;return old;
}
int _write(int fd,const void* data,size_t count) {
  (void)fd;
  for(size_t i=0;i<count;i++)bench_putchar(((const char*)data)[i]);
  return(int)count;
}
int _read(int fd,void* data,size_t count) { (void)fd;(void)data;(void)count;return 0; }
int _close(int fd) { (void)fd;errno=EBADF;return -1; }
int _fstat(int fd,struct stat* out) { (void)fd;out->st_mode=S_IFCHR;return 0; }
int _isatty(int fd) { (void)fd;return 1; }
int _lseek(int fd,int offset,int whence) { (void)fd;(void)offset;(void)whence;return 0; }
int _getpid(void) { return 1; }
int _kill(int pid,int signal) { (void)pid;(void)signal;errno=EINVAL;return -1; }
void _exit(int status) { bench_finish(status); }
void _init(void) {}
void _fini(void) {}

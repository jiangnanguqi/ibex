// Simple parallel support for CoreMark running on IBEX
// Software Simulation Only, no Verification

#include <stddef.h>

// 假设裸机环境下的硬件和编译器支持多线程操作

// Define thread id type
typedef unsigned int thread_id_t;
// Define thread state type
typedef int thread_state_t;
// Define thread function type
typedef void *(*thread_func_t)(void*);

// Define thread state
#define THREAD_CREATED    0
#define THREAD_READY      1
#define THREAD_RUNNING    2
#define THREAD_BLOCKED    3
#define THREAD_TERMINATED 4

// Thread Control Block (TCB)
typedef struct {
    thread_id_t tid;        // Thread Identifier
    thread_state_t state;   // Thread State
    thread_func_t function; // Thread Function Pointer
    void* arg;              // Thread Function Arguments
    void* stack_ptr;        // Thread Stack Pointer
} thread_t;

// 全局变量，用于存储当前活动的线程
extern thread_t* current_thread;

int thread_create(thread_t* thread, thread_id_t id, thread_func_t function, void* arg, void* stack_ptr);

int thread_schedule();

int thread_entry();

int thread_exit();

int thread_join(thread_t* thread);
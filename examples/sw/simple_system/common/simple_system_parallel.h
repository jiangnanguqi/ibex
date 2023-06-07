// Simple parallel support for CoreMark running on IBEX
// Software Simulation Only, no Verification

#include <stddef.h>

// 假设裸机环境下的硬件和编译器支持多线程操作

// 定义线程函数类型
typedef void *(*thread_func_t)(void*);

// 定义线程控制块（TCB）
typedef struct {
    void* stack_ptr;        // 栈指针
    thread_func_t function; // 线程函数指针
    void* arg;              // 线程函数参数
    // 其他线程相关的信息
} thread_t;

// 全局变量，用于存储当前活动的线程
extern thread_t* current_thread;

void thread_create(thread_t* thread, thread_func_t function, void* arg, void* stack_ptr);
void thread_entry();
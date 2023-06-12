// Simple parallel support for CoreMark running on IBEX
// Software Simulation Only, no Verification

#include <stddef.h>
#include "simple_system_parallel.h"

// 假设裸机环境下的硬件和编译器支持多线程操作

// // Thread Control Block (TCB)
// typedef struct {
//     thread_id_t tid;        // Thread Identifier
//     thread_state_t state;   // Thread State
//     thread_func_t function; // Thread Function Pointer
//     void* arg;              // Thread Function Arguments
//     void* stack_ptr;        // Thread Stack Pointer
// } thread_t;

// 全局变量，用于存储当前活动的线程
thread_t* current_thread = NULL;

// Create and initialise thread
int thread_create(thread_t* thread, thread_id_t id, thread_func_t function, void* arg, void* stack_ptr) {
    // Initialise thread
    thread->tid = id;
    thread->state = THREAD_CREATED;
    thread->stack_ptr = stack_ptr;
    thread->function = function;
    thread->arg = arg;
    // Thread initialised
    thread->state = THREAD_READY;
    return 0; // if succuss, return 0
}

// Schedule thread to system (hart)
//  Interface between software and hardware
// ...
int thread_schedule(thread_t* thread) {
    // 切换到下一个线程的上下文
    // Context Switching
    // 这里可以使用汇编代码或处理器提供的指令来实现上下文切换
    // Can use Assembly Code or Processor Instructions
    int hart_idle;
    // Check hart availability
    //   Ecall ? -- Get mstatus of another hart
    //
    // ...
    hart_idle = 0;

    if (hart_idle == 1) {
        // Start scheduling
        //   Copy context to a new hart
        //
        // ...
        return 0; // if succuss, return 0
    } else {
        return 1; // if fail, return ERRNO
    }

}

// Thread entry function
int thread_entry(thread_t* thread) {
    if (thread->state == THREAD_READY) {
        // Run thread function
        thread->state = THREAD_RUNNING;
        thread->function(thread->arg);
        // Finished, Terminate the thread
        thread_exit(thread);
        return 0; // if succuss, return 0
    } else {
        return -1; // if fail, return ERRNO
    }
}

// Terminate thread
int thread_exit(thread_t* thread) {
    if (thread->state == THREAD_RUNNING) {
        // Run thread function
        thread->state = THREAD_TERMINATED;
        return 0; // if succuss, return 0
    } else {
        return -1; // if fail, return ERRNO
    }
}

// 等待线程结束
int thread_join(thread_t* thread) {
    // Wait for thread ending
    while (thread->state != THREAD_TERMINATED) {
        // 检查线程是否结束
        // 如果线程结束，则清理线程资源并退出循环
        // 否则继续等待线程结束
    }
    return 0;
}

// // 示例线程函数
// void thread_function(void* arg) {
//     // 线程执行的代码逻辑
//     // ...
// }

// int main() {
//     // 初始化线程控制块
//     thread_t thread1, thread2;
    
//     // 创建线程
//     thread_create(&thread1, thread_function, NULL, stack_ptr1);
//     thread_create(&thread2, thread_function, NULL, stack_ptr2);
    
//     // 启动线程调度
//     current_thread = &thread1;
//     thread_schedule();

//     // 等待线程结束
//     thread_join(&thread1);
//     thread_join(&thread2);

//     // 所有线程执行完毕，程序结束
//     return 0;
// }
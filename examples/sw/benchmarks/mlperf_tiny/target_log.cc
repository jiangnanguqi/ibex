// SPDX-License-Identifier: Apache-2.0
#include "platform.h"
#include <cstdarg>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <new>

extern "C" void DebugLog(const char* format, va_list args) {
  char buffer[256];
  std::vsnprintf(buffer, sizeof(buffer), format, args);
  tiny_print(buffer);
}
extern "C" int DebugVsnprintf(char* buffer, size_t size, const char* format,
                              va_list args) {
  return std::vsnprintf(buffer, size, format, args);
}
extern "C" void __cxa_pure_virtual() {
  tiny_print_error("pure_virtual", 1);
  tiny_finish(1);
}

// TFLM's virtual destructors refer to these even though the interpreter and
// tensor arena live for the whole bare-metal run.
void operator delete(void* pointer) noexcept { std::free(pointer); }
void operator delete(void* pointer, size_t) noexcept { std::free(pointer); }


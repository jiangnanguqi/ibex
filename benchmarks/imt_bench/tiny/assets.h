// SPDX-License-Identifier: Apache-2.0
#ifndef IMT_TINY_ASSETS_H_
#define IMT_TINY_ASSETS_H_
#include <cstddef>
#include <cstdint>
namespace imt_tiny {
constexpr int kInputElements = 640;
constexpr int kFixtureCount = 3;
extern const unsigned char kModelData[];
extern const size_t kModelBytes;
extern const uint32_t kInputBits[kFixtureCount][kInputElements];
}  // namespace imt_tiny
#endif


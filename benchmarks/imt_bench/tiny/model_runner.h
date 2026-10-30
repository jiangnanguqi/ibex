// SPDX-License-Identifier: Apache-2.0
#ifndef IMT_TINY_MODEL_RUNNER_H_
#define IMT_TINY_MODEL_RUNNER_H_
#include <cstddef>
#include <cstdint>
#include "assets.h"
namespace imt_tiny {
int Initialize();
int PrepareInput(int fixture);
int Invoke();
const int8_t* Output();
size_t OutputBytes();
size_t ArenaBytesUsed();
float AnomalyScore(int fixture);
uint32_t FloatBits(float value);
uint32_t OutputHash();
}  // namespace imt_tiny
#endif


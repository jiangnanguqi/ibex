// SPDX-License-Identifier: Apache-2.0
// Portable TFLM operators; the same code is built for the host and RV32IM.
#include "model_runner.h"
#include <cmath>
#include <cstring>
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"

namespace imt_tiny {
namespace {
alignas(16) uint8_t arena[64 * 1024];
tflite::micro::MicroInterpreter* interpreter;
TfLiteTensor* input;
TfLiteTensor* output;

float InputValue(int fixture, int index) {
  float value;
  const uint32_t bits = kInputBits[fixture][index];
  std::memcpy(&value, &bits, sizeof(value));
  return value;
}
}  // namespace

int Initialize() {
  const tflite::Model* model = tflite::GetModel(kModelData);
  if (model->version() != TFLITE_SCHEMA_VERSION) return 1;
  static tflite::micro::MicroMutableOpResolver<3> resolver;
  if (resolver.AddFullyConnected() != kTfLiteOk ||
      resolver.AddQuantize() != kTfLiteOk ||
      resolver.AddDequantize() != kTfLiteOk) return 2;
  static tflite::micro::MicroInterpreter instance(
      // Preserve tensors so the planner cannot overwrite the loaded input
      // with an intermediate/output between repeated Invoke() calls.
      model, resolver, arena, sizeof(arena), nullptr, nullptr, true);
  interpreter = &instance;
  if (interpreter->AllocateTensors() != kTfLiteOk) return 3;
  input = interpreter->input(0);
  output = interpreter->output(0);
  if (input->type != kTfLiteInt8 || output->type != kTfLiteInt8 ||
      input->bytes != kInputElements || output->bytes != kInputElements ||
      input->params.scale <= 0.0f) return 4;
  return 0;
}

int PrepareInput(int fixture) {
  if (fixture < 0 || fixture >= kFixtureCount) return 1;
  for (int i = 0; i < kInputElements; ++i) {
    // Matches MLPerf Tiny's QuantizeFloatToInt8: round, then saturate.
    float value = ::roundf(InputValue(fixture, i) / input->params.scale +
                           input->params.zero_point);
    if (value < -128.0f) value = -128.0f;
    if (value > 127.0f) value = 127.0f;
    input->data.int8[i] = static_cast<int8_t>(value);
  }
  return 0;
}

int Invoke() { return interpreter->Invoke() == kTfLiteOk ? 0 : 1; }
const int8_t* Output() { return output->data.int8; }
size_t OutputBytes() { return output->bytes; }
size_t ArenaBytesUsed() { return interpreter->arena_used_bytes(); }

float AnomalyScore(int fixture) {
  float sum = 0.0f;
  for (int i = 0; i < kInputElements; ++i) {
    const float reconstructed =
        (static_cast<int>(output->data.int8[i]) - output->params.zero_point) *
        output->params.scale;
    const float difference = reconstructed - InputValue(fixture, i);
    sum += difference * difference;
  }
  return sum / static_cast<float>(kInputElements);
}

uint32_t FloatBits(float value) {
  uint32_t bits;
  std::memcpy(&bits, &value, sizeof(bits));
  return bits;
}

uint32_t OutputHash() {
  uint32_t hash = 2166136261u;
  for (size_t i = 0; i < OutputBytes(); ++i) {
    hash = (hash ^ static_cast<uint8_t>(Output()[i])) * 16777619u;
  }
  return hash;
}
}  // namespace imt_tiny


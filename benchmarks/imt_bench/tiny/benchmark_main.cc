// SPDX-License-Identifier: Apache-2.0
#include "model_runner.h"
#include "platform.h"
#include "golden.h"
#ifndef TINY_ITERATIONS
#define TINY_ITERATIONS 1
#endif
static_assert(TINY_ITERATIONS > 0, "TINY_ITERATIONS must be positive");

namespace {
int Check(int fixture, bool report) {
  using namespace imt_tiny;
  unsigned mismatches = 0;
  for (size_t i = 0; i < OutputBytes(); ++i) {
    if (Output()[i] != kExpected[fixture][i]) ++mismatches;
  }
  const uint32_t score = FloatBits(AnomalyScore(fixture));
  if (report) tiny_print_check(fixture, mismatches, OutputHash(), score,
                                kExpectedScoreBits[fixture]);
  return mismatches != 0 || score != kExpectedScoreBits[fixture];
}
}  // namespace

int main() {
  using namespace imt_tiny;
  const int status = Initialize();
  if (status) { tiny_print_error("initialize", status); return 1; }
  tiny_print_arena(static_cast<unsigned>(ArenaBytesUsed()));
  for (int fixture = 0; fixture < kFixtureCount; ++fixture) {
    if (PrepareInput(fixture) || Invoke()) {
      tiny_print_error("validation_invoke", fixture); return 2;
    }
    if (Check(fixture, true)) return 3;
  }
  // One untimed warmup of the measured fixture, after input preparation.
  if (PrepareInput(0) || Invoke()) return 4;
  int failed = 0;
  if (tiny_measure_begin()) return 6;
  for (unsigned i = 0; i < TINY_ITERATIONS; ++i) failed |= Invoke();
  tiny_measure_end();
  if (failed || Check(0, false)) {
    tiny_print_error("measured_invoke", failed);
    Check(0, true);
    tiny_print_measurement(TINY_ITERATIONS);
    return 5;
  }
  tiny_print_measurement(TINY_ITERATIONS);
  tiny_mark_pass();
  return 0;
}


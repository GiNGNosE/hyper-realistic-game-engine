.PHONY: lint perf-lane lpg-review runtime-benchmark-build runtime-benchmark-run

lint:
	@mkdir -p artifacts/policy
	@POLICY_PHASE=pre-phase-0 .github/scripts/resolve-applicable-rules.sh
	@.github/scripts/run-lint-suite.sh

perf-lane:
	@mkdir -p artifacts/policy
	@POLICY_PHASE=pre-phase-0 .github/scripts/run-performance-lane.sh

lpg-review:
	@python3 .github/scripts/review-lpg-artifacts.py

runtime-benchmark-build:
	@cmake -S runtime -B build/runtime -DCMAKE_BUILD_TYPE=Release
	@cmake --build build/runtime --config Release --target lpg-runtime-benchmark

runtime-benchmark-run: runtime-benchmark-build
	@./build/runtime/lpg-runtime-benchmark --phase pre-phase-0 --scenario-set canonical-s1-s3 --output artifacts/perf/lpg-metrics.json

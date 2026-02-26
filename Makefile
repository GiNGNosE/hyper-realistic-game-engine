.PHONY: lint perf-lane lpg-review

lint:
	@mkdir -p artifacts/policy
	@POLICY_PHASE=pre-phase-0 .github/scripts/resolve-applicable-rules.sh
	@.github/scripts/run-lint-suite.sh

perf-lane:
	@mkdir -p artifacts/policy
	@POLICY_PHASE=pre-phase-0 .github/scripts/run-performance-lane.sh

lpg-review:
	@python3 .github/scripts/review-lpg-artifacts.py

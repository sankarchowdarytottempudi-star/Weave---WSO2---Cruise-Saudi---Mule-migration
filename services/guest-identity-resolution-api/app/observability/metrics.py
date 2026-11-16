"""Prometheus metrics (section 20.2)."""
from prometheus_client import Counter, Histogram

DECISIONS = Counter("gir_decisions_total", "Identity decisions", ["decision", "decision_type", "rule_version"])
CANDIDATES = Histogram("gir_candidate_count", "Candidates per evaluation", buckets=(0, 1, 2, 5, 10, 25, 50, 100, 200))
DURATION = Histogram("gir_evaluation_seconds", "Evaluation duration")
REVIEW_FRESHNESS_FAILURES = Counter("gir_review_freshness_failures_total", "Manual decisions cancelled by freshness")
PAIR_CONFLICTS = Counter("gir_pair_allocation_conflicts_total", "Pair allocation retries")
ERRORS = Counter("gir_errors_total", "Stable error codes returned", ["code"])

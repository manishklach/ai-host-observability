# MetricZScoreHigh

## Meaning
The host-local anomaly baseline exporter has detected a metric running more than three standard deviations above its recent rolling baseline.

## Impact
This is often an early warning before a user-facing incident. Memory pressure, RDMA registration growth, and fabric error counters can all move materially before a host OOM, timeout storm, or job hang.

## Diagnosis
Check `nixl_baseline_current`, `nixl_baseline_mean`, `nixl_baseline_stddev`, and the raw source metric for the same `metric_id`. Verify whether the increase is transient or part of a step-change caused by a new workload, rollout, or hardware issue.

## Remediation
If the change is expected, reset or allow the baseline to relearn. If it is unexpected, follow the raw metric's runbook first, then reduce pressure sources such as pinned memory, registration fan-out, or overloaded network paths.

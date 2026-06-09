# MetricExceedsP99

## Meaning
The current metric value is above the local rolling p99 learned from recent history.

## Impact
This highlights rare-but-not-yet-critical behavior. It is particularly useful for operators who want a warning before thresholds like OOMs, throttling, or retransmit storms are crossed.

## Diagnosis
Check `nixl_baseline_p99`, `nixl_baseline_current`, and `nixl_baseline_window_size` for the affected `metric_id`. Confirm whether the baseline has enough history and whether the raw metric is a gauge or a per-scrape counter proxy.

## Remediation
Correlate the metric with workload changes, fleet drift, or host degradation. Reset `.baseline/` if the host intentionally changed roles and the old baseline is no longer representative.

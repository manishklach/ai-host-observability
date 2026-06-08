# CPUFreqBelowMax

## Meaning

CPU package mean frequency is staying materially below the rated maximum frequency.

## Impact

CPU-heavy training input pipelines, networking, and orchestration paths may underperform even when the job looks GPU-bound at a glance.

## Diagnosis

- `nixl_cpu_freq_current_khz{stat="mean"} / nixl_cpu_freq_max_khz`
- `nixl_cpu_freq_governor_info`
- `rate(nixl_cpu_thermal_throttle_total[5m])`

## Remediation

Confirm the system is in a performance governor, check for thermal throttle activity or power caps, and compare BIOS package power limits against the intended workload envelope.

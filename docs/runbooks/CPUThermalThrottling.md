# CPUThermalThrottling

## Meaning

One or more CPU cores or packages are accumulating thermal throttle events.

## Impact

The host can show unstable training throughput, jittery all-reduce performance, and unexpected latency spikes when clocks are forced down by thermal limits.

## Diagnosis

- `rate(nixl_cpu_thermal_throttle_total[5m])`
- `nixl_thermal_zone_temp_celsius`
- `nixl_cpu_freq_current_khz{stat="mean"} / nixl_cpu_freq_max_khz`

## Remediation

Check heatsink contact, fan curves, inlet temperature, BIOS power settings, and whether the workload is running in an enclosure that constrains airflow.

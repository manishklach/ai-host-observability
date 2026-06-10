# NVMeTempHigh

## Meaning

The NVMe composite temperature is elevated for a sustained period.

## Impact

High temperature can trigger throttling, increase latency, and accelerate reliability degradation during checkpoint or dataset-heavy workloads.

## Diagnosis

- `nixl_nvme_temperature_celsius{sensor="composite"}`
- `nixl_nvme_critical_warning`
- `rate(nixl_diskstat_io_time_ms_total[5m])`
- `nixl_diskstat_io_in_progress`

## Remediation

Check airflow, nearby GPU heat, chassis fan state, and device placement. Reduce sustained writes or move workloads if the device is throttling.

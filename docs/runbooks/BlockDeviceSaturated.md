# BlockDeviceSaturated

## Meaning

The number of in-flight I/O requests is close to the block device request queue depth.

## Impact

Storage latency can climb quickly, causing training stalls, stale checkpoints, slow data loaders, or delayed container and model artifact reads.

## Diagnosis

- `nixl_diskstat_io_in_progress`
- `nixl_block_queue_depth`
- `rate(nixl_diskstat_weighted_io_time_ms_total[5m])`
- `rate(nixl_diskstat_reads_completed_total[5m])`
- `rate(nixl_diskstat_writes_completed_total[5m])`

## Remediation

Reduce concurrent I/O, move checkpoint or dataset traffic away from the saturated device, validate scheduler and queue settings, and check for device or filesystem errors.

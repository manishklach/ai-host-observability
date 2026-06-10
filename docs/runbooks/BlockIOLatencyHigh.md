# BlockIOLatencyHigh

## Meaning

The block device is spending a high amount of time doing I/O compared with completed read and write operations.

## Impact

Checkpoint writes, data loading, container startup, and local scratch traffic can become slow or bursty even while CPU and GPU metrics look normal.

## Diagnosis

- `rate(nixl_diskstat_io_time_ms_total[5m]) / (rate(nixl_diskstat_reads_completed_total[5m]) + rate(nixl_diskstat_writes_completed_total[5m]) + 1)`
- `nixl_diskstat_io_in_progress`
- `nixl_block_queue_depth`
- `nixl_filesystem_bytes`

## Remediation

Check whether the queue is saturated, identify the workload driving I/O, inspect kernel storage errors, and compare against NVMe SMART or RAID/LVM health if those exporters are enabled.

# DiskWriteErrorsIncreasing

## Meaning

The device still has I/O in progress, but completed writes are not increasing.

## Impact

Applications may appear hung while the kernel is waiting on storage completion. Training checkpoints and logs can stop moving forward.

## Diagnosis

- `rate(nixl_diskstat_writes_completed_total[5m])`
- `nixl_diskstat_io_in_progress`
- `rate(nixl_kernel_log_pattern_total{pattern=~"kernel_oops|hung_task|oom"}[5m])`
- `nixl_filesystem_bytes`

## Remediation

Inspect kernel logs, filesystem state, device health, and storage controller events. Drain or restart affected jobs only after capturing enough evidence to distinguish device failure from workload idleness.

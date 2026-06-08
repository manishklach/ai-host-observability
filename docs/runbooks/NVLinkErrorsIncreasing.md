# NVLinkErrorsIncreasing

## Meaning

NVLink replay, recovery, or CRC counters are increasing over time.

## Impact

The fabric may still be up, but link quality is degrading and can turn into hangs, retries, or large performance cliffs under heavy communication.

## Diagnosis

- `rate(nixl_nvlink_error_total[5m])`
- `nixl_nvlink_replay_errors_total`
- `rate(nixl_kernel_log_pattern_total{pattern=~"nvlink_error|nvlink_fatal|gpu_xid"}[5m])`

## Remediation

Check thermals, seating, firmware consistency, and whether a specific GPU or link is accumulating the errors. If rates continue rising, drain the node and investigate hardware.

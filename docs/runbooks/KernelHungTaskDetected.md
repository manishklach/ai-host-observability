# KernelHungTaskDetected

## Meaning

The kernel has reported a blocked or hung task.

## Impact

Subsystems such as storage, filesystems, or device drivers may be stuck long enough to stall user workloads and trigger cascading timeouts.

## Diagnosis

- `rate(nixl_kernel_log_pattern_total{pattern="hung_task"}[5m])`
- `nixl_kernel_hung_task_timeout_seconds`
- `rate(nixl_kernel_log_pattern_total{pattern="kernel_oops"}[5m])`

## Remediation

Identify the blocked subsystem from kernel logs, check for related device errors, and remove the host from production if tasks are not recovering.

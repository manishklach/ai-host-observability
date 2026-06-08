# KernelSoftLockupDetected

## Meaning

The kernel has reported a soft lockup event.

## Impact

The host may already be partially unresponsive, and distributed training or storage operations can stall unpredictably or fail outright.

## Diagnosis

- `rate(nixl_kernel_log_pattern_total{pattern="soft_lockup"}[5m])`
- `nixl_kernel_watchdog_enabled`
- `nixl_kernel_watchdog_thresh_seconds`

## Remediation

Inspect CPU saturation, interrupt storms, and recent kernel-driver events. If the host is unstable, drain it and capture logs before rebooting.

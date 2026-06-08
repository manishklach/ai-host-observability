# RCUStallDetected

## Meaning

The kernel has logged an RCU stall.

## Impact

This indicates severe CPU scheduling failure or runaway interrupt behavior and can precede a full host hang or panic.

## Diagnosis

- `rate(nixl_kernel_log_pattern_total{pattern="rcu_stall"}[5m])`
- `rate(nixl_softirq_total[5m])`
- `rate(nixl_irq_total[5m])`

## Remediation

Check for interrupt storms, runaway CPUs, or driver bugs. Drain the host if possible and preserve logs for kernel or vendor escalation.

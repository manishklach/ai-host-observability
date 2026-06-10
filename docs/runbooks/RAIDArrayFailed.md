# RAIDArrayFailed

## Meaning

An md software RAID array is inactive, failed, or otherwise not cleanly active.

## Impact

Storage paths on the array may return errors or hang. Checkpoints, datasets, and local scratch may be unavailable.

## Diagnosis

- `nixl_md_state`
- `nixl_md_degraded`
- `nixl_md_disks_failed`
- `nixl_kernel_log_pattern_total`

## Remediation

Drain workloads, inspect mdadm state and kernel logs, recover or assemble the array if safe, and escalate to storage replacement if members have failed.

# RAIDArrayDegraded

## Meaning

An md software RAID array has fewer active disks than expected.

## Impact

The host may have lost redundancy. Additional disk trouble can turn a warning into data loss or job failure quickly.

## Diagnosis

- `nixl_md_degraded`
- `nixl_md_disks_total`
- `nixl_md_disks_active`
- `nixl_md_disks_failed`
- `nixl_md_sync_action`

## Remediation

Check `/proc/mdstat`, replace or re-add failed members, confirm rebuild progress, and avoid starting long jobs on affected storage until redundancy is restored.

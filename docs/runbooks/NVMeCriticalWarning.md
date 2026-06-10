# NVMeCriticalWarning

## Meaning

One or more NVMe SMART critical warning bits are set.

## Impact

The device may have low spare, thermal threshold violations, degraded reliability, read-only mode, or volatile backup failure.

## Diagnosis

- `nixl_nvme_critical_warning`
- `nixl_nvme_warn_spare_low`
- `nixl_nvme_warn_temp_threshold`
- `nixl_nvme_warn_reliability_degraded`
- `nixl_nvme_warn_read_only`
- `nixl_nvme_warn_volatile_backup_failed`

## Remediation

Decode the warning bit, check temperature and media error counters, and drain or replace the drive when reliability or read-only warnings are present.

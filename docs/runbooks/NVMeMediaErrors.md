# NVMeMediaErrors

## Meaning

The NVMe media or data integrity error counter increased.

## Impact

Active jobs may see corrupted reads, failed writes, or filesystem errors depending on the affected path and redundancy layer.

## Diagnosis

- `increase(nixl_nvme_media_errors_total[1h])`
- `nixl_nvme_error_log_entries_total`
- `nixl_kernel_log_pattern_total`
- `nixl_filesystem_bytes`

## Remediation

Protect running jobs, inspect kernel logs and SMART details, verify RAID or filesystem health, and replace the drive if errors are confirmed.

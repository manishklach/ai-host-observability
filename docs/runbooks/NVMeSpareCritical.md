# NVMeSpareCritical

## Meaning

Available spare has fallen below the drive's SMART threshold.

## Impact

This is a critical reliability signal. The device may degrade, go read-only, or fail under continued write pressure.

## Diagnosis

- `nixl_nvme_available_spare_percent`
- `nixl_nvme_available_spare_threshold_percent`
- `nixl_nvme_warn_spare_low`
- `nixl_nvme_critical_warning`

## Remediation

Drain workloads from the host where possible and replace the device. Confirm that checkpoint or scratch paths have redundancy before continuing long jobs.

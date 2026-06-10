# NVMeWearHigh

## Meaning

An NVMe drive reports high lifetime usage through SMART percentage used.

## Impact

The device may still work, but the replacement window is approaching. AI hosts that write checkpoints or local cache data can consume endurance quickly.

## Diagnosis

- `nixl_nvme_percentage_used`
- `nixl_nvme_available_spare_percent`
- `nixl_nvme_critical_warning`
- `increase(nixl_nvme_media_errors_total[1h])`

## Remediation

Plan replacement, reduce unnecessary write amplification where possible, and compare the drive against peers of the same model and workload class.

# GPUPowerCapThrottling

## Meaning

The GPU is throttling because of a configured software power cap.

## Impact

The device may be healthy but underpowered relative to the expected workload, which creates avoidable performance cliffs.

## Diagnosis

- `nixl_gpu_throttle_reason{reason="sw_power_cap"}`
- `nixl_gpu_power_limit_watts`
- `nixl_gpu_power_enforced_limit_watts`

## Remediation

Confirm whether the power cap is intentional. If not, review `nvidia-smi -pl` policy, host BIOS settings, and rack-level power management.

# GPUHWSlowdown

## Meaning

The GPU is actively reporting a hardware slowdown throttle reason.

## Impact

Training throughput can fall sharply, latency becomes unstable, and the node may no longer be representative of the rest of the fleet.

## Diagnosis

- `nixl_gpu_throttle_reason{reason="hw_slowdown"}`
- `nixl_gpu_clock_sm_mhz / nixl_gpu_clock_max_sm_mhz`
- `nixl_gpu_temperature_celsius`

## Remediation

Check thermals, power delivery, and recent XID or reset events. If slowdown persists, drain the node and inspect hardware or firmware limits.

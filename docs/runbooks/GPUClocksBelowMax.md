# GPUClocksBelowMax

## Meaning

The GPU SM clock is staying well below its rated maximum.

## Impact

Training or inference throughput may be lower than expected even though the GPU is allocated and apparently healthy at a coarse level.

## Diagnosis

- `nixl_gpu_clock_sm_mhz / nixl_gpu_clock_max_sm_mhz`
- `nixl_gpu_throttle_reason`
- `nixl_gpu_power_draw_watts`

## Remediation

Check for thermal, power, or policy throttling and compare current clocks against intended application clocks for the workload.

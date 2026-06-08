# GPUNotAtP0

## Meaning

The GPU is staying in a lower performance state instead of P0.

## Impact

Even when jobs appear active, the GPU may not be delivering expected throughput because it is not in its maximum-performance operating state.

## Diagnosis

- `nixl_gpu_pstate`
- `nixl_gpu_throttle_reason`
- `nixl_gpu_utilization_percent`

## Remediation

Check whether the workload is truly active, whether clocks or power policies are constrained, and whether the device is being thermally or electrically limited.

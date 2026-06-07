## Meaning

One or more GPUs have recorded new volatile ECC errors.

## Impact

This may indicate memory integrity problems, instability under load, or a hardware issue that needs vendor-level investigation.

## Diagnosis

Run these PromQL queries:

```promql
increase(nixl_gpu_ecc_volatile_total[10m])
```

```promql
nixl_gpu_temperature_celsius
```

```promql
nixl_gpu_utilization_percent
```

## Remediation

Identify the affected GPU, review thermal and workload context, and consider removing the GPU from service if the error rate continues increasing.

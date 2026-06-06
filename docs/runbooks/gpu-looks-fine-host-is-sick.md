# GPU Looks Fine, Host Is Sick

## Symptoms

- GPU utilization and HBM look normal
- host memory PSI and reclaim are bad
- processes or cgroups begin to fail on the host

## Likely Causes

- pinned host memory growth
- BAR1 pressure
- PCIe-side or RDMA-side overhead outside GPU HBM accounting

## Metrics to Inspect

- `nixl_gpu_utilization_percent`
- `nixl_gpu_memory_used_bytes`
- `nixl_gpu_bar1_used_bytes`
- `nixl_host_meminfo_bytes`
- `nixl_host_fw_pages_sum`

## Manual Commands

```bash
nvidia-smi --query-gpu=index,utilization.gpu,memory.used,bar1_memory.used --format=csv
cat /proc/pressure/memory
```

## PromQL

```promql
nixl_gpu_memory_used_bytes
nixl_gpu_bar1_used_bytes / nixl_gpu_bar1_total_bytes
nixl_host_meminfo_bytes{field="memavailable"}
```

## Correlate

- compare host memory collapse against steady GPU HBM usage
- look for BAR1 growth or firmware-page growth happening in parallel

## Safe Mitigations

- reduce registration-heavy data movement
- reduce per-host workload density

## Avoid Early Conclusions

- do not assume “GPU metrics look okay” means the node is healthy


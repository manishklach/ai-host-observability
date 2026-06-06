# Host Memory Pressure

## Symptoms

- `MemAvailable` falls steadily
- memory PSI rises
- reclaim counters accelerate
- host OOM events begin appearing

## Likely Causes

- host-side pinned memory growth
- RDMA registration fan-out
- cgroup pressure hidden from guest-level dashboards
- unrelated page-cache or filesystem pressure

## Metrics to Inspect

- `nixl_host_meminfo_bytes`
- `nixl_host_memory_psi_avg`
- `nixl_host_vmstat`
- `nixl_host_fw_pages_sum`
- `nixl_host_cgroup_memory_events`

## Manual Commands

```bash
grep -E 'MemAvailable|MemFree|SwapFree|Buffers|Cached' /proc/meminfo
cat /proc/pressure/memory
grep -E 'pgscan|pgsteal|pswp' /proc/vmstat
find /sys/kernel/debug/mlx5 -name fw_pages_total -exec sh -c 'printf "%s " "$1"; cat "$1"' _ {} \;
```

## PromQL

```promql
nixl_host_meminfo_bytes{field="memavailable"}
rate(nixl_host_vmstat{field="pgscan_direct"}[10m])
nixl_host_memory_psi_avg{scope="some",window="60s"}
```

## Correlate

- compare guest RAM or GPU memory graphs with host `fw_pages_total`
- check whether pressure is global or isolated to one cgroup

## Safe Mitigations

- reduce workload concurrency
- constrain RDMA registration footprint
- increase host memory headroom if policy allows

## Avoid Early Conclusions

- do not assume GPU memory dashboards explain host OOM
- do not assume the kernel is leaking before checking registration growth


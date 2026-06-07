## Meaning

Host-side mlx5 firmware page usage is increasing, indicating rising RDMA registration footprint.

## Impact

The host can run into hidden memory pressure and degraded transport behavior even while GPU HBM appears healthy.

## Diagnosis

Run these PromQL queries:

```promql
increase(nixl_host_fw_pages_sum[15m])
```

```promql
nixl_host_fw_pages_total
```

```promql
nixl_host_meminfo_bytes{field="memavailable"}
```

## Remediation

Check whether the workload is registering the same buffers across too many HCAs or transport lanes, and reduce multi-rail fan-out or exposed buffer count if possible.

# RDMA Registration Growth

## Symptoms

- `nixl_host_fw_pages_sum` climbs steadily
- host memory pressure rises without corresponding guest RAM growth
- RDMA transport errors may follow later

## Likely Causes

- multi-HCA registration fan-out
- topology-unaware buffer registration
- repeated registration churn from userspace

## Metrics to Inspect

- `nixl_host_fw_pages_total`
- `nixl_host_fw_pages_sum`
- `nixl_infiniband_counter`
- `nixl_net_ethtool_stat`

## Manual Commands

```bash
find /sys/kernel/debug/mlx5 -name fw_pages_total -exec sh -c 'printf "%s " "$1"; cat "$1"' _ {} \;
ethtool -S <iface>
ls /sys/class/infiniband/*/ports/*/counters
```

## PromQL

```promql
rate(nixl_host_fw_pages_sum[15m])
increase(nixl_infiniband_counter{counter="port_rcv_errors"}[15m])
```

## Correlate

- map firmware-page growth against workload start times
- compare NIC-local growth versus system-wide host memory pressure

## Safe Mitigations

- reduce the number of HCAs targeted per GPU buffer
- roll back recent UCX or registration-policy changes

## Avoid Early Conclusions

- do not blame GPU HBM usage by default
- do not treat link errors as the root cause until registration growth is understood


## Meaning

The host networking stack is dropping receive work at the softnet layer.

## Impact

Packet loss, retries, latency inflation, and data-plane slowdown may follow, especially for RDMA-adjacent or high-throughput AI serving workloads.

## Diagnosis

Run these PromQL queries:

```promql
rate(nixl_softnet_stat_total{field="dropped"}[5m])
```

```promql
rate(nixl_net_ethtool_stat{stat=~".*drop.*|.*error.*"}[5m])
```

```promql
nixl_cpu_psi_avg{scope="some",window="60s"}
```

## Remediation

Check IRQ distribution, CPU saturation, NIC queue pressure, and whether ingress bursts or RDMA traffic are overrunning the host’s receive path.

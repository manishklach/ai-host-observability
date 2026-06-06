# Softirq and Network Pressure

## Symptoms

- high `NET_RX` or `NET_TX` softirq totals
- rising `softnet_stat` drops or `time_squeezed`
- throughput degradation without obvious link-down events

## Likely Causes

- per-CPU networking backlog
- interrupt imbalance
- packet processing overhead from accelerated traffic

## Metrics to Inspect

- `nixl_softirq_total`
- `nixl_softnet_stat_total`
- `nixl_netdev_total`
- `nixl_irq_total`
- `nixl_net_ethtool_stat`

## Manual Commands

```bash
cat /proc/softirqs
cat /proc/net/softnet_stat
cat /proc/interrupts | grep -E 'mlx5|pciehp|nv'
```

## PromQL

```promql
rate(nixl_softnet_stat_total{field="dropped"}[5m])
rate(nixl_softnet_stat_total{field="time_squeezed"}[5m])
```

## Correlate

- compare pressure per CPU with IRQ distribution
- check whether NIC error counters move with softnet drops

## Safe Mitigations

- rebalance IRQ affinity
- reduce traffic bursts or host density

## Avoid Early Conclusions

- do not assume the link is bad just because throughput fell


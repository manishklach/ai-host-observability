# InterfaceNearSaturation

## Meaning
An interface is sustaining traffic near its reported link capacity.

## Impact
NCCL collectives, checkpoint uploads, data staging, and distributed rendezvous can all slow sharply when a single host-side interface is the bottleneck.

## Diagnosis
Check `nixl_netflow_iface_rx_utilization_ratio`, `nixl_netflow_iface_tx_utilization_ratio`, likely NCCL connection counts, and retransmit counters. Confirm whether the pressure is expected bulk traffic or an imbalance caused by skewed sharding or poor affinity.

## Remediation
Reduce concurrent transfer load, rebalance traffic, validate RSS and IRQ placement, and check whether the link is negotiating at the intended speed. If a virtual interface is noisy, exclude it from collection or routing decisions.

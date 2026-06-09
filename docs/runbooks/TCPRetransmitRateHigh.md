# TCPRetransmitRateHigh

## Meaning
The exporter is observing a high TCP retransmit rate across active sockets.

## Impact
Retransmits are a strong sign of congestion or packet loss and often correlate with slower collectives, longer checkpoint times, and training step instability.

## Diagnosis
Inspect `nixl_netflow_tcp_retrans_total`, `nixl_netstat_ext`, interface utilization ratios, and any matching fabric or softirq alerts. Look for a specific port class such as NCCL or RDMA-adjacent traffic that is driving the retransmits.

## Remediation
Investigate the lossy path, oversubscription, or host networking bottleneck. Fix queue pressure, NIC settings, routing asymmetry, or noisy background transfers before rerunning the workload.

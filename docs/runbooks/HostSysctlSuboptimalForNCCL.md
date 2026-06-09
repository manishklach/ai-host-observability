# HostSysctlSuboptimalForNCCL

## Meaning
The host is using socket buffer settings below the recommended baseline for high-throughput GPU and RDMA-heavy training traffic.

## Impact
Undersized receive buffers can amplify drops, retransmits, or burst sensitivity during NCCL collectives and checkpoint traffic.

## Diagnosis
Check `nixl_host_sysctl{name="net.core.rmem_max"}` and related buffer settings across the fleet. Compare good and bad nodes to see whether the issue is a cluster-wide policy gap or local drift.

## Remediation
Raise the socket buffer sysctls to the recommended values for the environment and roll the change consistently across the training fleet.

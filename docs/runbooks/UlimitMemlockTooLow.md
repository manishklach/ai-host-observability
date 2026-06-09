# UlimitMemlockTooLow

## Meaning
The host's hard `memlock` limit is below the level typically needed for large pinned-memory and RDMA-heavy AI workloads.

## Impact
RDMA registration, pinned-memory allocation, or peer-memory paths can fail unexpectedly at scale even when the host otherwise looks healthy.

## Diagnosis
Check `nixl_host_ulimit{resource="memlock"}` across hosts and compare failures with RDMA registration growth, pinned memory usage, and GPU transport symptoms.

## Remediation
Raise the hard and soft memlock limits for the service account or workload runtime, ideally to unlimited or a clearly sufficient value for the fleet.

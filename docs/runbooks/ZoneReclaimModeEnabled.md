# ZoneReclaimModeEnabled

## Meaning
The kernel is attempting local-zone reclaim before remote NUMA allocation.

## Impact
This can introduce reclaim stalls and latency spikes under memory pressure, especially on multi-socket AI hosts where remote memory is often preferable to reclaim churn.

## Diagnosis
Check `nixl_host_sysctl{name="vm.zone_reclaim_mode"}`, host memory PSI, and reclaim counters. Compare affected hosts with nodes that show steadier behavior under similar workloads.

## Remediation
Set `vm.zone_reclaim_mode=0` for GPU training nodes unless a workload-specific tuning reason says otherwise, and keep the setting consistent fleet-wide.

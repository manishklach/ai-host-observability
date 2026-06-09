# PerfEventParanoidTooHigh

## Meaning
The host's `perf_event_paranoid` setting is restrictive enough to block common non-root profiling and tracing workflows.

## Impact
During a live incident, operators may lose access to the perf, trace, and sampling tools needed to understand NCCL stalls, scheduler starvation, or kernel-side hotspots quickly.

## Diagnosis
Check `nixl_perf_event_paranoid` along with the surrounding perf knob metrics. Confirm whether the restriction is intentional for the environment or whether it is unexpectedly tighter on a subset of hosts.

## Remediation
Lower `kernel.perf_event_paranoid` according to your security policy for performance-debuggable GPU nodes. Apply the change consistently across the fleet so debugging playbooks do not work on only part of the cluster.

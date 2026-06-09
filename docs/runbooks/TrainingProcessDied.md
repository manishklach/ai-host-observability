# TrainingProcessDied

## Meaning
GPU activity is visible, but the heartbeat exporter cannot find a training-like process in the process table.

## Impact
The job launcher may have crashed, a worker may have been orphaned, or a context may still be active while the owning process has already failed. This can waste cluster capacity and confuse schedulers.

## Diagnosis
Check `nixl_gpu_utilization_percent`, process supervision logs, scheduler state, and whether orphaned containers or namespaces are still present. Confirm whether the GPU activity is real work or cleanup noise.

## Remediation
Terminate orphaned contexts if necessary, restart the launcher, and inspect recent job, container, or scheduler failures. If the heuristic matches too broadly, refine the process pattern or the watched log/checkpoint roots.

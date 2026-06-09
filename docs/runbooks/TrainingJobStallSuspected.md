# TrainingJobStallSuspected

## Meaning
The host still shows training-like processes and active GPUs, but the heartbeat exporter cannot find fresh checkpoint or log progress signals.

## Impact
This usually means compute resources are burning time without making forward progress. Hang paths often include NCCL collectives, blocked data loaders, filesystem stalls, or deadlocked framework control flow.

## Diagnosis
Check `nixl_job_training_processes_total`, `nixl_job_stall_duration_seconds`, `nixl_job_checkpoint_last_write_age_seconds`, and `nixl_job_log_last_update_age_seconds`. Compare those with GPU utilization, host PSI, fabric errors, and recent kernel log anomalies.

## Remediation
Capture stack traces or framework diagnostics before killing the job. If the issue is recurrent, narrow the fault domain by checking storage latency, NCCL transport health, and data pipeline backpressure.

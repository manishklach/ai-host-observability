# CheckpointWritesStalled

## Meaning
Training processes are still running, but checkpoint outputs beneath a watched directory have stopped updating.

## Impact
A long-running job may continue to consume GPU time without creating durable recovery points. If the node fails, the rollback window grows quickly.

## Diagnosis
Inspect `nixl_job_checkpoint_files_recent` and `nixl_job_checkpoint_last_write_age_seconds` by directory. Check free space, inode pressure, filesystem latency, permissions, and whether the job intentionally disabled checkpointing.

## Remediation
Restore checkpoint writeability, free space, or route output to healthy storage. If the job is intentionally in a no-checkpoint phase, tune the alerting window for that workload class.

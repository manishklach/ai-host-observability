# GPUMemoryFragmentationHigh

## Meaning
The GPU memory pressure exporter estimates that a significant fraction of HBM is reserved by the driver instead of freely available to applications.

## Impact
Applications can encounter allocation failures earlier than expected, especially during large tensor, graph, or activation allocations after long-running reuse-heavy jobs.

## Diagnosis
Compare `nixl_gpu_memory_reserved_bytes`, `nixl_gpu_memory_free_bytes`, and `nixl_gpu_process_memory_bytes`. Confirm whether the node has long-lived processes, failed jobs, or MIG/context churn that may have left fragmented allocations behind.

## Remediation
Drain or restart the affected workload, clear stale contexts, and reboot the node or reset the GPU if fragmentation does not recover. Avoid immediately blaming the framework before checking driver and context lifecycle behavior.

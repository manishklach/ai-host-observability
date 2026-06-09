# GPUMemoryOversubscribed

## Meaning
Processes using the GPU are collectively consuming nearly all available device memory.

## Impact
Even if a job has not yet OOMed, the next model shard, batch-size increase, or checkpoint-side allocation may fail abruptly.

## Diagnosis
Review `nixl_gpu_process_memory_bytes` per process alongside total/free/reserved GPU memory. Distinguish a single runaway process from a legitimate multi-process workload approaching the device limit.

## Remediation
Reduce batch size, trim process concurrency, or move work to a larger GPU profile. If reserved memory is also high, consider draining the node instead of simply restarting one process.

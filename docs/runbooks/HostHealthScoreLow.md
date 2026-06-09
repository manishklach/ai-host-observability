# HostHealthScoreLow

## Meaning
The composite host health score derived from GPU, storage, and fabric recording rules has dropped below the healthy threshold.

## Impact
This is a convenience roll-up alert that tells you the node is not broadly healthy even before you open the more specific panels. It is not the root cause by itself.

## Diagnosis
Break the score back down into `nixl:gpu:available`, `nixl:storage:healthy`, and `nixl:fabric:healthy`, then inspect the underlying raw metrics and alerts for the failing layer.

## Remediation
Treat this as a navigation aid: resolve the degraded GPU, storage, or fabric component first, then confirm the composite score recovers once the underlying fault is fixed.

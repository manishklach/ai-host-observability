# CollectionPipelineStalled

## Meaning
More than half of the exporter outputs on the host are stale at the same time.

## Impact
This is a control-plane problem for observability itself. Other host alerts may disappear or freeze even while the underlying incident gets worse.

## Diagnosis
Check `nixl_collector_exporters_stale`, `nixl_collector_total_metrics`, wrapper failure metrics, timer execution, and filesystem health for the textfile directory. Distinguish a single bad exporter from a timer, service, or disk-wide failure.

## Remediation
Restore the collection pipeline first: fix permissions, timer execution, service failures, or disk issues. Once fresh `.prom` files resume, reevaluate the host using the underlying exporters.

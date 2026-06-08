# NVLinkDown

## Meaning

At least one NVLink is not in an active state.

## Impact

All-reduce bandwidth can collapse, topology assumptions can break, and distributed jobs may hang or time out.

## Diagnosis

- `nixl_nvlink_state`
- `rate(nixl_nvlink_error_total[5m])`
- `rate(nixl_kernel_log_pattern_total{pattern=~"gpu_xid|nvlink_error|nvlink_fatal"}[5m])`

## Remediation

Inspect GPU and NVLink topology health with `nvidia-smi nvlink --status`, check for XID or reset events, and drain the host if the fabric is not stable.

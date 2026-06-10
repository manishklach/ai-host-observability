# LVMThinPoolFull

## Meaning

An LVM thin pool is approaching full data usage.

## Impact

Writes can fail sharply when the thin pool fills, causing checkpoint failure, container errors, or filesystem stalls.

## Diagnosis

- `nixl_lvm_thin_data_percent`
- `nixl_lvm_thin_metadata_percent`
- `nixl_filesystem_bytes`
- `nixl_diskstat_io_in_progress`

## Remediation

Extend the thin pool, remove unused volumes or snapshots, verify metadata headroom, and avoid scheduling write-heavy jobs until there is enough capacity.

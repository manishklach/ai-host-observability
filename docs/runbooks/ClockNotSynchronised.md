# ClockNotSynchronised

## Meaning

The system clock is not reporting a synchronised NTP state.

## Impact

Distributed training checkpoints, event ordering, and cross-node timeout analysis become much less reliable when clocks are unsynchronised.

## Diagnosis

- `nixl_timesync_synchronized`
- `nixl_timesync_offset_seconds`
- `nixl_timesync_stratum`

## Remediation

Check NTP or chrony service status, upstream reachability, and whether the host recently lost network access to its time source.

# ClockStratumHigh

## Meaning

The host is more than three strata away from a primary time source.

## Impact

Clock quality is degraded and drift risk rises, especially for long-running distributed training or inference fleets.

## Diagnosis

- `nixl_timesync_stratum`
- `nixl_timesync_reference_id_info`
- `nixl_timesync_offset_seconds`

## Remediation

Review chrony peer configuration, confirm reachability to closer or more reliable sources, and correct any site-wide time hierarchy issues.

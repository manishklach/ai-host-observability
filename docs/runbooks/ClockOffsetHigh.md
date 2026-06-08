# ClockOffsetHigh

## Meaning

The host clock offset has remained above 10 milliseconds.

## Impact

Timestamps can drift enough to create spurious timeout interpretation and confusing cross-node event ordering during distributed jobs.

## Diagnosis

- `abs(nixl_timesync_offset_seconds)`
- `nixl_timesync_rms_offset_seconds`
- `nixl_timesync_freq_error_ppm`

## Remediation

Verify upstream time source quality, chrony tracking health, and whether the host has unstable frequency or intermittent network reachability.

# EDACUncorrectableErrors

## Meaning

EDAC has reported one or more uncorrectable memory errors.

## Impact

This is a data-integrity event. Running workloads may have already seen corruption, process termination, or a host machine-check path.

## Diagnosis

- `increase(nixl_edac_uncorrectable_errors_total[10m])`
- `nixl_edac_uncorrectable_errors_total`
- `nixl_rasdaemon_ue_total`

## Remediation

Drain the host from production workloads, preserve logs for hardware triage, and treat the affected memory subsystem as failed until validated or replaced.

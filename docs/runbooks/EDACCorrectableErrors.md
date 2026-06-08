# EDACCorrectableErrors

## Meaning

Correctable memory errors are being reported by EDAC for one or more DIMMs or controller channels.

## Impact

The host may still be operating normally, but the DIMM or memory channel is degrading and can progress to uncorrectable errors, crashes, or silent instability under load.

## Diagnosis

- `increase(nixl_edac_correctable_errors_total[1h])`
- `nixl_edac_correctable_errors_total`
- `nixl_rasdaemon_ce_total`

## Remediation

Check the affected controller and DIMM mapping, review recent firmware or thermal events, and plan DIMM replacement or host drain before the error rate worsens.

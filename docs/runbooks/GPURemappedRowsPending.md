# GPURemappedRowsPending

## Meaning
The GPU reports pending memory row remaps, indicating the hardware has detected row-level degradation that has not been fully resolved.

## Impact
This is a stronger hardware-health signal than ordinary utilization or temperature drift and should be treated as an elevated reliability risk for training jobs.

## Diagnosis
Inspect remapped row metrics, ECC history, XID events, and any correlated thermal or power excursions. Determine whether the device is still safe for production or should be drained immediately.

## Remediation
Drain the GPU from service and schedule maintenance or replacement. Reboot if the platform guidance requires it to complete pending remap actions, but do not treat reboot alone as a final fix if the condition recurs.

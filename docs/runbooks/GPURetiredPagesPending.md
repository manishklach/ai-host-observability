# GPURetiredPagesPending

## Meaning
The GPU has memory pages pending retirement due to ECC-related faults.

## Impact
The device may continue running, but it is no longer in a clean steady state. Ignoring the condition increases the chance of repeat faults or a later, more disruptive failure.

## Diagnosis
Check retired page counts, ECC history, thermals, and whether the fault is isolated to one device or part of a broader host cooling or power issue.

## Remediation
Schedule a reboot or maintenance action to complete the retirement, then watch the device closely for recurring faults. If counts keep increasing, plan replacement.

## Meaning

At least one ai-host-observability exporter is failing to complete successfully.

## Impact

You may lose visibility into part of the host seam layer exactly when you need it most during an incident.

## Diagnosis

Run these PromQL queries:

```promql
ai_host_exporter_last_run_success
```

```promql
ai_host_exporter_duration_seconds
```

```promql
count by (exporter) (ai_host_exporter_last_run_success == 0)
```

## Remediation

Check file permissions, missing host paths, missing vendor tools, and wrapper logs; then rerun the failing exporter manually with the same environment to reproduce the failure.

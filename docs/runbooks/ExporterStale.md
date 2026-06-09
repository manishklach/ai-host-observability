# ExporterStale

## Meaning
An exporter `.prom` file has not been updated inside the expected collection window.

## Impact
Metrics from that exporter are becoming stale, which can hide real host problems or create false confidence during an incident.

## Diagnosis
Check `nixl_collector_last_run_age_seconds`, file sizes, and wrapped exporter status metrics. Confirm the exporter still runs under the service account and that the textfile directory is writable.

## Remediation
Restart the timer or service if needed, fix permissions, and inspect the exporter named in the stale file label. If many exporters are stale together, treat it as a pipeline-wide issue instead of an isolated signal gap.

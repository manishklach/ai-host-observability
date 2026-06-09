# NodeExporterNotRunning

## Meaning
The collector health exporter could not detect a `node_exporter` process on the host.

## Impact
Prometheus may stop scraping the entire textfile collector directory, which means all host-side seam metrics become invisible even if the exporters are still writing files.

## Diagnosis
Check systemd service state, the node_exporter process table, and scrape target health in Prometheus. Validate the textfile collector directory path matches the running node_exporter configuration.

## Remediation
Restart node_exporter, repair its unit or container configuration, and confirm the `--collector.textfile.directory` flag still points at the intended path.

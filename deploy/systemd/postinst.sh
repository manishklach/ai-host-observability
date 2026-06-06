#!/bin/bash
set -e

mkdir -p /etc/ai-host-observability

systemctl daemon-reload
systemctl enable --now ai-host-observability.timer

echo "ai-host-observability installed and timer started."
echo "Metrics will be written to /var/lib/node_exporter/textfile_collector/"
echo "Configure node_exporter with: --collector.textfile.directory=/var/lib/node_exporter/textfile_collector"
echo "Drop-in configs: /etc/ai-host-observability/collector.conf and /etc/ai-host-observability/timer.conf"
echo "Examples: /etc/ai-host-observability/collector.conf.example and /etc/ai-host-observability/timer.conf.example"
#!/bin/bash
set -e

systemctl disable --now ai-host-observability.timer 2>/dev/null || true
systemctl stop ai-host-observability.service 2>/dev/null || true

echo "ai-host-observability timer stopped and disabled."
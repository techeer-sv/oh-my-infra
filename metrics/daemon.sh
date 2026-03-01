#!/bin/bash
# File: enable-docker-metrics.sh
# Purpose: Enable Docker Engine metrics on 0.0.0.0:9323 and restart Docker

set -e

DAEMON_JSON="/etc/docker/daemon.json"

if [ ! -f "$DAEMON_JSON" ]; then
  echo "{}" | sudo tee "$DAEMON_JSON" > /dev/null
fi

# Merge or add metrics config using jq
sudo jq '. + {"metrics-addr": "0.0.0.0:9323", "experimental": true}' "$DAEMON_JSON" | sudo tee "$DAEMON_JSON" > /dev/null

echo "Restarting Docker..."
sudo systemctl restart docker

echo "Docker metrics enabled on 0.0.0.0:9323 and Docker restarted."
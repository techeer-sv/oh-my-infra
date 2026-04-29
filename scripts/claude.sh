#!/usr/bin/env bash

ZSHRC="$HOME/.zshrc"

add_if_missing() {
  local line="$1"
  grep -qxF "$line" "$ZSHRC" || echo "$line" >> "$ZSHRC"
}

echo "Updating $ZSHRC..."

add_if_missing 'export CLAUDE_CODE_ENABLE_TELEMETRY=1'

add_if_missing 'export OTEL_METRICS_EXPORTER=otlp'
add_if_missing 'export OTEL_LOGS_EXPORTER=otlp'

add_if_missing 'export OTEL_EXPORTER_OTLP_PROTOCOL=grpc'
add_if_missing 'export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317'

echo "Done. Reloading..."

# Reload zshrc
source "$ZSHRC"

echo "Telemetry env vars set."
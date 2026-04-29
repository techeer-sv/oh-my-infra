#!/usr/bin/env bash

ZSHRC="$HOME/.zshrc"

add_if_missing() {
  local line="$1"
  grep -qxF "$line" "$ZSHRC" || echo "$line" >> "$ZSHRC"
}

echo "$ZSHRC 업데이트중..."

add_if_missing 'export CLAUDE_CODE_ENABLE_TELEMETRY=1'

add_if_missing 'export OTEL_METRICS_EXPORTER=otlp'
add_if_missing 'export OTEL_LOGS_EXPORTER=otlp'

add_if_missing 'export OTEL_EXPORTER_OTLP_PROTOCOL=grpc'
add_if_missing 'export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317'

add_if_missing 'export OTEL_LOG_USER_PROMPTS=1'
add_if_missing 'export OTEL_LOG_TOOL_DETAILS=1'

echo "완료: 텔레메트리 환경 변수가 $ZSHRC에 추가되었습니다."

# Reload zshrc
source "$ZSHRC"

echo "완료: $ZSHRC가 다시 로드되었습니다."
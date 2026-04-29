# Claude Code 관측성 (OTLP)

Claude Code의 로그와 메트릭을 기존 관측성 스택(Jaeger, Prometheus, Loki)으로 내보내는 OpenTelemetry Collector 연동 설정입니다.

## 변경 사항

### `scripts/claude.sh`
Claude Code의 내장 텔레메트리를 활성화하고 로컬 OTLP Collector 엔드포인트를 지정하는 환경변수를 `~/.zshrc`에 추가하는 스크립트입니다.

### `tracing/otel-config.yaml`
OTel Collector 설정을 다음과 같이 확장했습니다.

- **메트릭 파이프라인** — OTLP 메트릭을 수신해 Prometheus 스크래핑 엔드포인트(`0.0.0.0:9464`)로 노출
- **로그 파이프라인** — OTLP 로그를 수신해 `otlphttp`를 통해 Loki로 전달
- **`attributes/drop_high_card` 프로세서** — Prometheus·Loki의 카디널리티 폭발을 방지하기 위해 메트릭·로그 파이프라인에서 고카디널리티 속성 제거 (`session.id`, `conversation.id`, `tool.call.id`, `prompt.id`)

### `tracing/tracing-stack.yml`
`otel-collector` 서비스를 두 개의 외부 Docker 네트워크에 추가로 연결했습니다.

- `logging-network` — Loki 접근용
- `metrics-network` — Prometheus 접근용

### `metrics/prometheus/prometheus.yml`
OTel Collector의 Prometheus 엔드포인트 스크래핑 잡을 추가했습니다.

```yaml
- job_name: "otel"
  static_configs:
    - targets: ["otel-collector:9464"]
```

꼭 서버에서 `make prom-reload`를 통해 Scrape Job을 반영 해주세요

## 시작하기

### 1단계: 환경변수 설정

```bash
bash scripts/claude.sh
```

아래 환경변수를 `~/.zshrc`에 추가합니다 (이미 존재하면 중복 추가하지 않습니다).

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1

export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp

export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 # localhost가 아닌 올바른 호스트로 바꿔주세요

export OTEL_LOG_USER_PROMPTS=1
export OTEL_LOG_TOOL_DETAILS=1
```

설정 후 셸을 다시 로드합니다.

```bash
source ~/.zshrc
```

### 2단계: 트레이싱 스택 실행

```bash
make tracing
```

OTel Collector 수신 엔드포인트:

| 엔드포인트 | 프로토콜 | 용도 |
|---|---|---|
| `localhost:4317` | gRPC | 트레이스·메트릭·로그 수신 |
| `localhost:4318` | HTTP | 동일 (HTTP 대안) |
| `0.0.0.0:9464` | HTTP | Prometheus 스크래핑 |

### 3단계: 확인

Claude Code 세션을 시작하면 텔레메트리가 자동으로 전송됩니다.

| 데이터 | 경로 |
|---|---|
| 메트릭 | OTel Collector → Prometheus → Grafana |
| 로그 | OTel Collector → Loki → Grafana |
| 트레이스 | OTel Collector → Jaeger |

## 고카디널리티 속성 필터링

Claude Code는 세션·대화 단위 ID를 OTLP 속성으로 내보냅니다. 트레이싱에는 유용하지만, Prometheus와 Loki에서는 레이블 카디널리티가 무한히 증가하는 문제를 일으킵니다. `attributes/drop_high_card` 프로세서가 메트릭·로그 파이프라인에서 이 속성들을 제거하며, 트레이스 파이프라인에는 영향을 주지 않습니다.

제거 대상 속성:

- `session.id`
- `conversation.id`
- `tool.call.id`
- `prompt.id`

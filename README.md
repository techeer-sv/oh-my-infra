# oh-my-infra

서비스 인프라 설정을 간편하게~

Docker Compose 기반의 통합 관측성(Observability) 스택입니다. 메트릭, 로그, 트레이싱, 시각화를 독립적인 모듈로 구성하고, 외부 Docker 네트워크로 서비스 간 통신합니다.

## 전체 아키텍처

```
  Django App (server/)
  ┌─────────────────────────────────────────────────────┐
  │  gunicorn + OpenTelemetry + pyroscope-io            │
  │  - Traces  → otel-collector:4317 (OTLP gRPC)       │
  │  - Metrics → /metrics (Prometheus scrape)           │
  │  - Logs    → stdout JSON → Alloy → Loki             │
  │  - Flames  → pyroscope-distributor:4040             │
  └─────────────────────────────────────────────────────┘
                             │
                             ▼
                      ┌─────────────┐
                      │   Traefik   │  리버스 프록시 /django → django-app:8000
                      └──────┬──────┘
                             │
                             ▼
                      ┌─────────────┐
                      │   Grafana   │  대시보드 시각화
                      └──────┬──────┘
                             │
        ┌────────────────────┼──────────────────────┐
        │                    │                      │
        ▼                    ▼                      ▼
┌──────────────┐   ┌──────────────────┐   ┌─────────────────────┐
│  Prometheus  │   │  query-frontend  │   │  pyroscope-         │
│  (metrics)   │   │  (Loki, port     │   │  query-frontend     │
└──────┬───────┘   │   3100)          │   │  (Flame graphs)     │
       │           └────────┬─────────┘   └──────────┬──────────┘
       │                    │                        │
       │            ┌───────▼────────┐      ┌────────▼────────┐
       │            │query-scheduler │      │pyroscope-querier│
       │            └───────┬────────┘      └────────┬────────┘
       │                    │                    │         │
       │         ┌──────────┴──────────┐         ▼         ▼
       │         ▼                     ▼    ┌─────────┐ ┌──────────────┐
       │    ┌──────────┐        ┌──────────┐│ingester │ │store-gateway │
       │    │loki-read │        │loki-     ││(최근)   │ │(과거 블록)   │
       │    └────┬─────┘        │backend   │└────┬────┘ └──────┬───────┘
       │         └──────┬───────┘          │     │             │
       │                ▼                  │     └──────┬───────┘
       │          ┌──────────┐             │            ▼
       │          │  MinIO   │◀────────────┘       ┌──────────┐
       │          │  (Loki)  │                     │  MinIO   │
       │          └──────────┘                     │(Pyroscope│
       │                 ▲                         └──────────┘
       │          ┌──────┴─────┐
       │          │ loki-write │
       │          └──────▲─────┘
       │                 │
       │          ┌──────┴─────┐
       │          │   Alloy    │  stdout JSON 수집 (logging=enabled)
       │          └──────▲─────┘
       ▼                 │ Docker socket
  ┌───────────────┐      │
  │   cAdvisor    │──────┘
  │ Docker daemon │
  │   Traefik     │  (메트릭 스크래핑 대상)
  └───────────────┘
```

## 스택 구성

| 디렉토리 | 역할 | 주요 서비스 |
|---|---|---|
| `visualize/` | 시각화 진입점 | Traefik, Grafana |
| `metrics/` | 메트릭 수집 및 저장 | Prometheus, cAdvisor |
| `logging/` | 로그 수집 및 저장 | Loki (분산 구성), Alloy, MinIO |
| `tracing/` | 분산 트레이싱 | Jaeger, OTel Collector, ScyllaDB |
| `profiling/` | 지속적 프로파일링 | Pyroscope (분산 구성), MinIO — UI: `http://<host>:4041` |
| `server/` | 관측성 예제 애플리케이션 | Django + Gunicorn (Traces·Metrics·Logs·Flames) |
| `grafana/` | Grafana 대시보드 JSON 정의 | container_usage 대시보드 |
| `scripts/` | 유틸리티 스크립트 | 네트워크 설정, daemon 설정 등 |

## Docker 네트워크

모든 스택은 사전에 생성된 외부 네트워크를 통해 통신합니다. 네트워크는 기능 단위로 분리되어 있어 스택을 독립적으로 실행하거나 중단할 수 있습니다.

| 네트워크 | 연결 서비스 |
|---|---|
| `logging-network` | Loki 구성 요소, Alloy, Prometheus (Loki 메트릭 스크래핑) |
| `metrics-network` | Prometheus, cAdvisor, Grafana, Django (메트릭 스크래핑) |
| `tracing-network` | Traefik (OTEL), Jaeger, OTel Collector, Django (트레이스 전송) |
| `profiling-network` | Pyroscope 구성 요소, Django (프로파일 전송) |
| `traefik-network` | Traefik 라우팅 대상 서비스 (Django 포함) |
| `grafana-network` | Grafana ↔ Prometheus, Loki, Jaeger, Pyroscope 데이터소스 |

## 시작하기

### 1단계: 네트워크 생성

```bash
make networks
```

### 2단계: (선택) Docker daemon 메트릭 활성화

```bash
make daemon
```

### 3단계: 스택 실행

권장 실행 순서:

```bash
make http       # Traefik + Grafana (HTTP)
make metrics    # Prometheus + cAdvisor
make logging    # Loki + Alloy + MinIO
make tracing    # Jaeger + OTel Collector + ScyllaDB
make profiling  # Pyroscope + MinIO
make server     # Django 예제 애플리케이션
```

HTTPS를 사용하려면 `visualize/https.yml`의 `{YOUR_EMAIL}@gmail.com`을 실제 이메일로 수정한 뒤 `make https`를 실행합니다.

### 정리

```bash
make stop-all   # 모든 컨테이너 중지
make clean      # 모든 Docker 리소스 삭제
```

## 컨테이너 로그 수집 활성화

Alloy가 로그를 수집하도록 하려면 대상 컨테이너에 다음 라벨을 추가합니다.

```yaml
labels:
  logging: "enabled"
```

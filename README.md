# oh-my-infra

서비스 인프라 설정을 간편하게~

Docker Compose 기반의 통합 관측성(Observability) 스택입니다. 메트릭, 로그, 트레이싱, 시각화를 독립적인 모듈로 구성하고, 외부 Docker 네트워크로 서비스 간 통신합니다.

## 전체 아키텍처

```
                        외부 트래픽
                             │
                             ▼
                      ┌─────────────┐
                      │   Traefik   │  리버스 프록시 (port 80 / 443)
                      └──────┬──────┘
                             │
                             ▼
                      ┌─────────────┐
                      │   Grafana   │  대시보드 시각화 (port 3000)
                      └──────┬──────┘
                             │
           ┌─────────────────┼──────────────────┐
           │                 │                  │
           ▼                 ▼                  ▼
   ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐
   │  Prometheus  │  │query-frontend │  │    (tracing)    │
   │  (port 9090) │  │  (port 3100)  │  │    미구현        │
   └──────┬───────┘  └───────┬───────┘  └─────────────────┘
          │                  │
          │          ┌───────▼────────┐
          │          │query-scheduler │
          │          └───────┬────────┘
          │                  │
          │     ┌────────────┴────────────┐
          │     │                         │
          │     ▼                         ▼
          │ ┌──────────┐          ┌──────────────┐
          │ │ loki-read│          │ loki-backend │
          │ │(querier) │          │(compactor /  │
          │ └────┬─────┘          │ index/store) │
          │      │                └──────┬───────┘
          │      └──────────┬────────────┘
          │                 │
          │                 ▼
          │          ┌──────────┐
          │          │  MinIO   │  S3 호환 오브젝트 스토리지
          │          └──────────┘
          │                 ▲
          │          ┌──────┴─────┐
          │          │ loki-write │  로그 인제스터
          │          └──────▲─────┘
          │                 │
          │          ┌──────┴─────┐
          │          │   Alloy    │  로그 수집 에이전트
          │          └──────▲─────┘
          │                 │ Docker socket / 컨테이너 로그
          │                 │ (label: logging=enabled)
          ▼                 │
  ┌───────────────┐         │
  │   cAdvisor    │         │
  │ Docker daemon │─────────┘
  │   Traefik     │  (메트릭 스크래핑 대상)
  └───────────────┘
```

## 스택 구성

| 디렉토리 | 역할 | 주요 서비스 |
|---|---|---|
| `visualize/` | 시각화 진입점 | Traefik, Grafana |
| `metrics/` | 메트릭 수집 및 저장 | Prometheus, cAdvisor |
| `logging/` | 로그 수집 및 저장 | Loki (분산 구성), Alloy, MinIO |
| `tracing/` | 분산 트레이싱 | (구성 예정) |
| `grafana/` | Grafana 대시보드 JSON 정의 | container_usage 대시보드 |
| `scripts/` | 유틸리티 스크립트 | 네트워크 설정, daemon 설정 등 |

## Docker 네트워크

모든 스택은 사전에 생성된 외부 네트워크를 통해 통신합니다. 네트워크는 기능 단위로 분리되어 있어 스택을 독립적으로 실행하거나 중단할 수 있습니다.

| 네트워크 | 연결 서비스 |
|---|---|
| `logging-network` | Loki 구성 요소, Alloy, Prometheus (Loki 메트릭 스크래핑) |
| `metrics-network` | Prometheus, cAdvisor, Grafana |
| `tracing-network` | Traefik (OTEL), 트레이싱 서비스 |
| `traefik-network` | Traefik 라우팅 대상 서비스 |
| `grafana-network` | Grafana ↔ Prometheus, Loki 데이터소스 |

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
make tracing    # 트레이싱 스택
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

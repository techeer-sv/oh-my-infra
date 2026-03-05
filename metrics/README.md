# metrics

Prometheus와 cAdvisor로 구성된 메트릭 수집 스택입니다. 컨테이너 자원 사용량과 인프라 서비스 메트릭을 수집하여 Grafana에 제공합니다.

## 서비스 구성

### cAdvisor (v0.55.1) — 컨테이너 메트릭 수집기

Google이 개발한 컨테이너 리소스 모니터링 도구입니다. 호스트의 Docker 런타임에 직접 접근하여 각 컨테이너의 CPU, 메모리, 네트워크, 디스크 사용량을 수집합니다.

| 포트 | 역할 |
|---|---|
| `8080` | 메트릭 엔드포인트 (Prometheus 스크래핑 대상) |

주요 설정:
- **Privileged 모드**: 호스트 시스템 정보 접근을 위해 필요
- **마운트**: `/`, `/var/run`, `/sys`, `/var/lib/docker` (읽기 전용)
- **리소스 제한**: CPU 0.3코어, 메모리 250MB

### Prometheus (v3.10.0) — 메트릭 저장 및 쿼리

시계열 데이터베이스로, 다양한 서비스에서 메트릭을 스크래핑하여 저장합니다.

| 포트 | 역할 |
|---|---|
| `9090` | Prometheus UI 및 API |

주요 설정:
- **데이터 보존**: 15일 / 최대 3GB
- **설정 파일**: `./prometheus/prometheus.yml`
- **Hot reload**: `/-/reload` 엔드포인트 활성화 (`make prom-reload`)
- **리소스 제한**: CPU 0.5코어, 메모리 1GB

## 데이터 흐름

```
┌──────────────────────────────────────────────┐
│              스크래핑 대상                      │
│                                              │
│  cAdvisor:8080   → 컨테이너 리소스 메트릭       │
│  host.docker.internal:9323 → Docker daemon   │
│  traefik:8091    → Traefik 프록시 메트릭       │
│  prometheus:9090 → Prometheus 자체 메트릭      │
│  query-frontend:3100 → Loki 메트릭            │
└──────────────────┬───────────────────────────┘
                   │ 15초마다 스크래핑
                   ▼
           ┌──────────────┐
           │  Prometheus  │  시계열 저장 (15일 보존)
           └──────┬───────┘
                  │
                  ▼
           ┌──────────────┐
           │   Grafana    │  대시보드 시각화
           └──────────────┘
```

## 스크래핑 설정 (`prometheus/prometheus.yml`)

| 대상 | 주소 | 수집 내용 |
|---|---|---|
| cAdvisor | `cadvisor:8080` | 컨테이너별 CPU/메모리/네트워크/디스크 |
| Docker daemon | `host.docker.internal:9323` | Docker 엔진 메트릭 |
| Traefik | `traefik:8091` | HTTP 요청 수, 레이턴시, 라우팅 상태 |
| Prometheus | `prometheus:9090` | Prometheus 자체 상태 |
| Loki | `query-frontend:3100` | Loki 쿼리 처리 메트릭 |

> Docker daemon 메트릭을 활성화하려면 `make daemon`을 먼저 실행해야 합니다.

## 실행

```bash
make metrics
```

Prometheus 설정 변경 후 재시작 없이 반영:

```bash
make prom-reload
```

## 연결 네트워크

| 네트워크 | 용도 |
|---|---|
| `metrics-network` | Prometheus ↔ cAdvisor, Grafana 연결 |
| `grafana-network` | Grafana가 Prometheus를 데이터소스로 사용 |
| `logging-network` | Prometheus가 Loki(query-frontend) 메트릭 스크래핑 |

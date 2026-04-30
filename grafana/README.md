# grafana

Grafana 대시보드 JSON 정의 파일을 보관하는 디렉토리입니다. Grafana 서비스 자체는 `visualize/` 스택에서 실행됩니다.

## 포함된 대시보드

### `container_usage.json` — 컨테이너 리소스 사용량

cAdvisor가 수집한 메트릭을 기반으로 Docker 컨테이너의 자원 사용 현황을 시각화하는 대시보드입니다.

주요 시각화 항목:
- 컨테이너별 CPU 사용률
- 컨테이너별 메모리 사용량
- 컨테이너별 네트워크 I/O
- 컨테이너별 디스크 I/O

> 이 대시보드는 Prometheus 데이터소스에 의존합니다. `metrics/` 스택이 먼저 실행되어 있어야 합니다.

## 자동 프로비저닝

`make http` 또는 `make https` 실행 시 Grafana가 시작되면 데이터소스와 대시보드가 자동으로 구성됩니다.

| 항목 | 경로 |
|---|---|
| 데이터소스 | `provisioning/datasources/datasources.yaml` |
| 대시보드 프로바이더 | `provisioning/dashboards/dashboards.yaml` |

### 자동 구성 데이터소스

| 이름 | 타입 | URL |
|---|---|---|
| prometheus | Prometheus | `http://prometheus:9090` |
| loki | Loki | `http://loki-query-frontend:3100` |
| jaeger | Jaeger | `http://jaeger-query:16686` |
| pyroscope | Pyroscope | `http://pyroscope-query-frontend:4040` |

> 각 데이터소스는 해당 스택(`make metrics`, `make logging`, `make tracing`, `make profiling`)이 먼저 실행되어 있어야 정상 연결됩니다.

## 대시보드 추가

`grafana/` 디렉토리에 `.json` 파일을 추가하면 Grafana 재시작 시 자동으로 로드됩니다.

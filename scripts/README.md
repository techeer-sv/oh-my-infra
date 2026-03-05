# scripts

인프라 초기 설정 및 운영에 필요한 유틸리티 스크립트 모음입니다. 대부분의 스크립트는 `Makefile`의 `make` 명령을 통해 실행됩니다.

## 스크립트 목록

### `create-networks.sh` — Docker 네트워크 생성

각 스택이 사용하는 외부 Docker 네트워크를 생성합니다. **모든 스택을 실행하기 전에 반드시 먼저 실행해야 합니다.**

생성되는 네트워크:

| 네트워크 | 용도 |
|---|---|
| `logging-network` | Loki 컴포넌트 및 Alloy 통신 |
| `metrics-network` | Prometheus 및 cAdvisor 통신 |
| `tracing-network` | 트레이싱 서비스 통신 |
| `traefik-network` | Traefik 라우팅 대상 서비스 연결 |
| `grafana-network` | Grafana ↔ 데이터소스 연결 |

```bash
make networks
# 또는
./scripts/create-networks.sh
```

---

### `daemon.sh` — Docker daemon 메트릭 활성화

Docker 엔진 자체의 메트릭을 Prometheus가 스크래핑할 수 있도록 설정합니다. `/etc/docker/daemon.json`을 수정하고 Docker daemon을 재시작합니다.

활성화 내용:
- `metrics-addr`: `0.0.0.0:9323`으로 메트릭 엔드포인트 노출
- `experimental`: Docker 실험적 기능 활성화

```bash
make daemon
# 또는
./scripts/daemon.sh
```

> **주의**: 이 스크립트는 Docker daemon을 재시작합니다. 실행 중인 컨테이너가 있다면 재시작 정책에 따라 자동으로 복구됩니다.

---

### `reload.sh` — Prometheus 설정 핫 리로드

Prometheus를 재시작하지 않고 `prometheus.yml` 설정 변경 사항을 즉시 반영합니다. Prometheus의 `--web.enable-lifecycle` 옵션을 통해 가능합니다.

```bash
make prom-reload
# 또는
./scripts/reload.sh
```

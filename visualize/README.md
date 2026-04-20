# visualize

Traefik과 Grafana로 구성된 시각화 진입점 스택입니다. 외부 트래픽을 받아 Grafana 대시보드로 라우팅하며, HTTP와 HTTPS 두 가지 구성 파일을 제공합니다.

## 서비스 구성

### Traefik (v3.6.9) — 리버스 프록시

외부 트래픽을 받아 내부 서비스로 라우팅합니다.

| 포트 | 역할 |
|---|---|
| `80` (HTTP) / `443` (HTTPS) | 외부 트래픽 진입점 |
| `8090` | Traefik API 대시보드 |
| `8091` | Prometheus 메트릭 엔드포인트 |

주요 설정:
- **Docker provider**: 컨테이너 라벨 기반 자동 라우팅 감지
- **OTLP 트레이싱**: `TRACING_ENDPOINT` 환경변수로 트레이싱 백엔드 연결
- **Prometheus 메트릭**: `/metrics` 경로로 Prometheus 스크래핑 가능
- **리소스 제한**: CPU 0.5코어, 메모리 500MB

### Grafana (v12.4) — 대시보드 시각화

메트릭, 로그, 트레이싱 데이터를 시각화하는 대시보드입니다.

| 포트 | 역할 |
|---|---|
| `3000` | Grafana 웹 UI |

주요 설정:
- **데이터 영속성**: `grafana-data` 볼륨으로 대시보드/설정 유지
- **리소스 제한**: CPU 0.5코어, 메모리 1GB

## 데이터 흐름

```
외부 클라이언트
      │
      ▼
┌─────────────┐    8090    ┌──────────────────┐
│   Traefik   │ ─────────▶ │  Traefik API UI  │
│             │    8091    ├──────────────────┤
│             │ ─────────▶ │  Prometheus 수집  │
└──────┬──────┘            └──────────────────┘
       │ 라우팅
       ▼
┌─────────────┐
│   Grafana   │ ──▶ metrics-network  (Prometheus)
│             │ ──▶ grafana-network  (데이터소스 전반)
│             │ ──▶ logging-network  (Loki)
└─────────────┘
```

## HTTP vs HTTPS 구성

| 항목 | `http.yml` | `https.yml` |
|---|---|---|
| 진입 포트 | 80 | 443 |
| TLS | 없음 | Let's Encrypt ACME |
| HTTP→HTTPS 리다이렉트 | 없음 | 자동 적용 |
| 인증서 저장 | 해당 없음 | `traefik-certificates` 볼륨 |
| Traefik API | 인증 없음 (insecure) | 인증 없음 (insecure) |

### HTTPS 사용 시 사전 설정

`https.yml`에서 아래 항목을 실제 값으로 수정해야 합니다.

```yaml
--certificatesresolvers.letsencrypt.acme.email={YOUR_EMAIL}@gmail.com
```

## 실행

```bash
# HTTP로 실행
make http

# HTTPS로 실행 (이메일 설정 후)
make https
```

## 연결 네트워크

| 네트워크 | 용도 |
|---|---|
| `traefik-network` | Traefik 라우팅 대상 서비스 연결 |
| `tracing-network` | OTLP 트레이싱 백엔드 연결 |
| `metrics-network` | Prometheus가 Traefik 메트릭 스크래핑 |
| `grafana-network` | Grafana ↔ 데이터소스 연결 |
| `logging-network` | Grafana ↔ Loki 연결 (http.yml만) |

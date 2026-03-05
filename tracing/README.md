# tracing

분산 트레이싱 스택입니다. 현재는 `tracing-network` Docker 네트워크만 정의되어 있으며, 트레이싱 서비스는 구성 예정입니다.

## 현재 상태

`tracing-stack.yml`에는 `tracing-network` 외부 네트워크 연결 정의만 포함되어 있습니다.

Traefik은 이미 OTLP 트레이싱을 지원하도록 구성되어 있습니다. `TRACING_ENDPOINT` 환경변수에 수신 엔드포인트를 지정하면 즉시 트레이싱 데이터를 전송할 수 있습니다.

## 예정된 아키텍처

```
애플리케이션 / Traefik
       │ OTLP (gRPC/HTTP)
       ▼
┌────────────────────┐
│  OpenTelemetry     │  트레이스 수신 및 처리
│  Collector (OTEL)  │
└─────────┬──────────┘
          │
          ▼
┌─────────────────┐
│  Jaeger / Tempo  │  트레이스 저장 및 쿼리
└────────┬─────────┘
         │
         ▼
┌─────────────────┐
│    Grafana       │  트레이스 시각화
└─────────────────┘
```

## 트레이싱 네트워크

`tracing-network`에 연결된 서비스:
- **Traefik**: HTTP 요청에 대한 트레이스를 `TRACING_ENDPOINT`로 전송

## 실행

```bash
make tracing
```

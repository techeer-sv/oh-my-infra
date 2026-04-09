# tracing

OpenTelemetry Collector, Jaeger, ScyllaDB로 구성된 분산 트레이싱 스택입니다. 애플리케이션과 Traefik에서 발생한 트레이스를 수집하여 저장하고, Grafana에서 시각화합니다.

## 서비스 구성

### ScyllaDB (v6.2) — 트레이스 저장소

Jaeger의 트레이스 데이터를 저장하는 Cassandra 호환 고성능 NoSQL 데이터베이스입니다. Cassandra 대비 낮은 레이턴시와 높은 처리량을 제공합니다.

주요 설정:
- **SMP**: CPU 코어 1개 사용 (`--smp 1`)
- **메모리**: 512MB 고정 할당 (`--memory 512M`)
- **개발자 모드**: 디스크 I/O 최적화 비활성화 (`--developer-mode 1`)
- **데이터**: `scylla-data` 볼륨에 영속 저장
- **헬스체크**: `cqlsh -e 'describe keyspaces'`로 준비 상태 확인 (최대 5분 대기)
- **리소스 제한**: CPU 1코어, 메모리 768MB

### jaeger-schema-init — Cassandra 스키마 초기화

ScyllaDB에 Jaeger가 사용할 키스페이스와 테이블을 생성하는 일회성 컨테이너입니다. ScyllaDB가 healthy 상태가 된 후 실행되고 완료되면 종료됩니다.

주요 설정:
- **키스페이스**: `jaeger_v1_dc1`
- **Datacenter**: `datacenter1`
- **프로토콜**: Cassandra 프로토콜 v4
- **복제 계수**: 1 (단일 노드)

### jaeger-collector (v2.17.0) — 트레이스 수신 및 저장

OTEL Collector로부터 트레이스를 받아 ScyllaDB에 저장합니다. Jaeger의 스토리지 백엔드 역할을 합니다.

설정 파일: `jaeger-collector-config.yaml`

파이프라인:
- **수신**: OTLP gRPC (4317), OTLP HTTP (4318)
- **처리**: batch 프로세서로 묶음 처리
- **저장**: `cassandra_store` → ScyllaDB (`jaeger_v1_dc1` 키스페이스)

Cassandra 스키마 설정:
- **Datacenter**: `datacenter1`
- **Trace TTL**: 72시간 (만료된 트레이스 자동 삭제)
- **Dependencies TTL**: 48일
- **Compaction Window**: 2시간 (TWCS 기반 압축 주기)
- **복제 계수**: 1
- **연결**: `scylla:9042`, TLS 비활성화

리소스 제한: CPU 0.5코어, 메모리 512MB

### jaeger-query (v2.17.0) — 트레이스 쿼리 UI

ScyllaDB에 저장된 트레이스를 조회하는 서비스입니다. Jaeger UI와 gRPC API를 제공합니다.

설정 파일: `jaeger-query-config.yaml`

| 포트 | 역할 |
|---|---|
| `16686` | Jaeger Web UI 및 HTTP API |
| `16685` | gRPC API (Grafana 데이터소스 연결용) |

주요 설정:
- **스토리지**: ScyllaDB `cassandra_store` (jaeger-collector와 동일한 스키마 설정 공유)
- Grafana에서 Jaeger 데이터소스로 연결 시 `http://jaeger-query:16686` 사용

리소스 제한: CPU 0.3코어, 메모리 256MB

### otel-collector (v0.149.0) — OpenTelemetry 수집기

애플리케이션과 Traefik으로부터 트레이스를 수신하는 단일 진입점입니다. 수신한 트레이스를 일괄 처리하여 jaeger-collector로 전달합니다.

설정 파일: `otel-config.yaml`

| 포트 | 역할 |
|---|---|
| `4317` | OTLP gRPC 수신 |
| `4318` | OTLP HTTP 수신 |

파이프라인:
- **수신**: OTLP gRPC / HTTP
- **처리**: batch 프로세서
- **전달**: `jaeger-collector:4317` (OTLP gRPC, TLS 없음)

리소스 제한: CPU 0.3코어, 메모리 256MB

## 데이터 흐름

```
애플리케이션 / Traefik
       │ OTLP gRPC (4317) / HTTP (4318)
       ▼
┌─────────────────────┐
│   otel-collector    │  트레이스 수신 + batch 처리
└──────────┬──────────┘
           │ OTLP gRPC → jaeger-collector:4317
           ▼
┌─────────────────────┐
│  jaeger-collector   │  트레이스 파싱 + ScyllaDB 저장
└──────────┬──────────┘
           │ CQL (port 9042)
           ▼
┌─────────────────────┐
│      ScyllaDB       │  영구 저장 (keyspace: jaeger_v1_dc1)
└──────────┬──────────┘
           │ CQL (port 9042)
           ▼
┌─────────────────────┐
│   jaeger-query      │  트레이스 조회 (port 16686)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│      Grafana        │  트레이스 시각화
└─────────────────────┘
```

## 시작 순서

컨테이너 의존성에 따라 아래 순서로 기동됩니다.

```
ScyllaDB (healthy)
    │
    ▼
jaeger-schema-init (completed)
    │
    ├──▶ jaeger-collector
    │
    └──▶ jaeger-query
              ▲
              │
    jaeger-collector
              ▲
              │
       otel-collector
```

## Traefik 연동

`visualize/http.yml`의 Traefik은 OTLP gRPC로 트레이스를 전송하도록 구성되어 있습니다. `TRACING_ENDPOINT` 환경변수에 otel-collector 주소를 지정합니다.

```bash
TRACING_ENDPOINT=otel-collector:4317
```

## Grafana 데이터소스 설정

Jaeger 데이터소스 추가 시:
- **URL**: `http://jaeger-query:16686`
- **타입**: Jaeger

## 실행

```bash
make tracing
```

## 연결 네트워크

| 네트워크 | 용도 |
|---|---|
| `tracing-network` | 모든 트레이싱 컴포넌트 내부 통신 |
| `grafana-network` | Grafana → jaeger-query 연결 |

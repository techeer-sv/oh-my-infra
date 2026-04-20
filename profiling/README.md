# profiling

Pyroscope v1 분산 아키텍처와 MinIO 오브젝트 스토리지로 구성된 지속적 프로파일링(Continuous Profiling) 스택입니다. CPU, 메모리, goroutine 등 성능 데이터를 수집하여 저장하고, Grafana에서 Flame graph로 시각화합니다.

> v2 아키텍처(`segment-writer`, `metastore` 등)는 `grafana/pyroscope:1.21.0` 이미지에서 지원되지 않습니다. v2가 공개 이미지에 포함되면 마이그레이션 예정입니다.

## 서비스 구성

### MinIO (`pyroscope-minio`) — S3 호환 오브젝트 스토리지

Ingester가 플러시한 블록과 Compactor가 병합한 블록을 장기 저장합니다.

| 포트 | 역할 |
|---|---|
| `9002` | S3 API (logging 스택 9000과 충돌 방지) |
| `9003` | MinIO Console UI |

- **자격 증명**: `minio` / `minio123`
- **버킷**: `pyroscope` (pyroscope-minio-init이 자동 생성)

---

### `pyroscope-ingester` — 데이터 수신 및 저장

Distributor로부터 프로파일 데이터를 받아 메모리에 버퍼링하고, 주기적으로 MinIO에 블록을 플러시합니다. Memberlist 클러스터의 기준 노드입니다 (port 7946).

- `minio-init` 완료 후 기동
- 리소스 제한: CPU 0.5코어, 메모리 512MB

---

### `pyroscope-distributor` — 수신 및 라우팅

애플리케이션 SDK로부터 프로파일 데이터를 수신하는 단일 진입점입니다. Memberlist 링에서 담당 Ingester를 찾아 라우팅합니다.

| 포트 | 역할 |
|---|---|
| `4040` | 프로파일 데이터 수신 (HTTP/gRPC) |

- 리소스 제한: CPU 0.3코어, 메모리 256MB

---

### `pyroscope-store-gateway` — 과거 블록 서빙

MinIO에 저장된 과거 블록을 Querier에게 제공합니다. Ingester가 플러시 완료한 이후의 데이터를 쿼리할 때 사용됩니다.

- `minio-init` 완료 후 기동
- 리소스 제한: CPU 0.3코어, 메모리 256MB

---

### `pyroscope-compactor` — 블록 압축

MinIO에 쌓인 소형 블록들을 주기적으로 병합하여 쿼리 성능을 향상시키고 스토리지 비용을 절감합니다.

- `minio-init` 완료 후 기동
- 리소스 제한: CPU 0.3코어, 메모리 256MB

---

### `pyroscope-query-scheduler` — 쿼리 스케줄러

Query-frontend로부터 쿼리를 받아 대기열에 넣고, Querier가 폴링하여 가져가도록 중계합니다. 이 컴포넌트 없이는 Query-frontend가 Querier에 쿼리를 전달할 수 없어 30초 타임아웃이 발생합니다.

- `pyroscope-ingester` 기동 후 시작
- 리소스 제한: CPU 0.3코어, 메모리 256MB

---

### `pyroscope-querier` — 쿼리 실행

Query-scheduler로부터 쿼리를 폴링하여 Ingester(최근 데이터)와 Store-gateway(과거 데이터) 양쪽에서 조회하여 결과를 반환합니다.

- 리소스 제한: CPU 0.3코어, 메모리 256MB

---

### `pyroscope-query-frontend` — 쿼리 진입점

Grafana로부터 쿼리를 받아 Query-scheduler로 전달합니다. `profiling-network`에만 연결되며, Grafana도 동일 네트워크에 있어 내부적으로 접근합니다.

> **주의**: 이 컨테이너를 `grafana-network`에도 연결하면 멀티 네트워크 인터페이스로 인해 Memberlist가 잘못된 IP를 광고하여 링에 합류하지 못합니다. Grafana는 `profiling-network`를 통해 접근합니다.

| 포트 | 역할 |
|---|---|
| `4041` | Pyroscope UI 및 API (호스트 접근용) |

- **Grafana 데이터소스 URL**: `http://pyroscope-query-frontend:4040`
- **Pyroscope UI**: `http://<host>:4041`
- 리소스 제한: CPU 0.3코어, 메모리 256MB

---

## 데이터 흐름

### 쓰기 경로

```
애플리케이션 (Pyroscope SDK)
       │ HTTP POST /ingest (port 4040)
       ▼
┌──────────────────────┐
│ pyroscope-distributor│  Memberlist 링으로 Ingester 라우팅
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ pyroscope-ingester   │  메모리 버퍼링 → 블록 플러시
└──────────┬───────────┘
           │ S3 API
           ▼
┌──────────────────────┐
│  MinIO (pyroscope)   │  블록 영구 저장
└──────────┬───────────┘
           │ S3 API (블록 병합)
           ▼
┌──────────────────────┐
│ pyroscope-compactor  │  소형 블록 → 대형 블록 압축
└──────────────────────┘
```

### 읽기 경로

```
┌──────────────────────┐
│       Grafana        │
└──────────┬───────────┘
           │ HTTP (profiling-network)
           ▼
┌─────────────────────────┐
│pyroscope-query-frontend │  쿼리 수신
└──────────┬──────────────┘
           │
           ▼
┌──────────────────────────┐
│pyroscope-query-scheduler │  쿼리 대기열 관리
└──────────┬───────────────┘
           │ 폴링
           ▼
┌──────────────────────┐
│  pyroscope-querier   │  Ingester + Store-gateway 병합 조회
└──────────┬───────────┘
           │                        │
           ▼                        ▼
┌──────────────────┐    ┌───────────────────────┐
│pyroscope-ingester│    │pyroscope-store-gateway│
│  (최근 데이터)    │    │   (과거 블록, MinIO)   │
└──────────────────┘    └───────────────────────┘
```

## 시작 순서

```
MinIO (pyroscope-minio)
       │
       ▼
pyroscope-minio-init (완료 후 종료)
       │
       ├──▶ pyroscope-ingester (Memberlist 기준 노드)
       │          │
       │          ▼
       │    pyroscope-distributor
       │
       ├──▶ pyroscope-store-gateway
       │
       └──▶ pyroscope-compactor

pyroscope-ingester
       │
       ▼
pyroscope-query-scheduler

pyroscope-ingester + pyroscope-store-gateway + pyroscope-query-scheduler
       │
       ▼
pyroscope-querier
       │
       ▼
pyroscope-query-frontend
```

## Pyroscope 설정 (`pyroscope-config.yaml`)

| 항목 | 값 |
|---|---|
| HTTP 포트 | 4040 |
| gRPC 포트 | 9095 |
| Memberlist 포트 | 7946 |
| Memberlist join | `pyroscope-ingester:7946` |
| Ring KV 스토어 | Memberlist |
| 복제 계수 | 1 |
| 스토리지 백엔드 | MinIO S3 (`insecure: true`) |
| Store-gateway 링 | Memberlist (복제 계수 1) |
| Query-scheduler | Memberlist 링으로 자동 탐색 |

### 쿼리 디스패치 구조

Query-scheduler가 Query-frontend와 Querier 사이의 중계자 역할을 합니다. Query-frontend는 쿼리를 Scheduler 대기열에 넣고, Querier가 폴링하여 가져갑니다. Scheduler 없이는 Query-frontend가 Querier를 찾지 못해 30초 타임아웃이 발생합니다.

Query-frontend는 `profiling-network`에만 연결합니다. 멀티 네트워크 인터페이스 환경에서는 Memberlist가 잘못된 IP를 광고하여 링 합류에 실패합니다. Grafana는 `profiling-network`를 공유하므로 별도의 `grafana-network` 연결이 불필요합니다.

## 애플리케이션 연동

Distributor의 port 4040으로 프로파일 데이터를 전송합니다.

Go (Pyroscope SDK) 예시:
```go
pyroscope.Start(pyroscope.Config{
    ApplicationName: "my-app",
    ServerAddress:   "http://<host>:4040",
})
```

## Grafana 데이터소스 설정

- **타입**: Grafana Pyroscope
- **URL**: `http://pyroscope-query-frontend:4040`

## 실행

```bash
make profiling
```

## 연결 네트워크

| 네트워크 | 용도 |
|---|---|
| `profiling-network` | 모든 Pyroscope 컴포넌트 + MinIO 내부 통신 + Grafana 접근 |

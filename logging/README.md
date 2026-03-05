# logging

Loki 분산 구성과 Alloy 에이전트, MinIO 오브젝트 스토리지로 구성된 로그 수집 스택입니다. 컨테이너 로그를 자동으로 수집하여 저장하고, Grafana를 통해 쿼리할 수 있습니다.

## 서비스 구성

### Alloy (v1.13.2) — 로그 수집 에이전트

Docker 소켓을 통해 컨테이너를 자동으로 감지하고, `logging=enabled` 라벨이 붙은 컨테이너의 로그를 수집하여 Loki로 전달합니다.

주요 설정:
- **Docker 자동 감지**: Docker socket 마운트를 통해 실행 중인 컨테이너 탐색
- **선택적 수집**: `logging=enabled` 라벨이 있는 컨테이너만 대상
- **컨테이너 이름 라벨링**: 수집된 로그에 컨테이너 이름을 메타데이터로 부착
- **리소스 제한**: CPU 0.5코어, 메모리 300MB

### MinIO — S3 호환 오브젝트 스토리지

Loki의 로그 데이터를 장기 저장하는 백엔드입니다. AWS S3 호환 API를 제공하여 Loki가 S3와 동일한 방식으로 사용합니다.

| 포트 | 역할 |
|---|---|
| `9000` | MinIO S3 API |

주요 설정:
- **기본 자격 증명**: `minio` / `minio123`
- **버킷**: `loki` (minio-init 컨테이너가 초기화 시 자동 생성)
- **리소스 제한**: CPU 1코어, 메모리 1000MB

### Loki (v3.6.7) — 분산 로그 저장소

Loki를 역할별 컴포넌트로 분리하여 실행하는 분산 구성입니다. 각 컴포넌트는 독립적으로 스케일링할 수 있습니다.

| 컴포넌트 | 역할 | 리소스 제한 |
|---|---|---|
| `loki-write` | 로그 수신 및 MinIO에 저장 (Ingestor) | CPU 0.5 / 메모리 300MB |
| `loki-read` | 로그 쿼리 처리 (Querier) | CPU 0.5 / 메모리 300MB |
| `loki-backend` | 인덱스 압축 및 장기 저장 관리 (Compactor) | CPU 0.5 / 메모리 300MB |
| `query-scheduler` | 쿼리 요청 분배 및 스케줄링 | CPU 0.5 / 메모리 300MB |
| `query-frontend` | 외부 쿼리 API 진입점 (port 3100) | CPU 0.5 / 메모리 300MB |

## 데이터 흐름

### 로그 수집 경로 (쓰기)

```
컨테이너 (label: logging=enabled)
         │ Docker 로그
         ▼
     ┌────────┐
     │ Alloy  │  로그 수집 + 메타데이터 부착
     └───┬────┘
         │ HTTP POST /loki/api/v1/push
         ▼
  ┌────────────┐
  │ loki-write │  로그 수신 및 압축
  └─────┬──────┘
        │ 오브젝트 저장
        ▼
  ┌──────────┐
  │  MinIO   │  영구 저장 (버킷: loki)
  └──────────┘
```

### 로그 쿼리 경로 (읽기)

```
     ┌─────────┐
     │ Grafana │
     └────┬────┘
          │ LogQL 쿼리
          ▼
  ┌────────────────┐
  │ query-frontend │  API 진입점 (port 3100)
  └───────┬────────┘
          │
          ▼
  ┌────────────────┐
  │query-scheduler │  쿼리 분배
  └───────┬────────┘
          │
    ┌─────┴──────┐
    │            │
    ▼            ▼
┌──────────┐ ┌──────────────┐
│loki-read │ │ loki-backend │  인덱스 조회 + 압축
└────┬─────┘ └──────┬───────┘
     │               │
     └───────┬───────┘
             │
             ▼
      ┌──────────┐
      │  MinIO   │  오브젝트 데이터 조회
      └──────────┘
```

## Loki 설정 (`loki-config.yaml`)

| 항목 | 값 |
|---|---|
| 인증 | 비활성화 |
| HTTP 포트 | 3100 |
| gRPC 포트 | 9095 |
| 스토리지 백엔드 | MinIO (S3 호환) |
| 스키마 | TSDB (2024-01-01 이후) |
| 인덱스 주기 | 24시간 |
| 로그 보존 기간 | 168시간 (7일) |
| 복제 계수 | 1 |
| 클러스터 통신 | Memberlist (loki-write 기준) |
| 압축 주기 | 5분 |
| 최대 동시 쿼리 | 테넌트당 1024 |

## 컨테이너 로그 수집 활성화

로그를 수집할 컨테이너에 다음 라벨을 추가합니다.

```yaml
labels:
  logging: "enabled"
```

## 실행

```bash
make logging
```

## 연결 네트워크

| 네트워크 | 용도 |
|---|---|
| `logging-network` | Loki 컴포넌트 간 통신, Alloy → loki-write, Prometheus → query-frontend |
| `grafana-network` | Grafana → query-frontend (로그 쿼리) |

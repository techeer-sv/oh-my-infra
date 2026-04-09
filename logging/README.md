# logging

Loki 분산 구성과 Alloy 에이전트, MinIO 오브젝트 스토리지로 구성된 로그 수집 스택입니다. 컨테이너 로그를 자동으로 수집하여 저장하고, Grafana를 통해 쿼리할 수 있습니다.

## 서비스 구성

### Alloy (v1.13.2) — 로그 수집 에이전트

Grafana Alloy는 파이프라인 방식으로 로그를 수집합니다. `alloy-config.alloy`에 정의된 세 단계로 동작합니다.

**1단계 — `discovery.docker`: 컨테이너 탐색**

Docker socket(`/var/run/docker.sock`)에 연결하여 현재 실행 중인 모든 컨테이너 목록을 가져옵니다. 각 컨테이너의 이름, 이미지, 라벨 등의 메타데이터가 `__meta_docker_*` 형태의 내부 라벨로 수집됩니다.

**2단계 — `discovery.relabel`: 필터링 및 라벨 가공**

두 가지 규칙을 적용합니다.
- `__meta_docker_container_name`에서 앞의 `/`를 제거하여 `container_name` 라벨로 변환 (예: `/my-app` → `my-app`)
- `logging=enabled` 라벨이 없는 컨테이너는 파이프라인에서 제외 (`action: keep`)

**3단계 — `loki.source.docker` + `loki.write`: 로그 수집 및 전송**

필터링된 컨테이너의 로그를 `/var/lib/docker/containers` 경로에서 직접 읽어, `http://loki-write:3100/loki/api/v1/push`로 전송합니다.

마운트:
- `/var/run/docker.sock` → 컨테이너 목록 감지용
- `/var/lib/docker/containers` → 컨테이너 로그 파일 읽기 (읽기 전용)

리소스 제한: CPU 0.5코어, 메모리 300MB

---

### MinIO — S3 호환 오브젝트 스토리지

Loki의 로그 청크와 인덱스를 장기 저장하는 백엔드입니다. AWS S3 호환 API를 제공하므로 Loki는 MinIO를 S3와 동일하게 취급합니다.

| 포트 | 역할 |
|---|---|
| `9000` | S3 호환 API |

**minio-init**: 스택 최초 실행 시 MinIO Client(`mc`)를 사용해 초기화 작업을 수행하고 종료되는 일회성 컨테이너입니다.
- MinIO 서버를 `local` 별칭으로 등록
- `loki` 버킷 생성 (`mc mb -p local/loki`)
- 버킷 접근 정책을 `public`으로 설정 (Loki 컴포넌트들이 인증 없이 접근 가능)

데이터는 `minio-data` 볼륨에 영속 저장됩니다.

리소스 제한: CPU 1코어, 메모리 1000MB

---

### Loki (v3.6.7) — 분산 로그 저장소

Loki를 `-target` 플래그로 역할별 컴포넌트로 분리하여 실행하는 분산(Simple Scalable) 구성입니다.

#### `loki-write` — Distributor + Ingester (쓰기 경로)

**Distributor**: Alloy로부터 로그 스트림을 수신합니다. 스트림의 라벨을 해시하여 링(ring) 내의 담당 Ingester를 결정하고 라우팅합니다.

**Ingester**: Distributor에서 받은 로그를 메모리 내 청크(chunk) 단위로 버퍼링합니다. 청크가 가득 차거나 일정 시간이 지나면 MinIO로 플러시하고, TSDB 인덱스를 `/loki/index`에 로컬 기록합니다.

또한 Memberlist 클러스터의 기준 노드 역할을 합니다. 다른 컴포넌트들은 `loki-write`를 통해 클러스터에 참가합니다.

리소스 제한: CPU 0.5코어, 메모리 300MB

---

#### `loki-read` — Querier (쿼리 실행)

query-scheduler로부터 서브쿼리를 받아 실제 로그 데이터를 조회합니다.

- **최근 로그 (아직 플러시 안 된 데이터)**: Ingester(`loki-write`)에 직접 gRPC로 조회
- **오래된 로그**: MinIO에서 청크 파일을 다운로드하여 로컬에서 쿼리 실행
- 어떤 청크를 읽어야 하는지는 TSDB 인덱스를 통해 결정하며, 인덱스 조회는 `loki-backend`의 Index Gateway를 경유합니다.

리소스 제한: CPU 0.5코어, 메모리 300MB

---

#### `loki-backend` — Compactor + Index Gateway (백엔드 관리)

**Compactor**: 주기적으로(5분마다) 작은 TSDB 인덱스 파일들을 MinIO에서 가져와 하나의 큰 파일로 병합합니다. 보존 기간(168시간)을 초과한 로그 청크와 인덱스를 삭제하는 retention 처리도 담당합니다. 작업 디렉토리는 `/loki/compactor`입니다.

**Index Gateway**: Querier들이 쿼리마다 MinIO에서 인덱스를 직접 다운로드하는 대신, 캐시된 인덱스를 gRPC(`loki-backend:9095`)로 서빙합니다. 인덱스 조회 트래픽을 MinIO에서 분리하여 부하를 줄입니다.

리소스 제한: CPU 0.5코어, 메모리 300MB

---

#### `query-scheduler` — 쿼리 큐 관리

query-frontend와 loki-read(Querier) 사이의 중간 레이어입니다.

query-frontend로부터 서브쿼리를 받아 큐에 쌓고, 처리 여유가 생긴 Querier에게 순서대로 분배합니다. 이를 통해 특정 Querier가 과부하 되는 상황을 방지하고, 테넌트별 공정한 쿼리 분배(테넌트당 최대 1024개 동시 요청)를 보장합니다.

리소스 제한: CPU 0.5코어, 메모리 300MB

---

#### `query-frontend` — 쿼리 API 진입점

외부에서 접근 가능한 유일한 Loki 엔드포인트입니다 (port 3100). Grafana와 Prometheus 모두 이 주소로 연결합니다.

- 들어온 LogQL 쿼리를 시간 범위 기준으로 더 작은 서브쿼리로 분할하여 병렬 처리 효율을 높입니다.
- 쿼리 결과를 캐싱하여 동일한 쿼리의 반복 비용을 줄입니다.
- 분할된 서브쿼리를 query-scheduler로 전달하고, 결과를 취합하여 클라이언트에 반환합니다.

리소스 제한: CPU 0.5코어, 메모리 300MB

---

#### `loki-ui` — 실험적 내장 Web UI

Grafana에서 사용가능한 `Loki Operational UI` 플러그인을 사용할수 있게 해줍니다.

![Loki UI](/assets/loki-ui.png)

- query-frontend에 의존하여 실행됩니다.
- `http://localhost:3101`로 접근합니다.
- Datasource에 `http://loki-ui:3100`를 추가해주면 됩니다
- 공식문서: https://grafana.com/grafana/plugins/grafana-lokioperational-app/

리소스 제한: CPU 0.5코어, 메모리 300MB

---

## 데이터 흐름

### 로그 수집 경로 (쓰기)

```
컨테이너 (label: logging=enabled)
         │ Docker 로그 파일
         ▼
     ┌────────┐  1. 컨테이너 탐색 (discovery.docker)
     │ Alloy  │  2. 필터링 + 라벨 가공 (discovery.relabel)
     └───┬────┘  3. 로그 읽기 (loki.source.docker)
         │
         │ HTTP POST /loki/api/v1/push
         ▼
  ┌──────────────┐
  │  loki-write  │  Distributor: 해시 링으로 라우팅
  │              │  Ingester: 메모리 청크 버퍼링
  └──────┬───────┘
         │ 청크 플러시 + 인덱스 저장
         ▼
  ┌──────────┐
  │  MinIO   │  영구 저장 (버킷: loki)
  └──────────┘
```

### 로그 쿼리 경로 (읽기)

```
┌─────────┐  ┌────────────┐
│ Grafana │  │ Prometheus │  (Loki 메트릭 스크래핑)
└────┬────┘  └──────┬─────┘
     │              │
     └───────┬──────┘
             │ LogQL / HTTP
             ▼
  ┌────────────────┐
  │ query-frontend │  쿼리 분할 + 결과 캐싱 + 취합
  └───────┬────────┘
          │ 서브쿼리
          ▼
  ┌────────────────┐
  │query-scheduler │  큐 관리 + 공정 분배
  └───────┬────────┘
          │ 서브쿼리 할당
          ▼
  ┌──────────┐
  │loki-read │  Querier: 실제 데이터 조회
  └────┬─────┘
       │                     ┌──────────────┐
       ├────────────────────▶│ loki-backend │  Index Gateway (인덱스 조회)
       │                     │              │  Compactor (인덱스 병합/삭제)
       │                     └──────┬───────┘
       │                            │
       └────────────────┬───────────┘
                        │ 청크 + 인덱스 조회
                        ▼
                 ┌──────────┐
                 │  MinIO   │
                 └──────────┘
```

## Loki 설정 (`loki-config.yaml`)

| 항목 | 값 |
|---|---|
| 인증 | 비활성화 |
| HTTP 포트 | 3100 |
| gRPC 포트 | 9095 |
| 스토리지 백엔드 | MinIO (S3 호환, `s3forcepathstyle`) |
| 스키마 | TSDB v13 (2024-01-01 이후) |
| 인덱스 주기 | 24시간 |
| 로그 보존 기간 | 168시간 (7일) |
| 복제 계수 | 1 |
| 클러스터 통신 | Memberlist (`loki-write` 기준으로 join) |
| Compactor gRPC | `loki-backend:9095` |
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

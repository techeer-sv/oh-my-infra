# Docker Native Loki Logging Driver

Docker 데몬에 플러그인으로 설치하여, 컨테이너 로그를 Alloy 에이전트 없이 Loki로 직접 전송하는 방식입니다.

## Alloy 방식과의 비교

| 항목 | Alloy (에이전트) | Docker Native Driver |
|---|---|---|
| 설치 | Docker Compose 서비스로 실행 | Docker 플러그인으로 설치 |
| 수집 방식 | Docker socket + 컨테이너 로그 파일 폴링 | dockerd가 직접 로그를 Loki로 push |
| 필터링 | `logging: enabled` 라벨 기반 | 서비스별 `logging.driver` 설정 |
| 네트워크 접근 | Docker 내부 네트워크 사용 가능 | dockerd 프로세스에서 실행 → host 네트워크만 사용 가능 |
| 라벨 가공 | Alloy 파이프라인에서 유연하게 처리 | `loki-pipeline-stages`, `loki-external-labels`로 제한적 처리 |
| 장애 격리 | Alloy 컨테이너만 재시작하면 됨 | dockerd 재시작 필요할 수 있음 |

---

## 동작 원리

Docker Native Logging Driver는 컨테이너가 아닌 **dockerd 프로세스 내부에서 플러그인으로 실행**됩니다.

```
컨테이너 stdout/stderr
        │
        ▼ (dockerd가 로그 캡처)
  ┌──────────────────────────────┐
  │        dockerd               │
  │  ┌───────────────────────┐   │
  │  │ loki-docker-driver    │   │
  │  │ (플러그인, host 프로세스)  │   │
  │  └──────────┬────────────┘   │
  └─────────────┼────────────────┘
                │ HTTP POST /loki/api/v1/push
                ▼
       localhost:3102 (loki-write)
```

플러그인은 dockerd와 같은 네트워크 네임스페이스에서 실행되므로, Docker 내부 네트워크(예: `loki-write:3100`)에는 접근할 수 없습니다. **반드시 host의 포트를 통해 접근해야 합니다.**

이 때문에 `logging-stack.yml`에서 `loki-write`의 포트 `3102:3100`을 호스트에 노출합니다.

### Linux에서 `host.docker.internal`을 사용할 수 없는 이유

`host.docker.internal`은 Docker Desktop(Mac/Windows)에서만 제공하는 특수 DNS입니다. Linux 환경의 Docker Engine에서는 이 호스트명이 존재하지 않아 다음 오류가 발생합니다.

```
dial tcp: lookup host.docker.internal on 127.0.0.53:53: no such host
```

따라서 Linux에서는 `loki-url`에 `http://localhost:<포트>`를 직접 사용해야 합니다.

---

## 설치

```bash
docker plugin install grafana/loki-docker-driver:3.7.0-amd64 --alias loki --grant-all-permissions
```

설치 확인:

```bash
docker plugin ls
```

출력 예시:

```
ID             NAME          DESCRIPTION           ENABLED
abc123def456   loki:latest   Loki Logging Driver   true
```

---

## Docker Compose 설정

`server-stack.yml`의 `django-app-loki` 서비스를 예시로 설명합니다.

```yaml
services:
  django-app-loki:
    image: django-app
    logging:
      driver: loki
      options:
        mode: non-blocking
        loki-url: http://localhost:3102/loki/api/v1/push
        loki-pipeline-stages: |
          - docker: {}
        loki-external-labels: "container_name=django-app-loki,driver=docker-loki"
```

### 옵션 설명

| 옵션 | 값 | 설명 |
|---|---|---|
| `driver` | `loki` | 설치한 플러그인의 alias 사용 |
| `mode` | `non-blocking` | 로그 전송이 지연되더라도 컨테이너를 블로킹하지 않음 |
| `loki-url` | `http://localhost:3102/loki/api/v1/push` | host에 노출된 loki-write 포트로 전송 |
| `loki-pipeline-stages` | `- docker: {}` | Docker 메타데이터(container_name, image 등)를 자동으로 라벨로 추가 |
| `loki-external-labels` | `"key=value,..."` | 정적 라벨을 모든 로그 스트림에 추가 |

### `loki-external-labels` 주의사항

`loki-external-labels`에 Go 템플릿(예: `{{.Name}}`)을 사용하면 파싱에 실패할 수 있습니다. 정적 문자열만 사용하는 것을 권장합니다.

```yaml
# 권장
loki-external-labels: "container_name=django-app-loki,driver=docker-loki"

# 비권장 (파싱 실패 가능)
loki-external-labels: "container_name={{.Name}},driver=docker-loki"
```

컨테이너 이름 등 동적 메타데이터는 `loki-pipeline-stages: - docker: {}` 를 통해 자동으로 수집됩니다.

---

## 실행

```bash
make server
```

---

## 검증

### 로깅 드라이버 확인

```bash
docker inspect -f '{{.HostConfig.LogConfig.Type}}' django-app-loki
```

출력이 `loki`이면 정상입니다.

### Loki에서 로그 확인

Grafana → Explore → Loki 데이터소스에서 다음 쿼리로 확인합니다.

```logql
{driver="docker-loki"}
```

또는

```logql
{container_name="django-app-loki"}
```

---

## 데이터 흐름

```
django-app-loki (stdout)
        │
        ▼ (dockerd 캡처)
  loki-docker-driver (플러그인)
        │
        │ HTTP POST
        ▼
  localhost:3102 ──▶ loki-write:3100
                           │
                           ▼
                     loki-backend (MinIO)
```

---

## Alloy 방식과 병행 운영

이 스택은 두 가지 방식을 동시에 운영합니다.

| 컨테이너 | 방식 | 식별 라벨 |
|---|---|---|
| `django-app` | Alloy (logging: enabled 라벨) | `container_name=django-app` |
| `django-app-loki` | Docker Native Driver | `driver=docker-loki` |

Grafana에서 두 스트림을 별도로 쿼리하여 수집 방식 간 차이를 비교할 수 있습니다.

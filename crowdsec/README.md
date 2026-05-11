# CrowdSec 보안 스택

## 개요

Traefik 리버스 프록시와 CrowdSec IPS(침입 방지 시스템)를 연동한 보안 스택입니다.

---

## 현재 구성된 항목

### 1. Traefik (`secured-traefik`)
- **버전**: v3.6.9
- **포트**: 80 (HTTP), 8090 (대시보드), 8091 (Prometheus 메트릭)
- **액세스 로그**: JSON 형식으로 `/traefik/logs/access.log`에 저장, CrowdSec이 읽을 수 있도록 볼륨 공유
- **OTLP 트레이싱**: `otel-collector:4317`로 전송
- **CrowdSec 바운서 플러그인**: `crowdsec-bouncer-traefik-plugin v1.6.0` 설치됨 (실험적 플러그인)

### 2. CrowdSec (`crowdsec`)
- **버전**: v1.7.7
- **컬렉션**:
  - `crowdsecurity/traefik` — Traefik 로그 파싱 및 공격 시나리오
  - `crowdsecurity/http-cve` — 알려진 HTTP CVE 탐지
  - `crowdsecurity/appsec-virtual-patching` — 가상 패치 (WAF 룰)
  - `crowdsecurity/appsec-generic-rules` — 일반 웹 공격 탐지 룰
- **바운서 키**: 환경변수 `BOUNCER_KEY_TRAEFIK`으로 사전 등록됨
- **로그 수집**:
  - `acquis.yaml` → Traefik 액세스 로그 파싱 (`/var/log/traefik/access.log`)
  - `appsec.yaml` → AppSec 컴포넌트 (`:7422`에서 Traefik 요청 수신)
- **API**: 포트 8080 (LAPI), 포트 7422 (AppSec) 노출

### 3. Grafana (`secured-grafana`)
- **버전**: v12.4
- **바운서 미들웨어**: Traefik 레이블에 `crowdsec` 미들웨어 설정 및 라우터에 적용 완료
  - LAPI 연동: `crowdsec:8080`
  - AppSec 연동: `crowdsec:7422` (실시간 요청 검사 활성화)

### 4. CrowdSec Web UI (`crowdsec-web-ui`)
- 포트 3001에서 CrowdSec API를 시각화하는 웹 인터페이스
- `crowdsec-network`를 통해 CrowdSec 컨테이너와 통신

### 5. 헬퍼 스크립트 및 설정 파일
| 파일 | 역할 |
|------|------|
| `secured.sh` | `secured-traefik-network`, `crowdsec-network` Docker 네트워크 생성 |
| `bouncer_key.sh` | CrowdSec에 `traefik-bouncer` 등록 (`cscli bouncers add`) |
| `acquis.yaml` | CrowdSec 로그 수집 소스 설정 (Traefik 액세스 로그) |
| `appsec.yaml` | AppSec 컴포넌트 설정 — `crowdsecurity/appsec-default` 사용, `:7422` 수신 |

---

## 다음 단계 (해야 할 것들)

### 1. API 키를 .env 파일로 분리 (보안)

현재 바운서 API 키가 `sec-stack.yml`에 평문으로 하드코딩되어 있습니다.
`.env` 파일로 분리하고 `.gitignore`에 추가하세요:

```env
# .env
CROWDSEC_BOUNCER_KEY=Z4MqdVoA2QGWoWbSr8cj/Ms74bP/aD4H060LIhawEWA
```

`sec-stack.yml`에서는 `${CROWDSEC_BOUNCER_KEY}`로 참조합니다.

### 3. Web UI 기본 비밀번호 변경

현재 Web UI 비밀번호가 `testing`으로 설정되어 있습니다. 프로덕션 환경에서는 반드시 변경하세요:

```yaml
- CROWDSEC_PASSWORD=<강력한_비밀번호>
```

### 4. HTTPS/TLS 설정

현재 HTTP만 지원합니다. Let's Encrypt 또는 내부 인증서로 HTTPS 엔트리포인트를 추가하세요:

```yaml
- "--entrypoints.websecure.address=:443"
- "--certificatesresolvers.letsencrypt.acme.email=<이메일>"
- "--certificatesresolvers.letsencrypt.acme.storage=/acme/acme.json"
- "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
```

### 3. Grafana에 CrowdSec 대시보드 추가

CrowdSec의 결정(차단/허용) 현황을 Grafana에서 시각화할 수 있습니다.
CrowdSec Prometheus 메트릭을 Prometheus가 수집하도록 설정한 후, 공식 대시보드를 임포트하세요:
- Grafana 대시보드 ID: `14584` (CrowdSec)

### 4. 스택 실행 순서

```bash
# 1. 네트워크 생성
bash secured.sh

# 2. 스택 실행
docker compose -f sec-stack.yml up -d

# 3. 바운서 등록 (키가 자동 등록되지 않는 경우)
bash bouncer_key.sh

# 4. CrowdSec 상태 확인
docker exec crowdsec cscli decisions list
docker exec crowdsec cscli bouncers list
docker exec crowdsec cscli alerts list

# 5. AppSec 상태 확인
docker exec crowdsec cscli appsec-rules list
```

---

## 아키텍처

```
인터넷 요청
    │
    ▼
[Traefik :80]
    │
    ├─► AppSec 실시간 요청 검사 ──► [CrowdSec AppSec :7422]
    │                                      │ (appsec.yaml)
    │                                      │ WAF 룰, CVE 가상 패치
    │
    ├─► IP 평판 차단/허용 판정 ───► [CrowdSec LAPI :8080]
    │                                      │
    │                               Traefik 액세스 로그 파싱
    │                               (acquis.yaml → /var/log/traefik/access.log)
    ▼
[Grafana :3000]          [CrowdSec Web UI :3001]
```

# CrowdSec 보안 스택

Traefik 리버스 프록시와 CrowdSec IPS(침입 방지 시스템)를 연동한 보안 스택입니다. HTTP 요청 분석, WAF, 방화벽 수준의 IP 차단을 포함합니다.

---

## 사이버보안 개념

이 스택을 이해하기 위해 필요한 기본 개념입니다.

### IDS / IPS

| 용어 | 역할 |
|---|---|
| **IDS** (Intrusion Detection System) | 공격을 탐지하고 경고만 발생 |
| **IPS** (Intrusion Prevention System) | 공격을 탐지하고 자동으로 차단 |

CrowdSec은 IPS입니다. 로그를 분석하여 공격 패턴을 탐지하고, 바운서(Bouncer)를 통해 실제 차단을 수행합니다.

### WAF (Web Application Firewall)

L7(애플리케이션 계층)에서 HTTP 요청을 검사하는 방화벽입니다. 일반 방화벽이 IP/포트 기반으로 필터링하는 반면, WAF는 요청 본문, 헤더, URI 파라미터 등을 분석합니다. CrowdSec AppSec 컴포넌트가 이 역할을 합니다.

### OWASP Top 10

OWASP(Open Worldwide Application Security Project)가 선정한 가장 빈번한 웹 취약점 목록입니다. 이 스택은 다음 위협들을 탐지·차단합니다:

| 순위 | 취약점 | 탐지 방법 |
|---|---|---|
| A01 | **Broken Access Control** — 인가되지 않은 리소스 접근 | Traefik 로그 분석 (403/401 급증) |
| A03 | **Injection** — SQL/Command/LDAP 인젝션 | AppSec WAF 룰 (appsec-generic-rules) |
| A05 | **Security Misconfiguration** — 기본 자격증명, 노출된 엔드포인트 | HTTP CVE 컬렉션 |
| A06 | **Vulnerable Components** — 알려진 CVE가 있는 컴포넌트 공격 | crowdsecurity/http-cve, appsec-virtual-patching |
| A07 | **Auth Failures** — 브루트포스, 크리덴셜 스터핑 | SSH/Traefik 로그 분석, 로그인 실패 횟수 추적 |
| A09 | **Logging & Monitoring Failures** | Loki + Alloy로 모든 로그 수집 |

### CVE와 가상 패치 (Virtual Patching)

CVE(Common Vulnerabilities and Exposures)는 공개된 보안 취약점의 식별 번호입니다. 소프트웨어 업데이트가 즉시 불가능할 때, WAF 룰을 통해 해당 공격 패턴의 요청을 차단하는 것을 **가상 패치**라고 합니다. `crowdsecurity/appsec-virtual-patching` 컬렉션이 이를 담당합니다.

### 크라우드소싱 위협 인텔리전스

CrowdSec의 핵심 특징입니다. 전 세계 CrowdSec 인스턴스들이 탐지한 악성 IP를 중앙 CTI(Cyber Threat Intelligence) 서버에 공유합니다. 내 서버가 직접 공격받지 않아도, 다른 서버를 공격한 IP를 미리 차단할 수 있습니다.

---

## 서비스 구성

### Traefik (`secured-traefik`) — 리버스 프록시 + 보안 미들웨어

**버전**: v3.6.9

모든 외부 HTTP 요청의 진입점입니다. CrowdSec 바운서 플러그인을 통해 요청마다 두 단계 보안 검사를 수행합니다.

| 포트 | 역할 |
|---|---|
| `80` | HTTP 진입점 |
| `8090` | Traefik 대시보드 |
| `8091` | Prometheus 메트릭 |

**CrowdSec 바운서 플러그인** (`crowdsec-bouncer-traefik-plugin v1.6.0`):

Traefik 미들웨어로 동작하며, 요청이 백엔드에 도달하기 전에 두 가지를 확인합니다.

1. **IP 평판 확인** → CrowdSec LAPI(`crowdsec:8080`)에 요청 IP가 차단 목록에 있는지 조회
2. **실시간 WAF 검사** → 요청 내용을 AppSec 컴포넌트(`crowdsec:7422`)로 전송하여 공격 패턴 검사

액세스 로그는 JSON 형식으로 `/traefik/logs/access.log`에 저장되고, CrowdSec과 볼륨을 공유합니다.

---

### CrowdSec (`crowdsec`) — 핵심 IPS 엔진

**버전**: v1.7.8-debian

로그를 분석하고 공격을 탐지하는 핵심 컴포넌트입니다. 다음 세 가지 역할을 합니다.

**1. 로그 수집 및 파싱 (Acquisition)**

`acquis.d/` 디렉토리의 설정 파일들이 각 소스에서 로그를 읽는 방법을 정의합니다.

| 파일 | 소스 | 파싱 대상 |
|---|---|---|
| `acquis.yaml` | 파일 | `/var/log/traefik/access.log` — Traefik HTTP 요청 로그 |
| `sshd.yaml` | journald | `ssh.service` — SSH 접속 로그 |
| `appsec.yaml` | AppSec | `:7422` 수신 — Traefik이 전달하는 실시간 HTTP 요청 |

**2. 시나리오 분석 (Detection)**

파싱된 로그 이벤트를 시나리오(탐지 규칙)와 매칭합니다. 일정 임계값을 넘으면 결정(Decision)을 생성합니다.

설치된 컬렉션:

| 컬렉션 | 탐지 내용 |
|---|---|
| `crowdsecurity/traefik` | Traefik 로그 파서 + HTTP 스캐닝, 열거 공격 시나리오 |
| `crowdsecurity/http-cve` | Log4Shell, Spring4Shell 등 알려진 HTTP CVE 공격 패턴 |
| `crowdsecurity/appsec-virtual-patching` | 공개 CVE에 대한 WAF 가상 패치 룰 |
| `crowdsecurity/appsec-generic-rules` | SQLi, XSS, Path Traversal, RCE 등 일반 웹 공격 룰 |
| `crowdsecurity/sshd` | SSH 브루트포스, 잘못된 사용자 반복 시도 |
| `crowdsecurity/linux` | Linux 시스템 로그 기반 공격 탐지 |
| `crowdsecurity/iptables` | iptables/nftables 드롭 로그 분석 |

**3. AppSec 컴포넌트 — 인라인 WAF**

`:7422` 포트에서 Traefik이 전달하는 HTTP 요청을 실시간으로 검사합니다. 로그 기반 사후 분석이 아니라, 요청이 백엔드에 도달하기 전에 차단합니다.

`appsec-default` 룰셋을 기반으로 동작하며, `appsec-virtual-patching`과 `appsec-generic-rules` 컬렉션의 룰을 적용합니다.

| 포트 | 역할 |
|---|---|
| `8080` | LAPI — 바운서와의 통신, API 쿼리 |
| `7422` | AppSec — Traefik 실시간 요청 수신 |

---

### CrowdSec Firewall Bouncer (`crowdsec-firewall-bouncer`) — 네트워크 계층 차단

CrowdSec의 결정(Decision)을 **nftables** 규칙으로 변환하여 커널 레벨에서 IP를 차단합니다. WAF 검사 이전에 네트워크 패킷 자체를 드롭하므로 가장 효율적인 차단 방법입니다.

- **모드**: `nftables`
- **업데이트 주기**: 10초마다 CrowdSec LAPI에서 최신 차단 목록 동기화
- **차단 방식**: `deny_action: drop` (패킷 드롭)
- **적용 대상**: IPv4(`crowdsec-blacklists`), IPv6(`crowdsec6-blacklists`) 모두 처리
- `network_mode: host` + `NET_ADMIN`/`NET_RAW` 권한으로 동작

---

### Grafana (`secured-grafana`) — 대시보드

**버전**: v12.4

CrowdSec 미들웨어를 통해 보호받는 서비스입니다. 모든 Grafana 요청은 Traefik을 거쳐 IP 평판 확인 + AppSec WAF 검사를 받습니다.

Traefik 라벨 설정:
- `crowdsec` 미들웨어 적용 (`crowdsec@docker`)
- LAPI 연동: `crowdsec:8080`
- AppSec 연동: `crowdsec:7422`

---

### CrowdSec Web UI (`crowdsec-web-ui`) — 관리 인터페이스

**버전**: 2026.5.3

포트 `3001`에서 CrowdSec LAPI를 시각화하는 웹 인터페이스입니다. 차단된 IP, 활성 결정, 알람 현황을 확인할 수 있습니다.

---

### Alloy (`alloy`) — 로그 수집 에이전트

**버전**: v1.13.2

`alloy-config.alloy`에 정의된 두 가지 소스에서 로그를 수집하여 Loki로 전송합니다.

1. **Docker 컨테이너 로그**: `logging=enabled` 라벨이 있는 컨테이너의 로그 자동 수집
2. **Traefik 액세스 로그**: `/traefik/logs/access.log` 파일을 직접 읽어 `job=traefik_access` 라벨로 전송

---

## 설정 파일

| 파일 | 역할 |
|---|---|
| `sec-http.yml` | 전체 스택 Docker Compose 정의 |
| `config/acquis.yaml` | Traefik 액세스 로그 수집 소스 설정 |
| `config/appsec.yaml` | AppSec 컴포넌트 설정 (`:7422`, `appsec-default` 룰셋) |
| `config/sshd.yaml` | SSH journald 로그 수집 설정 |
| `config/crowdsec-firewall-bouncer.yaml` | nftables 모드 방화벽 바운서 설정 |
| `config/config.yaml` | CrowdSec 서버 설정 — CTI 공유 정책 (공유 비활성화, 커뮤니티/블록리스트 수신 활성화) |
| `alloy-config.alloy` | Alloy 로그 수집 파이프라인 |
| `scripts/secured.sh` | Docker 네트워크 생성 (`crowdsec-network`) |
| `scripts/bouncer_key.sh` | 바운서 등록 (`traefik-bouncer`, `firewall-bouncer`) |
| `scripts/add_user.sh` | Web UI 사용자 등록 |

---

## 아키텍처

```
인터넷 요청
    │
    ▼
[Traefik :80]
    │
    ├─► 1단계: IP 평판 확인 ──────────► [CrowdSec LAPI :8080]
    │                                          │
    │                                   차단 목록에 있으면 → 403 반환
    │
    ├─► 2단계: WAF 실시간 검사 ────────► [CrowdSec AppSec :7422]
    │                                          │
    │                                   공격 패턴 감지되면 → 차단
    │
    ▼ (검사 통과)
[Grafana :3000]           [기타 서비스]

──────────────────────────────────────────────────────────

사후 분석 (로그 기반 탐지)

[Traefik access.log] ──► CrowdSec 파서/시나리오 ──► Decision 생성
[SSH journald]       ──►        (crowdsec)        ──►     │
                                                          │
                                              ┌───────────┴────────────┐
                                              ▼                        ▼
                                  [Traefik Bouncer]       [Firewall Bouncer]
                                  미들웨어에서 IP 차단      nftables 커널 차단
```

```
로그 수집 경로 (Alloy → Loki)

컨테이너(logging=enabled) ──► Alloy ──► Loki (원격)
Traefik access.log        ──►      ──►
```

---

## 실행

```bash
# 1. Docker 네트워크 생성
bash scripts/secured.sh

# 2. 스택 실행
docker compose -f sec-stack.yml up -d

# 3. Web UI 사용자 등록
bash scripts/add_user.sh

# 4. 바운서 키 등록 (환경변수로 자동 등록되지 않을 경우)
bash scripts/bouncer_key.sh
```

### 상태 확인

```bash
# 차단된 IP 목록
docker exec crowdsec cscli decisions list

# 등록된 바운서 목록
docker exec crowdsec cscli bouncers list

# 알람(탐지 이벤트) 목록
docker exec crowdsec cscli alerts list

# AppSec 룰 목록
docker exec crowdsec cscli appsec-rules list

# 전체 메트릭 (파서 히트율, 시나리오 트리거 횟수 등)
docker exec crowdsec cscli metrics
```

---

## 주의사항 (프로덕션 전 필수)

- **바운서 API 키 변경**: `sec-http.yml`의 `BOUNCER_KEY_TRAEFIK`, `BOUNCER_KEY_FIREWALL` 및 `traefik-secret-key`, `firewall-secret-key`를 모두 강력한 랜덤 값으로 교체 후 `.env`로 분리
- **Web UI 비밀번호 변경**: `CROWDSEC_PASSWORD=testing` → 강력한 비밀번호로 변경
- **HTTPS 설정**: 현재 HTTP만 지원. Let's Encrypt 또는 내부 인증서로 TLS 엔트리포인트 추가 권장

---

## 연결 네트워크

| 네트워크 | 용도 |
|---|---|
| `crowdsec-network` | CrowdSec ↔ Traefik 바운서, CrowdSec ↔ Web UI 통신 |
| `traefik-network` | Traefik ↔ Grafana 라우팅 |
| `metrics-network` | Prometheus가 Traefik 메트릭 스크래핑 |
| `logging-network` | Grafana → Loki 쿼리 |
| `grafana-network` | Grafana 데이터소스 연결 |
| `tracing-network` | 트레이싱 연동 (현재 주석 처리됨) |
| `profiling-network` | 프로파일링 연동 |

# grafana

Grafana 대시보드 JSON 정의 파일을 보관하는 디렉토리입니다. Grafana 서비스 자체는 `visualize/` 스택에서 실행됩니다.

## 포함된 대시보드

### `container_usage.json` — 컨테이너 리소스 사용량

cAdvisor가 수집한 메트릭을 기반으로 Docker 컨테이너의 자원 사용 현황을 시각화하는 대시보드입니다.

주요 시각화 항목:
- 컨테이너별 CPU 사용률
- 컨테이너별 메모리 사용량
- 컨테이너별 네트워크 I/O
- 컨테이너별 디스크 I/O

> 이 대시보드는 Prometheus 데이터소스에 의존합니다. `metrics/` 스택이 먼저 실행되어 있어야 합니다.

## 대시보드 가져오기

Grafana UI에서 수동으로 가져오는 방법:

1. Grafana 접속 (`http://localhost:3000`)
2. 좌측 메뉴 → **Dashboards** → **Import**
3. **Upload dashboard JSON file** 선택
4. `container_usage.json` 파일 업로드
5. Prometheus 데이터소스 선택 후 **Import**

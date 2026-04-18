# Makefile
.PHONY: help
help:
	@echo "사용 가능한 커맨드들:"
	@echo "  make networks       - 필요한 도커 네트워크들 생성"
	@echo "  make daemon         - 도커 데몬 메트릭 활성화"
	@echo "  make prom-reload    - 프로메테우스 설정 리로드"
	@echo "  make clean          - 모든 도커 리소스 제거"
	@echo "  make stop-all       - 모든 도커 서비스 중지"
	@echo "  make metrics        - 메트릭 컴포즈 실행"
	@echo "  make logging        - 로깅 컴포즈 실행"
	@echo "  make tracing        - 트레이싱 컴포즈 실행"
	@echo "  make profiling      - 프로파일링 컴포즈 실행"
	@echo "  make http           - HTTP 컴포즈 실행"
	@echo "  make https          - HTTPS 컴포즈 실행"

.PHONY: networks
networks:
	@echo "도커 네트워크 생성 중..."
	bash ./scripts/create-networks.sh

.PHONY: daemon
daemon:
	@echo "도커 데몬 설정 중..."
	bash ./scripts/daemon.sh

.PHONY: prom-reload
prom-reload:
	@echo "프로메테우스 설정 리로드 중..."
	bash ./scripts/reload.sh

.PHONY: clean
clean:
	@echo "모든 도커 리소스 정리 중..."
	docker system prune -af
	docker volume prune -af

.PHONY: stop-all
stop-all:
	@echo "모든 도커 컨테이너 멈추는중..."
	docker stop $(shell docker ps -q)

.PHONY: metrics
metrics:
	@echo "메트릭 컴포즈 실행 중..."
	docker compose -f ./metrics/metrics-stack.yml up -d

.PHONY: logging
logging:
	@echo "로깅 컴포즈 실행 중..."
	docker compose -f ./logging/logging-stack.yml up -d

.PHONY: tracing
tracing:
	@echo "트레이싱 컴포즈 실행 중..."
	docker compose -f ./tracing/tracing-stack.yml up -d

.PHONY: profiling
profiling:
	@echo "프로파일링 컴포즈 실행 중..."
	docker compose -f ./profiling/profiling-stack.yml up -d

.PHONY: http
http:
	@echo "HTTP 컴포즈 실행 중..."
	docker compose -f ./visualize/http.yml up -d

.PHONY: https
https:
	@echo "HTTPS 컴포즈 실행 중..."
	docker compose -f ./visualize/https.yml up -d
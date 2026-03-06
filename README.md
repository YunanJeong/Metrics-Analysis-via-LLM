# Metric LLM Reporter

Prometheus에서 수집한 인프라 메트릭을 LLM(Large Language Model)에 전달하여 자동으로 상태를 분석하고 리포트를 생성하는 쉘 기반 도구.

## 주요 기능
- 자동화된 메트릭 수집: Prometheus API를 통해 CPU, Memory, Storage, Network RX/TX 지표 추출.
- 멀티 노드 대응: Node Exporter가 설치된 여러 서버(인스턴스)의 데이터를 Job 단위로 그룹화하여 처리.
- AI 기반 분석: 수집된 데이터를 LLM(GPT-4o 등)에 전달하여 리소스 임계치 초과 및 이상 징후를 자연어로 보고받음.
- 경량 구조: 외부 라이브러리 없이 curl과 jq만 사용하여 실행.

## 시스템 구조
1. Extraction (추출): PromQL을 사용하여 각 인스턴스별 최신 메트릭을 JSON 형태로 수집.
2. Formatting (정제): 수집된 복잡한 JSON 데이터를 LLM이 문맥을 파악하기 쉬운 텍스트 리포트 형식으로 변환.
3. Analysis (분석): 정제된 리포트를 LLM API에 전송하여 전문가 수준의 SRE 분석 의견을 결과로 도출.

## 사용 방법
### 사전 요구 사항
- jq: JSON 파싱을 위한 도구
- curl: API 통신을 위한 도구
- Prometheus 서버 접근 권한

### 실행 단계
1. 환경 변수 설정 (LLM 분석이 필요한 경우):
   export OPENAI_API_KEY='your-api-key-here'

2. 스크립트 실행:
   chmod +x reporter.sh
   ./reporter.sh

## 리포트 예시
Node: 172.x.x.x:xxxx (Job: xxxxx)
- CPU Usage: 5%
- Memory Usage: 44%
- Storage Usage: 24%
- Net RX: 23329 bytes/s
- Net TX: 25801 bytes/s
...
(이후 LLM이 해당 데이터를 분석한 요약본이 출력됨)

# 📊 AI 서버 리포터 (Metric-AI-Reporter)

Prometheus 메트릭을 수집하고, AI(LLM)를 통해 서버 상태를 다각도로 점검한 뒤 결과를 메일로 발송하는 SRE 자동화 도구입니다.

---

## 🛠 주요 특징

- **멀티 소스 지원**: 여러 대의 Prometheus 서버에서 데이터를 한 번에 수집할 수 있습니다.
- **토큰 최적화**: LLM 비용 절감을 위해 '1노드 1줄'의 고밀도 압축 리포트 형식을 사용합니다. (기존 대비 토큰 약 70% 절감)
- **통합 식별자**: `Source/Job/Instance` 형태의 통합 ID를 사용하여 AI 분석 시 데이터 혼선을 방지합니다.
- **증감폭 분석**: 현재 지표뿐만 아니라 24시간 전 지표와의 차이(증감폭)를 제공하여 변화 추이를 즉시 파악합니다.
- **가시성 강화**: 80%(!), 90%(!!) 이상의 리소스 과부하 상태를 시각적 기호로 즉시 노출합니다.

---

## ⚙️ 설정 가이드 (`0.env`)

이 프로젝트는 `0.env` 파일을 기반으로 동작합니다. (`0.env.sample`을 복사하여 사용하세요.)

### [1] Prometheus 서버 설정
여러 대상을 **공백(Space)** 또는 **줄바꿈(Newline)**으로 구분하여 자유롭게 나열할 수 있습니다.

#### 💡 방법 1: 줄바꿈 사용 (가독성이 좋아 권장됨)
```bash
PROM_TARGETS="
PRODUCTION-SEOUL|http://monitor.wai:9090
STAGING-TOKYO|http://staging-monitor:9090
DEVELOP-OFFICE|http://office-monitor:9090
"
```

### [2] AI 엔진 선택
다음 세 가지 AI 엔진 중 하나를 선택할 수 있습니다.

#### 🏠 옵션 1: 로컬 LLM (Ollama)
```bash
AI_TYPE="local"
AI_MODEL="qwen3.5:9b"
AI_API_URL="http://localhost:11434"
```

#### ☁️ 옵션 2: 상용 API (OpenAI 등)
```bash
AI_TYPE="api"
AI_MODEL="gpt-4o"
AI_API_KEY="sk-..."
AI_API_URL="https://api.openai.com/v1"
```

#### 🔶 옵션 3: AWS Bedrock
```bash
AI_TYPE="bedrock"
AI_MODEL="arn:aws:bedrock:ap-northeast-2::foundation-model/anthropic.claude-3-7-sonnet-20250219-v1:0"
AWS_REGION="ap-northeast-2"
```

**AWS 인증 필요:**
```bash
# 방법 1: AWS CLI 설정
aws configure

# 방법 2: 환경변수
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

# 사용 가능한 모델 확인
aws bedrock list-foundation-models --region ap-northeast-2
```

### [3] AI 프롬프트 커스터마이징 (선택사항)

기본 프롬프트가 제공되므로 설정하지 않아도 됩니다. 필요시 `AI_PROMPT` 환경변수로 프롬프트를 커스터마이징할 수 있습니다.

```bash
# 0.env 또는 다른 환경변수 파일에 추가
AI_PROMPT="
You are an SRE expert. Analyze server metrics and provide insights.
Focus on anomalies, resource usage trends, and potential issues.
Output in Korean, use plain text only (no Markdown).
"
```

**⚠️ 주의사항:**
- **AWS Bedrock 사용 시**: ASCII 문자만 사용 가능 (한글, 중국어 등 직접 사용 불가)
- bedrock.env에는 영어 프롬프트가 미리 설정되어 있습니다

---

## 🚀 사용 방법

### 기본 실행

```bash
# 1. 실행 권한 부여
chmod +x *.sh

# 2. 기본 환경변수 파일(0.env)로 실행
./run.sh
```

### 환경변수 파일 지정

각 스크립트는 첫 번째 파라미터로 환경변수 파일 경로를 받을 수 있습니다.

```bash
# 전체 파이프라인 실행 (다른 환경 설정 사용)
./run.sh prod.env
./run.sh dev.env
./run.sh staging.env

# 개별 모듈 단독 실행 예시
./1.fetch.sh prod.env                        # 메트릭만 수집
cat report.txt | ./2.brain.sh dev.env        # AI 분석만 실행 (로컬 LLM)
cat report.txt | ./2.brain.sh bedrock.env    # AI 분석만 실행 (Bedrock)
cat analysis.txt | ./3.mail.sh prod.env      # 메일만 발송
```

### 환경변수 우선순위

1. **직접 전달한 환경변수** (최우선)
2. 파라미터로 지정한 환경변수 파일
3. 기본 환경변수 파일 (`./0.env`)

```bash
# 예시: PROM_TARGETS만 임시로 변경하고 나머지는 prod.env 사용
PROM_TARGETS="TEST|http://test:9090" ./1.fetch.sh prod.env
```

---

## 📝 리포트 명세 (Data Specification)

AI 분석에 전달되는 데이터는 다음과 같은 포맷을 가집니다. (모든 수치는 24시간 전 대비 **증감폭**을 포함합니다.)

- **ID**: `Source/Job/Instance` (예: SEOUL/node-exporter/10.1.1.1:9100)
- **C:CPU% (diff)**: 최근 **5분 평균** CPU 사용률(%)
- **M:MEM% (diff)**: 현재 메모리 사용률(%)
- **D:DSK% (diff)**: 현재 디스크 사용률(%)
- **R:RX / T:TX (diff)**: 네트워크 수신/송신 속도 (단위: Mbps, SI 표준 10^6 기준)
- **기호(!, !!)**: 80% 이상(!), 90% 이상(!!)의 리소스 사용 상태 표시

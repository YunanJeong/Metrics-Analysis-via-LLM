# 📊 AI 서버 리포터 (Metric-AI-Reporter)

Prometheus 메트릭을 수집하고, AI(LLM)를 통해 서버 상태를 다각도로 점검한 뒤 결과를 메일로 발송하는 SRE 자동화 도구입니다.

---

## 🛠 주요 특징

- **멀티 소스 지원**: 여러 대의 Prometheus 서버에서 데이터를 한 번에 수집할 수 있습니다.
- **토큰 최적화**: LLM 비용 절감을 위해 '1노드 1줄'의 고밀도 압축 리포트 형식을 사용합니다. (기존 대비 토큰 약 70% 절감)
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

#### 💡 방법 2: 공백(Space) 사용 (한 줄에 나열)
```bash
# 형식: "라벨|URL 라벨2|URL2"
PROM_TARGETS="SEOUL|http://url1 TOKYO|http://url2 OFFICE|http://url3"
```

### [2] AI 엔진 선택
로컬 LLM(Ollama) 또는 상용 API(OpenAI 등)를 선택할 수 있습니다.

#### 🏠 로컬 LLM (Ollama 등)
```bash
AI_TYPE="local"
AI_MODEL="qwen3.5:9b"
AI_API_URL="http://localhost:11434"
```

#### 🏢 상용 API (OpenAI 등)
```bash
AI_TYPE="api"
AI_MODEL="gpt-4o"
AI_API_KEY="sk-..."
AI_API_URL="https://api.openai.com/v1"
```

---

## 🚀 사용 방법

```bash
# 1. 실행 권한 부여
chmod +x *.sh

# 2. 실행
./run.sh
```

---

## 📝 리포트 명세 (Data Specification)

AI 분석에 전달되는 데이터는 다음과 같은 포맷을 가집니다. (모든 수치는 24시간 전 대비 **증감폭**을 포함합니다.)

- **[Job]**: 서비스 이름 또는 그룹 식별자
- **Instance**: 서버의 IP 주소와 포트 번호
- **CPU% (diff)**: 최근 **5분 평균** CPU 사용률(%)
- **MEM% (diff)**: 현재 메모리 사용률(%)
- **DISK% (diff)**: 현재 디스크 사용률(%)
- **R:RX / T:TX (diff)**: 네트워크 수신/송신 속도 (단위: Mbps)
- **기호(!, !!)**: 80% 이상(!), 90% 이상(!!)의 리소스 사용 상태 표시

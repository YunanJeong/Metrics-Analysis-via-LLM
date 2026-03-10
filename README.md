# 📊 AI 서버 리포터 (Metric-AI-Reporter)

Prometheus 메트릭을 수집하고 AI를 통해 서버 상태를 점검한 뒤 결과를 메일로 발송하는 자동화 도구입니다.

---

## 💡 AI 엔진 선택 (`0.env`)

이 도구는 기본적으로 **로컬 LLM (Ollama)**을 사용하도록 설정되어 있습니다.

### 🏠 로컬 LLM 사용 (Ollama 등)
`0.env`에서 `AI_TYPE="local"`을 활성화하세요.
```bash
AI_TYPE="local"
AI_MODEL="qwen3.5:9b"
AI_API_URL="http://localhost:11434"
```

### 🏢 상용 API 사용 (OpenAI 등)
`0.env`에서 `AI_TYPE="api"`를 활성화하세요.
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

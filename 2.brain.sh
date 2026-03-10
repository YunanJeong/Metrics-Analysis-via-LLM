#!/bin/bash
# ==============================================================================
# [모듈 이름] 2.brain.sh - AI 분석 엔진 (범용 분석 버전)
# ==============================================================================

# 0. 설정 로드
[ -f "./0.env" ] && source ./0.env

# 1. 기본값 설정 (0.env에 설정이 없을 경우 대비)
AI_TYPE=${AI_TYPE:-"local"}
AI_MODEL=${AI_MODEL:-"qwen3.5:9b"}
AI_API_URL=${AI_API_URL:-"http://localhost:11434"}
AI_API_KEY=${AI_API_KEY:-"not-needed"}

REPORT_TEXT=$(cat -)
if [ -z "$REPORT_TEXT" ]; then
    echo "Error: No input text provided." >&2
    exit 1
fi

# 범용적인 SRE 분석 프롬프트로 복구
PROMPT="아래는 Prometheus에서 수집한 노드별 서버 메트릭 데이터이다. 
SRE 전문가 입장에서 각 노드의 리소스 상태를 점검하고, 리소스 사용량이 80%를 넘거나 비정상적인 지표가 있는 경우를 식별해줘. 
리포트는 한국어로 간결하게 작성해줘.

$REPORT_TEXT"

if [ "$AI_TYPE" == "local" ]; then
    # Ollama Native API (기본 포트 11434 사용)
    ENDPOINT="${AI_API_URL}/api/generate"
    PAYLOAD=$(jq -n --arg p "$PROMPT" --arg m "$AI_MODEL" '{model: $m, prompt: $p, stream: false}')
    curl -s "$ENDPOINT" -H "Content-Type: application/json" -d "$PAYLOAD" | jq -r '.response // .error'

elif [ "$AI_TYPE" == "api" ]; then
    # OpenAI 또는 호환 API (Chat Completion 방식)
    ENDPOINT="${AI_API_URL}/chat/completions"
    PAYLOAD=$(jq -n --arg p "$PROMPT" --arg m "$AI_MODEL" '{model: $m, messages: [{role: "system", content: "You are a senior SRE engineer."}, {role: "user", content: $p}]}')
    curl -s "$ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $AI_API_KEY" \
      -d "$PAYLOAD" | jq -r '.choices[0].message.content // .error.message'
fi

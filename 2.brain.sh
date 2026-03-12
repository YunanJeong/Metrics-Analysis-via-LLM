#!/bin/bash
# ==============================================================================
# [모듈 이름] 2.brain.sh - AI 분석 엔진 (SRE 리포트 분석 도구)
#
# [주요 기능]
# 1. 입력된 텍스트 리포트를 바탕으로 AI(LLM) 분석 수행
# 2. 로컬 LLM(Ollama) 및 상용 API(OpenAI 등) 연동 지원
# 3. 분석 소요 시간 측정 및 결과 출력
#
# [단독 사용 방법]
#   1. 파일 또는 텍스트를 파이프로 전달:
#      $ cat report.txt | ./2.brain.sh
#      $ echo "Node 1: CPU 90%!!" | ./2.brain.sh
#
#   2. AI 설정을 환경 변수로 직접 지정하여 실행:
#      $ echo "Data..." | AI_TYPE="api" AI_MODEL="gpt-4o" AI_API_KEY="sk-..." ./2.brain.sh
#
#   3. 0.env 파일에 설정 후 실행:
#      $ cat report.txt | ./2.brain.sh
# ==============================================================================

# 0. 설정 로드
[ -f "./0.env" ] && source ./0.env

# 1. 기본값 설정
AI_TYPE=${AI_TYPE:-"local"}
AI_MODEL=${AI_MODEL:-"qwen3.5:9b"}
AI_API_URL=${AI_API_URL:-"http://localhost:11434"}
AI_API_KEY=${AI_API_KEY:-"not-needed"}

REPORT_TEXT=$(cat -)
if [ -z "$REPORT_TEXT" ]; then
    echo "[Error] No input text provided." >&2
    exit 1
fi

# 추론 과정을 생략하고 결과만 즉시 출력하라. => 매우 빠르게 반환하고, 터지지 않음. 출력물이 지나치게 짧다.
# bold처리 등 텍스트를 꾸미는 데 신경쓰지말고 신속한 결과출력에 집중하라. => 적당한 길이, 적당한 출력시간, 간헐적 터짐
PROMPT="
### Qwen Optimized SRE Metrics Analysis Prompt
# Role
你是一位资深的 SRE 专家。请分析以下来自 Prometheus 的节点服务器指标数据，并生成一份分析报告。

# Task
1. 统计并列出本次分析的节点总数。
2. 检查各节点的资源状态，识别利用率超过 80% 的指标。
3. 对比今日与昨日的数据，指出显著的变化趋势（如上升、下降或持平）。
4. 发现任何异常指标（如 Network Error, Disk I/O Wait 等）。

# Output Requirements
- 语言：韩语 (한국어)
- 风格：简洁、结果导向
- 格式：纯文本 (禁止使用 bold 等 Markdown 装饰)
- 要求：直接输出结果，跳过推理过程。报告开头必须包含“분석 노드 수: N개” 및 “전일 대비 변동 사항 요약”。

# Critical Thresholds
- CPU/Memory/Disk Usage: > 80% (Warning), > 90% (Critical)
- Network Error Rate: > 0.1%
- Disk I/O Wait: > 10%
$REPORT_TEXT"


# 시간 측정 시작
START_TIME=$SECONDS

echo "[AI] 분석을 시작합니다 (Model: $AI_MODEL)..." >&2

if [ "$AI_TYPE" == "local" ]; then
    ENDPOINT="${AI_API_URL}/api/generate"
    PAYLOAD=$(jq -n --arg p "$PROMPT" --arg m "$AI_MODEL" '{model: $m, prompt: $p, stream: false}')
    
    RESPONSE=$(curl -sS -X POST "$ENDPOINT" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      --connect-timeout 5 \
      --max-time 120)

    if [ $? -ne 0 ]; then
        echo "[Error] AI 서버와 연결할 수 없습니다. 주소나 포트를 확인하세요 ($AI_API_URL)." >&2
        exit 1
    fi

    RESULT=$(echo "$RESPONSE" | jq -r '.response // .error')

elif [ "$AI_TYPE" == "api" ]; then
    ENDPOINT="${AI_API_URL}/chat/completions"
    PAYLOAD=$(jq -n --arg p "$PROMPT" --arg m "$AI_MODEL" '{model: $m, messages: [{role: "system", content: "You are a senior SRE engineer."}, {role: "user", content: $p}]}')
    
    RESPONSE=$(curl -sS -X POST "$ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $AI_API_KEY" \
      -d "$PAYLOAD" \
      --connect-timeout 10 \
      --max-time 60)

    if [ $? -ne 0 ]; then
        echo "[Error] API 서버 호출에 실패했습니다." >&2
        exit 1
    fi

    RESULT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // .error.message')
fi

# 최종 결과 검증 및 출력
if [ -z "$RESULT" ] || [ "$RESULT" == "null" ]; then
    echo "[Error] AI로부터 응답을 받지 못했습니다. 서버 로그를 확인하세요." >&2
    echo "Raw Response: $RESPONSE" >&2
    exit 1
fi

# 시간 측정 종료 및 계산
DURATION=$((SECONDS - START_TIME))

echo "$RESULT"
echo "[AI] 분석이 완료되었습니다. (소요 시간: ${DURATION}초)" >&2

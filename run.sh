#!/bin/bash
# run.sh - AI 서버 리포터 실행기

# 0. 설정 로드
if [ -f "./0.env" ]; then
    source ./0.env
else
    echo "Error: 0.env file not found." >&2
    exit 1
fi

# 1. 메트릭 추출
# PROM_URL 설정은 0.env에서 로드된 것을 사용
REPORT_TEXT=$(PROM_URL="$PROM_URL" ./1.fetch.sh)

# 2. 결과 출력 (확인용)
echo -e "\n================ [METRICS SUMMARY] ================"
echo "$REPORT_TEXT"
echo "===================================================\n"

# 3. AI 분석 요청
# AI_TYPE, AI_MODEL, AI_API_KEY, AI_API_URL을 0.env에서 그대로 전달
ANALYSIS_RESULT=$(echo "$REPORT_TEXT" | \
    AI_TYPE="$AI_TYPE" \
    AI_MODEL="$AI_MODEL" \
    AI_API_KEY="$AI_API_KEY" \
    AI_API_URL="$AI_API_URL" \
    ./2.brain.sh)

# 4. 분석 결과 출력 및 메일 발송
if [ -n "$ANALYSIS_RESULT" ]; then
    echo "================ [AI SRE ANALYSIS] ================"
    echo "$ANALYSIS_RESULT"
    echo "==================================================="

    # # 5. 메일 발송
    # echo "$ANALYSIS_RESULT" | \
    # RECIPIENT="$MAIL_RECIPIENT" \
    # SUBJECT="$MAIL_SUBJECT ($(date +'%Y-%m-%d %H:%M'))" \
    # ./3.mail.sh
fi

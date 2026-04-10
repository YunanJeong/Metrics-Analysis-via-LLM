#!/bin/bash
# ==============================================================================
# [모듈 이름] 3.mail.sh - 메일 전송 도구
#
# [설명] 표준 입력(stdin)으로 받은 내용을 지정된 수신자에게 메일로 발송합니다.
#
# [단독 사용 방법 (복붙 시)]
#   1. 필수 도구: mailutils (또는 bsd-mailx)
#   2. 실행 방법:
#      $ echo "메일본문" | RECIPIENT="admin@site.com" SUBJECT="서버장애" ./3.mail.sh
#   3. From 주소 및 SMTP 서버 지정:
#      $ echo "메일본문" | FROM_NAME="SRE Bot" FROM_ADDR="noreply@site.com" \
#        SMTP_SERVER="smtp.site.com" SMTP_PORT="25" RECIPIENT="admin@site.com" ./3.mail.sh
# ==============================================================================

# 0. 설정 로드 (프로젝트 내 사용 시)
ENV_FILE=${1:-"./0.env"}
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# 1. 환경변수 우선, 없으면 설정파일(ENV_FILE)에서 가져온 변수 사용
RECIPIENT=${RECIPIENT:-$MAIL_RECIPIENT}
SUBJECT=${SUBJECT:-$MAIL_SUBJECT}
SUBJECT=${SUBJECT:-"[SRE Report] Server Resource AI Analysis ($(date +'%Y-%m-%d %H:%M'))"}

FROM_NAME=${FROM_NAME:-$FROM_NAME}
FROM_ADDR=${FROM_ADDR:-$FROM_ADDR}
SMTP_SERVER=${SMTP_SERVER:-$SMTP_SERVER}
SMTP_PORT=${SMTP_PORT:-$SMTP_PORT}

CONTENT=$(cat -)
if [ -z "$CONTENT" ]; then
    echo "Error: No content to send." >&2
    exit 1
fi

# 메일 발송 옵션 구성
MAIL_OPTS="-s \"$SUBJECT\""

# From 주소 지정
if [ -n "$FROM_NAME" ] && [ -n "$FROM_ADDR" ]; then
    MAIL_OPTS="$MAIL_OPTS -a \"From: $FROM_NAME <$FROM_ADDR>\""
elif [ -n "$FROM_ADDR" ]; then
    MAIL_OPTS="$MAIL_OPTS -a \"From: $FROM_ADDR\""
fi

# SMTP 서버 지정
if [ -n "$SMTP_SERVER" ] && [ -n "$SMTP_PORT" ]; then
    MAIL_OPTS="$MAIL_OPTS --exec=\"set sendmail=smtp://$SMTP_SERVER:$SMTP_PORT\""
fi

# 메일 발송 실행
eval "echo \"\$CONTENT\" | mail $MAIL_OPTS \"$RECIPIENT\""

if [ $? -eq 0 ]; then
    echo "[Mail] Sent to $RECIPIENT successfully."
    [ -n "$FROM_ADDR" ] && echo "[Mail] From: $FROM_ADDR"
else
    echo "[Mail] Failed to send. Check your mail system." >&2
    exit 1
fi

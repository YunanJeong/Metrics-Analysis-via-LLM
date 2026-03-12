#!/bin/bash
# ==============================================================================
# [모듈 이름] 1.fetch.sh - 멀티 소스 Prometheus 메트릭 수집 및 컴팩트 포맷 변환기
#
# [설정 방법] 0.env의 PROM_TARGETS에 "라벨|URL" 형식으로 설정하십시오.
# (여러 대상을 지정할 경우 줄바꿈(Newline)으로 구분하여 나열할 수 있습니다.)
#
# [단독 사용 방법]
#   1. 환경 변수로 직접 지정하여 실행 (즉석 테스트):
#      $ PROM_TARGETS="MY-SERVER|http://localhost:9090" ./1.fetch.sh
#
#   2. 여러 서버를 한 번에 지정하여 실행:
#      $ PROM_TARGETS="S1|http://url1 S2|http://url2" ./1.fetch.sh
#      (또는 줄바꿈 사용)
#      $ PROM_TARGETS="
#        S1|http://url1
#        S2|http://url2
#        " ./1.fetch.sh
#
#   3. 0.env 파일에 설정 후 실행:
#      $ ./1.fetch.sh
#
# 예시:
# PROM_TARGETS="
# SEOUL-PROD|http://10.1.1.1:9090
# TOKYO-STG|http://10.2.2.2:9090
# "
# ==============================================================================

# 0. 설정 로드
if [ -f "./0.env" ]; then
    source ./0.env
else
    # 0.env가 없으면 기본값 사용
    PROM_TARGETS=${PROM_TARGETS:-"PRODUCTION-SEOUL|http://monitor.wai:9090"}
fi

METRIC_KEYS=("cpu" "memory" "storage" "net_rx" "net_tx")
PROM_QUERIES=(
  "100 - (avg by (instance, job) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)"
  "100 * (1 - (avg by (instance, job) (node_memory_MemAvailable_bytes) / avg by (instance, job) (node_memory_MemTotal_bytes)))"
  "max by (instance, job) (100 * (1 - (node_filesystem_avail_bytes{fstype!~'tmpfs|overlay'} / node_filesystem_size_bytes{fstype!~'tmpfs|overlay'})))"
  "sum by (instance, job) (irate(node_network_receive_bytes_total{device!~'lo'}[5m]))"
  "sum by (instance, job) (irate(node_network_transmit_bytes_total{device!~'lo'}[5m]))"
)

fetch_raw_json() {
    local url="$1"
    local target_time="$2"
    local time_param=""
    [ -n "$target_time" ] && time_param="--data-urlencode time=$target_time"

    local full_json="{}"
    for i in "${!METRIC_KEYS[@]}"; do
        local key="${METRIC_KEYS[$i]}"
        local query="${PROM_QUERIES[$i]}"
        local response=$(curl -s -G "${url}/api/v1/query" --data-urlencode "query=${query}" $time_param)
        if echo "$response" | jq -e '.data.result' >/dev/null 2>&1; then
            full_json=$(echo "$full_json" | jq --arg key "$key" --argjson val "$response" '. + {($key): $val.data.result}')
        else
            full_json=$(echo "$full_json" | jq --arg key "$key" '. + {($key): []}')
        fi
    done
    echo "$full_json"
}

format_compact() {
    local source_label="$1"
    local today_json="$2"
    local yesterday_json="$3"

    # 1. 오늘/어제 데이터를 결합하여 jq로 전달
    echo "$today_json" | jq -r --arg src "$source_label" --argjson yesterday "$yesterday_json" '
      . as $today |
      ([.[] | .[]? | {instance: .metric.instance, job: .metric.job}] | unique)[] as $node |
      
      # 헬퍼 함수: 특정 노드의 지표 추출 (없으면 0)
      def get_val(dataset; key): (dataset[key][]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1] | tonumber) // 0;
      
      # 헬퍼 함수: 소수점 1자리 반올림
      def to_f1: . * 10 | round / 10;

      # 지표 계산 (오늘/어제)
      (get_val($today; "cpu") | to_f1) as $c0 | (get_val($yesterday; "cpu") | to_f1) as $c1 |
      (get_val($today; "memory") | to_f1) as $m0 | (get_val($yesterday; "memory") | to_f1) as $m1 |
      (get_val($today; "storage") | to_f1) as $d0 | (get_val($yesterday; "storage") | to_f1) as $d1 |
      (get_val($today; "net_rx") * 8 / 1000000) as $rx0 | (get_val($yesterday; "net_rx") * 8 / 1000000) as $rx1 |
      (get_val($today; "net_tx") * 8 / 1000000) as $tx0 | (get_val($yesterday; "net_tx") * 8 / 1000000) as $tx1 |
      
      # 기호 처리 (!, !!)
      (if $c0 >= 90 then "!!" elif $c0 >= 80 then "!" else "" end) as $cs |
      (if $m0 >= 90 then "!!" elif $m0 >= 80 then "!" else "" end) as $ms |
      (if $d0 >= 90 then "!!" elif $d0 >= 80 then "!" else "" end) as $ds |
      
      # Diff 포맷팅 함수
      def fmt_diff(now; old): 
        (now - old | to_f1) as $diff | 
        (if $diff >= 0 then "+" + ($diff|tostring) else ($diff|tostring) end);

      fmt_diff($c0; $c1) as $cdstr |
      fmt_diff($m0; $m1) as $mdstr |
      fmt_diff($d0; $d1) as $ddstr |
      fmt_diff($rx0; $rx1) as $rx_diff |
      fmt_diff($tx0; $tx1) as $tx_diff |
      
      # 최종 출력 포맷팅 (Source/Job/Instance 통합)
      $src + "/" + $node.job + "/" + $node.instance + " | " + 
      "C:" + ($c0|tostring) + "%" + $cs + "(" + $cdstr + ") | " +
      "M:" + ($m0|tostring) + "%" + $ms + "(" + $mdstr + ") | " +
      "D:" + ($d0|tostring) + "%" + $ds + "(" + $ddstr + ") | " +
      "R:" + ($rx0|to_f1|tostring) + "Mbps(" + $rx_diff + ") | " +
      "T:" + ($tx0|to_f1|tostring) + "Mbps(" + $tx_diff + ")"
    '
}

# --- 메인 실행부 ---

# 리포트 명세(Specification) 출력 - LLM 학습용
cat <<EOF
# ==============================================================================
# [SRE METRIC SPECIFICATION]
# All (diff): 24h delta (Current - Yesterday)
# 1. N:NodeID   : Node Identifier
# 2. C:CPU%     : 5min avg usage
# 3. M:MEM%     : Current usage
# 4. D:DSK%     : Current usage
# 5. R:RX_Mbps  : Inbound Mbps
# 6. T:TX_Mbps  : Outbound Mbps

# [Status Symbols]
# - '!'  : Warning (> 80%)
# - '!!' : Critical (> 90%)
# ==============================================================================
EOF

# 리포트 메타 정보 출력
echo "Generated at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 결과 수집용 변수
RAW_RESULTS=""

# PROM_TARGETS 순회 (줄바꿈 또는 공백으로 구분된 "LABEL|URL" 목록)
for target in $PROM_TARGETS; do
    # 빈 줄 제외
    [[ -z "$target" ]] && continue
    
    LABEL=$(echo "$target" | cut -d'|' -f1)
    URL=$(echo "$target" | cut -d'|' -f2)
    
    # 데이터 수집
    RAW_NOW=$(fetch_raw_json "$URL" "")
    TIME_YESTERDAY=$(date -d "24 hours ago" +%s)
    RAW_YESTERDAY=$(fetch_raw_json "$URL" "$TIME_YESTERDAY")
    
    # 컴팩트 포맷 수집
    RESULT=$(format_compact "$LABEL" "$RAW_NOW" "$RAW_YESTERDAY")
    if [ -n "$RESULT" ]; then
        RAW_RESULTS+="$RESULT"$'\n'
    fi
done

# Node ID 단순화 및 매핑 테이블 생성
declare -A ID_MAP
declare -a ID_LIST
COUNTER=1
FINAL_METRICS=""

while IFS= read -r line; do
    [ -z "$line" ] && continue
    
    # 첫 번째 '|'를 기준으로 ID와 메트릭 분리
    FULL_ID=$(echo "$line" | cut -d'|' -f1 | xargs)
    METRICS=$(echo "$line" | cut -d'|' -f2-)
    
    # ID가 처음 등장하면 매핑 등록
    if [[ -z "${ID_MAP[$FULL_ID]}" ]]; then
        SHORT_ID="N:$COUNTER"
        ID_MAP[$FULL_ID]=$SHORT_ID
        ID_LIST+=("$SHORT_ID | $FULL_ID")
        ((COUNTER++))
    fi
    
    FINAL_METRICS+="${ID_MAP[$FULL_ID]} |$METRICS"$'\n'
done <<< "$RAW_RESULTS"

# 1. 메트릭 테이블 출력
echo "# [METRIC REPORT]"
echo -e "$FINAL_METRICS"

# 2. 노드 ID 매핑 테이블 출력
echo "# [NODE ID MAPPING TABLE]"
for mapping in "${ID_LIST[@]}"; do
    echo "$mapping"
done

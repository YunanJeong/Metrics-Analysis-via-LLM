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

    echo "@SOURCE: [$source_label]"
    echo "# [Job] Instance | C:CPU%(diff) | M:MEM%(diff) | D:DSK%(diff) | R:RX_Mbps(diff) | T:TX_Mbps(diff)"
    
    # 1. 오늘/어제 데이터를 결합하여 jq로 전달
    echo "$today_json" | jq -r --argjson yesterday "$yesterday_json" '
      . as $today |
      ([.[] | .[]? | {instance: .metric.instance, job: .metric.job}] | unique)[] as $node |
      
      # 헬퍼 함수: 특정 노드의 지표 추출 (없으면 0)
      def get_val(dataset; key): (dataset[key][]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1] | tonumber) // 0;
      
      # 지표 계산 (오늘/어제)
      (get_val($today; "cpu") | round) as $c0 | (get_val($yesterday; "cpu") | round) as $c1 |
      (get_val($today; "memory") | round) as $m0 | (get_val($yesterday; "memory") | round) as $m1 |
      (get_val($today; "storage") | round) as $d0 | (get_val($yesterday; "storage") | round) as $d1 |
      (get_val($today; "net_rx") * 8 / 1000000) as $rx0 | (get_val($yesterday; "net_rx") * 8 / 1000000) as $rx1 |
      (get_val($today; "net_tx") * 8 / 1000000) as $tx0 | (get_val($yesterday; "net_tx") * 8 / 1000000) as $tx1 |
      
      # 기호 처리 (!, !!)
      (if $c0 >= 90 then "!!" elif $c0 >= 80 then "!" else "" end) as $cs |
      (if $m0 >= 90 then "!!" elif $m0 >= 80 then "!" else "" end) as $ms |
      (if $d0 >= 90 then "!!" elif $d0 >= 80 then "!" else "" end) as $ds |
      
      # Diff 포맷팅 함수
      def fmt_diff(now; old; is_net): 
        (now - old) as $diff | 
        if is_net then
          (if $diff >= 0 then "+" + ($diff*10|round/10|tostring) else ($diff*10|round/10|tostring) end)
        else
          (if $diff >= 0 then "+" + ($diff|tostring) else ($diff|tostring) end)
        end;

      fmt_diff($c0; $c1; false) as $cdstr |
      fmt_diff($m0; $m1; false) as $mdstr |
      fmt_diff($d0; $d1; false) as $ddstr |
      fmt_diff($rx0; $rx1; true) as $rx_diff |
      fmt_diff($tx0; $tx1; true) as $tx_diff |
      
      # 최종 출력 포맷팅
      "[" + $node.job + "] " + $node.instance + " | " + 
      "C:" + ($c0|tostring) + "%" + $cs + "(" + $cdstr + ") | " +
      "M:" + ($m0|tostring) + "%" + $ms + "(" + $mdstr + ") | " +
      "D:" + ($d0|tostring) + "%" + $ds + "(" + $ddstr + ") | " +
      "R:" + ($rx0*10|round/10|tostring) + "Mbps(" + $rx_diff + ") | " +
      "T:" + ($tx0*10|round/10|tostring) + "Mbps(" + $tx_diff + ")"
    '
}

# --- 메인 실행부 ---

# 리포트 명세(Specification) 출력 - LLM 학습용
cat <<EOF
# ==============================================================================
# [SRE SERVER METRIC REPORT - DATA SPECIFICATION]
# 이 리포트는 다음 형식을 따르며, 모든 수치는 24시간 전과 비교한 증감폭(diff)을 포함합니다.
#
# 1. [Job] : 서비스 이름 또는 그룹 식별자입니다.
# 2. Instance : 서버의 전체 IP 주소와 포트 번호입니다.
# 3. CPU% (diff) : 최근 5분 평균 CPU 사용률(%)
# 4. MEM% (diff) : 현재 메모리 사용률(%)
# 5. DISK% (diff) : 현재 디스크 사용률(%)
# 6. R:RX (diff) : 네트워크 수신(RX) 속도(Mbps)
# 7. T:TX (diff) : 네트워크 송신(TX) 속도(Mbps)
#
# [상태 알림 기호]
# - '!'  : 해당 리소스 사용량이 80%를 초과하여 주의가 필요함을 의미합니다.
# - '!!' : 해당 리소스 사용량이 90%를 초과하여 즉각적인 조치가 필요한 위험 상태입니다.
# ==============================================================================
EOF

# 리포트 메타 정보 출력
echo "Generated at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

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
    
    # 컴팩트 포맷 출력
    format_compact "$LABEL" "$RAW_NOW" "$RAW_YESTERDAY"
    echo ""
done

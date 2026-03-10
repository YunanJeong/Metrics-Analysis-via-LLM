#!/bin/bash
# ==============================================================================
# [모듈 이름] 1.fetch.sh - Prometheus 메트릭 추출 도구 (단위 교정판)
#
# [설명] 데이터를 추출하며 네트워크 단위는 MB/s(MegaBytes per second)로 변환합니다.
# ==============================================================================

# 0. 설정 로드
[ -z "$PROM_URL" ] && [ -f "./0.env" ] && source ./0.env
PROM_URL=${PROM_URL:-"http://monitor.wai:9090"}

METRIC_KEYS=("cpu" "memory" "storage" "net_rx" "net_tx")
PROM_QUERIES=(
  "100 - (avg by (instance, job) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)"
  "100 * (1 - (avg by (instance, job) (node_memory_MemAvailable_bytes) / avg by (instance, job) (node_memory_MemTotal_bytes)))"
  "max by (instance, job) (100 * (1 - (node_filesystem_avail_bytes{fstype!~'tmpfs|overlay'} / node_filesystem_size_bytes{fstype!~'tmpfs|overlay'})))"
  "sum by (instance, job) (irate(node_network_receive_bytes_total{device!~'lo'}[5m]))"
  "sum by (instance, job) (irate(node_network_transmit_bytes_total{device!~'lo'}[5m]))"
)

fetch_metrics_at() {
    local target_time="$1"
    local time_param=""
    [ -n "$target_time" ] && time_param="--data-urlencode time=$target_time"

    local full_json="{}"
    for i in "${!METRIC_KEYS[@]}"; do
        local key="${METRIC_KEYS[$i]}"
        local query="${PROM_QUERIES[$i]}"
        local response=$(curl -s -G "${PROM_URL}/api/v1/query" --data-urlencode "query=${query}" $time_param)
        if echo "$response" | jq -e '.data.result' >/dev/null 2>&1; then
            full_json=$(echo "$full_json" | jq --arg key "$key" --argjson val "$response" '. + {($key): $val.data.result}')
        else
            full_json=$(echo "$full_json" | jq --arg key "$key" '. + {($key): []}')
        fi
    done
    echo "$full_json"
}

format_to_text() {
    local label="$1"
    local input_json="$2"
    echo "--- [$label] ---"
    echo "$input_json" | jq -r '
      . as $root | 
      ([.[] | .[]? | {instance: .metric.instance, job: .metric.job}] | unique)[] as $node |
      "Node: " + $node.instance + " (Job: " + $node.job + ")\n" +
      "- CPU: " + ([$root.cpu[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + "%\n" +
      "- MEM: " + ([$root.memory[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + "%\n" +
      "- DISK: " + ([$root.storage[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + "%\n" +
      "- Net RX: " + (([$root.net_rx[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber) / 1048576 | . * 100 | round | . / 100 | tostring) + " MB/s\n" +
      "- Net TX: " + (([$root.net_tx[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber) / 1048576 | . * 100 | round | . / 100 | tostring) + " MB/s\n"
    '
}

RAW_NOW=$(fetch_metrics_at "")
TIME_YESTERDAY=$(date -d "24 hours ago" +%s)
RAW_YESTERDAY=$(fetch_metrics_at "$TIME_YESTERDAY")

echo "=== SERVER METRIC TREND REPORT ==="
echo "Generated at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Units: CPU/MEM/DISK (%), Network (MB/s)"
echo ""
format_to_text "TODAY (NOW)" "$RAW_NOW"
echo ""
format_to_text "YESTERDAY (24H AGO)" "$RAW_YESTERDAY"

#!/bin/bash

# ==============================================================================
# [SECTION A] PROMETHEUS METRIC EXTRACTION (프로메테우스 메트릭 추출부)
# ==============================================================================

# Prometheus Configuration
PROM_URL="http://monitor.wai:9090"

# Prometheus Queries (Keys and PromQL)
METRIC_KEYS=("cpu" "memory" "storage" "net_rx" "net_tx")
PROM_QUERIES=(
  "100 - (avg by (instance, job) (irate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)"
  "100 * (1 - (avg by (instance, job) (node_memory_MemAvailable_bytes) / avg by (instance, job) (node_memory_MemTotal_bytes)))"
  "max by (instance, job) (100 * (1 - (node_filesystem_avail_bytes{fstype!~'tmpfs|overlay'} / node_filesystem_size_bytes{fstype!~'tmpfs|overlay'})))"
  "sum by (instance, job) (irate(node_network_receive_bytes_total{device!~'lo'}[5m]))"
  "sum by (instance, job) (irate(node_network_transmit_bytes_total{device!~'lo'}[5m]))"
)

# Function: Fetch all metrics and return a single JSON object
fetch_raw_metrics() {
    local full_json="{}"
    echo "[Prometheus] Fetching metrics..." >&2
    
    for i in "${!METRIC_KEYS[@]}"; do
        local key="${METRIC_KEYS[$i]}"
        local query="${PROM_QUERIES[$i]}"
        local response=$(curl -s -G "${PROM_URL}/api/v1/query" --data-urlencode "query=${query}")
        
        # Merge results into one JSON
        if echo "$response" | jq -e '.data.result' >/dev/null 2>&1; then
            full_json=$(echo "$full_json" | jq --arg key "$key" --argjson val "$response" '. + {($key): $val.data.result}')
        else
            full_json=$(echo "$full_json" | jq --arg key "$key" '. + {($key): []}')
        fi
    done
    echo "$full_json"
}

# Function: Transform raw JSON into readable text for the LLM
format_metrics_to_text() {
    local input_json="$1"
    echo "$input_json" | jq -r '
      . as $root | 
      ([.[] | .[]? | {instance: .metric.instance, job: .metric.job}] | unique)[] as $node |
      "Node: " + $node.instance + " (Job: " + $node.job + ")\n" +
      "- CPU Usage: " + ([$root.cpu[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + "%\n" +
      "- Memory Usage: " + ([$root.memory[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + "%\n" +
      "- Storage Usage: " + ([$root.storage[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + "%\n" +
      "- Net RX: " + ([$root.net_rx[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + " bytes/s\n" +
      "- Net TX: " + ([$root.net_tx[]? | select(.metric.instance == $node.instance and .metric.job == $node.job).value[1]] | first // "0" | tonumber | round | tostring) + " bytes/s\n"
    '
}


# ==============================================================================
# [SECTION B] LLM ANALYSIS REQUEST (AI 분석 요청부)
# ==============================================================================

# LLM Configuration
LLM_API_URL="https://api.openai.com/v1/chat/completions"
MODEL="gpt-4o"

# Function: Send formatted report to LLM for expert analysis
request_llm_analysis() {
    local report_text="$1"
    
    # Check if API Key exists
    if [ -z "$OPENAI_API_KEY" ]; then
        echo -e "\n[LLM] Warning: OPENAI_API_KEY not found. Skipping analysis." >&2
        return
    fi

    echo "[LLM] Sending report for analysis..." >&2
    
    # Create Analysis Prompt
    local prompt="아래는 Prometheus에서 수집한 노드별 서버 메트릭 데이터이다. 
SRE 전문가 입장에서 각 노드의 리소스 상태를 점검하고, 리소스 사용량이 80%를 넘거나 비정상적인 지표가 있는 경우를 식별해줘. 
리포트는 한국어로 간결하게 작성해줘.

$report_text"

    # Call LLM API
    local payload=$(jq -n --arg p "$prompt" --arg m "$MODEL" '{model: $m, messages: [{role: "system", content: "You are a senior SRE engineer."}, {role: "user", content: $p}]}')
    
    local response=$(curl -s "$LLM_API_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -d "$payload")

    # Extract analysis from response
    echo "$response" | jq -r '.choices[0].message.content // .error.message'
}


# ==============================================================================
# [MAIN] ORCHESTRATION (스크립트 실행 흐름 제어)
# ==============================================================================

# 1. Prometheus에서 데이터 수집 및 텍스트 리포트 생성
RAW_JSON=$(fetch_raw_metrics)
REPORT_TEXT=$(format_metrics_to_text "$RAW_JSON")

# 2. 결과 출력 (수집된 데이터 확인용)
echo -e "\n================ [METRICS SUMMARY] ================"
echo "$REPORT_TEXT"
echo "===================================================\n"

# # 3. LLM 분석 요청
# ANALYSIS_RESULT=$(request_llm_analysis "$REPORT_TEXT")

# if [ -n "$ANALYSIS_RESULT" ]; then
#     echo "================ [AI SRE ANALYSIS] ================"
#     echo "$ANALYSIS_RESULT"
#     echo "==================================================="
# fi

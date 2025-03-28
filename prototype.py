import requests
import openai

# 여러 Prometheus 서버에서 메트릭 데이터 가져오기
def fetch_metrics(prometheus_urls, query):
    all_metrics = []
    for url in prometheus_urls:
        response = requests.get(f"{url}/api/v1/query", params={'query': query})
        if response.status_code == 200:
            all_metrics.append(response.json())
    return all_metrics

# OpenAI API 또는 로컬 LLM에 메트릭 등 포함해서 프롬프트 넘기기
def summarize_metrics(metrics_data):
    openai.api_key = '$OPENAI_API_KEY'
    prompt = f"Summarize the following metrics data: {metrics_data}"
    response = openai.Completion.create(engine="text-davinci-003", prompt=prompt, max_tokens=150)
    return response.choices[0].text.strip()

# Prometheus URL 목록과 쿼리 설정
prometheus_urls = ["http://prometheus1:9090", "http://prometheus2:9090"]
query = "up"

# 각 Prometheus 서버에서 메트릭 데이터 가져오기
metrics_data = fetch_metrics(prometheus_urls, query)

# 메트릭 데이터 요약
summary = summarize_metrics(metrics_data)
print(summary)


# 크론탭 돌려서 메일 쏴버리자

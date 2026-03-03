# Metrics-Analysis-via-LLM
목적: 내 서버들 너가 모니터링 해줘!@ 


```
# 참고용
# prometheus 쿼리: node-exporter에서 추출한 그대로의 내용을 보여줌. 비정형적이며, 여러 노드 구분이 안됨 => 실제로 활용하기는 힘듦 
curl prometheus-ip:9090/metrics

# promtheus 쿼리 모든 노드의 데이터 쿼리 => 기본적으로 json 출력
curl devnet-prom-kube-prometheu-prometheus.devnet.svc.cluster.local:9090/api/v1/query --data-urlencode 'query={__name__=~".+"}' 
```

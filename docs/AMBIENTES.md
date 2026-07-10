# Ambientes

Este repositório usa a estrutura primária `base/` e `overlays/{desenvolvimento,aceite,producao}`.

- `desenvolvimento`: perfil compatível com OpenShift Local/CRC, recursos leves, rotas e integrações de laboratório.
- `aceite`: perfil de homologação; substitua hosts `.example.invalid`, secrets e endpoints pelos valores do ambiente.
- `producao`: perfil operacional; exige revisão de TLS, storage, OAuth, retenção, backup e sizing antes do uso.

Validação:

```bash
oc kustomize overlays/desenvolvimento >/tmp/grafana-dev.yaml
oc kustomize overlays/aceite >/tmp/grafana-aceite.yaml
oc kustomize overlays/producao >/tmp/grafana-prod.yaml
oc apply --dry-run=client -k overlays/desenvolvimento
```

Secrets obrigatórios:

- `grafana/grafana-oauth`: `client-id`, `client-secret`.
- `grafana/prometheus-ocp-token`: token ServiceAccount para Thanos.
- `grafana/grafana-loki-token`: token ServiceAccount para Loki.
- `grafana/grafana-tempo-token`: token criado pelo `tempo-gitops`.
- `grafana/zabbix-datasource`: `username`, `password`.

Datasources provisionados:

- `prometheus-ocp`: métricas de plataforma/OpenShift.
- `prometheus-apps`: métricas de workloads e span metrics.
- `loki`: logs de aplicação via OpenShift Logging/LokiStack.
- `tempo`: traces e correlações trace → logs/métricas/profiles.
- `pyroscope`: profiles via `pyroscope-gitops`.
- `zabbix`: hosts, items e triggers do Zabbix.

Drilldown:

- Traces Drilldown usa Tempo + TraceQL metrics + `prometheus-apps`.
- Streaming do datasource Tempo fica desabilitado no CRC; o gateway
  multitenant responde 404 para os canais gRPC/HTTP2 usados pelo Grafana Live.
- Logs Drilldown pode ter endpoints 404 no gateway do LokiStack; LogQL e
  correlação por `trace_id` continuam suportados.
- Profiles Drilldown usa o datasource `pyroscope`; ele só mostra flamegraphs
  quando as aplicações enviam profiles com labels compatíveis.
- Detalhes operacionais: `docs/DRILLDOWN.md`.

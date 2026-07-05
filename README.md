# Grafana GitOps

Grafana Operator e instância Grafana declarativos para OpenShift Local. O
overlay integra Prometheus/Thanos, Loki, Tempo e Zabbix e provisiona dashboards
sem armazenar credenciais no Git.

## Correlação de observabilidade

```text
Prometheus --exemplar--> Tempo
Tempo ------trace------> Loki + Prometheus
Loki -------trace_id---> Tempo
```

Os datasources possuem UIDs estáveis e correlações provisionadas:

- exemplares de métricas abrem o trace correspondente no Tempo;
- spans oferecem links para logs e métricas do serviço;
- `trace_id` encontrado no Loki abre o trace;
- Tempo usa Prometheus para métricas RED e Service Graph;
- dashboards oficiais Keycloak de capacidade e troubleshooting são importados.

Metrics Drilldown requer Grafana `11.6+`; no Grafana `12+`, os aplicativos
Drilldown vêm habilitados por padrão. A experiência depende dos backends:
spanmetrics e exemplares são preparados por `opentelemetry-gitops`, enquanto
TraceQL metrics completo depende da versão/capacidade do Tempo instalado.

## Deploy

Pré-requisitos: OpenShift, `oc`, Kustomize, User Workload Monitoring e os
backends desejados. Crie somente a credencial opcional do Zabbix:

```bash
oc create namespace grafana --dry-run=client -o yaml | oc apply -f -
oc -n grafana create secret generic zabbix-datasource \
  --from-literal=username="${ZABBIX_USER}" \
  --from-literal=password="${ZABBIX_PASSWORD}" \
  --dry-run=client -o yaml | oc apply -f -

oc apply -k kustomize/overlays/crc
oc -n grafana get grafana,grafanadatasource,grafanadashboard,route
```

Valide a versão efetivamente instalada:

```bash
oc -n grafana exec deploy/grafana-deployment -- grafana server --version
```

O nome do Deployment pode variar com a versão do Operator; descubra-o com
`oc -n grafana get deploy`.

## Estrutura

```text
kustomize/base/          namespaces e instalação OLM do Operator
kustomize/overlays/crc/  instância, acesso, datasources e dashboards
```

## Segurança

- o token do Thanos fica em Secret e recebe somente leitura;
- TLS interno é ignorado apenas no perfil local; distribua a CA em produção;
- use External Secrets/Sealed Secrets para Zabbix e credenciais administrativas;
- restrinja a Route com autenticação e RBAC apropriados;
- fixe versões do Operator/Grafana após homologação.

## Diagnóstico

```bash
oc kustomize kustomize/overlays/crc >/tmp/grafana.yaml
oc apply --dry-run=server -f /tmp/grafana.yaml
oc -n grafana logs -l app=grafana --tail=100
```

Referências: [Grafana Drilldown](https://grafana.com/docs/grafana/latest/visualizations/simplified-exploration/)
e [Tempo datasource](https://grafana.com/docs/grafana/latest/datasources/tempo/).

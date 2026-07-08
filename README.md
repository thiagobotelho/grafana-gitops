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
- dashboard exemplo oficial do Argo CD é importado do repositório upstream e usa
  as métricas expostas pelo OpenShift GitOps Operator.

Metrics Drilldown requer Grafana `11.6+`; no Grafana `12+`, os aplicativos
Drilldown vêm habilitados por padrão. A experiência depende dos backends:
spanmetrics e exemplares são preparados por `opentelemetry-gitops`, enquanto
TraceQL metrics completo depende da versão/capacidade do Tempo instalado.

## Deploy

Pré-requisitos: OpenShift, `oc`, Kustomize, User Workload Monitoring e os
backends desejados.

Crie o Secret OIDC consumido pelo Grafana a partir do client `grafana` existente
no realm `observability` do Keycloak:

```bash
cp .env.example .env
scripts/bootstrap-grafana-oauth.sh
```

O datasource Zabbix usa um usuário técnico criado pelo repositório
`zabbix-gitops`. Se precisar criar manualmente:

```bash
oc create namespace grafana --dry-run=client -o yaml | oc apply -f -
oc -n grafana create secret generic zabbix-datasource \
  --from-literal=username="${ZABBIX_USER}" \
  --from-literal=password="${ZABBIX_PASSWORD}" \
  --dry-run=client -o yaml | oc apply -f -

oc apply -k kustomize/overlays/crc
oc -n grafana get grafana,grafanadatasource,grafanadashboard,route
```

### Secrets consumidos

| Secret | Namespace | Chaves | Criado por |
|---|---|---|---|
| `grafana-oauth` | `grafana` | `client-id`, `client-secret` | `scripts/bootstrap-grafana-oauth.sh` |
| `prometheus-ocp-token` | `grafana` | `token` | manifest `rules/openshift-monitoring-access.yaml` |
| `grafana-loki-token` | `grafana` | `token` | manifest `rules/loki-access.yaml` |
| `zabbix-datasource` | `grafana` | `username`, `password` | `zabbix-gitops/scripts/bootstrap-zabbix.sh` |

Rotação do OAuth: reexecute `scripts/bootstrap-grafana-oauth.sh` após rotacionar
o client secret no Keycloak e sincronize/reinicie o Grafana se necessário.

Os datasources usam UIDs estáveis: `prometheus-ocp`, `loki`, `tempo` e
`zabbix`.

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

## Dashboards provisionados

| Dashboard | Origem | Datasource | Dependências |
|---|---|---|---|
| OpenShift Local - Overview | JSON local versionado | `prometheus-ocp` | OpenShift Monitoring e kube-state-metrics |
| Argo CD Overview | `argoproj/argo-cd/examples/dashboard.json` | `prometheus-ocp` | ServiceMonitors do OpenShift GitOps |
| Keycloak Capacity Planning | `keycloak/keycloak-grafana-dashboard` | `prometheus-ocp` | ServiceMonitor do Keycloak e métricas de eventos |
| Keycloak Troubleshooting | `keycloak/keycloak-grafana-dashboard` | `prometheus-ocp` | ServiceMonitor do Keycloak e métricas de eventos |

Drilldown preparado:

- Prometheus → Tempo via exemplares `trace_id`;
- Tempo → Loki por `trace_id` e `service.name`;
- Loki → Tempo por campos `trace_id`/`traceId`;
- Argo CD → aplicações/workloads via labels e filtros do dashboard upstream;
- Zabbix → Host group/Host/Item pelo plugin `alexanderzobnin-zabbix-app`.

## Segurança

- o token do Thanos fica em Secret e recebe somente leitura;
- o OAuth usa Keycloak Generic OAuth/OIDC, grupos do realm e `role_attribute_path`;
- cookies seguros, CSP e HSTS ficam habilitados no overlay CRC para aproximar o
  comportamento local de um ambiente real;
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
Para autenticação, veja a documentação oficial de
[Keycloak OAuth2 no Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/keycloak/)
e [Generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/).

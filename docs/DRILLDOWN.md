# Grafana Drilldown, traces e profiles

Este documento registra como o Grafana Drilldown fica habilitado nesta stack e
quais limites existem no CRC/OpenShift Local.

## Estado atual

O Grafana é provisionado com datasources estáveis:

- `prometheus-ocp`: métricas nativas do OpenShift/Thanos.
- `prometheus-apps`: métricas de aplicações e span metrics.
- `loki`: logs de aplicação via LokiStack/OpenShift Logging.
- `tempo`: traces OTLP via TempoMonolithic.
- `zabbix`: dados operacionais via plugin Zabbix.

O datasource `tempo` possui:

- `nodeGraph` habilitado;
- `serviceMap` apontando para `prometheus-apps`;
- streaming de busca e métricas desabilitado no perfil CRC;
- `tracesToLogsV2` para abrir logs do span no Loki;
- `tracesToMetrics` para abrir PromQL contextualizado a partir do span.

Referências oficiais:

- [Traces Drilldown](https://grafana.com/docs/grafana/latest/visualizations/simplified-exploration/traces/)
- [Conceitos de traces e spans](https://grafana.com/docs/grafana/next/visualizations/simplified-exploration/traces/concepts/)
- [Provisionamento do datasource Tempo](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/provision/)
- [Troubleshooting do datasource Tempo](https://grafana.com/docs/grafana/latest/datasources/tempo/troubleshooting/)
- [Profiles Drilldown](https://grafana.com/docs/grafana/latest/visualizations/simplified-exploration/profiles/access/)
- [Trace to profiles](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/configure-trace-to-profiles/)

## Tempo streaming no CRC

O Grafana Tempo datasource suporta streaming para busca e métricas TraceQL, mas
em ambientes self-managed isso exige Tempo compatível, `stream_over_http_enabled`
e um caminho de rede/proxy com suporte a gRPC/HTTP2. No CRC validado, o gateway
multitenant do Tempo Operator responde `404 text/plain` para os canais live/gRPC
do Grafana, por exemplo:

```text
rpc error: code = Unimplemented desc = unexpected HTTP status code received from server: 404
```

Por isso `streamingEnabled.search` e `streamingEnabled.metrics` ficam
desabilitados no `grafana-gitops`. A busca HTTP normal continua funcionando, e
foi validada com retorno `200` no endpoint:

```text
/api/traces/v1/dev/tempo/api/search
```

Se o ambiente evoluir para um endpoint Tempo/query-frontend que suporte
gRPC/HTTP2 ponta a ponta, o streaming pode ser reavaliado.

## Como funciona o Traces Drilldown

O Traces Drilldown explora métricas RED geradas a partir dos traces:

- Rate: volume de requisições/spans.
- Errors: spans com erro.
- Duration: latência/duração.

Um trace representa o caminho de uma requisição. Ele é composto por spans. Cada
span tem início, duração, nome/operação, atributos e normalmente um span pai. O
primeiro span é o root span.

No Drilldown, a navegação útil costuma ser:

```text
Root spans -> serviço -> operação -> trace -> span -> logs/métricas
```

Campos importantes para o Drilldown:

- `resource.service.name`: agrupa spans por serviço.
- `status`: separa sucesso/erro.
- `duration`: permite filtros de latência.
- `kind = server`: ajuda a montar a visão de relação entre serviços.
- `trace_id`/`traceId`: permite correlação logs ↔ traces.

## Service structure

A tela Service structure aparece no fluxo de análise de traces e usa consultas
TraceQL para relacionar serviços a partir de spans raiz e spans de servidor.
Ela depende de dados bem instrumentados:

- spans com `resource.service.name`;
- spans com hierarquia pai/filho;
- spans de servidor quando houver comunicação entre serviços;
- TraceQL metrics funcionando no Tempo;
- métricas de grafo, quando se espera visualizar Service Graph completo.

No CRC atual, o `opentelemetry-gitops` gera métricas RED via `span_metrics`.
Isso alimenta dashboards e links `tracesToMetrics`. O Service Graph completo
depende de métricas `traces_service_graph_*`, geradas por Tempo
metrics-generator, Grafana Alloy ou outro pipeline compatível. O Red Hat
OpenTelemetry Collector validado no CRC expõe `span_metrics`, mas não expõe
connector `servicegraph`.

## Erros analisados no Trace Drilldown

Foram observados erros 400 no Grafana/Tempo com queries geradas pelo Drilldown,
por exemplo:

```text
unknown identifier: undefined
syntax error: unexpected }
```

As queries problemáticas continham variáveis vazias, como:

```text
{nestedSetParent<0 && true && undefined != nil} | rate() by(undefined)
{nestedSetParent<0 && true && duration > }
```

Isso indica que o backend Tempo não estava indisponível; o Tempo respondeu 200
para queries TraceQL válidas no mesmo período. O problema é a montagem de query
com estado incompleto do Drilldown, geralmente por URL/filtros vazios ou uma
incompatibilidade fina entre versão do Grafana/app e estado salvo da tela.

Workaround operacional:

1. Abra Drilldown > Traces a partir do menu, não de um link antigo.
2. Selecione datasource `Tempo`.
3. Comece com `Root spans`, métrica `Rate` e agrupamento
   `resource.service.name`.
4. Para Duration/Service structure, preencha limites de latência antes de usar
   filtros avançados.
5. Se voltar a aparecer `undefined`, limpe os parâmetros da URL ou abra uma nova
   janela anônima para descartar estado local da UI.

Se persistir mesmo com estado limpo, homologue uma atualização do Grafana/app
Drilldown ou fixe uma combinação conhecida como estável para o ambiente.

## Logs Drilldown

O Loki datasource aponta para o gateway suportado do LokiStack/OpenShift
Logging. Consultas LogQL e labels funcionam nesse caminho, mas alguns endpoints
usados pelo Logs Drilldown, como `drilldown-limits`, `detected_labels` e
`detected_fields`, podem retornar 404 nesse gateway.

Isso não quebra a correlação básica:

```text
Loki log com trace_id -> Tempo trace
Tempo span -> Loki logs do serviço/trace
```

Para Logs Drilldown completo, use uma versão/gateway do Loki que exponha os
endpoints esperados pelo Grafana ou um Loki self-managed compatível.

## Profiles Drilldown

Profiles Drilldown é a experiência de exploração de profiling no Grafana. Ela
serve para responder perguntas como:

- qual função consome mais CPU;
- onde há alocação excessiva de memória;
- quais serviços pioraram após um deploy;
- qual span/trace tem flamegraph associado.

Pré-requisitos oficiais para Grafana OSS/Enterprise:

- Grafana 11.5 ou superior;
- datasource Pyroscope configurado;
- aplicações enviando profiles para Pyroscope;
- para conectar trace e profile no span, instrumentação que adicione o vínculo
  de profiling, como `pyroscope.profile.id`.

Grafana 12 ou superior já inclui os apps de Drilldown por padrão. Nesta stack,
o backend Pyroscope é provisionado pelo repositório `pyroscope-gitops` e o
datasource `pyroscope` é criado pelo `grafana-gitops`. Portanto, Profiles
Drilldown fica preparado na UI, mas só exibirá flamegraphs quando aplicações ou
Grafana Alloy enviarem profiles com labels compatíveis.

No Keycloak, a stack usa o Pyroscope Java Agent com async-profiler in-process e
saída JFR. O perfil padrão usa `wall` para capturar latência percebida e também
habilita amostras de alocação (`alloc=512k`) e contenção de locks (`lock=10ms`).
A correlação é por serviço/namespace. Isso alimenta o Profiles Drilldown com
flamegraphs reais sem exigir SCC privilegiada. O vínculo exato de um span
individual com um profile (`pyroscope.profile.id`) exige a ponte de span
profiles do Pyroscope/OpenTelemetry para Java; como o Keycloak já usa tracing
nativo, essa evolução deve ser homologada separadamente para evitar duplicidade
de spans.

## Como habilitar dados reais no Profiles Drilldown

Passos:

1. Sincronizar `pyroscope-gitops`.
2. Confirmar o datasource Grafana com UID estável `pyroscope`.
3. Instrumentar aplicações com profiling ou habilitar Grafana Alloy/eBPF.
4. Garantir labels compatíveis entre traces e profiles. No padrão atual:
   `service.name -> service_name`, `service.namespace -> service_namespace` e
   `k8s.namespace.name -> namespace`.
5. Validar `tracesToProfiles` no datasource Tempo.

Bloco provisionado no datasource Tempo:

```yaml
tracesToProfiles:
  datasourceUid: pyroscope
  tags:
    - key: service.name
      value: service_name
    - key: service.namespace
      value: service_namespace
    - key: k8s.namespace.name
      value: namespace
  profileTypeId: process_cpu:cpu:nanoseconds:cpu:nanoseconds
```

No provisionamento YAML oficial do Tempo datasource, o exemplo documentado usa
`profileTypeId` singular. Por isso o link trace→profile mantém CPU como tipo
padrão. Profile types adicionais, como wall, alloc e lock, aparecem no Profiles
Drilldown quando forem ingeridos pelo Pyroscope; se quiser trocar o tipo padrão
do link, altere `profileTypeId` no datasource Tempo e reinicie/sincronize o
Grafana.

Se não houver profiles para o período/serviço selecionado, o Drilldown abre sem
resultado útil. Isso é esperado até instrumentar workloads.

## Validação

Plugins instalados:

```bash
oc -n grafana exec deploy/grafana-deployment -- grafana cli plugins ls | \
  grep -Ei 'drill|trace|profile|pyroscope|loki|zabbix'
```

Logs do Grafana:

```bash
oc -n grafana logs deploy/grafana-deployment --tail=300 | \
  grep -Ei 'tempo|trace|drill|profile|pyroscope|undefined|error|warn'
```

Logs do Tempo:

```bash
oc -n tempo logs statefulset/tempo-tempo-monolithic -c tempo --tail=300 | \
  grep -Ei 'traceql|metrics|query|error|warn'
```

Pipeline de traces/métricas:

```bash
oc -n tempo get tempomonolithic,pods,svc,pvc
oc -n observability get opentelemetrycollector,pods,svc,servicemonitor
oc -n observability-apps get monitoringstack,pods,svc,pvc
```

## Melhorias futuras

- Adicionar Grafana Alloy opcional para service graph e profiling.
- Evoluir TempoMonolithic para TempoStack quando houver object storage e
  necessidade de HA/retenção formal.
- Homologar uma matriz de versões Grafana/app Drilldown/Tempo antes de produção.
- Adicionar dashboards que mostrem a jornada
  `Namespace -> Workload -> Pod -> Trace -> Logs -> Profile`.

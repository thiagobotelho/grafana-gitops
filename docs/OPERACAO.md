# Operação do Grafana

Sincronize o overlay do ambiente após preparar os Secrets de OAuth e datasources. Confira as condições dos CRs:

```bash
oc -n grafana get grafana,grafanadatasource,grafanafolder,grafanadashboard
oc -n grafana get pods,pvc
```

Para endpoints com TLS interno, configure a CA pública e mantenha a verificação de certificados. valuesFrom deve apontar para chaves existentes; quando o datasource exigir substituição, mantenha também o placeholder correspondente em secureJsonData.

Revise as condições de sincronização da pasta e do dashboard. Depois abra os painéis, selecione uma janela temporal com amostras e confirme variáveis e consultas. Provisionamento de CR e disponibilidade de dados são verificações distintas. Consulte [DRILLDOWN.md](DRILLDOWN.md) para navegação entre métricas, logs, traces e profiles.

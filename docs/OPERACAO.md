# Operação do Grafana

Sincronize o overlay do ambiente após preparar os Secrets de OAuth e datasources. Confira as condições dos CRs:

```bash
oc -n grafana get grafana,grafanadatasource,grafanafolder,grafanadashboard
oc -n grafana get pods,pvc
```

Para endpoints com TLS interno, configure a CA pública e mantenha a verificação de certificados. valuesFrom deve apontar para chaves existentes; quando o datasource exigir substituição, mantenha também o placeholder correspondente em secureJsonData.

Revise as condições de sincronização da pasta e do dashboard. Depois abra os painéis, selecione uma janela temporal com amostras e confirme variáveis e consultas. Provisionamento de CR e disponibilidade de dados são verificações distintas. Consulte [DRILLDOWN.md](DRILLDOWN.md) para navegação entre métricas, logs, traces e profiles.

## Confiança TLS do provedor OAuth

Aceite e produção validam certificado e hostname do Keycloak. Certificado emitido por uma CA pública usa o trust store da imagem. Para CA privada, obtenha a cadeia pública PEM do administrador da PKI, crie o ConfigMap grafana-oidc-ca no namespace grafana e inclua o patch de [CA OAuth](../examples/ca-oauth/patch.yaml) no overlay. Não use certificado ou senha de outro ambiente.

Antes de sincronizar, renderize o overlay e confirme que o volume e tls_client_ca apontam ao bundle correto. Valide login com a cadeia válida; em teste isolado, CA desconhecida e hostname divergente devem falhar. Confirme também login negativo de grupo sem papel. Não contorne falhas ativando tls_skip_verify_insecure.

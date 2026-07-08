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

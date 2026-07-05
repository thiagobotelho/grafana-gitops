# grafana-gitops

Repositório GitOps responsável pela instalação e gerenciamento do **Grafana Operator** e das instâncias do Grafana em ambiente OpenShift (CRC / OCP), utilizando abordagem declarativa baseada em Kustomize.

---

## 🎯 Objetivo

Provisionar e gerenciar de forma versionada e automatizada:

- Grafana Operator (via OLM)
- Instâncias Grafana
- Dashboards
- Datasources
- Alert Rules
- Policies e demais recursos suportados pelo operator

Todo o ciclo de vida é controlado via Git, garantindo rastreabilidade, padronização e reprodutibilidade.

---

## 🏗 Estrutura do Repositório

```bash
grafana-gitops/
└── kustomize/
    ├── base/
    │   ├── namespace-operator.yaml
    │   ├── namespace-grafana.yaml
    │   ├── operatorgroup.yaml
    │   ├── subscription.yaml
    │   └── kustomization.yaml
    └── overlays/
        └── crc/
            ├── kustomization.yaml
            └── grafana-instance.yaml
```

---

### 📌 Base

Contém os recursos fundamentais para instalação do operador:

- Namespace do operador
- Namespace da aplicação Grafana
- OperatorGroup
- Subscription (OLM)

### 📌 Overlays

Contém customizações por ambiente:

- Instância do Grafana
- Configurações específicas
- Recursos adicionais (datasources, dashboards etc.)

---

## 🚀 Deploy Manual (CRC / OpenShift)

O overlay cria uma ServiceAccount somente leitura para o Thanos Querier do
OpenShift e provisiona datasources Prometheus, Loki, Tempo e Zabbix. Crie
somente as credenciais do Zabbix fora do Git:

```bash
oc -n grafana create secret generic zabbix-datasource \
  --from-literal=username="$ZABBIX_USER" \
  --from-literal=password="$ZABBIX_PASSWORD"

oc apply -k kustomize/overlays/crc
```

As credenciais administrativas e tokens não são armazenados nos manifests.
Consulte o Secret gerado pelo Grafana Operator ou integre um gerenciador de
segredos para ambientes compartilhados.

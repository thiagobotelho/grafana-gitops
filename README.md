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

grafana-gitops/
└── kustomize/
├── base/
│ ├── namespace-operator.yaml
│ ├── namespace-grafana.yaml
│ ├── operatorgroup.yaml
│ ├── subscription.yaml
│ └── kustomization.yaml
└── overlays/
└── crc/
├── kustomization.yaml
└── grafana-instance.yaml

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

Aplicar via Kustomize:

```bash
oc apply -k kustomize/overlays/crc

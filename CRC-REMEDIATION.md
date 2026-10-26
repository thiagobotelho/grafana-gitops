# Correções CRC — 26/10/2026

Mudanças preparadas a partir dos SHAs reais auditados; sem senhas, tokens ou kubeconfig no Git. A CA eventualmente incluída é somente pública e deve acompanhar recriação/rotação do CRC. A branch de correção permite validar antes da integração em main.

Credenciais do realm são seeds iniciais, não um mecanismo de recuperação da senha atual. Não sobrescrever contas existentes ou reimportar credenciais sem intenção explícita. O realm contínuo não contém credentials, preservando as senhas atuais. bootstrap/initial-passwords.json, quando presente, contém somente placeholders e deve ser importado manualmente apenas no primeiro provisionamento ou recuperação explicitamente pretendida; não é recurso do Kustomize. A configuração SAML do client Zabbix usa um único atributo groups com múltiplos valores e remove apenas role_list dos scopes default; o scope global não é alterado.

O overlay crc-validation do repositório argocd-gitops direciona somente os componentes em correção para a branch de validação. O overlay desenvolvimento normal permanece em main. Voltar a esse overlay após integrar as correções aprovadas.

O overlay desenvolvimento de loki-gitops usa imagens locais compiladas dos commits oficiais MinIO/MC. Cria ImageStreams e BuildConfigs sem triggers automáticos. Em um CRC novo, aplicar os recursos de build, executar oc start-build mc-crc e minio-crc em openshift-logging, aguardar Complete e então reconciliar os workloads. O registry interno não constitui backup das imagens. Fontes antigas compiladas não equivalem a versão atualmente suportada ou sem vulnerabilidades.

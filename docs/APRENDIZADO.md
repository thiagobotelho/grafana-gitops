# OAuth, datasources e confiança


OAuth autentica o usuário e os grupos são mapeados para papéis. Datasources usam credenciais próprias provisionadas por Secret. CA do IdP e CA do datasource são relações de confiança diferentes. Revise o exemplo examples/ca-oauth/patch.yaml antes de integrar uma CA privada. Valide Viewer sem privilégios administrativos.

## Validar visualização

Confira a condição DashboardSynchronized no CR, a saúde de cada datasource e uma consulta conhecida no período selecionado. Um painel vazio pode significar ausência de séries, janela inadequada ou falha de ingestão. O dashboard de segurança mantém sem dados distinto de zero e separa Loki de aplicação, Loki-Audit e Prometheus Apps.

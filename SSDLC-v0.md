# Análise SSDLC do projeto

Comparação entre as fases do **SSDLC** (Secure Software Development Life Cycle) e o que o projeto já faz hoje.

**Escopo analisado**

| Repositório | Conteúdo |
|---|---|
| `api-go-cicd-aws-ecs` | API Go (Gin + GORM), Dockerfile, docker-compose e workflows do GitHub Actions (`go.yml`, `Docker.yml`, `EC2.yml`, `ECS.yml`, `EKS.yml`, `LoadTest.yml`) |
| `infra-api-go-cicd-aws-ecs` | Terraform da infra ECS (VPC, ALB, ECS Fargate, RDS, IAM) |
| `infra-api-go-cicd-aws-eks` | Terraform da infra EKS (VPC, EKS, RDS, Service) e o Deployment `go.yaml` |

**Legenda:** ✅ já faz · ⚠️ faz em parte · ❌ não faz · 🔴 prioridade alta · 🟡 média · 🟢 baixa

---

## Tabela: fase do SSDLC × o que o repo já faz × o que falta

| # | Fase do SSDLC | O que o repo já faz | O que falta |
|---|---|---|---|
| 1 | **Requisitos de segurança** | ⚠️ Validação de formato dos campos do aluno (`validate:"nonzero"`, `len=11`, regex numérica para CPF e RG). | ❌ 🔴 Nenhum requisito de autenticação ou autorização: qualquer pessoa lista, edita e apaga alunos. <br>❌ 🔴 A API guarda e devolve **CPF e RG** (dados pessoais, LGPD) sem definir quem pode ver, por quanto tempo guardar ou como mascarar. <br>❌ 🟡 Sem requisitos não funcionais de segurança escritos (rate limit, tamanho máximo de payload, logs de auditoria). |
| 2 | **Design e modelagem de ameaças** | ⚠️ Arquitetura com load balancer na frente; RDS do EKS com `publicly_accessible = false` em subnet de banco. | ❌ 🟡 Sem modelagem de ameaças (STRIDE ou similar) nem diagrama de fluxo de dados com fronteiras de confiança. <br>❌ 🔴 RDS do ECS com `publicly_accessible = true` **e** security group liberando a porta 5432 para `0.0.0.0/0`: o banco fica aberto para a internet. <br>❌ 🟡 SSH (22) liberado para `0.0.0.0/0` nos nós do EKS. <br>❌ 🟡 Tráfego sem TLS: API em HTTP puro na porta 8000/80; banco com `sslmode=disable` e `rds.force_ssl = 0`. |
| 3 | **Codificação segura** | ⚠️ Validação de entrada no `POST` e no `PATCH`; as páginas HTML usam `html/template` (escapa XSS automaticamente); a busca por CPF usa struct no `Where` (parametrizado). | ❌ 🔴 **SQL injection** em `BuscarAlunoPorID`, `DeletarAluno` e `EditarAluno` (detalhe abaixo). <br>❌ 🟡 `log.Panic` na conexão com o banco derruba a API inteira, sem retry. <br>❌ 🟢 Respostas de erro devolvem `err.Error()` cru para o cliente. <br>❌ 🟢 `gin.Default()` em modo debug em produção (não define `GIN_MODE=release`). |
| 4 | **Gestão de segredos** | ✅ Credenciais da AWS, do Docker Hub, do SSH e do banco ficam nos **secrets do GitHub Actions**. <br>✅ No EKS, as variáveis do banco chegam aos pods por **Secrets do Kubernetes** (`secretKeyRef`). | ❌ 🔴 Senha do RDS (`rootroot`) **escrita no código** nos dois repositórios de infra, e no ECS também na task definition (`ECS.tf`). <br>❌ 🔴 A pasta **`postgres-data/` está versionada** (1.260 arquivos do banco local dentro do git): qualquer dado que já esteve no banco local está no histórico. <br>❌ 🟡 Senhas fixas no `Dockerfile` (`ENV PASSWORD=root`) e no `docker-compose.yml` (banco e pgAdmin). <br>❌ 🟡 Sem varredura de segredos (gitleaks ou o secret scanning do GitHub) e sem `.gitignore` no repositório da API. <br>❌ 🟢 Sem cofre de segredos (AWS Secrets Manager / SSM Parameter Store). |
| 5 | **Dependências (SCA)** | ⚠️ `go.sum` versionado (garante integridade dos módulos baixados). | ❌ 🔴 Dependências de 2021/2022 sem atualização: `gin v1.7.7` (versões anteriores à 1.9.1 têm vulnerabilidades públicas), `gorm v1.22.4`, `golang.org/x/crypto` de 2021. `go.mod` declara `go 1.15`. <br>❌ 🔴 Sem análise de vulnerabilidades no CI (`govulncheck`, Trivy ou OSV-Scanner). <br>❌ 🟡 Sem **Dependabot** (nem para módulos Go, nem para as GitHub Actions). |
| 6 | **Build e imagem de contêiner** | ✅ Build automatizado no CI, e só depois dos testes passarem (`needs: test`). <br>✅ Imagem versionada por execução (`go_ci3:<run_number>`), o que permite rollback. | ❌ 🟡 Imagem base `ubuntu:latest` (não fixa versão e é grande; o ideal é `distroless` ou `alpine` com versão fixa). <br>❌ 🟡 Contêiner roda como **root** (sem `USER` no Dockerfile e sem `securityContext` no `go.yaml`). <br>❌ 🔴 Sem varredura da imagem (Trivy, Grype, Docker Scout) antes do push. <br>❌ 🟢 Sem SBOM e sem assinatura da imagem (cosign). |
| 7 | **Testes de segurança** | ✅ Testes automatizados com banco real no CI (`main_test.go` + docker-compose), em matriz de versões e sistemas. <br>✅ Teste de carga com Locust no `LoadTest.yml`. <br>✅ Smoke test pós-deploy no ECS (`wget /bruno`) e `rollout status` no EKS. | ❌ 🔴 Sem **SAST** (`gosec`, Semgrep ou CodeQL), que pegaria o SQL injection. <br>❌ 🟡 Sem **DAST** (OWASP ZAP baseline contra o ambiente de homologação). <br>❌ 🟡 Sem testes de casos de abuso (ID não numérico, payload gigante, CPF de outro aluno). <br>❌ 🟢 Testes rodam em Go 1.17/1.18, versões sem suporte. |
| 8 | **Infraestrutura como código (IaC)** | ✅ Infra 100% em Terraform, com módulos versionados (`~> 21.0`, `~> 6.0`). <br>✅ State remoto no S3 com trava (`use_lockfile = true`) e uma key por projeto. <br>✅ Ambientes separados (`env/Homolog`). | ❌ 🔴 Sem varredura de IaC (Trivy config, Checkov ou tfsec), que apontaria banco público, `0.0.0.0/0` e senha no código. <br>❌ 🟡 `apply -auto-approve` sem `plan` revisado por alguém. <br>❌ 🟡 O state guarda a senha do RDS em texto puro; o bucket não declara `encrypt = true` nem bloqueio de acesso público no código. <br>❌ 🟢 Endpoint do EKS público para a internet inteira (`endpoint_public_access = true` sem restringir IPs). |
| 9 | **Pipeline e cadeia de suprimentos (CI/CD)** | ✅ Workflows reutilizáveis com `secrets: inherit`. <br>✅ Testes antes do build e build antes do deploy (`needs`). | ❌ 🔴 Credenciais da AWS de **longa duração** (access key do usuário IAM) em vez de **OIDC** com role temporária. <br>❌ 🔴 `easingthemes/ssh-deploy@main`: action apontando para uma branch que pode mudar a qualquer momento. As outras actions usam tag, não SHA fixo. <br>❌ 🟡 Sem `permissions:` mínimas declaradas nos workflows (o `GITHUB_TOKEN` usa o padrão do repositório). <br>❌ 🟡 Actions desatualizadas (`checkout@v3`, `setup-go@v3`, `build-push-action@v3`, `setup-buildx-action@v2`). |
| 10 | **Deploy e release** | ✅ Deploy automatizado no EKS e no ECS. <br>✅ **Rollback automático** no ECS (`task-definition.json.old`). <br>✅ RollingUpdate e `livenessProbe` no Kubernetes. <br>✅ Load test só na branch `Homolog`. | ❌ 🔴 O `Deploy_EKS` roda em **push de qualquer branch**: qualquer push cria ou altera infra paga, sem aprovação. <br>❌ 🟡 Sem **GitHub Environments** com aprovação manual e regras de proteção. <br>❌ 🟡 Sem proteção de branch exigindo PR, revisão e checks verdes (não dá para confirmar pelo código; conferir em Settings → Branches). <br>❌ 🟢 Sem `resources` (limits/requests) no `go.yaml`. |
| 11 | **Operação, monitoramento e resposta a incidentes** | ⚠️ Logs padrão do Gin no stdout; `livenessProbe` reinicia pods travados; healthcheck do banco no docker-compose. | ❌ 🟡 Sem logs centralizados nem retenção definida (CloudWatch Logs / Container Insights). <br>❌ 🟡 Sem alertas (erro 5xx, pods em CrashLoop, custo). <br>❌ 🟡 Sem trilha de auditoria (CloudTrail) nem logs de acesso do load balancer. <br>❌ 🟢 Sem plano de resposta a incidentes (`SECURITY.md`, quem acionar, como rotacionar segredos). |
| 12 | **Manutenção e descarte** | ✅ `terraform destroy` garantido no load test (`if: always()`). <br>✅ Infra do EKS destruída e verificada ao fim do estudo. | ❌ 🟡 Sem rotina de atualização (Dependabot / Renovate) nem revisão periódica de acessos. <br>❌ 🟡 Usuário IAM do terminal com access entry de admin criada manualmente; sem revisão de quem tem acesso. <br>❌ 🟢 Repositório ainda usa o módulo `github.com/guilhermeonrails/api-go-gin` (nome do projeto original). |

---

## Achados críticos em detalhe

### 1. SQL injection pelo `id` da URL

Em `controllers/controller.go`, o `id` vem da URL como **string** e vai direto para o GORM:

```go
id := c.Params.ByName("id")
database.DB.First(&aluno, id)    // BuscarAlunoPorID e EditarAluno
database.DB.Delete(&aluno, id)   // DeletarAluno
```

No GORM v1.22.4 (`statement.go`, `BuildCondition`), quando esse valor **não é um número**, ele é tratado como um **trecho de SQL** e colado no `WHERE`. Em `DELETE /alunos/<id>`, um valor como uma condição sempre verdadeira apaga **todos** os alunos.

**Correção:** converter para número e recusar o resto.

```go
id, err := strconv.Atoi(c.Param("id"))
if err != nil {
    c.JSON(http.StatusBadRequest, gin.H{"erro": "id inválido"})
    return
}
database.DB.First(&aluno, id)
```

### 2. Banco de dados do ECS exposto para a internet

No `infra-api-go-cicd-aws-ecs`, o RDS tem `publicly_accessible = true`, o security group libera a porta 5432 para `0.0.0.0/0` e a senha (`rootroot`) está no código. Se o repositório for público, a combinação é: endereço acessível + porta aberta + senha publicada.

**Correção:** `publicly_accessible = false`, liberar a 5432 só para o security group das tarefas (`source_security_group_id`) e tirar a senha do código (variável sensível alimentada por secret, ou `manage_master_user_password = true` para a AWS guardar no Secrets Manager).

### 3. Pasta `postgres-data/` versionada

Os arquivos do banco local estão no git. Remover só do próximo commit não apaga do histórico.

**Correção:** `git rm -r --cached postgres-data`, criar `.gitignore` com `postgres-data/` e, se houver dado real, limpar o histórico (`git filter-repo`).

### 4. API sem autenticação expondo CPF e RG

Todas as rotas são abertas, inclusive `DELETE`, `PATCH` e a listagem completa com CPF e RG.

**Correção:** autenticação (JWT ou API key) nas rotas `/alunos`, autorização por perfil para apagar e editar, e não devolver CPF e RG completos na listagem.

### 5. Deploy em toda branch, com chave da AWS de longa duração

Qualquer push em qualquer branch roda `terraform apply` com uma access key permanente.

**Correção:** OIDC (`role-to-assume` no `configure-aws-credentials`, com `permissions: id-token: write`), deploy só na branch principal e um GitHub Environment com aprovação.

---

## Plano sugerido, por ordem

| Ordem | Ação | Fases cobertas | Esforço |
|---|---|---|---|
| 1 | Corrigir o SQL injection (`strconv.Atoi`) | 3 | Baixo |
| 2 | Tirar `postgres-data/` do git e criar `.gitignore` | 4 | Baixo |
| 3 | Fechar o RDS do ECS (`publicly_accessible = false`, SG restrito) e tirar as senhas do código | 2, 4, 8 | Baixo |
| 4 | Restringir o `Deploy_EKS` à branch principal + Environment com aprovação | 10 | Baixo |
| 5 | Adicionar ao `go.yml` um job de segurança: `gosec`, `govulncheck`, `gitleaks` e Trivy (imagem + Terraform) | 4, 5, 6, 7, 8 | Médio |
| 6 | Ativar Dependabot para `gomod` e `github-actions` e atualizar Gin, GORM e Go | 5, 9, 12 | Médio |
| 7 | Trocar as access keys por OIDC e fixar actions por SHA | 9 | Médio |
| 8 | Imagem `distroless` com usuário não root + `securityContext` e `resources` no `go.yaml` | 6, 10 | Médio |
| 9 | Autenticação na API e mascaramento de CPF e RG | 1, 3 | Alto |
| 10 | Logs centralizados, alertas, CloudTrail e `SECURITY.md` | 11 | Médio |

---

## Limitações desta análise

- Feita a partir do código dos três repositórios. Configurações que só existem no GitHub (visibilidade do repositório, proteção de branch, secret scanning, Environments) e na AWS (políticas do usuário IAM, configuração do bucket S3) não foram conferidas.
- A varredura automática de dependências (`govulncheck`) não foi executada. O status das bibliotecas acima vem das versões declaradas no `go.mod`; rodar `govulncheck ./...` dá a lista exata de vulnerabilidades e mostra quais são realmente alcançadas pelo código.

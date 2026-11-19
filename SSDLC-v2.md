# Análise SSDLC do projeto

Comparação entre as fases do **SSDLC** (Secure Software Development Life Cycle) e o que o projeto já faz hoje.

**Versões deste documento:** `SSDLC-v0.md` (levantamento original) · `SSDLC-v1.md` (SQL injection, `GIN_MODE` e Dependabot) · **`SSDLC-v2.md`** (correção dos itens 🔴 de "O que falta"). As mudanças da v2 estão explicadas em `CORRECAO-SSDLC-v2.md`.

**Escopo analisado**

| Repositório | Conteúdo |
|---|---|
| `api-go-cicd-aws-ecs` | API Go (Gin + GORM), Dockerfile, docker-compose e workflows do GitHub Actions (`go.yml`, `Docker.yml`, `EC2.yml`, `ECS.yml`, `EKS.yml`, `LoadTest.yml`) |
| `infra-api-go-cicd-aws-ecs` | Terraform da infra ECS (VPC, ALB, ECS Fargate, RDS, IAM, Secrets Manager) e o bootstrap do OIDC do GitHub |
| `infra-api-go-cicd-aws-eks` | Terraform da infra EKS (VPC, EKS, RDS, Service, Secrets Manager) e o Deployment `go.yaml` |

**Legenda:** ✅ já faz · ⚠️ faz em parte · ❌ não faz · 🔴 prioridade alta · 🟡 média · 🟢 baixa

---

## Tabela: fase do SSDLC × o que o repo já faz × o que falta

| # | Fase do SSDLC | O que o repo já faz | O que falta |
|---|---|---|---|
| 1 | **Requisitos de segurança** | ⚠️ Validação de formato dos campos do aluno (`validate:"nonzero"`, `len=11`, regex numérica para CPF e RG). <br>✅ **Autenticação por chave de API** (`X-API-Key`) nas rotas de `/alunos`, com dois perfis: **leitura** consulta; **admin** consulta, cria, edita e apaga. Sem chave ou com chave errada: `401`; perfil insuficiente: `403`; chave não configurada: recusa tudo. <br>✅ **Política de CPF e RG** escrita em `REQUISITOS-SEGURANCA.md`: só o admin vê completo; o perfil leitura recebe `*********01`; a exclusão apaga o registro de verdade (sem *soft delete*). | ❌ 🟡 Sem requisitos não funcionais de segurança escritos (rate limit, tamanho máximo de payload, logs de auditoria). <br>❌ 🟢 A página `/index` continua pública e mostra os nomes dos alunos (sem CPF e RG). <br>❌ 🟢 Sem rotação periódica das chaves de API. |
| 2 | **Design e modelagem de ameaças** | ⚠️ Arquitetura com load balancer na frente; RDS do EKS com `publicly_accessible = false` em subnet de banco. <br>✅ **RDS do ECS fechado**: `publicly_accessible = false`, porta 5432 liberada só para o security group das tarefas e subnets de banco sem rota para a internet. <br>✅ Porta 5432 do RDS do EKS restrita ao CIDR da VPC (antes `0.0.0.0/0`). | ❌ 🟡 Sem modelagem de ameaças (STRIDE ou similar) nem diagrama de fluxo de dados com fronteiras de confiança. <br>❌ 🟡 SSH (22) liberado para `0.0.0.0/0` nos nós do EKS. <br>❌ 🟡 Tráfego sem TLS: API em HTTP puro na porta 8000/80; banco com `sslmode=disable` e `rds.force_ssl = 0`. |
| 3 | **Codificação segura** | ⚠️ Validação de entrada no `POST` e no `PATCH`; as páginas HTML usam `html/template` (escapa XSS automaticamente); a busca por CPF usa struct no `Where` (parametrizado). <br>✅ `id` da URL convertido para inteiro positivo antes de chegar ao GORM (`idDaURL`); valor inválido responde `400`. Fecha a SQL injection em `BuscarAlunoPorID`, `DeletarAluno` e `EditarAluno`. <br>✅ `EditarAluno` responde `404` quando o aluno não existe (antes criava um registro novo). <br>✅ `GIN_MODE=release` definido no `Dockerfile`. <br>✅ Erros de `AutoMigrate` e de `r.Run()` tratados (apontados pelo gosec). | ❌ 🟡 `log.Panic` na conexão com o banco derruba a API inteira, sem retry. <br>❌ 🟢 Respostas de erro devolvem `err.Error()` cru para o cliente. |
| 4 | **Gestão de segredos** | ✅ Credenciais do Docker Hub, do SSH e do banco (fluxos EC2/ECS antigos) ficam nos **secrets do GitHub Actions**. <br>✅ No EKS, as variáveis do banco chegam aos pods por **Secrets do Kubernetes** (`secretKeyRef`). <br>✅ **Senha do RDS fora do código** nos dois repositórios de infra: gerada pelo Terraform (`random_password`) e guardada no **AWS Secrets Manager**. O ECS lê pelo bloco `secrets` da task definition; o deploy do EKS lê do Secrets Manager e cria os Secrets do Kubernetes. <br>✅ Chaves de API geradas e guardadas da mesma forma. <br>✅ `postgres-data/` **removido do índice do git** e `.gitignore` criado no repositório da API. | ❌ 🔴 Os arquivos de `postgres-data/` continuam no **histórico** do git. Limpar exige reescrever o histórico (`git filter-repo`) e forçar o push, decisão do dono do repositório. <br>❌ 🟡 Senhas fixas no `Dockerfile` (`ENV PASSWORD=root`) e no `docker-compose.yml` (banco e pgAdmin). <br>❌ 🟡 Sem varredura de segredos (gitleaks ou o secret scanning do GitHub). |
| 5 | **Dependências (SCA)** | ✅ `go.sum` versionado (garante integridade dos módulos baixados). <br>✅ **Dependabot** configurado para `gomod` e `github-actions`, com verificação semanal (`.github/dependabot.yml`). <br>✅ **Dependências atualizadas**: `gin v1.12.0`, `gorm v1.31.2`, `gorm.io/driver/postgres v1.6.3` (pgx v5), `golang.org/x/crypto v0.59.0`, `golang.org/x/net v0.63.0`, `golang.org/x/text v0.44.0`; `go.mod` declara `go 1.26.0`. <br>✅ **`govulncheck` no CI**, bloqueando o build quando o código alcança uma vulnerabilidade conhecida. | Nada pendente nesta fase. |
| 6 | **Build e imagem de contêiner** | ✅ Build automatizado no CI, e só depois dos testes e da análise de segurança passarem (`needs: [test, seguranca]`). <br>✅ Imagem versionada por execução (`go_ci3:<run_number>`), o que permite rollback. <br>✅ **Trivy varre a imagem antes do push**: vulnerabilidade CRITICAL ou HIGH com correção disponível impede o envio ao Docker Hub. | ❌ 🟡 Imagem base `ubuntu:latest` (não fixa versão e é grande; o ideal é `distroless` ou `alpine` com versão fixa). <br>❌ 🟡 Contêiner roda como **root** (sem `USER` no Dockerfile e sem `securityContext` no `go.yaml`). <br>❌ 🟢 Sem SBOM e sem assinatura da imagem (cosign). |
| 7 | **Testes de segurança** | ✅ Testes automatizados com banco real no CI (`go test ./...` + docker-compose), em dois sistemas, com o Go estável mais recente. <br>✅ Teste de carga com Locust no `LoadTest.yml`. <br>✅ Smoke test pós-deploy no ECS (`wget /bruno`) e `rollout status` no EKS. <br>✅ **SAST com gosec** no CI, bloqueando o build. <br>✅ Testes de abuso da autenticação e da entrada: sem chave, chave errada, perfil insuficiente, chave não configurada, `id` não numérico, máscara de CPF e RG e exclusão definitiva. | ❌ 🟡 Sem **DAST** (OWASP ZAP baseline contra o ambiente de homologação). <br>❌ 🟡 Sem testes de payload gigante. |
| 8 | **Infraestrutura como código (IaC)** | ✅ Infra 100% em Terraform, com módulos versionados (`~> 21.0`, `~> 6.0`). <br>✅ State remoto no S3 com trava (`use_lockfile = true`) e uma key por projeto. <br>✅ Ambientes separados (`env/Homolog`). <br>✅ **Varredura de IaC com Trivy** em cada push dos dois repositórios de infra e antes de cada `apply` nos workflows da API. Bloqueia CRITICAL e HIGH; as exceções aceitas ficam no próprio recurso (`#trivy:ignore`) com justificativa. Uma checagem própria (`API-GO-0001`) barra a porta 5432 aberta para a internet, que as regras padrão não cobrem. <br>✅ RDS com disco criptografado e ALB descartando cabeçalhos inválidos. | ❌ 🟡 `apply -auto-approve` sem `plan` revisado por alguém. <br>❌ 🟡 O state guarda a senha do RDS e as chaves de API em texto puro; o bucket não declara `encrypt = true` nem bloqueio de acesso público no código. <br>❌ 🟢 Endpoint do EKS público para a internet inteira (`endpoint_public_access = true` sem restringir IPs). Hoje é uma exceção registrada na varredura. |
| 9 | **Pipeline e cadeia de suprimentos (CI/CD)** | ✅ Workflows reutilizáveis com `secrets: inherit`. <br>✅ Testes e análise de segurança antes do build, e build antes do deploy (`needs`). <br>✅ **Login na AWS por OIDC**: o GitHub assume a role `github-actions-api-go` com credencial temporária, e só em push nas branches `main` e `Homolog` deste repositório. Nenhum workflow usa mais access key. <br>✅ **Todas as actions fixadas pelo SHA do commit**, inclusive a `easingthemes/ssh-deploy` (antes `@main`). O Trivy roda por imagem fixada por digest. <br>✅ `permissions:` mínimas (`contents: read`; `id-token: write` só nos jobs de deploy). <br>✅ Actions atualizadas para as versões mais recentes. | ❌ 🟡 A role do OIDC tem `AdministratorAccess`. Reduzir para o mínimo que o Terraform precisa. <br>❌ 🟡 Passo manual: apagar `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` dos secrets do GitHub e desativar a access key no IAM, depois de validar o OIDC. |
| 10 | **Deploy e release** | ✅ Deploy automatizado no EKS e no ECS. <br>✅ **Rollback automático** no ECS (`task-definition.json.old`). <br>✅ RollingUpdate e `livenessProbe` no Kubernetes. <br>✅ Load test só em push na branch `Homolog`. <br>✅ **`Deploy_EKS` só em push na branch `main`** (antes rodava em push de qualquer branch). | ❌ 🟡 Sem **GitHub Environments** com aprovação manual e regras de proteção. <br>❌ 🟡 Sem proteção de branch exigindo PR, revisão e checks verdes (não dá para confirmar pelo código; conferir em Settings → Branches). <br>❌ 🟢 Sem `resources` (limits/requests) no `go.yaml`. |
| 11 | **Operação, monitoramento e resposta a incidentes** | ⚠️ Logs padrão do Gin no stdout; `livenessProbe` reinicia pods travados; healthcheck do banco no docker-compose. | ❌ 🟡 Sem logs centralizados nem retenção definida (CloudWatch Logs / Container Insights). <br>❌ 🟡 Sem alertas (erro 5xx, pods em CrashLoop, custo). <br>❌ 🟡 Sem trilha de auditoria (CloudTrail) nem logs de acesso do load balancer. <br>❌ 🟢 Sem plano de resposta a incidentes (`SECURITY.md`, quem acionar, como rotacionar segredos). |
| 12 | **Manutenção e descarte** | ✅ `terraform destroy` garantido no load test (`if: always()`). <br>✅ Infra do EKS destruída e verificada ao fim do estudo. <br>✅ Rotina de atualização semanal com Dependabot (`gomod` e `github-actions`). | ❌ 🟡 Sem revisão periódica de acessos. <br>❌ 🟡 Usuário IAM do terminal com access entry de admin criada manualmente; sem revisão de quem tem acesso. <br>❌ 🟢 Repositório ainda usa o módulo `github.com/guilhermeonrails/api-go-gin` (nome do projeto original). |

---

## Achados críticos em detalhe

### 1. SQL injection pelo `id` da URL — ✅ corrigido na v1

Em `controllers/controller.go`, o `id` vinha da URL como **string** e ia direto para o GORM:

```go
id := c.Params.ByName("id")
database.DB.First(&aluno, id)    // BuscarAlunoPorID e EditarAluno
database.DB.Delete(&aluno, id)   // DeletarAluno
```

No GORM v1.22.4 (`statement.go`, `BuildCondition`), quando esse valor **não é um número**, ele é tratado como um **trecho de SQL** e colado no `WHERE`. Em `DELETE /alunos/<id>`, um valor como uma condição sempre verdadeira apaga **todos** os alunos.

**Correção aplicada:** a função `idDaURL` converte o `:id` com `strconv.Atoi` e recusa valores não numéricos ou menores que 1 com `400`. Os três handlers passam a usar esse número.

```go
func idDaURL(c *gin.Context) (int, bool) {
    id, err := strconv.Atoi(c.Param("id"))
    if err != nil || id <= 0 {
        c.JSON(http.StatusBadRequest, gin.H{"erro": "id inválido"})
        return 0, false
    }
    return id, true
}
```

### 2. Banco de dados do ECS exposto para a internet — ✅ corrigido na v2

No `infra-api-go-cicd-aws-ecs`, o RDS tinha `publicly_accessible = true`, o security group liberava a porta 5432 para `0.0.0.0/0` e a senha (`rootroot`) estava no código.

**Correção aplicada:** `publicly_accessible = false`; a porta 5432 aceita só o security group das tarefas (`source_security_group_id`); as subnets de banco não têm mais rota para a internet; a senha é gerada pelo Terraform e lida do Secrets Manager. O mesmo modelo de senha foi aplicado ao RDS do EKS, cuja porta ficou restrita ao CIDR da VPC.

### 3. Pasta `postgres-data/` versionada — ⚠️ corrigido em parte na v2

**Correção aplicada:** `git rm -r --cached postgres-data` (1.260 arquivos fora do índice) e `.gitignore` com `postgres-data/`.

**Pendente:** os arquivos continuam no histórico. Para apagá-los de vez é preciso `git filter-repo --path postgres-data --invert-paths` e um push forçado, o que muda o histórico de todos que clonaram o repositório.

### 4. API sem autenticação expondo CPF e RG — ✅ corrigido na v2

**Correção aplicada:** chave de API com perfis leitura e admin nas rotas `/alunos`; CPF e RG mascarados para quem não é admin; exclusão definitiva do registro. Regras em `REQUISITOS-SEGURANCA.md`.

### 5. Deploy em toda branch, com chave da AWS de longa duração — ✅ corrigido na v2

**Correção aplicada:** OIDC (`role-to-assume` no `configure-aws-credentials`, com `permissions: id-token: write`), role criada por `bootstrap/github-oidc` no repositório de infra do ECS e aceitando só push nas branches `main` e `Homolog`; `Deploy_EKS` só em push na `main`. GitHub Environment com aprovação continua pendente (🟡).

---

## Plano sugerido, por ordem

| Ordem | Ação | Fases cobertas | Esforço |
|---|---|---|---|
| 1 | ✅ Corrigir o SQL injection (`strconv.Atoi`) — feito na v1 | 3 | Baixo |
| 2 | ⚠️ Tirar `postgres-data/` do git e criar `.gitignore` — feito na v2; falta limpar o histórico | 4 | Baixo |
| 3 | ✅ Fechar o RDS do ECS (`publicly_accessible = false`, SG restrito) e tirar as senhas do código — feito na v2 | 2, 4, 8 | Baixo |
| 4 | ⚠️ Restringir o `Deploy_EKS` à branch principal — feito na v2; falta o Environment com aprovação | 10 | Baixo |
| 5 | ⚠️ Job de segurança: `gosec`, `govulncheck` e Trivy (imagem + Terraform) — feito na v2; falta `gitleaks` | 4, 5, 6, 7, 8 | Médio |
| 6 | ✅ Ativar Dependabot (v1) e atualizar Gin, GORM e Go (v2) | 5, 9, 12 | Médio |
| 7 | ✅ Trocar as access keys por OIDC e fixar actions por SHA — feito na v2 | 9 | Médio |
| 8 | Imagem `distroless` com usuário não root + `securityContext` e `resources` no `go.yaml` | 6, 10 | Médio |
| 9 | ✅ Autenticação na API e mascaramento de CPF e RG — feito na v2 | 1, 3 | Alto |
| 10 | Logs centralizados, alertas, CloudTrail e `SECURITY.md` | 11 | Médio |

---

## Limitações desta análise

- Feita a partir do código dos três repositórios. Configurações que só existem no GitHub (visibilidade do repositório, proteção de branch, secret scanning, Environments) e na AWS (políticas do usuário IAM, configuração do bucket S3) não foram conferidas.
- As correções da v2 foram verificadas localmente: testes com PostgreSQL real, gosec, govulncheck, `terraform validate`, `actionlint` e Trivy (IaC e imagem). Os workflows ainda não rodaram no GitHub, o Terraform não foi aplicado na AWS e a role do OIDC ainda não existe. Os passos para isso estão em `CORRECAO-SSDLC-v2.md`.

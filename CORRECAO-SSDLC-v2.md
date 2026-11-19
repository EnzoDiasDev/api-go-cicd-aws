# Correção dos itens 🔴 — SSDLC v2

Este documento explica o que mudou entre a **v1** (`SSDLC-v1.md`) e a **v2** (`SSDLC-v2.md`) do levantamento de segurança do projeto. Ele cobre o que foi corrigido, por que cada correção importa, onde ela está no código, como foi verificada e o que ainda falta.

Foi escrito para quem está chegando agora ao projeto. Se você nunca viu o levantamento, comece pela seção 1. Se você só precisa pôr as mudanças para funcionar, vá direto para a seção 3.

---

## Sumário

1. [Contexto: o levantamento e as versões](#1-contexto-o-levantamento-e-as-versões)
2. [Visão geral: os 13 itens 🔴 e onde cada um foi tratado](#2-visão-geral-os-13-itens--e-onde-cada-um-foi-tratado)
3. [Antes de usar: passos fora do código, na ordem](#3-antes-de-usar-passos-fora-do-código-na-ordem)
4. [Mudanças de comportamento que afetam quem usa a API](#4-mudanças-de-comportamento-que-afetam-quem-usa-a-api)
5. [Cada correção em detalhe](#5-cada-correção-em-detalhe)
6. [Como tudo foi verificado](#6-como-tudo-foi-verificado)
7. [O que ficou pendente e por quê](#7-o-que-ficou-pendente-e-por-quê)
8. [Glossário](#8-glossário)

---

## 1. Contexto: o levantamento e as versões

O **SSDLC** (*Secure Software Development Life Cycle*) é o ciclo de desenvolvimento com segurança em cada etapa: requisitos, design, código, segredos, dependências, build, testes, infraestrutura, pipeline, deploy, operação e manutenção.

O arquivo `SSDLC-vN.md` tem uma tabela com as 12 fases. Para cada fase, duas colunas:

- **O que o repo já faz**: práticas que já existem.
- **O que falta**: lacunas, cada uma com uma prioridade.

| Símbolo | Significado |
|---|---|
| ✅ | Já faz |
| ⚠️ | Faz em parte |
| ❌ | Não faz |
| 🔴 | Prioridade alta |
| 🟡 | Prioridade média |
| 🟢 | Prioridade baixa |

O projeto está em três repositórios:

| Repositório | O que tem |
|---|---|
| `api-go-cicd-aws-ecs` (no GitHub: `EnzoDiasDev/Curso_CI_3-Projeto_inicial`) | A API em Go, o Dockerfile e os workflows do GitHub Actions |
| `infra-api-go-cicd-aws-ecs` | Terraform do ambiente ECS, usado pelo teste de carga |
| `infra-api-go-cicd-aws-eks` | Terraform do ambiente EKS (Kubernetes) e o `go.yaml` |

**Histórico das versões:**

- **v0**: levantamento original.
- **v1**: corrigiu a SQL injection pelo `id` da URL, ligou o modo de produção do Gin e configurou o Dependabot. Detalhes em `CORRECAO-SSDLC-v1.md`.
- **v2** (este documento): tratou **todos os itens 🔴** da coluna "O que falta".

---

## 2. Visão geral: os 13 itens 🔴 e onde cada um foi tratado

| # | Item 🔴 da v1 | Fase | Situação na v2 | Onde |
|---|---|---|---|---|
| 1 | Sem autenticação nem autorização | 1 | ✅ Corrigido | API: `autenticacao/`, `routes/route.go` |
| 2 | CPF e RG sem regra de quem vê, retenção ou máscara | 1 | ✅ Corrigido | API: `models/alunos.go`, `controllers/controller.go`, `REQUISITOS-SEGURANCA.md` |
| 3 | RDS do ECS público, porta 5432 aberta para a internet | 2 | ✅ Corrigido | Infra ECS: `RDS.tf`, `GrupoSeguranca.tf`, `VPC.tf` |
| 4 | Senha do RDS (`rootroot`) no código | 4 | ✅ Corrigido | Infra ECS e EKS: `Segredos.tf`, `RDS.tf`, `ECS.tf`, `IAM.tf`; API: `EKS.yml` |
| 5 | Pasta `postgres-data/` versionada | 4 | ⚠️ Em parte: saiu do índice; continua no histórico | API: `.gitignore` |
| 6 | Dependências de 2021/2022 | 5 | ✅ Corrigido | API: `go.mod`, `go.sum` |
| 7 | Sem análise de vulnerabilidades no CI | 5 | ✅ Corrigido | API: `go.yml` (govulncheck) |
| 8 | Sem varredura da imagem antes do push | 6 | ✅ Corrigido | API: `Docker.yml` (Trivy) |
| 9 | Sem SAST | 7 | ✅ Corrigido | API: `go.yml` (gosec) |
| 10 | Sem varredura de IaC | 8 | ✅ Corrigido | Infra: `.github/workflows/iac.yml`, `.trivy/checks/`; API: `EKS.yml`, `LoadTest.yml` |
| 11 | Access key da AWS de longa duração | 9 | ✅ Corrigido (falta apagar a chave antiga, passo manual) | Infra ECS: `bootstrap/github-oidc/`; API: workflows |
| 12 | `ssh-deploy@main` e actions por tag | 9 | ✅ Corrigido | API: todos os workflows; infra: `iac.yml` |
| 13 | `Deploy_EKS` em push de qualquer branch | 10 | ✅ Corrigido | API: `go.yml` |

**Commits:**

| Repositório | Branch | Conteúdo |
|---|---|---|
| `api-go-cicd-aws-ecs` | `Homolog` | Código, workflows, `.gitignore`, remoção de `postgres-data/` do índice e documentação |
| `infra-api-go-cicd-aws-ecs` | `seguranca/ssdlc-v2` (nova, a partir da `main`) | Terraform, bootstrap do OIDC e varredura de IaC |
| `infra-api-go-cicd-aws-eks` | `seguranca/ssdlc-v2` (nova, a partir da `main`) | Terraform, `go.yaml` e varredura de IaC |

Nada foi enviado ao GitHub (sem `push`), e nada foi aplicado na AWS.

---

## 3. Antes de usar: passos fora do código, na ordem

As mudanças dependem de coisas que só existem na AWS e no GitHub. **A ordem importa**: os workflows da API clonam a branch padrão dos repositórios de infra, e os workflows novos esperam a role do OIDC.

### Passo 1 — Levar a infra para a `main`

Os workflows `EKS.yml` e `LoadTest.yml` fazem `git clone` dos repositórios de infra **sem escolher branch**, ou seja, usam a `main`. O código novo da API espera as saídas novas do Terraform (`db_secret_arn` e `api_keys_secret_arn`). Por isso, as branches `seguranca/ssdlc-v2` dos dois repositórios de infra precisam entrar na `main` **antes** do código da API chegar à `main`.

### Passo 2 — Criar a role do OIDC (uma vez, por um administrador)

```bash
cd infra-api-go-cicd-aws-ecs
terraform -chdir=bootstrap/github-oidc init
terraform -chdir=bootstrap/github-oidc apply
terraform -chdir=bootstrap/github-oidc output -raw role_arn
```

O bootstrap cria:

- o **provedor OIDC** do GitHub na conta da AWS;
- a role `github-actions-api-go`, que só pode ser assumida por workflows do repositório `EnzoDiasDev/Curso_CI_3-Projeto_inicial` em push nas branches `main` e `Homolog`.

Se a conta já tiver um provedor OIDC do GitHub (só pode existir um por conta), o `apply` falha. Nesse caso, importe o existente e rode o `apply` de novo:

```bash
terraform -chdir=bootstrap/github-oidc import aws_iam_openid_connect_provider.github \
  arn:aws:iam::<ID-DA-CONTA>:oidc-provider/token.actions.githubusercontent.com
```

### Passo 3 — Cadastrar o secret `AWS_ROLE_ARN` no GitHub

No repositório da API: *Settings → Secrets and variables → Actions → New repository secret*. O nome é `AWS_ROLE_ARN` e o valor é a saída do passo 2 (algo como `arn:aws:iam::123456789012:role/github-actions-api-go`).

### Passo 4 — Só se for usar os fluxos antigos de EC2 ou ECS

Os workflows `EC2.yml` e `ECS.yml` (hoje comentados no `go.yml`) não usam o Terraform deste projeto e leem as chaves da API dos secrets do GitHub. Se forem reativados, cadastre também `API_KEY_LEITURA` e `API_KEY_ADMIN`. Use valores longos e aleatórios, por exemplo a saída de `openssl rand -hex 32`.

Os fluxos EKS e LoadTest **não** precisam desses secrets: lá as chaves são geradas pelo Terraform.

### Passo 5 — Rodar o pipeline

- Push na `Homolog`: roda testes, análise de segurança, build e varredura da imagem. Não faz deploy no EKS.
- Merge na `main`: roda tudo isso e o deploy no EKS.

### Passo 6 — Aposentar a access key antiga

Depois de confirmar que o deploy funcionou com OIDC:

1. Apague os secrets `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` do repositório no GitHub.
2. No IAM da AWS, desative e depois apague a access key do usuário que o pipeline usava.

Enquanto a chave existir, ela continua sendo uma credencial de longa duração que pode vazar.

### Como ler as chaves de API de um ambiente

As chaves ficam no AWS Secrets Manager. O ARN do segredo é uma saída do Terraform:

```bash
ARN=$(terraform -chdir=infra-api-go-cicd-aws-eks/env/Homolog output -raw api_keys_secret_arn)
aws secretsmanager get-secret-value --secret-id "$ARN" --query SecretString --output text
```

---

## 4. Mudanças de comportamento que afetam quem usa a API

| Antes | Agora |
|---|---|
| Qualquer pessoa listava, criava, editava e apagava alunos | As rotas de `/alunos` exigem o cabeçalho `X-API-Key` |
| A listagem devolvia CPF e RG completos | Só a chave de admin vê completo; a de leitura vê `*********01` |
| `DELETE` de um id inexistente respondia `200` | Responde `404` |
| `DELETE` fazia *soft delete*: o registro ficava no banco com `deleted_at` preenchido | O registro é removido de verdade |
| `DELETE /alunos/1` sem chave funcionava | Responde `401` |

Exemplos de chamada:

```bash
# Consulta com a chave de leitura (CPF e RG mascarados)
curl -H "X-API-Key: $API_KEY_LEITURA" http://<host>:8000/alunos

# Criação com a chave de admin
curl -X POST -H "X-API-Key: $API_KEY_ADMIN" -H "Content-Type: application/json" \
  -d '{"nome":"Ana","cpf":"12345678901","rg":"123456789"}' http://<host>:8000/alunos
```

**Continuam públicas:** `GET /:nome` (por exemplo `/bruno` e `/leo`, usadas pelo health check do load balancer, pela `livenessProbe` e pelo teste de carga), a página `GET /index` (que mostra só nomes) e `/assets`.

---

## 5. Cada correção em detalhe

### 5.1. Autenticação e autorização (itens 1 e 2, fase 1)

**O problema.** Todas as rotas eram abertas. Qualquer pessoa na internet podia listar todos os alunos com CPF e RG, alterar e apagar. Também não havia regra escrita sobre esses dados pessoais (LGPD).

**Por que chave de API.** Não precisa de serviço externo (como um provedor de login) nem de tabela de usuários. Ela se encaixa no modelo de segredos que já existe: as chaves são geradas e guardadas como a senha do banco. A troca por JWT ou por um provedor de identidade continua possível no futuro sem mudar as rotas.

**Como funciona.** O pacote novo `autenticacao/autenticacao.go`:

1. Lê `API_KEY_LEITURA` e `API_KEY_ADMIN` do ambiente ao subir a API.
2. A cada requisição, compara o cabeçalho `X-API-Key` com as duas chaves usando `crypto/subtle.ConstantTimeCompare`. Uma comparação comum (`==`) para no primeiro caractere diferente, e o tempo de resposta poderia revelar a chave aos poucos.
3. Define o perfil (`PerfilLeitura` ou `PerfilAdmin`) no contexto da requisição.
4. Sem chave válida, responde `401`. Com chave válida mas perfil insuficiente, responde `403`.
5. Uma chave configurada vazia **nunca** é aceita. Se ninguém configurar as chaves, a API recusa tudo em vez de liberar tudo. Isso se chama *falha fechada*.

Em `routes/route.go`, as rotas ficaram em dois grupos:

```go
leitura := r.Group("/alunos", autenticacao.Exige(chaves, autenticacao.PerfilLeitura))
leitura.GET("", controllers.TodosAlunos)
leitura.GET("/:id", controllers.BuscarAlunoPorID)
// ...
admin := r.Group("/alunos", autenticacao.Exige(chaves, autenticacao.PerfilAdmin))
admin.POST("", controllers.CriarNovoAluno)
admin.PATCH("/:id", controllers.EditarAluno)
admin.DELETE("/:id", controllers.DeletarAluno)
```

A montagem das rotas virou a função `NovoRouter(chaves)`. Isso permite testar as rotas sem banco e sem variáveis de ambiente.

**Dados pessoais.** Em `models/alunos.go`:

- `MascaraDocumento` troca tudo por `*`, menos os dois últimos caracteres.
- `Aluno.Mascarado()` devolve uma cópia com CPF e RG mascarados e não altera o original.

Em `controllers/controller.go`, a função `visaoDoAluno` decide o que devolver: só o perfil admin recebe o aluno completo. **Qualquer outro caso**, inclusive a ausência de perfil, recebe a versão mascarada. Ela é usada na listagem, na busca por id e na busca por CPF.

**Retenção.** O `DeletarAluno` passou a usar `database.DB.Unscoped().Delete(...)`. O `gorm.Model` faz, por padrão, uma exclusão lógica: só preenche a coluna `deleted_at` e o registro continua no banco, com CPF e RG. O `Unscoped()` apaga a linha de verdade. O handler também passou a responder `404` quando não apaga nada e `500` quando o banco falha.

**Regras escritas.** O arquivo `REQUISITOS-SEGURANCA.md` registra quem vê o quê, como é a máscara e por quanto tempo os dados ficam guardados.

**Como as chaves chegam à API em cada ambiente:**

| Ambiente | Origem das chaves |
|---|---|
| ECS (teste de carga) | Geradas pelo Terraform, guardadas no Secrets Manager, injetadas pelo bloco `secrets` da task definition |
| EKS | Geradas pelo Terraform, guardadas no Secrets Manager, lidas pelo `EKS.yml` e gravadas no Secret do Kubernetes `api-keys`, que o `go.yaml` usa |
| EC2 e ECS antigo | Secrets do GitHub `API_KEY_LEITURA` e `API_KEY_ADMIN` |
| Local | Variáveis de ambiente que você exporta antes de rodar |

### 5.2. Banco do ECS aberto para a internet (item 3, fase 2)

**O problema.** No repositório `infra-api-go-cicd-aws-ecs`, o RDS tinha `publicly_accessible = true` e o security group liberava a porta 5432 para `0.0.0.0/0`, a internet inteira. Com a senha no código, qualquer pessoa que lesse o repositório podia entrar no banco.

**O que mudou:**

| Arquivo | Mudança |
|---|---|
| `infra/RDS.tf` | `publicly_accessible = false`: o RDS não recebe endereço público |
| `infra/GrupoSeguranca.tf` | A regra `tcp_db` aceita só o security group `privado`, das tarefas do ECS (`source_security_group_id`) |
| `infra/GrupoSeguranca.tf` | A regra de saída do banco foi removida. Security groups são *stateful*: a resposta a uma conexão recebida sai sem regra de saída, e o banco não precisa iniciar conexões |
| `infra/VPC.tf` | `create_database_internet_gateway_route = false`: as subnets de banco não têm rota para a internet |

**No EKS também.** O RDS do EKS já não era público, mas o security group também liberava a 5432 para `0.0.0.0/0`. A regra passou a aceitar só o CIDR da VPC (`module.vpc.vpc_cidr_block`), onde ficam os nós e os pods. O EKS também perdeu a rota de internet das subnets de banco.

**Correções pequenas que vieram junto.** Para o gate de IaC (seção 5.7) passar sem exceções desnecessárias:

- `storage_encrypted = true` no RDS dos dois ambientes: o disco do banco fica criptografado.
- `drop_invalid_header_fields = true` no ALB do ECS: cabeçalhos HTTP malformados são descartados antes de chegar à API.

### 5.3. Senha do banco no código (item 4, fase 4)

**O problema.** A senha `rootroot` estava escrita no `RDS.tf` dos dois repositórios de infra e também na task definition do ECS (`ECS.tf`).

**O que mudou.** Foi criado `infra/Segredos.tf` nos dois repositórios de infra:

1. `random_password.db` gera uma senha de 32 caracteres. Ela não tem caracteres especiais porque a API monta a conexão no formato `chave=valor` separado por espaços, e aspas ou espaços quebrariam esse formato.
2. `aws_secretsmanager_secret.db` cria um segredo no **AWS Secrets Manager**, e `aws_secretsmanager_secret_version.db` grava nele um JSON com `username` e `password`.
3. O `aws_db_instance` usa `password = random_password.db.result`.
4. O mesmo foi feito para as chaves de API (`api_key_leitura` e `api_key_admin`).

Dois detalhes importantes:

- `recovery_window_in_days = 0`: por padrão, um segredo apagado fica 30 dias "agendado para exclusão", e não dá para criar outro com o mesmo nome nesse período. Como o teste de carga destrói e recria o ambiente a cada execução, sem isso o segundo `apply` falharia.
- `name_prefix` em vez de `name`: cada criação ganha um sufixo único, evitando conflito de nomes.

**Como o ECS lê o segredo.** Em `infra/ECS.tf`, `PASSWORD` saiu do bloco `environment`, onde ficava visível em texto puro na task definition, e foi para o bloco `secrets`:

```hcl
"secrets" = [
  { "name" = "PASSWORD", "valueFrom" = "${aws_secretsmanager_secret.db.arn}:password::" },
  ...
]
```

O sufixo `:password::` diz ao ECS para pegar só o campo `password` do JSON. Para isso, a role de execução ganhou, em `infra/IAM.tf`, permissão `secretsmanager:GetSecretValue` **apenas** nesses dois segredos. O serviço do ECS passou a depender das versões dos segredos (`depends_on`), para a primeira tarefa não subir antes de existir um valor gravado.

**Como o EKS lê o segredo.** No `EKS.yml`, o passo "Secrets do Kubernetes a partir do Secrets Manager":

1. pega os ARNs pelas saídas do Terraform;
2. lê os segredos com `aws secretsmanager get-secret-value`;
3. marca cada valor com `::add-mask::`, para o GitHub esconder o valor em qualquer log;
4. cria ou atualiza os Secrets `dbuser`, `dbpassword` e `api-keys` com `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -`. Esse comando cria o Secret se não existir e atualiza se existir.

Com isso, o EKS não usa mais os secrets do GitHub `DBUSER` e `DBPASSWORD`.

**Atenção:** o *state* do Terraform guarda os valores gerados. Isso continua listado como 🟡 na fase 8, porque o bucket do state precisa ser privado e criptografado.

### 5.4. Pasta `postgres-data/` no git (item 5, fase 4)

**O problema.** A pasta com os arquivos internos do PostgreSQL local (1.260 arquivos) estava versionada. Qualquer dado que já passou pelo banco local fica no repositório.

**O que mudou:**

- `git rm -r --cached postgres-data`: os arquivos saem do controle de versão, mas continuam no seu disco.
- Novo `.gitignore` com `postgres-data/`, `/main` (binário gerado pelo build) e `.env`.

**O que não foi feito, e por quê.** Os arquivos continuam no **histórico** do git: quem fizer checkout de um commit antigo ainda os vê. Apagar do histórico exige reescrever todos os commits (`git filter-repo --path postgres-data --invert-paths`) e fazer push forçado. Isso muda os hashes dos commits e quebra os clones de quem já baixou o repositório. É uma decisão do dono do repositório, então ficou registrada como pendência 🔴 na v2.

### 5.5. Dependências desatualizadas (item 6, fase 5)

**O problema.** `gin v1.7.7`, `gorm v1.22.4` e `golang.org/x/crypto` eram de 2021, com vulnerabilidades públicas, e o `go.mod` declarava `go 1.15`.

**O que mudou.** Atualização com `go get` e `go mod tidy`:

| Módulo | Antes | Depois |
|---|---|---|
| `github.com/gin-gonic/gin` | v1.7.7 | v1.12.0 |
| `gorm.io/gorm` | v1.22.4 | v1.31.2 |
| `gorm.io/driver/postgres` | v1.2.3 (pgx v4) | v1.6.3 (pgx v5) |
| `golang.org/x/crypto` | 2021 | v0.59.0 |
| `golang.org/x/net` | — | v0.63.0 |
| `golang.org/x/text` | v0.3.7 | v0.44.0 |
| Diretiva `go` | 1.15 | 1.26.0 |

**Resultado do govulncheck:**

| Momento | Resultado |
|---|---|
| Antes | 15 vulnerabilidades alcançadas pelo código (pgx v4, pgproto3, `x/text` e biblioteca padrão) |
| Depois, com o Go 1.26 mais recente | **"No vulnerabilities found."** |

**Consequência no CI.** Como o `go.mod` exige Go 1.26, a matriz antiga (Go 1.17 e 1.18, versões sem suporte) não funcionaria. Todos os jobs usam agora `go-version: stable` com `check-latest: true`, sempre a versão estável mais recente com as correções de segurança da biblioteca padrão. O job `build` antes nem configurava o Go e usava o que viesse instalado no runner; agora também usa `stable`.

### 5.6. SAST e análise de dependências no CI (itens 7 e 9, fases 5 e 7)

**O problema.** Nenhuma ferramenta olhava o código ou as dependências atrás de falhas de segurança. A SQL injection corrigida na v1, por exemplo, poderia ter sido pega automaticamente.

**O que mudou.** No `go.yml`, o novo job `seguranca` tem dois passos:

- **gosec (SAST)**: lê o código-fonte e aponta padrões inseguros, como SQL montado com string, erro ignorado ou credencial no código.
- **govulncheck (SCA)**: cruza as dependências e a versão do Go com a base de vulnerabilidades do Go, e reprova só o que o código **realmente alcança**.

As versões das ferramentas estão fixadas (`gosec@v2.30.0` e `govulncheck@v1.10.0`). O job `build` agora depende de `test` **e** de `seguranca`: se qualquer um falhar, não há build, nem imagem, nem deploy.

**Correções que o gosec pediu.** Na primeira execução, o gosec apontou dois erros ignorados:

- `DB.AutoMigrate(...)` em `database/db.go`: se a migração falhar, a API agora para com uma mensagem clara, em vez de subir sem a tabela.
- `r.Run()` em `routes/route.go`: se o servidor não conseguir subir (por exemplo, porta ocupada), agora registra o erro e encerra.

### 5.7. Varredura de IaC (item 10, fase 8)

**O problema.** Nada verificava o Terraform antes do `apply`. O banco público e a porta aberta poderiam ter sido pegos automaticamente.

**A ferramenta.** Trivy em modo `config`, que analisa Terraform e manifestos do Kubernetes. Ele roda pela imagem oficial **fixada por digest** (`aquasec/trivy@sha256:8f6bb9...`), a versão 0.76.2. O digest identifica o conteúdo exato da imagem. Mesmo que alguém reescreva a tag `0.76.2`, o pipeline continua usando a imagem que foi testada.

**Onde roda:**

- `.github/workflows/iac.yml`, novo nos dois repositórios de infra, em todo push e pull request;
- no `EKS.yml` e no `LoadTest.yml` da API, **antes** do `terraform init` e do `apply`. Se reprovar, nenhum recurso é criado.

**O que bloqueia.** Achados CRITICAL e HIGH (`--exit-code 1`).

**Exceções aceitas.** Alguns achados são de pendências 🟡 ou 🟢 já registradas, ou são necessários para o projeto funcionar. Eles foram marcados como exceção **no próprio recurso**, com um comentário que explica o motivo:

```hcl
# Exceção aceita na varredura de IaC: ainda sem HTTPS (precisa de domínio e
# certificado no ACM). Pendência registrada no SSDLC, fase 2 (tráfego sem TLS).
#trivy:ignore:AWS-0054
resource "aws_lb_listener" "http" {
```

A exceção vale só para aquele recurso e aquela regra. Uma regra igual em outro recurso continua sendo barrada.

| Regra | Onde | Por que é exceção |
|---|---|---|
| AWS-0053 | ALB do ECS | O load balancer é a entrada pública da API |
| AWS-0054 | Listener HTTP do ECS | Sem HTTPS ainda; pendência 🟡 da fase 2 |
| AWS-0104 | Saída do ALB, das tarefas do ECS e dos nós do EKS | Precisam acessar Docker Hub, Secrets Manager e APIs da AWS |
| AWS-0107 | SSH dos nós do EKS | Pendência 🟡 da fase 2 |
| AWS-0040, AWS-0041 | Endpoint do EKS | O `kubectl` roda no runner do GitHub, fora da VPC; pendência 🟢 da fase 8 |
| AWS-0164 | Subnets públicas do EKS | Os nós precisam de IP público (ver comentário em `VPC.tf`) |
| KSV-0014, KSV-0118 | `go.yaml` | Contêiner como root; pendência 🟡 da fase 6. Fica em `.trivyignore.yaml`, porque YAML do Kubernetes não aceita o comentário de exceção |

**Uma lacuna do Trivy, e a checagem própria.** Nos testes, o Trivy **não** acusou a porta 5432 aberta para `0.0.0.0/0`: as regras padrão dele só olham portas como a 22. Para não depender disso, foi escrita uma checagem própria em Rego, `.trivy/checks/porta_banco_publica.rego` (id `API-GO-0001`, severidade CRITICAL). Ela reprova qualquer security group que libere a 5432, ou todas as portas, para `0.0.0.0/0` ou `::/0`.

### 5.8. Varredura da imagem antes do push (item 8, fase 6)

**O problema.** A imagem ia para o Docker Hub sem verificação. Uma vulnerabilidade no Ubuntu base ou no binário Go seria publicada e implantada.

**O que mudou no `Docker.yml`:**

1. `docker build`: constrói a imagem localmente no runner, sem enviar.
2. `docker save` + Trivy `image --input`: varre a imagem exportada. Reprova vulnerabilidades CRITICAL ou HIGH **que já têm correção** (`--ignore-unfixed`). Vulnerabilidades sem correção publicada não bloqueiam, porque não há o que fazer além de esperar.
3. `docker login`.
4. `docker push`: envia **a mesma imagem que foi varrida**.

As actions `docker/setup-buildx-action` e `docker/build-push-action` deixaram de ser usadas. Os comandos `docker` do próprio runner fazem o mesmo trabalho, com duas dependências de terceiros a menos na cadeia de suprimentos.

O Trivy lê a imagem de um arquivo `.tar`, e não pelo socket do Docker. Assim o container do Trivy não precisa de acesso ao daemon do Docker da máquina.

### 5.9. Login na AWS por OIDC (item 11, fase 9)

**O problema.** Os workflows usavam `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY`, uma chave **permanente** de um usuário IAM. Se vazasse (log, fork, action comprometida), daria acesso à conta até alguém notar e apagar.

**Como o OIDC resolve.** A cada execução, o GitHub emite um token assinado que diz "sou o workflow do repositório X, na branch Y". A AWS confere a assinatura e as condições da role, e devolve uma credencial que **expira** ao fim do job. Não existe chave guardada para vazar.

**O que mudou:**

- `bootstrap/github-oidc/main.tf` (repositório de infra do ECS) cria o provedor OIDC e a role `github-actions-api-go`. A política de confiança aceita só tokens com:
  - `aud = sts.amazonaws.com`;
  - `sub = repo:EnzoDiasDev/Curso_CI_3-Projeto_inicial:ref:refs/heads/main` ou `...:ref:refs/heads/Homolog`.

  Pull requests, forks e outras branches não conseguem assumir a role.
- O bootstrap fica **fora** de `env/Homolog` de propósito. O teste de carga destrói e recria aquele ambiente, e não pode apagar a role que ele mesmo usa para entrar na AWS. Ele também tem seu próprio arquivo de state no bucket.
- `EKS.yml`, `LoadTest.yml` e `ECS.yml` trocaram a chave por `role-to-assume: ${{ secrets.AWS_ROLE_ARN }}`.
- Os jobs que falam com a AWS declaram `permissions: id-token: write`, necessário para pedir o token. No `go.yml`, o job que chama o `EKS.yml` também declara essa permissão, porque um workflow chamado nunca pode ter mais permissão do que quem o chama.

**Limitação assumida.** A role tem `AdministratorAccess`, porque o Terraform cria VPC, EKS, RDS, ECS e roles IAM. O ganho está em a credencial ser temporária e restrita ao repositório e às branches. Reduzir as permissões ao mínimo ficou como pendência 🟡.

### 5.10. Actions fixadas por SHA (item 12, fase 9)

**O problema.** `easingthemes/ssh-deploy@main` apontava para uma **branch**: o código executado mudava a cada commit do autor da action, e recebia a chave SSH do servidor. As outras actions usavam tags como `@v3`, que também podem ser movidas para outro código. Isso já aconteceu: em março de 2025, as tags da action `tj-actions/changed-files` foram reescritas para um código que vazava os secrets dos workflows que a usavam.

**O que mudou.** Toda action nos workflows dos três repositórios agora aponta para o **SHA completo do commit**, com a versão em comentário:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

Um SHA identifica um conteúdo exato e não pode ser movido. Os SHAs foram obtidos com `git ls-remote` nos repositórios oficiais de cada action. As versões foram atualizadas para as mais recentes, e os inputs usados foram conferidos no `action.yml` de cada versão.

O Dependabot (configurado na v1) entende esse formato: quando sair uma versão nova, ele abre um PR trocando o SHA e o comentário juntos.

**Permissões mínimas.** O `go.yml` declara `permissions: contents: read` para todos os jobs, e só os jobs de deploy pedem `id-token: write`. Antes, o `GITHUB_TOKEN` tinha as permissões padrão do repositório, que podem incluir escrita.

### 5.11. Deploy do EKS só na `main` (item 13, fase 10)

**O problema.** O job `Deploy_EKS` rodava em push de **qualquer** branch. Qualquer push, inclusive uma branch de teste, rodava `terraform apply` e criava ou alterava infraestrutura paga.

**O que mudou** no `go.yml`:

```yaml
Deploy_EKS:
  needs: docker
  if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}
```

Agora só um push na `main` (normalmente um merge) faz o deploy. Pull requests e outras branches param depois da imagem. O teste de carga, se reativado, segue a mesma lógica para a `Homolog`.

---

## 6. Como tudo foi verificado

Tudo abaixo foi executado localmente, sem tocar no GitHub nem na AWS.

| Verificação | Comando ou método | Resultado |
|---|---|---|
| Compilação e análise estática | `go build ./...`, `go vet ./...`, `gofmt -l` | Sem erros |
| Testes sem banco (autenticação, rotas, máscara) | `go test ./routes/ ./models/` | Passaram |
| Suíte completa com banco | PostgreSQL 16 em container + `go test ./...` | Passou, incluindo os testes novos de máscara e de exclusão definitiva |
| SAST | `gosec ./...` | Antes: 2 achados. Depois: 0 |
| Dependências | `govulncheck ./...` com Go 1.26.11 | Antes: 15 vulnerabilidades alcançadas. Depois: nenhuma |
| Terraform | `terraform init -backend=false` + `validate` nos três diretórios | Configuração válida |
| Workflows | `actionlint` nos três repositórios | Sem erros |
| Gate de IaC no estado atual | Trivy `config` em cópia limpa dos repositórios, como no CI | ECS e EKS passam (exit 0) |
| Gate de IaC no código original da `main` | Mesmo comando | Reprovaria os dois repositórios (exit 1), inclusive pela checagem `API-GO-0001` |
| Regressão proposital | Reabrir a 5432 para `0.0.0.0/0` numa cópia | Reprovado pela `API-GO-0001` (ECS e EKS) |
| Regressão proposital | Tornar o RDS do ECS público numa cópia | Reprovado pela `AWS-0180` |
| Gate de imagem | `docker build` + Trivy `image --input` | Imagem atual limpa (exit 0) |
| Controle negativo do gate de imagem | Mesma imagem com o binário do Go 1.26.8 | Reprovada com 4 CVEs HIGH da biblioteca padrão (exit 1) |

**Não verificado:**

- Os workflows não rodaram no GitHub.
- O Terraform não foi aplicado na AWS.
- A role do OIDC ainda não existe.

A primeira execução real deve ser acompanhada, principalmente:

- o passo de OIDC (secret `AWS_ROLE_ARN` cadastrado e condição de branch);
- a leitura dos segredos no `EKS.yml`;
- a primeira tarefa do ECS, que depende da permissão de leitura do Secrets Manager.

---

## 7. O que ficou pendente e por quê

| Pendência | Prioridade | Motivo |
|---|---|---|
| Apagar `postgres-data/` do **histórico** do git | 🔴 | Exige reescrever o histórico e fazer push forçado; decisão do dono do repositório |
| Apagar a access key antiga (GitHub e IAM) | 🟡 | Passo manual, depois de validar o OIDC (seção 3, passo 6) |
| Reduzir as permissões da role do OIDC | 🟡 | Precisa levantar o mínimo que o Terraform usa |
| GitHub Environment com aprovação manual | 🟡 | Configuração no GitHub, e muda o `sub` do token OIDC (a política de confiança teria de ser ajustada junto) |
| HTTPS no load balancer | 🟡 | Precisa de domínio e certificado |
| Contêiner sem root e `securityContext` | 🟡 | Muda Dockerfile e `go.yaml`; as exceções `KSV-*` devem ser apagadas quando isso for feito |
| Varredura de segredos (gitleaks) | 🟡 | Não fazia parte dos itens 🔴 |
| `/index` pública com nomes | 🟢 | Página HTML aberta em navegador não envia cabeçalho de chave; precisaria de outro mecanismo de login |

As demais pendências 🟡 e 🟢 estão na coluna "O que falta" do `SSDLC-v2.md`.

---

## 8. Glossário

| Termo | Significado |
|---|---|
| **SAST** | *Static Application Security Testing*. Analisa o código-fonte sem executá-lo, procurando padrões inseguros. Aqui: gosec |
| **SCA** | *Software Composition Analysis*. Verifica se as bibliotecas usadas têm vulnerabilidades conhecidas. Aqui: govulncheck |
| **DAST** | *Dynamic Application Security Testing*. Ataca a aplicação rodando, de fora. Ainda não existe no projeto |
| **IaC** | *Infrastructure as Code*. Infraestrutura descrita em código, aqui em Terraform |
| **OIDC** | *OpenID Connect*. Padrão em que um sistema (GitHub) emite um token assinado sobre quem está executando e outro (AWS) troca esse token por uma credencial temporária |
| **Role (IAM)** | Conjunto de permissões na AWS que pode ser "assumido" temporariamente, ao contrário de um usuário, que tem credenciais permanentes |
| **Secrets Manager** | Serviço da AWS para guardar segredos (senhas, chaves), com controle de acesso e auditoria |
| **Digest / SHA** | Identificador calculado a partir do conteúdo. Se o conteúdo mudar, o identificador muda. Fixar por digest ou SHA garante que o que roda é exatamente o que foi testado |
| **Soft delete** | Exclusão lógica: o registro é marcado como apagado, mas continua no banco |
| **Falha fechada** | Quando algo está mal configurado, o sistema nega o acesso em vez de liberar |
| **Security group** | Firewall da AWS associado a recursos. É *stateful*: a resposta de uma conexão permitida sai automaticamente |
| **Rego** | Linguagem das políticas do Open Policy Agent, usada pelo Trivy para checagens personalizadas |

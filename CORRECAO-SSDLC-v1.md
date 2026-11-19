# Correção da coluna "O que o repo já faz" — SSDLC v1

Este documento explica o que mudou entre a **v0** (`SSDLC-v0.md`) e a **v1** (`SSDLC-v1.md`) do levantamento de segurança do projeto, por que cada mudança foi feita e o que ainda está pendente. Foi escrito para quem está entrando agora no projeto e ainda não conhece a análise.

---

## 1. Contexto: o que é esse levantamento

O **SSDLC** (*Secure Software Development Life Cycle*) é o ciclo de desenvolvimento com segurança embutida em cada fase: requisitos, design, codificação, segredos, dependências, build, testes, infraestrutura, pipeline, deploy, operação e descarte.

O arquivo `SSDLC-v0.md` (o levantamento original) compara cada uma dessas 12 fases com o que o repositório faz hoje. Ele tem três colunas principais:

- **Fase do SSDLC**: a área analisada.
- **O que o repo já faz**: práticas que já existem no código ou nos workflows.
- **O que falta**: lacunas encontradas, com prioridade.

Cada item usa estes marcadores:

| Símbolo | Significado |
|---|---|
| ✅ | Já faz |
| ⚠️ | Faz em parte |
| ❌ | Não faz |
| 🔴 | Prioridade alta |
| 🟡 | Prioridade média |
| 🟢 | Prioridade baixa |

A análise cobre três repositórios:

- `api-go-cicd-aws-ecs`: a API em Go (Gin + GORM), o Dockerfile, o `docker-compose.yml` e os workflows do GitHub Actions.
- `infra-api-go-cicd-aws-ecs`: o Terraform da infraestrutura do ECS.
- `infra-api-go-cicd-aws-eks`: o Terraform do EKS e o Deployment do Kubernetes.

Esta correção mexeu **somente** no repositório da API. Os repositórios de infraestrutura não foram alterados.

---

## 2. Por que existe uma v1

A v0 apontava problemas reais, mas algumas linhas já não refletiam o código depois de correções feitas. A v1 atualiza só essas linhas. O restante do documento é igual à v0.

Ao corrigir o código, cinco linhas da coluna "O que o repo já faz" estavam com ⚠️. A análise foi feita fase a fase:

| Fase | Status na v0 | Situação após a correção |
|---|---|---|
| 1. Requisitos de segurança | ⚠️ | Sem mudança. Falta autenticação, que depende de decisão de projeto. |
| 2. Design e modelagem de ameaças | ⚠️ | Sem mudança. As lacunas estão no Terraform de outro repositório. |
| 3. Codificação segura | ⚠️ | Parte corrigida. A SQL injection foi fechada. Ainda falta tratar `log.Panic` e `err.Error()`. |
| 5. Dependências (SCA) | ⚠️ | Parte corrigida. Dependabot foi configurado. Ainda falta atualizar as bibliotecas e rodar análise de vulnerabilidades no CI. |
| 11. Operação e monitoramento | ⚠️ | Sem mudança. Logs centralizados e alertas são configuração da AWS, não código. |

Nenhuma linha passou de ⚠️ para ✅ por completo, porque em todas ainda há itens em aberto na coluna "O que falta". Por isso o marcador da coluna "já faz" continua ⚠️ e as correções aparecem como novos itens ✅ ao lado.

---

## 3. As mudanças, uma por uma

### 3.1. Fase 3 — SQL injection pelo `id` da URL (prioridade 🔴)

**O problema.** Os endpoints `GET /alunos/:id`, `PATCH /alunos/:id` e `DELETE /alunos/:id` pegavam o `id` da URL como texto e passavam esse texto direto para o GORM:

```go
id := c.Params.ByName("id")
database.DB.First(&aluno, id)
database.DB.Delete(&aluno, id)
```

Quando o valor passado ao GORM **não é um número**, ele é interpretado como um trecho de SQL e colado na cláusula `WHERE`. Por isso um `DELETE /alunos/<algo>` com uma condição sempre verdadeira poderia apagar todos os alunos. É uma SQL injection clássica, só que pelo caminho da URL.

**A correção.** Foi criada a função `idDaURL` em `controllers/controller.go`:

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

Ela converte o texto para inteiro com `strconv.Atoi`. Se a conversão falhar, ou se o número for zero ou negativo, a resposta é `400 Bad Request` com `{"erro": "id inválido"}` e o handler para ali. Nenhum valor chega ao GORM como texto.

Os três handlers (`BuscarAlunoPorID`, `DeletarAluno` e `EditarAluno`) agora começam com:

```go
id, ok := idDaURL(c)
if !ok {
    return
}
```

**Por que isso resolve.** Depois da conversão, o GORM só recebe um `int`. Não existe mais caminho para que o conteúdo da URL vire SQL.

**Efeito colateral corrigido junto.** No `EditarAluno`, se o aluno não existisse, o `First` falhava em silêncio, o `aluno` continuava com ID zero e o `Save` criava um registro novo. Agora o handler responde `404 Not Found`, como o `BuscarAlunoPorID` já fazia.

### 3.2. Fase 3 — modo de produção do Gin (prioridade 🟢)

**O problema.** O `Dockerfile` não definia `GIN_MODE`, então a API subia em modo debug do Gin, que imprime mais informação no log e não deveria estar ativo em produção.

**A correção.** Foi adicionada a linha abaixo ao `Dockerfile`, antes das demais variáveis de ambiente:

```dockerfile
ENV GIN_MODE=release
```

### 3.3. Fase 5 — Dependabot (prioridade 🟡)

**O problema.** Nenhuma ferramenta avisava quando uma dependência Go ou uma action do GitHub Actions ficava desatualizada. O projeto usa `gin v1.7.7`, `gorm v1.22.4` e `golang.org/x/crypto` de 2021.

**A correção.** Foi criado o arquivo `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

Com isso, o GitHub passa a abrir Pull Requests semanais quando há versões novas de módulos Go ou de actions. Ele **não atualiza nada sozinho**: cada PR precisa ser revisado e mergeado.

**Dependência do GitHub.** O Dependabot só funciona depois que o arquivo estiver na branch padrão do repositório. Em branches que não são a padrão, a verificação pode não rodar. Confira em *Settings → Code security* se o Dependabot está habilitado.

### 3.4. Fase 12 — rotina de atualização

A linha de manutenção ganhou o item "Rotina de atualização semanal com Dependabot", que é consequência direta do item 3.3. O que continuou em aberto é a revisão periódica de acessos.

---

## 4. Como verificar as mudanças

**Compilação e análise estática (feito):**

```bash
cd api-go-cicd-aws-ecs
gofmt -l controllers/      # não deve listar arquivos
go vet ./controllers/      # não deve mostrar erros
go build -o /dev/null .    # deve compilar sem erros
```

Essas três verificações passaram.

**Comportamento dos IDs inválidos (feito, com teste descartável).** Foi rodado um teste temporário, depois apagado, que chamou as três rotas com `1 OR 1=1`, `abc`, `0` e `-1`. Todas responderam `400`. Esse teste não precisa de banco de dados.

**Suíte completa (não rodada).** O arquivo `main_test.go` precisa do PostgreSQL do `docker-compose`. Para rodar:

```bash
docker compose up --wait -d
HOST=localhost DBPORT=5432 USER=root PASSWORD=root DBNAME=root go test -v main_test.go
```

Esse passo deve ser feito antes de fazer merge.

**Teste manual de regressão do SQL injection.** Com a API no ar, estas chamadas devem devolver `400`, e não apagar nada:

```bash
curl -i -X DELETE "http://localhost:8000/alunos/1%20OR%201=1"
curl -i "http://localhost:8000/alunos/abc"
curl -i -X PATCH "http://localhost:8000/alunos/0"
```

---

## 5. O que ficou de fora, e por quê

| Item | Fase | Motivo |
|---|---|---|
| Autenticação e autorização nas rotas | 1, 3 | Precisa de decisão de projeto: JWT ou API key, e quais perfis podem apagar e editar. Não é só código. |
| Mascaramento de CPF e RG na listagem | 1 | Depende da regra de negócio: quem pode ver o CPF completo. |
| `publicly_accessible = false` e security group restrito no RDS do ECS | 2, 4, 8 | Está no Terraform de outro repositório e altera o banco de produção. Precisa de revisão antes de aplicar. |
| Senha do RDS fora do código | 4, 8 | Mesmo motivo acima. Exige mudar a forma como o banco é criado. |
| Atualização de `gin`, `gorm` e Go | 5 | Subir `gin` para 1.9.1 pode exigir Go mais novo que o `go 1.15` do `go.mod`. A matriz de CI testa Go 1.17 e 1.18, que podem quebrar. Precisa de um passo próprio. |
| `govulncheck` ou Trivy no `go.yml` | 5, 6, 7 | Exige mudança no pipeline e uma decisão sobre bloquear ou só avisar. |
| `log.Panic` na conexão com o banco | 3 | Trocar por retry muda o comportamento de inicialização. Precisa ser decidido. |
| `err.Error()` devolvido ao cliente | 3 | Trocar por mensagem genérica muda o contrato de resposta da API. |
| Logs centralizados, alertas, CloudTrail | 11 | São configurações da AWS, não do código. |

---

## 6. Próximos passos sugeridos

Na ordem do plano da seção "Plano sugerido, por ordem" do `SSDLC-v1.md`:

1. Rodar a suíte `main_test.go` com o PostgreSQL no ar e confirmar que nada regrediu.
2. Decidir o modelo de autenticação (item 1 do plano). É o maior risco que ainda está aberto.
3. Fechar o RDS do ECS no Terraform (item 3 do plano), em PR separado no repositório de infraestrutura.
4. Tirar `postgres-data/` do git e criar `.gitignore` (item 2 do plano). Isso ainda não foi feito. A pasta aparece como não rastreada no `git status`.
5. Fazer o passo de atualização de `gin` e `gorm` em PR próprio, com a matriz de Go revisada.

---

## 7. Resumo em uma frase

A SQL injection pelo `id` da URL foi fechada, o Gin passou a rodar em modo de produção, o Dependabot foi configurado, e o `EditarAluno` deixou de criar registros fantasmas; o restante dos itens com ⚠️ depende de decisão de projeto, de mudança de infraestrutura ou de configuração da AWS.

# SAST da API de alunos: o script `scripts/sast.sh`

Este documento explica o script de análise estática de segurança (SAST) do projeto: o que ele faz, como usar e, principalmente, **como ele foi construído, passo a passo, por que cada passo existe e de onde veio cada decisão**. Foi escrito para quem está chegando agora no projeto e no levantamento SSDLC.

---

## 1. Contexto: o que é SAST e por que um script próprio

**SAST** (*Static Application Security Testing*) é a análise de segurança feita **lendo o código-fonte, sem executar o programa**. Ela procura padrões que costumam virar vulnerabilidade: SQL montado com texto, senha escrita no código, dado pessoal em log, rota sem autenticação.

Desde o SSDLC v2, o CI já rodava o **gosec**, um scanner de segurança genérico para Go. A pergunta que deu origem a este script foi: **o gosec pegaria os problemas reais que este projeto já teve?**

Para responder, rodamos o gosec v2.30.0 no código **anterior** às correções do SSDLC v1 (commit `35450c1^`). Resultado:

| O que o levantamento SSDLC achou à mão | O gosec achou? |
|---|---|
| SQL injection: `DB.First(&aluno, id)` com o `id` cru da URL, em 3 lugares | **Não** |
| 7 rotas de `/alunos` sem nenhuma autenticação | **Não** |
| `Delete` comum, que deixa CPF e RG guardados no banco | **Não** |
| Erro de `r.Run()` e de `AutoMigrate` ignorado | Sim (regra G104) |

E num segundo teste, com um arquivo escrito de propósito com 2 SQL injections, 2 credenciais no código e CPF em log, o gosec respondeu **"nenhum problema"**.

O motivo: o gosec conhece a biblioteca padrão do Go (`database/sql`, `crypto`, `net/http`), mas **não conhece o GORM nem o Gin**, nem as regras de negócio deste projeto (quem pode ver CPF, quais rotas exigem chave). Ele continua útil e continua no script, mas sozinho não protege contra os erros que este projeto de fato cometeu.

Daí a decisão: **um script que junta as ferramentas genéricas com regras próprias, escritas a partir do histórico do projeto.**

> Observação: o **govulncheck** (que procura vulnerabilidades conhecidas nas dependências) não é SAST, é SCA (*Software Composition Analysis*). Ele continua num passo separado do CI.

---

## 2. Como usar

```bash
# Na raiz do repositório
./scripts/sast.sh

# Analisando outra cópia do código (por exemplo, uma versão antiga)
./scripts/sast.sh /caminho/para/outra/copia
```

Precisa só do **Go** instalado. O gosec é baixado na versão certa pelo próprio script.

**Código de saída:**

| Código | Significado |
|---|---|
| `0` | Aprovado. Pode haver avisos de severidade MÉDIA. |
| `1` | Reprovado: go vet, gofmt, gosec ou alguma regra própria de severidade ALTA. |
| `2` | Não deu para rodar (Go ausente, pasta sem `go.mod`). |

**Relatórios** (pasta `relatorio-sast/`, fora do git):

| Arquivo | Conteúdo |
|---|---|
| `go-vet.txt` | Saída do go vet |
| `gosec.sarif` | Achados do gosec no formato SARIF |
| `regras-proprias.txt` | Achados das regras próprias, inclusive os aceitos |

**Exemplo de saída no código atual:**

```
== 1/3 go vet e gofmt ==
OK go vet não encontrou problemas
OK todos os arquivos seguem o gofmt

== 2/3 gosec v2.30.0 ==
OK gosec não encontrou problemas

== 3/3 regras próprias do projeto ==
[MEDIA] GO-SAST-007 conexão com o banco sem TLS (sslmode=disable)
    database/db.go:18  stringDeConexao := "host=" + ... + " sslmode=disable"
AVISO 1 achado(s) de severidade MÉDIA (não reprovam)

== Resultado ==
OK SAST aprovado
```

---

## 3. Como o script foi construído, passo a passo

### Passo 1 — Medir antes de construir

**O que foi feito:** rodar o gosec no código antigo e num arquivo com falhas plantadas, como descrito na seção 1.

**Por quê:** sem essa medição, o script seria uma lista de regras "que parecem boas". Com ela, cada regra própria responde a um problema que **comprovadamente** passaria pelo CI.

**De onde veio:** o código antigo é o commit anterior ao `35450c1` (correção do SQL injection no SSDLC v1). A lista de problemas vem do `SSDLC-v0.md`, `SSDLC-v1.md` e `SSDLC-v2.md`.

### Passo 2 — O esqueleto em Bash

**O que foi feito:** o script começa com:

```bash
set -euo pipefail
```

- `-e`: para na primeira falha inesperada, em vez de seguir como se nada tivesse acontecido.
- `-u`: variável não definida é erro (evita, por exemplo, `rm -rf "$PASTA/"` com `PASTA` vazia).
- `-o pipefail`: num `a | b`, a falha de `a` não é escondida pelo sucesso de `b`.

Depois ele descobre a raiz do projeto (a pasta acima de `scripts/`, ou a pasta passada como argumento), confere se existe `go.mod` e recria a pasta `relatorio-sast/`.

**Por que Bash:** roda igual na máquina de quem desenvolve e no runner do GitHub (Ubuntu), sem instalar nada além do Go. Assim **o CI e a pessoa rodam exatamente o mesmo comando**, e "passou na minha máquina" significa "vai passar no CI".

**Por que aceitar outra pasta como argumento:** foi o que permitiu testar o script contra o código antigo sem mexer no repositório (passo 10).

**Detalhe:** as cores só são usadas quando a saída é um terminal (`[[ -t 1 ]]`). No CI e em arquivos, o texto sai limpo, sem códigos de escape.

**De onde veio:** `set -euo pipefail` é a prática recomendada para scripts Bash; o shellcheck (ferramenta de análise de scripts shell) foi usado para revisar o script e não aponta nada.

### Passo 3 — Escolher quais arquivos analisar

**O que foi feito:** a lista de arquivos `.go` vem de `git ls-files`. Fora de um repositório git, o script usa `find` pulando `postgres-data/`, `vendor/` e `.git/`.

**Por quê:** a pasta `postgres-data/` ainda existe no disco de quem rodou o docker-compose (é o banco local, com arquivos do usuário root). O `git ls-files` só lista o que está versionado, então respeita o `.gitignore` e não tropeça nessa pasta.

As regras próprias olham só os arquivos **de produção** (sem `_test.go`). Os testes usam chaves falsas como `"chave-admin"` de propósito, e isso não é vulnerabilidade.

### Passo 4 — Etapa 1: `go vet` e `gofmt`

**go vet** é o verificador oficial que vem junto com o Go. Ele acha erros de programação que compilam mas estão errados (formato de `Printf` que não bate com os argumentos, cópia de mutex, código inalcançável). Não é uma ferramenta de segurança, mas bug de programação vira bug de segurança com frequência, e o custo é zero: já vem instalado.

**gofmt** é o formatador oficial do Go. O script reprova arquivos fora do padrão por um motivo específico: **as regras próprias contam com o espaçamento que o gofmt produz.** Por exemplo, a regra de credencial (GO-SAST-003) diferencia:

```go
senha := "abc123"                 // atribuição: gofmt sempre põe espaço antes e depois do :=
" password=" + os.Getenv("...")   // pedaço de texto: sem espaço
```

Sem a garantia do gofmt, alguém poderia escrever `senha:="abc123"` e a regra não pegaria. Exigir gofmt fecha essa porta. (O código antigo, aliás, reprova aqui: o `database/db.go` original não seguia o gofmt.)

### Passo 5 — Etapa 2: gosec, com versão fixa

**O que foi feito:**

```bash
go run github.com/securego/gosec/v2/cmd/gosec@v2.30.0 \
  -quiet -exclude-dir=postgres-data \
  -fmt=sarif -out=relatorio-sast/gosec.sarif \
  -stdout -verbose=text ./...
```

**Por que `go run módulo@versão`:**
- Baixa **exatamente** a v2.30.0, a mesma que estava no CI.
- O Go confere o checksum do download no **sum.golang.org** (banco público de checksums dos módulos Go). Se alguém trocar o código daquela versão, o download é recusado.
- Não altera o `go.mod` do projeto, porque o gosec é ferramenta, não dependência da API.
- Não precisa de `go install` antes. Na segunda execução, vem do cache.

**Por que versão fixa e não `@latest`:** uma versão nova do gosec pode trazer regras novas e reprovar o CI num dia sem nenhuma mudança no código. Atualizar a versão é uma decisão consciente, feita na linha `GOSEC_VERSAO` do script. O Dependabot não atualiza isso sozinho; vale revisar de tempos em tempos.

**Por que SARIF:** SARIF (*Static Analysis Results Interchange Format*) é o formato padrão (OASIS) para resultados de análise estática. O GitHub Code Scanning, o VS Code e outras ferramentas sabem ler. A tela continua mostrando texto (`-verbose=text`) para leitura humana.

### Passo 6 — Etapa 3: regras próprias

Cada regra tem um **ID** (`GO-SAST-00X`), uma **severidade** e um **comentário no script** explicando o que pega e por quê. Todas leem o código com `grep` ou `awk`.

| ID | Severidade | O que pega | De onde veio |
|---|---|---|---|
| GO-SAST-001 | ALTA | Valor da requisição (`c.Param`, `c.Query`, `c.Params.ByName`...) passado direto para o GORM | SQL injection do SSDLC v0, corrigido no v1 (`35450c1`) |
| GO-SAST-002 | ALTA | SQL montado com `+` ou `fmt.Sprintf` dentro de `Where`, `Raw`, `Exec`... | Mesma família do item acima, para SQL escrito à mão |
| GO-SAST-003 | ALTA | Senha, segredo, token ou chave de API com valor literal no código | Item 🔴 de segredos do SSDLC v2: segredos vêm do Secrets Manager |
| GO-SAST-004 | ALTA | CPF ou RG passado para `log.*`, `fmt.Print*` ou `slog.*` | Política de dados pessoais em `REQUISITOS-SEGURANCA.md` |
| GO-SAST-005 | ALTA | Rota registrada direto no roteador (`r.POST`, `r.GET("/alunos"...)`), fora dos grupos com `autenticacao.Exige` | Item 🔴 de autenticação do SSDLC v2 |
| GO-SAST-006 | ALTA | `.Delete(` sem `Unscoped()` | Política LGPD: exclusão definitiva, sem *soft delete* |
| GO-SAST-007 | MÉDIA | `sslmode=disable` na conexão com o banco | Achado novo deste script |
| GO-SAST-008 | MÉDIA | `gin.SetMode(gin.DebugMode)` no código | Correção do `GIN_MODE=release` no SSDLC v1 |

Os detalhes de cada uma:

**GO-SAST-001: a regra mais importante.** No GORM, `DB.First(&aluno, id)` com `id` do tipo `string` **não** é tratado como número: o texto vira um pedaço do SQL. Um `id` igual a `1 OR 1=1` lê (ou, no `Delete`, apaga) qualquer linha. Foi exatamente o bug do v0.

Um `grep` simples não basta, porque a linha perigosa (`DB.First(&aluno, id)`) parece idêntica a uma segura quando `id` é um `int`. Por isso a regra usa `awk` e faz um **rastreamento simples de variável dentro da função**:

1. Ao ver `id := c.Params.ByName("id")`, anota que `id` veio da requisição ("contaminada").
2. Ao ver um método do banco (`First`, `Find`, `Delete`, `Where`, `Raw`...) recebendo `id` como argumento ou concatenado com `+`, acusa.
3. Ao começar uma nova `func`, esquece as anotações.

No código atual, o `id` vem de `idDaURL(c)`, que converte com `strconv.Atoi` e devolve um `int`, então não é anotado e não há achado. E o `cpf` usado em `Where(&models.Aluno{CPF: cpf})` também não é acusado, porque ali ele é campo de struct, e o GORM transforma isso em parâmetro (`WHERE cpf = $1`), que é seguro.

**GO-SAST-005.** A regra encontra a variável que recebe `gin.Default()` ou `gin.New()` (no projeto, `r`) e acusa qualquer `r.POST/PUT/PATCH/DELETE`, ou `r.GET/Any/Handle` com caminho começando em `/alunos`. As rotas certas estão em `leitura.GET(...)` e `admin.POST(...)`, que são grupos com o middleware de autenticação. As rotas públicas (`r.GET("/:nome")`, `r.GET("/index")`) não são acusadas.

**GO-SAST-006.** O model `Aluno` usa `gorm.Model`, que tem o campo `DeletedAt`. Com ele, um `Delete` comum só preenche a data e esconde a linha, mas o CPF e o RG continuam no banco. A regra acusa qualquer `.Delete(` que não esteja junto de `Unscoped()`.

**GO-SAST-007.** Este é um achado **novo**, que o levantamento manual não tinha registrado: a string de conexão usa `sslmode=disable`, então usuário, senha e dados trafegam sem criptografia entre a API e o RDS. Vale virar item 🟡 na próxima versão do SSDLC.

### Passo 7 — Severidade: o que reprova e o que só avisa

**Regra do gate:** ALTA reprova, MÉDIA só avisa.

**Por quê:** um gate que reprova por tudo faz as pessoas aprenderem a ignorá-lo (ou a desligá-lo). O `sslmode=disable` é um bom exemplo: é um problema real na AWS, mas o Postgres local do docker-compose e o banco do CI não têm TLS. Se reprovasse, ninguém conseguiria rodar o projeto localmente até a correção completa. Como aviso, ele aparece em toda execução e não cai no esquecimento.

### Passo 8 — Como aceitar um achado (`sast:ignore`)

Todo scanner erra às vezes, e às vezes um risco é aceito conscientemente. Para isso:

```go
// sast:ignore GO-SAST-004 log de auditoria aprovado pelo time de segurança
log.Println("RG mascarado:", aluno.Mascarado().RG)
```

Regras:
- O comentário vai **na mesma linha ou na linha de cima**.
- Precisa citar **o ID da regra**: aceitar a GO-SAST-004 não aceita a GO-SAST-003 na mesma linha.
- Precisa de **um motivo**. `// sast:ignore GO-SAST-004` sozinho **não vale** e o achado continua reprovando (testado no passo 10).
- Achados aceitos aparecem no resumo ("1 achado(s) aceito(s)") e no relatório com a marca `[ACEITO]`. Nada é escondido.

**De onde veio:** o mesmo modelo usado no projeto para o Trivy (`#trivy:ignore:AWS-xxxx` com justificativa, no SSDLC v2) e o `#nosec` do próprio gosec. Exigir o motivo garante que, meses depois, alguém saiba por que aquilo foi aceito.

### Passo 9 — Ligar no CI

No `.github/workflows/go.yml`, job `seguranca`, o passo que instalava e rodava o gosec foi trocado por:

```yaml
- name: SAST (scripts/sast.sh)
  run: ./scripts/sast.sh

- name: Relatórios do SAST
  if: always()
  uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
  with:
    name: relatorio-sast
    path: relatorio-sast/
```

- O job `build` já depende do job `seguranca` (`needs: [test, seguranca]`). Então, **se o SAST reprovar, não há build, imagem nem deploy.**
- O `if: always()` guarda os relatórios mesmo quando o SAST reprova, que é justamente quando eles são mais úteis.
- A action segue fixada por SHA, como todas as outras desde o SSDLC v2.
- O govulncheck continua no passo seguinte, separado.

Também foi adicionado `relatorio-sast/` ao `.gitignore`.

### Passo 10 — Testar o próprio scanner

Um scanner que nunca reprova pode estar quebrado. O script foi testado em três cenários:

| Cenário | Resultado esperado | Resultado obtido |
|---|---|---|
| **Código atual** | Aprova | Aprovado, com 1 aviso MÉDIO (`sslmode=disable`) |
| **Código antigo** (antes do SSDLC v1) | Reprova com os problemas conhecidos | Reprovado: gofmt, gosec (2 × G104), **3 × GO-SAST-001** (os SQL injections), **7 × GO-SAST-005** (as rotas sem autenticação), **1 × GO-SAST-006** (soft delete) |
| **Cópia com falhas plantadas** | Reprova regra por regra | Reprovado: GO-SAST-001, 002, 003 (2×), 004, 008; o `sast:ignore` com motivo foi aceito e o sem motivo foi recusado. O gosec, no mesmo arquivo, não achou nada. |

Os testes também encontraram **falsos positivos**, que foram corrigidos antes da versão final:

1. `const chaveDoContexto = "perfil"` era acusado como credencial, porque "chave" estava na lista de palavras. Em português, "chave" aparece em nomes inocentes, então saiu da lista (ficou só `chave_api`/`chaveApi`).
2. O trecho `" password=" + os.Getenv("PASSWORD")` da string de conexão era acusado como senha no código. Foi aí que a regra passou a exigir o espaçamento do gofmt (passo 4).
3. `fmt.Sprintf("... rg = '%s'", ...)` era acusado como "RG em log", mas `Sprintf` só monta texto. A regra passou a olhar só funções que escrevem saída (`log.*`, `fmt.Print*`, `slog.*`).

Por fim, o próprio script passou no **shellcheck** e o workflow passou no **actionlint**.

---

## 4. Limitações (o que o script não faz)

Seja honesto com a ferramenta: regras baseadas em `grep` e `awk` leem **texto**, não entendem o programa como o compilador entende.

- **O rastreamento da GO-SAST-001 é simples.** Ele segue a variável só dentro da mesma função e só pelo nome. Não pega um valor que passa por outra função antes de chegar ao banco, nem um valor renomeado (`x := id`).
- **Uma instrução quebrada em várias linhas** pode escapar das regras que olham linha a linha.
- **Não substitui revisão de código nem teste.** Regras de autorização mais finas (quem pode ver qual aluno) continuam dependendo de teste automatizado.

**Próximo passo natural**, se o projeto crescer: trocar as regras próprias por regras do **Semgrep** ou consultas do **CodeQL**. Essas ferramentas entendem a estrutura do código e seguem o dado entre funções (análise de *taint* de verdade). As regras deste script, com IDs, exemplos e motivos, servem de especificação para essa migração.

---

## 5. Como adicionar uma regra nova

1. Escolha o próximo ID (`GO-SAST-009`) e a severidade (ALTA reprova, MÉDIA avisa).
2. No script, na etapa 3, escreva um comentário dizendo **o que** a regra pega e **por que** isso é perigoso neste projeto.
3. Se uma expressão regular basta:
   ```bash
   registra GO-SAST-009 ALTA "descrição curta" \
     < <(procura 'expressão regular')
   ```
   Se precisar de contexto (como a 001 e a 005), escreva uma função com `awk`, que imprima `arquivo:linha:código`.
4. **Teste nos dois sentidos:** escreva um trecho que deve ser acusado e confirme que é; rode no código atual e confirme que não aparece falso positivo.
5. Atualize a tabela da seção 3, passo 6, deste documento.

> Por que `registra ... < <(comando)` e não `comando | registra ...`? Com o `|`, o Bash roda a função `registra` num subshell (um processo separado), e os contadores de achados se perdem quando ele termina. O script reprovaria por nada. O `< <(...)` mantém a função no processo principal.

---

## 6. Glossário

| Termo | Significado |
|---|---|
| **SAST** | Análise de segurança lendo o código, sem executar. |
| **SCA** | Análise das dependências atrás de vulnerabilidades conhecidas (o govulncheck). |
| **gosec** | Scanner SAST open source para Go, mantido pela comunidade securego. |
| **go vet** | Verificador oficial do Go para erros de programação. |
| **gofmt** | Formatador oficial do Go. |
| **SARIF** | Formato padrão para resultados de análise estática. |
| **Taint (contaminação)** | Técnica que segue um dado vindo de fora (da requisição) até um ponto perigoso (o banco). |
| **Falso positivo** | Achado que não é problema de verdade. |
| **Soft delete** | Exclusão lógica: a linha só é marcada como apagada e os dados continuam no banco. |
| **Gate** | Etapa do CI que impede o avanço (build, deploy) quando reprova. |

#!/usr/bin/env bash
#
# sast.sh — análise estática de segurança (SAST) da API de alunos.
#
# Uso:
#   ./scripts/sast.sh            analisa o repositório onde o script está
#   ./scripts/sast.sh <pasta>    analisa outra cópia do código (ex.: uma versão antiga)
#
# O script roda três etapas e só termina com sucesso (código 0) se nenhuma
# reprovar:
#   1. go vet          verificador oficial do Go (erros de programação)
#   2. gosec           scanner de segurança genérico para Go
#   3. regras próprias padrões perigosos deste projeto que o gosec não conhece
#
# Os relatórios ficam em <pasta>/relatorio-sast/.
#
# Para aceitar um achado das regras próprias, escreva na mesma linha ou na
# linha de cima:   // sast:ignore GO-SAST-00X motivo do aceite
# Sem o motivo, o comentário não vale.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Preparação
# ---------------------------------------------------------------------------

# Versão fixa do gosec: a mesma do CI. Trocar a versão é uma decisão
# consciente, feita aqui, e não algo que acontece sozinho.
readonly GOSEC_VERSAO="v2.30.0"
readonly GOSEC_MODULO="github.com/securego/gosec/v2/cmd/gosec@${GOSEC_VERSAO}"

PASTA_DO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "${1:-${PASTA_DO_SCRIPT}/..}" && pwd)"
RELATORIO="${RAIZ}/relatorio-sast"

# Cores só quando a saída é um terminal (no CI e em arquivo, texto puro).
if [[ -t 1 ]]; then
  VERMELHO=$'\e[31m'; AMARELO=$'\e[33m'; VERDE=$'\e[32m'; NEGRITO=$'\e[1m'; NORMAL=$'\e[0m'
else
  VERMELHO=""; AMARELO=""; VERDE=""; NEGRITO=""; NORMAL=""
fi

etapa() { printf '\n%s== %s ==%s\n' "$NEGRITO" "$1" "$NORMAL"; }
falha() { printf '%sREPROVADO%s %s\n' "$VERMELHO" "$NORMAL" "$1"; }
aviso() { printf '%sAVISO%s %s\n' "$AMARELO" "$NORMAL" "$1"; }
ok()    { printf '%sOK%s %s\n' "$VERDE" "$NORMAL" "$1"; }

command -v go >/dev/null || { echo "Go não encontrado no PATH." >&2; exit 2; }
[[ -f "${RAIZ}/go.mod" ]] || { echo "Não achei go.mod em ${RAIZ}." >&2; exit 2; }

cd "$RAIZ"
rm -rf "$RELATORIO"
mkdir -p "$RELATORIO"

# Arquivos .go que entram na análise das regras próprias. Num repositório git,
# só os versionados (respeita o .gitignore e pula o postgres-data local). Fora
# do git, procura no disco ignorando pastas que não são código.
listar_arquivos_go() {
  if git -C "$RAIZ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$RAIZ" ls-files -- '*.go'
  else
    find . \( -path ./postgres-data -o -path ./vendor -o -path ./.git \) -prune \
      -o -type f -name '*.go' -print | sed 's|^\./||'
  fi
}
mapfile -t ARQUIVOS_GO < <(listar_arquivos_go)
mapfile -t ARQUIVOS_PRODUCAO < <(printf '%s\n' "${ARQUIVOS_GO[@]}" | grep -v '_test\.go$' || true)

printf 'Analisando %s (%d arquivos .go, %d fora de teste)\n' \
  "$RAIZ" "${#ARQUIVOS_GO[@]}" "${#ARQUIVOS_PRODUCAO[@]}"

REPROVOU=0

# ---------------------------------------------------------------------------
# 1. go vet
# ---------------------------------------------------------------------------
etapa "1/3 go vet e gofmt"
if go vet ./... 2>"${RELATORIO}/go-vet.txt"; then
  ok "go vet não encontrou problemas"
else
  cat "${RELATORIO}/go-vet.txt"
  falha "go vet encontrou problemas (detalhes em relatorio-sast/go-vet.txt)"
  REPROVOU=1
fi

# As regras próprias (etapa 3) contam com o espaçamento padrão do gofmt. Um
# arquivo fora do padrão poderia esconder um achado, então ele reprova aqui.
mapfile -t SEM_GOFMT < <(gofmt -l "${ARQUIVOS_GO[@]}")
if (( ${#SEM_GOFMT[@]} == 0 )); then
  ok "todos os arquivos seguem o gofmt"
else
  printf '    %s\n' "${SEM_GOFMT[@]}"
  falha "arquivos fora do gofmt (corrija com: gofmt -w <arquivo>)"
  REPROVOU=1
fi

# ---------------------------------------------------------------------------
# 2. gosec
# ---------------------------------------------------------------------------
etapa "2/3 gosec ${GOSEC_VERSAO}"
# go run <módulo>@<versão> baixa a ferramenta exata, confere o checksum no
# sum.golang.org e executa, sem mexer no go.mod do projeto.
# Saída em texto na tela e em SARIF no arquivo (formato que o GitHub e as IDEs
# entendem).
if go run "$GOSEC_MODULO" \
    -quiet \
    -exclude-dir=postgres-data \
    -fmt=sarif -out="${RELATORIO}/gosec.sarif" \
    -stdout -verbose=text \
    ./...; then
  ok "gosec não encontrou problemas"
else
  falha "gosec encontrou problemas (detalhes em relatorio-sast/gosec.sarif)"
  REPROVOU=1
fi

# ---------------------------------------------------------------------------
# 3. Regras próprias
# ---------------------------------------------------------------------------
etapa "3/3 regras próprias do projeto"

ACHADOS="${RELATORIO}/regras-proprias.txt"
: >"$ACHADOS"
TOTAL_ALTA=0
TOTAL_MEDIA=0
TOTAL_ACEITOS=0

# Um achado é aceito se a própria linha ou a linha de cima tiver
# "sast:ignore <ID> <motivo>".
foi_aceito() {
  local arquivo="$1" linha="$2" id="$3" trecho
  trecho="$(sed -n "$(( linha > 1 ? linha - 1 : 1 )),${linha}p" "$arquivo")"
  grep -qE "sast:ignore[[:space:]]+${id}[[:space:]]+[^[:space:]]" <<<"$trecho"
}

# registra <ID> <ALTA|MEDIA> <título> ; lê "arquivo:linha:código" da entrada.
# A entrada chega por "< <(comando)" e não por pipe: com pipe a função rodaria
# num subshell e os contadores TOTAL_* se perderiam.
registra() {
  local id="$1" severidade="$2" titulo="$3" arquivo linha codigo cor
  while IFS=: read -r arquivo linha codigo; do
    [[ -z "$arquivo" ]] && continue
    if foi_aceito "$arquivo" "$linha" "$id"; then
      TOTAL_ACEITOS=$((TOTAL_ACEITOS + 1))
      printf '[ACEITO] %s %s:%s\n' "$id" "$arquivo" "$linha" >>"$ACHADOS"
      continue
    fi
    if [[ "$severidade" == "ALTA" ]]; then
      TOTAL_ALTA=$((TOTAL_ALTA + 1)); cor="$VERMELHO"
    else
      TOTAL_MEDIA=$((TOTAL_MEDIA + 1)); cor="$AMARELO"
    fi
    printf '%s[%s]%s %s %s\n    %s:%s  %s\n' \
      "$cor" "$severidade" "$NORMAL" "$id" "$titulo" "$arquivo" "$linha" "${codigo#"${codigo%%[![:space:]]*}"}"
    printf '[%s] %s %s — %s:%s: %s\n' "$severidade" "$id" "$titulo" "$arquivo" "$linha" "$codigo" >>"$ACHADOS"
  done
}

# Procura uma expressão regular nos arquivos de produção. Sai no formato
# arquivo:linha:código. "|| true" porque grep sem resultado devolve 1.
# Com -i, ignora maiúsculas e minúsculas.
procura() {
  local opcoes=(-nHE)
  if [[ "$1" == "-i" ]]; then opcoes+=(-i); shift; fi
  [[ ${#ARQUIVOS_PRODUCAO[@]} -eq 0 ]] && return 0
  grep "${opcoes[@]}" -- "$1" "${ARQUIVOS_PRODUCAO[@]}" || true
}

# GO-SAST-001 — valor da requisição passado direto para o GORM (ALTA)
# No GORM, First/Find/Take/Last/Delete(&x, valor) com valor do tipo string vira
# SQL cru: id="1 OR 1=1" apaga ou lê qualquer linha. Foi o SQL injection do
# SSDLC v0, e o gosec não acusa porque não conhece a API do GORM.
# A regra segue a variável dentro da função: anota quem recebeu c.Param,
# c.Query etc. e acusa se ela aparecer como argumento de um método do banco.
regra_gorm_valor_da_requisicao() {
  local arquivo
  for arquivo in "${ARQUIVOS_PRODUCAO[@]}"; do
    awk -v arquivo="$arquivo" '
      /^func / { delete contaminada }
      {
        if (match($0, /([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:?=[[:space:]]*c\.(Param|Params\.ByName|Query|DefaultQuery|PostForm|GetHeader)\(/)) {
          nome = substr($0, RSTART, RLENGTH)
          sub(/[[:space:]]*:?=.*/, "", nome)
          contaminada[nome] = 1
        }
      }
      /\.(First|Find|Take|Last|Delete|Where|Raw|Exec|Order|Group|Having|Joins|Select)\(/ {
        if ($0 ~ /\.(First|Find|Take|Last|Delete|Where|Raw|Exec|Order|Group|Having|Joins|Select)\([^)]*c\.(Param|Params\.ByName|Query|DefaultQuery|PostForm|GetHeader)\(/) {
          print arquivo ":" NR ":" $0; next
        }
        for (v in contaminada) {
          if ($0 ~ ("[(,][[:space:]]*" v "[[:space:]]*[),]") || $0 ~ ("\\+[[:space:]]*" v "([^A-Za-z0-9_]|$)")) {
            print arquivo ":" NR ":" $0; next
          }
        }
      }
    ' "$arquivo"
  done
}
registra GO-SAST-001 ALTA "valor da requisição usado direto como condição do GORM (SQL injection)" \
  < <(regra_gorm_valor_da_requisicao)

# GO-SAST-002 — SQL montado com concatenação ou fmt.Sprintf (ALTA)
# Mesmo sem saber de onde o valor vem, montar o texto do SQL na mão abre
# espaço para injeção. O certo é usar "?" e passar o valor como parâmetro.
registra GO-SAST-002 ALTA "SQL montado com concatenação ou Sprintf" \
  < <(procura '\.(Where|Raw|Exec|Order|Group|Having|Joins|Select)\([[:space:]]*("[^"]*"[[:space:]]*\+|fmt\.Sprintf)')

# GO-SAST-003 — credencial escrita no código (ALTA)
# Senha, segredo, token ou chave de API com valor literal. Desde o SSDLC v2 os
# segredos vêm do ambiente (Secrets Manager). Arquivos de teste ficam de fora.
# A regra procura um NOME de variável, constante ou campo que contenha a
# palavra (senhaDoBanco, apiKey, Password...) seguido de valor literal. Ela
# exige o espaçamento que o gofmt sempre produz ("x := ", "X = ", "Campo: ")
# para não confundir com um trecho dentro de string, como o "password=" da
# string de conexão, que só monta o texto e lê a senha do ambiente.
# "chave" sozinho ficou de fora: em português aparece em nomes inocentes
# (chaveDoContexto).
registra GO-SAST-003 ALTA "credencial com valor escrito no código" \
  < <(procura -i '[a-z0-9_]*(password|passwd|senha|secret|segredo|token|api_?key|chave_?api)[a-z0-9_]*([[:space:]]+(:=|=)[[:space:]]+|:[[:space:]]+)"[^"]{6,}"')

# GO-SAST-004 — CPF ou RG em log (ALTA)
# Log é lido por mais gente e guardado por mais tempo que o banco. A política
# em REQUISITOS-SEGURANCA.md só deixa o perfil admin ver CPF e RG completos.
# Só conta função que escreve saída (log.*, fmt.Print*, slog.*); fmt.Sprintf
# monta texto e não é log.
registra GO-SAST-004 ALTA "CPF ou RG escrito em log" \
  < <(procura '(log\.(Print|Fatal|Panic)[a-z]*|fmt\.(F?Print)[a-z]*|slog\.(Debug|Info|Warn|Error|Log)[A-Za-z]*)\(.*([^A-Za-z]CPF|[^A-Za-z]RG|\.Cpf|\.Rg|[^A-Za-z]cpf[^A-Za-z]|[^A-Za-z]rg[^A-Za-z])')

# GO-SAST-005 — rota de alunos ou de escrita fora dos grupos autenticados (ALTA)
# As rotas de /alunos só podem existir dentro de r.Group(..., autenticacao.Exige(...)).
# Uma rota registrada direto no roteador (r.POST, r.GET("/alunos"...)) não
# passa pela checagem da X-API-Key.
regra_rota_sem_autenticacao() {
  local arquivo
  for arquivo in "${ARQUIVOS_PRODUCAO[@]}"; do
    awk -v arquivo="$arquivo" '
      match($0, /([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:?=[[:space:]]*gin\.(Default|New)\(\)/) {
        nome = substr($0, RSTART, RLENGTH); sub(/[[:space:]]*:?=.*/, "", nome); roteador[nome] = 1
      }
      {
        for (r in roteador) {
          if ($0 ~ ("(^|[^A-Za-z0-9_.])" r "\\.(POST|PUT|PATCH|DELETE)\\(") ||
              $0 ~ ("(^|[^A-Za-z0-9_.])" r "\\.(GET|Any|Handle)\\([^,]*\"/alunos")) {
            print arquivo ":" NR ":" $0
          }
        }
      }
    ' "$arquivo"
  done
}
registra GO-SAST-005 ALTA "rota registrada fora dos grupos com autenticação" \
  < <(regra_rota_sem_autenticacao)

# GO-SAST-006 — exclusão lógica de aluno (ALTA)
# O model usa gorm.Model, que tem DeletedAt: um Delete comum só marca a linha
# como apagada e o CPF e o RG continuam no banco. A política exige exclusão
# definitiva, com Unscoped().
registra GO-SAST-006 ALTA "Delete sem Unscoped() deixa CPF e RG guardados (soft delete)" \
  < <(procura '\.Delete\(' | grep -v 'Unscoped()')

# GO-SAST-007 — conexão com o banco sem TLS (MÉDIA)
# sslmode=disable manda usuário, senha e dados em texto puro pela rede. Não
# reprova porque o Postgres local do docker-compose não tem TLS; vira aviso.
registra GO-SAST-007 MEDIA "conexão com o banco sem TLS (sslmode=disable)" \
  < <(procura 'sslmode=disable')

# GO-SAST-008 — Gin forçado em modo debug (MÉDIA)
# O modo debug escreve cada rota e cada requisição no log. O Dockerfile define
# GIN_MODE=release desde o SSDLC v1; forçar debug no código desfaz isso.
registra GO-SAST-008 MEDIA "Gin forçado em modo debug" \
  < <(procura 'gin\.SetMode\(gin\.DebugMode\)')

if (( TOTAL_ALTA == 0 && TOTAL_MEDIA == 0 )); then
  ok "nenhum achado nas regras próprias"
fi
(( TOTAL_ALTA > 0 )) && { falha "${TOTAL_ALTA} achado(s) de severidade ALTA"; REPROVOU=1; }
(( TOTAL_MEDIA > 0 )) && aviso "${TOTAL_MEDIA} achado(s) de severidade MÉDIA (não reprovam)"
(( TOTAL_ACEITOS > 0 )) && aviso "${TOTAL_ACEITOS} achado(s) aceito(s) com sast:ignore"

# ---------------------------------------------------------------------------
# Resultado
# ---------------------------------------------------------------------------
etapa "Resultado"
echo "Relatórios em ${RELATORIO}/"
if (( REPROVOU )); then
  falha "SAST reprovou"
  exit 1
fi
ok "SAST aprovado"

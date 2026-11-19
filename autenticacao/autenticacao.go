// Package autenticacao protege as rotas de alunos com chave de API.
//
// Existem dois perfis:
//   - leitura: pode consultar alunos; CPF e RG voltam mascarados.
//   - admin: pode consultar, criar, editar e apagar; vê CPF e RG completos.
//
// As chaves vêm das variáveis de ambiente API_KEY_LEITURA e API_KEY_ADMIN e
// são enviadas pelo cliente no cabeçalho X-API-Key. Se uma chave não estiver
// configurada, nenhum valor é aceito para ela (falha fechada).
package autenticacao

import (
	"crypto/subtle"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

// Perfil é o nível de acesso de quem fez a requisição.
type Perfil int

const (
	PerfilNenhum Perfil = iota
	PerfilLeitura
	PerfilAdmin
)

// Cabecalho é o cabeçalho HTTP que carrega a chave de API.
const Cabecalho = "X-API-Key"

const chaveDoContexto = "perfil"

// Chaves guarda as chaves aceitas para cada perfil.
type Chaves struct {
	Leitura string
	Admin   string
}

// ChavesDoAmbiente lê as chaves das variáveis de ambiente.
func ChavesDoAmbiente() Chaves {
	chaves := Chaves{
		Leitura: os.Getenv("API_KEY_LEITURA"),
		Admin:   os.Getenv("API_KEY_ADMIN"),
	}
	if chaves.Leitura == "" && chaves.Admin == "" {
		log.Println("AVISO: API_KEY_LEITURA e API_KEY_ADMIN vazias; todas as rotas de alunos vão responder 401")
	}
	return chaves
}

// iguais compara em tempo constante, para não vazar a chave pelo tempo de
// resposta. Chave configurada vazia nunca é aceita.
func iguais(recebida, configurada string) bool {
	if configurada == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(recebida), []byte(configurada)) == 1
}

// perfilDaChave descobre o perfil a partir da chave recebida.
func (k Chaves) perfilDaChave(recebida string) Perfil {
	if recebida == "" {
		return PerfilNenhum
	}
	if iguais(recebida, k.Admin) {
		return PerfilAdmin
	}
	if iguais(recebida, k.Leitura) {
		return PerfilLeitura
	}
	return PerfilNenhum
}

// Exige devolve um middleware que só deixa passar quem tem pelo menos o
// perfil mínimo. Sem chave válida: 401. Com chave válida mas perfil
// insuficiente: 403.
func Exige(chaves Chaves, minimo Perfil) gin.HandlerFunc {
	return func(c *gin.Context) {
		perfil := chaves.perfilDaChave(c.GetHeader(Cabecalho))
		if perfil == PerfilNenhum {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"erro": "chave de API ausente ou inválida"})
			return
		}
		if perfil < minimo {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"erro": "perfil sem permissão para esta operação"})
			return
		}
		DefinePerfil(c, perfil)
		c.Next()
	}
}

// DefinePerfil grava o perfil no contexto da requisição.
func DefinePerfil(c *gin.Context, perfil Perfil) {
	c.Set(chaveDoContexto, perfil)
}

// PerfilDe lê o perfil gravado no contexto. Sem perfil gravado, devolve
// PerfilNenhum, e quem chama deve tratar como o acesso mais restrito.
func PerfilDe(c *gin.Context) Perfil {
	valor, existe := c.Get(chaveDoContexto)
	if !existe {
		return PerfilNenhum
	}
	perfil, ok := valor.(Perfil)
	if !ok {
		return PerfilNenhum
	}
	return perfil
}

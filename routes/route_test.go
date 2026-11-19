package routes

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/guilhermeonrails/api-go-gin/autenticacao"
	"github.com/stretchr/testify/assert"
)

// Estes testes não precisam de banco: as requisições recusadas param no
// middleware, antes de chegar ao controller.

var chavesDeTeste = autenticacao.Chaves{Leitura: "chave-leitura", Admin: "chave-admin"}

func requisicao(t *testing.T, r *gin.Engine, metodo, caminho, chave string) int {
	t.Helper()
	req, _ := http.NewRequest(metodo, caminho, strings.NewReader(`{}`))
	if chave != "" {
		req.Header.Set(autenticacao.Cabecalho, chave)
	}
	resposta := httptest.NewRecorder()
	r.ServeHTTP(resposta, req)
	return resposta.Code
}

func TestRotasDeAlunosSemChaveRespondem401(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := NovoRouter(chavesDeTeste)
	casos := []struct{ metodo, caminho string }{
		{"GET", "/alunos"},
		{"GET", "/alunos/1"},
		{"GET", "/alunos/cpf/12345678901"},
		{"POST", "/alunos"},
		{"PATCH", "/alunos/1"},
		{"DELETE", "/alunos/1"},
	}
	for _, caso := range casos {
		assert.Equal(t, http.StatusUnauthorized, requisicao(t, r, caso.metodo, caso.caminho, ""), caso.metodo+" "+caso.caminho)
		assert.Equal(t, http.StatusUnauthorized, requisicao(t, r, caso.metodo, caso.caminho, "chave-errada"), caso.metodo+" "+caso.caminho)
	}
}

func TestPerfilLeituraNaoPodeAlterarAlunos(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := NovoRouter(chavesDeTeste)
	assert.Equal(t, http.StatusForbidden, requisicao(t, r, "POST", "/alunos", "chave-leitura"))
	assert.Equal(t, http.StatusForbidden, requisicao(t, r, "PATCH", "/alunos/1", "chave-leitura"))
	assert.Equal(t, http.StatusForbidden, requisicao(t, r, "DELETE", "/alunos/1", "chave-leitura"))
}

func TestPerfilAdminPassaPeloMiddlewareComIDInvalido(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := NovoRouter(chavesDeTeste)
	// Com a chave de admin a requisição chega ao controller, que recusa o id
	// não numérico com 400 antes de tocar no banco.
	assert.Equal(t, http.StatusBadRequest, requisicao(t, r, "DELETE", "/alunos/abc", "chave-admin"))
	assert.Equal(t, http.StatusBadRequest, requisicao(t, r, "GET", "/alunos/abc", "chave-leitura"))
}

func TestChavesNaoConfiguradasRecusamTudo(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := NovoRouter(autenticacao.Chaves{})
	assert.Equal(t, http.StatusUnauthorized, requisicao(t, r, "GET", "/alunos", ""))
	assert.Equal(t, http.StatusUnauthorized, requisicao(t, r, "DELETE", "/alunos/1", ""))
}

func TestSaudacaoContinuaPublica(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := NovoRouter(chavesDeTeste)
	// Usada pelo health check do load balancer e pela livenessProbe.
	assert.Equal(t, http.StatusOK, requisicao(t, r, "GET", "/bruno", ""))
}

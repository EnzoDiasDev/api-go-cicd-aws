package routes

import (
	"log"

	"github.com/gin-gonic/gin"
	"github.com/guilhermeonrails/api-go-gin/autenticacao"
	"github.com/guilhermeonrails/api-go-gin/controllers"
)

// NovoRouter monta as rotas da API.
//
// Rotas públicas: a saudação /:nome (usada pelo health check do load balancer,
// pela livenessProbe do Kubernetes e pelo teste de carga), a página /index
// (mostra só os nomes) e os arquivos de /assets.
//
// Rotas de alunos: consulta exige o perfil de leitura; criar, editar e apagar
// exigem o perfil admin.
func NovoRouter(chaves autenticacao.Chaves) *gin.Engine {
	r := gin.Default()
	r.Static("/assets", "./assets")
	r.GET("/:nome", controllers.Saudacoes)
	r.GET("/index", controllers.ExibePaginaIndex)

	leitura := r.Group("/alunos", autenticacao.Exige(chaves, autenticacao.PerfilLeitura))
	leitura.GET("", controllers.TodosAlunos)
	leitura.GET("/", controllers.BuscaAlunoPorCPF)
	leitura.GET("/:id", controllers.BuscarAlunoPorID)
	leitura.GET("/cpf/:cpf", controllers.BuscaAlunoPorCPF)

	admin := r.Group("/alunos", autenticacao.Exige(chaves, autenticacao.PerfilAdmin))
	admin.POST("", controllers.CriarNovoAluno)
	admin.PATCH("/:id", controllers.EditarAluno)
	admin.DELETE("/:id", controllers.DeletarAluno)

	r.NoRoute(controllers.RotaNaoEncontrada)
	return r
}

func HandleRequest() {
	r := NovoRouter(autenticacao.ChavesDoAmbiente())
	r.LoadHTMLGlob("templates/*")
	if err := r.Run(); err != nil {
		log.Fatal("Erro ao iniciar o servidor: ", err)
	}
}

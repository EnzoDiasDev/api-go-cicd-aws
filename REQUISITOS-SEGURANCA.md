# Requisitos de segurança da API de alunos

Este documento define as regras de acesso e de tratamento de dados pessoais da API. O código em `autenticacao/`, `controllers/` e `models/` implementa estas regras; os testes em `routes/route_test.go`, `models/alunos_test.go` e `main_test.go` as verificam.

## 1. Autenticação

- As rotas de `/alunos` exigem uma chave de API no cabeçalho `X-API-Key`.
- As chaves vêm das variáveis de ambiente `API_KEY_LEITURA` e `API_KEY_ADMIN`.
- Nos ambientes da AWS, as chaves são geradas pelo Terraform e guardadas no AWS Secrets Manager. Ninguém escreve chave no código.
- Se uma variável estiver vazia, nenhuma chave é aceita para aquele perfil. Se as duas estiverem vazias, todas as rotas de alunos respondem `401` (falha fechada).
- A comparação da chave é feita em tempo constante, para não vazar informação pelo tempo de resposta.

## 2. Autorização (perfis)

| Rota | Sem chave ou chave inválida | Perfil leitura | Perfil admin |
|---|---|---|---|
| `GET /alunos`, `GET /alunos/:id`, `GET /alunos/cpf/:cpf` | `401` | Permitido, com CPF e RG mascarados | Permitido, com CPF e RG completos |
| `POST /alunos`, `PATCH /alunos/:id`, `DELETE /alunos/:id` | `401` | `403` | Permitido |

Rotas públicas, sem chave:

- `GET /:nome` (saudação): usada pelo health check do load balancer, pela `livenessProbe` do Kubernetes e pelo teste de carga. Não acessa dados.
- `GET /index`: página HTML que mostra **só os nomes** dos alunos, sem CPF e sem RG.
- `/assets`: arquivos estáticos.

## 3. Dados pessoais (LGPD)

A API guarda nome, CPF e RG de alunos.

**Quem pode ver CPF e RG completos:** só o perfil admin.

**Como mascarar:** para qualquer outro perfil, CPF e RG voltam com todos os caracteres trocados por `*`, menos os dois últimos. Exemplo: `12345678901` vira `*********01`. A máscara é aplicada também quando não há perfil definido (falha fechada).

**Por quanto tempo guardar:** enquanto o aluno estiver cadastrado. Ao apagar o aluno (`DELETE /alunos/:id`), o registro é removido de verdade do banco. Não existe exclusão lógica (*soft delete*) que deixe o CPF e o RG guardados.

## 4. O que ainda não está coberto

- Limite de requisições (*rate limit*) e tamanho máximo do corpo da requisição.
- Log de auditoria de quem consultou ou alterou cada aluno.
- Rotação periódica das chaves de API.
- HTTPS no load balancer (o tráfego ainda é HTTP).

package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMascaraDocumento(t *testing.T) {
	assert.Equal(t, "*********01", MascaraDocumento("12345678901"))
	assert.Equal(t, "*******89", MascaraDocumento("123456789"))
	assert.Equal(t, "**", MascaraDocumento("12"))
	assert.Equal(t, "", MascaraDocumento(""))
}

func TestMascaradoNaoAlteraOOriginal(t *testing.T) {
	aluno := Aluno{Nome: "Ana", CPF: "12345678901", RG: "123456789"}
	mascarado := aluno.Mascarado()
	assert.Equal(t, "*********01", mascarado.CPF)
	assert.Equal(t, "*******89", mascarado.RG)
	assert.Equal(t, "Ana", mascarado.Nome)
	assert.Equal(t, "12345678901", aluno.CPF)
}

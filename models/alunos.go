package models

import (
	"strings"

	"gopkg.in/validator.v2"
	"gorm.io/gorm"
)

type Aluno struct {
	gorm.Model
	Nome string `json:"nome" validate:"nonzero"`
	RG   string `json:"rg" validate:"len=9, regexp=^[0-9]*$"`
	CPF  string `json:"cpf" validate:"len=11, regexp=^[0-9]*$"`
}

func ValidaDadosDeAluno(aluno *Aluno) error {
	if err := validator.Validate(aluno); err != nil {
		return err
	}
	return nil
}

// digitosVisiveis é quantos dígitos finais de CPF e RG ficam à mostra quando
// o documento é mascarado.
const digitosVisiveis = 2

// MascaraDocumento troca todos os caracteres por "*", menos os últimos dois.
// Ex.: "12345678901" vira "*********01".
func MascaraDocumento(documento string) string {
	runas := []rune(documento)
	if len(runas) <= digitosVisiveis {
		return strings.Repeat("*", len(runas))
	}
	ocultos := len(runas) - digitosVisiveis
	return strings.Repeat("*", ocultos) + string(runas[ocultos:])
}

// Mascarado devolve uma cópia do aluno com CPF e RG mascarados. É o formato
// usado para quem tem só o perfil de leitura.
func (a Aluno) Mascarado() Aluno {
	a.CPF = MascaraDocumento(a.CPF)
	a.RG = MascaraDocumento(a.RG)
	return a
}

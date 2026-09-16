/**
 * Traduz os erros do banco no 13º salário para instrução em português.
 *
 * As travas da Entrega 2 (unicidade da parcela viva, CHECKs de encargos e
 * de valores) existem justamente para o sistema não gravar coisa errada —
 * mas o que o usuário via era o texto cru do PostgreSQL, em inglês, com o
 * nome do índice. Erro que não diz o que fazer vira chamado de suporte.
 *
 * Cada mensagem responde a duas perguntas: o que aconteceu e qual é o
 * próximo passo na tela.
 */
export interface ErroBanco {
  message?: string;
  code?: string;
  details?: string;
}

const TRADUCOES: Array<{ marca: RegExp; texto: string }> = [
  {
    marca: /folha_13_calculo_parcela_viva_uq/i,
    texto:
      "Este colaborador já tem essa parcela do 13º lançada neste ano-base. " +
      "Não se calcula a mesma parcela duas vezes: abra o cálculo existente na lista " +
      "e use Reabrir (se precisar refazer) ou cancele-o antes de lançar de novo.",
  },
  {
    marca: /folha_13_calculo_encargos_2a_ck/i,
    texto:
      "INSS e IRRF não incidem sobre a 1ª parcela — eles são descontados de uma vez " +
      "na 2ª, sobre o 13º integral (Lei 4.749/1965). Deixe os encargos zerados nesta parcela.",
  },
  {
    marca: /folha_13_calculo_primeira_ck/i,
    texto:
      "O valor informado como 1ª parcela não confere com o 13º apurado. " +
      "Reapure a base antes de gravar a 2ª parcela.",
  },
  {
    marca: /folha_13_calculo_base_fgts_ck/i,
    texto: "A base de FGTS não pode ser negativa nem maior que o 13º integral.",
  },
  {
    marca: /folha_13_calculo_valores_ck/i,
    texto: "Há valor negativo no cálculo do 13º — confira remuneração base, média e encargos.",
  },
  {
    marca: /folha_13_calculo_aprovacao_ck/i,
    texto:
      "Cálculo marcado como aprovado sem registro de quem aprovou e quando. " +
      "Use o botão Aprovar na lista — é ele que grava responsável e data.",
  },
  {
    marca: /folha_13_calculo_pagamento_ck/i,
    texto:
      "Cálculo marcado como pago sem data de pagamento. " +
      "Use o botão Pagar na lista e informe a data — ela é o que prova o cumprimento do prazo legal.",
  },
  {
    marca: /folha_13_calculo_status_ck|violates check constraint .*status/i,
    texto:
      "Situação inválida para o cálculo do 13º. As situações aceitas são: " +
      "calculado, aprovado, pago e cancelado.",
  },
  {
    marca: /meses_trabalhados/i,
    texto: "Os avos precisam ficar entre 0 e 12 — use Apurar para o sistema contá-los do vínculo.",
  },
  {
    marca: /decimo_terceiro_trava_fechado|row is locked|calculo fechado/i,
    texto:
      "Este cálculo já foi aprovado ou pago e por isso não aceita alteração de valores. " +
      "Para corrigi-lo, use Reabrir — a reabertura fica registrada com motivo e responsável.",
  },
  {
    marca: /row-level security|permission denied/i,
    texto:
      "Seu perfil não tem acesso à remuneração deste colaborador. " +
      "Peça a liberação do módulo Financeiro ao administrador.",
  },
];

export function traduzirErro13(erro: unknown): string {
  const e = (erro || {}) as ErroBanco;
  const cru = [e.message, e.details].filter(Boolean).join(" ");
  if (!cru) return "Não foi possível gravar o cálculo do 13º.";
  const achado = TRADUCOES.find((t) => t.marca.test(cru));
  return achado ? achado.texto : cru;
}

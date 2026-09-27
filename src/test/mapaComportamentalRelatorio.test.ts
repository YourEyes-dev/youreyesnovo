import { describe, it, expect } from "vitest";
import {
  PERFIL_RELATORIO,
  OUTROS_PERFIS,
} from "@/data/mapaComportamentalRelatorio";
import { ARQUETIPO_LABEL, type Arquetipo } from "@/data/instrumentos/mapaComportamental";

const ARQUETIPOS = Object.keys(ARQUETIPO_LABEL) as Arquetipo[];

// Junta todo o texto "que fala com a pessoa" de um perfil (exclui os rótulos
// fixos de abertura/enquadramento, que citam de propósito o que o mapa NÃO é).
function textoDoPerfil(a: Arquetipo): string {
  const p = PERFIL_RELATORIO[a];
  const partes = [
    p.emUmaFrase,
    p.noDiaADia.reuniao, p.noDiaADia.prazo, p.noDiaADia.desacordo,
    ...p.rendeMais.flatMap((c) => [c.condicao, c.acao]),
    ...p.desgasta.flatMap((c) => [c.condicao, c.acao]),
    ...p.precos.flatMap((c) => [c.texto, c.sinal]),
    ...p.ajustesImediatos,
    ...p.contrapesos.flatMap((c) => [c.nome, c.porque, c.comoTreinar]),
    ...p.pedidosLider,
    p.zonaConforto.onde, p.zonaConforto.saida,
    p.comunicacao.entrega, p.comunicacao.perde, p.comunicacao.ajuste,
    p.feedback.comoPedir, p.feedback.reacaoHabitual,
  ];
  return partes.join(" \n ").toLowerCase();
}

describe("Biblioteca do Relatório Meu Mapa", () => {
  it("cobre os quatro arquétipos", () => {
    for (const a of ARQUETIPOS) expect(PERFIL_RELATORIO[a]).toBeDefined();
  });

  for (const a of ARQUETIPOS) {
    describe(`perfil ${a}`, () => {
      const p = PERFIL_RELATORIO[a];

      it("tem exatamente 3 ajustes imediatos (RN-024)", () => {
        expect(p.ajustesImediatos).toHaveLength(3);
        p.ajustesImediatos.forEach((t) => expect(t.trim().length).toBeGreaterThan(0));
      });

      it("tem exatamente 2 contrapesos de desenvolvimento (RN-025)", () => {
        expect(p.contrapesos).toHaveLength(2);
      });

      it("tem ao menos 2 pedidos ao líder", () => {
        expect(p.pedidosLider.length).toBeGreaterThanOrEqual(2);
      });

      it("tem 3 custos, cada um com sinal (RN-022)", () => {
        expect(p.precos).toHaveLength(3);
        p.precos.forEach((c) => {
          expect(c.texto.trim().length).toBeGreaterThan(0);
          expect(c.sinal.trim().length).toBeGreaterThan(0);
        });
      });

      it("tem 4 condições de render mais e 4 de desgaste, com ação", () => {
        expect(p.rendeMais).toHaveLength(4);
        expect(p.desgasta).toHaveLength(4);
        [...p.rendeMais, ...p.desgasta].forEach((c) => {
          expect(c.condicao.trim().length).toBeGreaterThan(0);
          expect(c.acao.trim().length).toBeGreaterThan(0);
        });
      });

      it("não usa linguagem de capacidade/limitação (RN-021)", () => {
        const texto = textoDoPerfil(a);
        for (const termo of ["não consegue", "nao consegue", "incapaz", "dificuldade em", "é limitad", "e limitad", "você não sabe"]) {
          expect(texto, `termo proibido: "${termo}"`).not.toContain(termo);
        }
      });

      it("não recomenda movimentação de pessoal (RN-026)", () => {
        const texto = textoDoPerfil(a);
        for (const termo of ["promoção", "promocao", "aumento de salário", "mudar de cargo", "trocar de cargo", "demiss", "desligamento"]) {
          expect(texto, `termo proibido: "${termo}"`).not.toContain(termo);
        }
      });
    });
  }

  it("a seção 'outros perfis' não fala do próprio arquétipo e cobre os outros três", () => {
    for (const a of ARQUETIPOS) {
      const blocos = OUTROS_PERFIS[a];
      const chaves = Object.keys(blocos) as Arquetipo[];
      expect(chaves).not.toContain(a); // não fala de si mesmo
      expect(chaves).toHaveLength(3);
      chaves.forEach((outro) => {
        const b = blocos[outro]!;
        expect(b.comoTeVe.trim().length).toBeGreaterThan(0);
        expect(b.atrito.trim().length).toBeGreaterThan(0);
        expect(b.ajuste.trim().length).toBeGreaterThan(0);
      });
    }
  });
});

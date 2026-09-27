// ─────────────────────────────────────────────────────────────────────────────
// Mapa Comportamental — geração do PDF do relatório "Meu Mapa" (RF-028).
//
// Programático (jsPDF, texto), no mesmo padrão dos demais relatórios da casa —
// nada de rasterizar a tela. Escrito em 2ª pessoa, respeita os limites do
// documento: marca d'água com nome do titular e data de emissão (desestimula
// circulação indevida), rodapé com a versão da biblioteca e do algoritmo
// (RN-030), e conteúdo curado da biblioteca fixa.
//
// Baixa confiabilidade suprime "Como melhorar" e "Trabalhando com os outros
// perfis" (RN-028). Perfil misto apresenta os dois arquétipos e segue as
// orientações do lado predominante.
// ─────────────────────────────────────────────────────────────────────────────

import jsPDF from "jspdf";
import type { MapaResultado, Arquetipo, Modo } from "@/data/instrumentos/mapaComportamental";
import {
  ARQUETIPO_LABEL,
  MOTOR_LABEL,
  MODO_LABEL,
} from "@/data/instrumentos/mapaComportamental";
import {
  PERFIL_RELATORIO,
  OUTROS_PERFIS,
  OUTRO_PERFIL_APRESENTACAO,
  PRESSAO_POR_MODO,
  MOTOR_RELATORIO,
  MODO_RELATORIO,
  textoIntensidade,
  RELATORIO_ABERTURA,
  RELATORIO_SOBRE,
  RELATORIO_BIBLIOTECA_VERSAO,
} from "@/data/mapaComportamentalRelatorio";

export interface DadosRelatorioPdf {
  resultado: MapaResultado;
  nome?: string | null;
  concluidoEm?: string | null;
  venceEm?: string | null;
}

const AZUL: [number, number, number] = [79, 70, 229]; // indigo-600
const CINZA: [number, number, number] = [90, 90, 90];

function dataBR(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("pt-BR");
}

export function gerarRelatorioMeuMapaPdf({ resultado, nome, concluidoEm, venceEm }: DadosRelatorioPdf) {
  const doc = new jsPDF();
  const pageW = doc.internal.pageSize.getWidth();
  const pageH = doc.internal.pageSize.getHeight();
  const margin = 18;
  const maxW = pageW - margin * 2;
  let y = margin;

  const baixa = resultado.confiabilidade === "baixa";
  const primario = resultado.arquetipos[0];
  const secundario = resultado.arquetipos[1] ?? null;
  const lib = PERFIL_RELATORIO[primario];
  const intensidadeBaixa = resultado.foco.misto || resultado.ritmo.misto;
  const emissao = new Date().toLocaleDateString("pt-BR");
  const titular = (nome ?? "").trim() || "Colaborador(a)";

  // Marca d'água + rodapé em cada página (RF-028).
  const decorarPagina = () => {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7);
    doc.setTextColor(...CINZA);
    // Marca d'água discreta no rodapé (nome + data de emissão).
    doc.text(`Documento pessoal de ${titular} · emitido em ${emissao}`, margin, pageH - 8);
    doc.text(
      `Mapa Comportamental · biblioteca ${RELATORIO_BIBLIOTECA_VERSAO} · algoritmo ${resultado.algoritmoVersao}`,
      pageW - margin,
      pageH - 8,
      { align: "right" },
    );
    doc.setTextColor(0);
  };

  const quebraSePreciso = (alturaPrevista = 8) => {
    if (y + alturaPrevista > pageH - 16) {
      decorarPagina();
      doc.addPage();
      y = margin;
    }
  };

  const secao = (titulo: string) => {
    quebraSePreciso(16);
    y += 3;
    doc.setFontSize(12);
    doc.setFont("helvetica", "bold");
    doc.setTextColor(...AZUL);
    doc.text(titulo, margin, y);
    doc.setTextColor(0);
    y += 2;
    doc.setDrawColor(...AZUL);
    doc.setLineWidth(0.3);
    doc.line(margin, y, pageW - margin, y);
    y += 6;
  };

  const paragrafo = (texto: string, opts: { tamanho?: number; negrito?: boolean; cor?: [number, number, number] } = {}) => {
    if (!texto) return;
    doc.setFontSize(opts.tamanho ?? 9.5);
    doc.setFont("helvetica", opts.negrito ? "bold" : "normal");
    doc.setTextColor(...(opts.cor ?? [0, 0, 0]));
    const linhas = doc.splitTextToSize(texto, maxW);
    for (const linha of linhas) {
      quebraSePreciso(5.2);
      doc.text(linha, margin, y);
      y += 5.2;
    }
    doc.setTextColor(0);
    y += 1.5;
  };

  const bullet = (texto: string, subTexto?: string) => {
    doc.setFontSize(9.5);
    doc.setFont("helvetica", "bold");
    const linhas = doc.splitTextToSize(`•  ${texto}`, maxW);
    for (const linha of linhas) {
      quebraSePreciso(5);
      doc.text(linha, margin, y);
      y += 5;
    }
    if (subTexto) {
      doc.setFont("helvetica", "normal");
      doc.setTextColor(...CINZA);
      const subs = doc.splitTextToSize(`→  ${subTexto}`, maxW - 4);
      for (const linha of subs) {
        quebraSePreciso(5);
        doc.text(linha, margin + 4, y);
        y += 5;
      }
      doc.setTextColor(0);
    }
    y += 1.5;
  };

  // ── Cabeçalho ──────────────────────────────────────────────────────────────
  doc.setFillColor(...AZUL);
  doc.rect(0, 0, pageW, 26, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(16);
  doc.text("MEU MAPA", margin, 13);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(10);
  doc.text(`${titular}`, margin, 20);
  doc.setFontSize(8);
  doc.text(
    `emitido em ${emissao}${venceEm ? ` · válido até ${dataBR(venceEm)}` : ""}`,
    pageW - margin,
    20,
    { align: "right" },
  );
  doc.setTextColor(0);
  y = 34;

  // ── Abertura (seção 1) ───────────────────────────────────────────────────────
  RELATORIO_ABERTURA.forEach((p) => paragrafo(p));

  if (baixa) {
    quebraSePreciso(20);
    doc.setFillColor(254, 242, 242);
    doc.setDrawColor(220, 38, 38);
    const boxH = 16;
    doc.rect(margin, y, maxW, boxH, "FD");
    doc.setTextColor(153, 27, 27);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(9);
    doc.text("Atenção: este resultado pode não refletir bem você.", margin + 3, y + 6);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8.5);
    doc.text(
      doc.splitTextToSize(
        "As respostas ficaram pouco consistentes. Vale refazer o mapa com calma. As seções de recomendação foram omitidas até uma nova aplicação.",
        maxW - 6,
      ),
      margin + 3,
      y + 11,
    );
    doc.setTextColor(0);
    y += boxH + 4;
  }

  // ── Seção 2 — Seu mapa em uma frase ──────────────────────────────────────────
  secao("Seu mapa em uma frase");
  paragrafo(lib.emUmaFrase, { tamanho: 11 });
  const motoresTxt = resultado.motor.predominantes.map((m) => `Motor ${MOTOR_LABEL[m]}`).join(" e ");
  const modoTxt = resultado.modo.resultado === "misto" ? "Modo Misto" : `Modo ${MODO_LABEL[resultado.modo.resultado as Modo]}`;
  const arqTxt = resultado.arquetipos.map((a) => ARQUETIPO_LABEL[a]).join(" · ");
  paragrafo(`(${arqTxt} · ${motoresTxt} · ${modoTxt})`, { tamanho: 9, cor: CINZA });

  if (secundario) {
    paragrafo(
      `Seu perfil ficou entre ${ARQUETIPO_LABEL[primario]} e ${ARQUETIPO_LABEL[secundario]} — trate isso como flexibilidade, não indefinição. As orientações abaixo seguem o ${ARQUETIPO_LABEL[primario]}, seu lado predominante; vale ler também com o ${ARQUETIPO_LABEL[secundario]} em mente.`,
      { tamanho: 9, cor: CINZA },
    );
  }

  // ── Seção 3 — Como você tende a trabalhar ─────────────────────────────────────
  secao("Como você tende a trabalhar");
  paragrafo(`Foco (Pessoas ↔ Tarefas): ${textoIntensidade(resultado.foco.intensidade)}`, { negrito: true, tamanho: 9 });
  paragrafo(`Ritmo (Acelerado ↔ Ponderado): ${textoIntensidade(resultado.ritmo.intensidade)}`, { negrito: true, tamanho: 9 });
  resultado.motor.predominantes.forEach((m) => paragrafo(`Motor ${MOTOR_LABEL[m]}: ${MOTOR_RELATORIO[m]}`, { tamanho: 9 }));
  paragrafo(`Modo ${resultado.modo.resultado === "misto" ? "Misto" : MODO_LABEL[resultado.modo.resultado as Modo]}: ${MODO_RELATORIO[resultado.modo.resultado]}`, { tamanho: 9 });

  // ── Seção 4 — No dia a dia ────────────────────────────────────────────────────
  secao("O que isso significa no dia a dia");
  paragrafo(`Numa reunião: ${lib.noDiaADia.reuniao}`);
  paragrafo(`Num prazo apertado: ${lib.noDiaADia.prazo}`);
  paragrafo(`Num desacordo: ${lib.noDiaADia.desacordo}`);

  // ── Seção 5 — Onde você rende mais ────────────────────────────────────────────
  secao("Onde você costuma render mais");
  lib.rendeMais.forEach((c) => bullet(c.condicao, c.acao));

  // ── Seção 6 — O que te desgasta ───────────────────────────────────────────────
  secao("O que costuma te desgastar");
  lib.desgasta.forEach((c) => bullet(c.condicao, c.acao));

  // ── Seção 7 — O preço do seu estilo (obrigatória, RN-022) ─────────────────────
  secao("O preço do seu estilo");
  const custos = intensidadeBaixa ? lib.precos.slice(0, 2) : lib.precos;
  custos.forEach((c) => {
    paragrafo(c.texto, { negrito: true, tamanho: 9 });
    paragrafo(`Sinal de que está sendo pago agora: ${c.sinal}`, { tamanho: 8.5, cor: CINZA });
  });

  // ── Seção 8 — Como melhorar (suprimida em baixa confiabilidade) ───────────────
  if (!baixa) {
    secao("Como melhorar seu desempenho");
    paragrafo("Para começar esta semana", { negrito: true, tamanho: 10, cor: AZUL });
    lib.ajustesImediatos.forEach((a, i) => paragrafo(`${i + 1}. ${a}`, { tamanho: 9 }));
    paragrafo("Para desenvolver nos próximos meses", { negrito: true, tamanho: 10, cor: AZUL });
    lib.contrapesos.forEach((c) => {
      paragrafo(c.nome, { negrito: true, tamanho: 9 });
      paragrafo(`Por que importa para você: ${c.porque}`, { tamanho: 9 });
      paragrafo(`Como treinar: ${c.comoTreinar}`, { tamanho: 9, cor: CINZA });
    });
    paragrafo("O que pedir ao seu líder", { negrito: true, tamanho: 10, cor: AZUL });
    paragrafo("Use estas frases na próxima conversa, do jeito que estão:", { tamanho: 9, cor: CINZA });
    lib.pedidosLider.forEach((f) => paragrafo(`“${f}”`, { tamanho: 9 }));
  }

  // ── Seção 9 — Zona de conforto ────────────────────────────────────────────────
  secao("Sua zona de conforto");
  paragrafo(lib.zonaConforto.onde, { tamanho: 9 });
  paragrafo(lib.zonaConforto.saida, { tamanho: 9, cor: CINZA });

  // ── Seção 10 — Como você se comunica ──────────────────────────────────────────
  secao("Como você se comunica");
  paragrafo(lib.comunicacao.entrega, { tamanho: 9 });
  paragrafo(lib.comunicacao.perde, { tamanho: 9 });
  paragrafo(`Ajuste: ${lib.comunicacao.ajuste}`, { tamanho: 9, cor: CINZA });

  // ── Seção 11 — Em pressão e em conflito ───────────────────────────────────────
  secao("Em pressão e em conflito");
  paragrafo(PRESSAO_POR_MODO[resultado.modo.resultado], { tamanho: 9 });

  // ── Seção 12 — Trabalhando com os outros perfis (suprimida em baixa confiab.) ─
  if (!baixa) {
    secao("Trabalhando com os outros perfis");
    const blocos = OUTROS_PERFIS[primario];
    (Object.keys(blocos) as Arquetipo[]).forEach((outro) => {
      const b = blocos[outro];
      if (!b) return;
      paragrafo(`Com ${OUTRO_PERFIL_APRESENTACAO[outro]} (${ARQUETIPO_LABEL[outro]})`, { negrito: true, tamanho: 9, cor: AZUL });
      paragrafo(`Como te vê: ${b.comoTeVe}`, { tamanho: 9 });
      paragrafo(`Onde atrita: ${b.atrito}`, { tamanho: 9 });
      paragrafo(`Ajuste: ${b.ajuste}`, { tamanho: 9, cor: CINZA });
    });
  }

  // ── Seção 13 — Como pedir e receber feedback ──────────────────────────────────
  secao("Como pedir e receber feedback");
  paragrafo(lib.feedback.comoPedir, { tamanho: 9 });
  paragrafo(lib.feedback.reacaoHabitual, { tamanho: 9, cor: CINZA });

  // ── Seção 15 — Sobre este resultado ───────────────────────────────────────────
  secao("Sobre este resultado");
  if (venceEm) paragrafo(`Válido até ${dataBR(venceEm)}. Depois disso, vale refazer — as pessoas mudam.`, { tamanho: 9 });
  RELATORIO_SOBRE.forEach((p) => paragrafo(p, { tamanho: 9 }));
  paragrafo("Você pode consultar quem acessou o seu mapa e abrir uma contestação a qualquer momento na tela do Mapa Comportamental.", { tamanho: 8.5, cor: CINZA });

  decorarPagina();

  const arquivo = `meu-mapa-${titular.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")}.pdf`;
  doc.save(arquivo);
}

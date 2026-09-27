// ─────────────────────────────────────────────────────────────────────────────
// Mapa Comportamental — PDF do relatório "Meu Mapa" (RF-028).
//
// Monta um HTML estilizado e o renderiza pelo pipeline da casa
// (generatePdfFromHtml → html2canvas + jsPDF). Assim o documento sai com
// tipografia de verdade (fonte, espaçamento entre linhas, margens ABNT
// — superior/esquerda 3 cm, inferior/direita 2 cm), acentuação e caracteres
// especiais corretos, e quebras de página que não cortam blocos no meio.
//
// A versão anterior era desenhada célula a célula no jsPDF e quebrava nos
// caracteres fora do Latin-1 (setas, aspas tipográficas), além de ficar com
// espaçamento apertado. Mantidas as cores da marca.
//
// Baixa confiabilidade suprime "Como melhorar" e "Trabalhando com os outros
// perfis" (RN-028). Perfil misto apresenta os dois arquétipos.
// ─────────────────────────────────────────────────────────────────────────────

import { generatePdfFromHtml } from "@/utils/generatePdfFromHtml";
import type { MapaResultado, Modo } from "@/data/instrumentos/mapaComportamental";
import { ARQUETIPO_LABEL, MOTOR_LABEL, MODO_LABEL } from "@/data/instrumentos/mapaComportamental";
import {
  PERFIL_RELATORIO, OUTROS_PERFIS, OUTRO_PERFIL_APRESENTACAO, PRESSAO_POR_MODO,
  MOTOR_RELATORIO, MODO_RELATORIO, textoIntensidade,
  RELATORIO_ABERTURA, RELATORIO_SOBRE, RELATORIO_BIBLIOTECA_VERSAO,
} from "@/data/mapaComportamentalRelatorio";

export interface DadosRelatorioPdf {
  resultado: MapaResultado;
  nome?: string | null;
  concluidoEm?: string | null;
  venceEm?: string | null;
}

const esc = (s: unknown): string =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

function dataBR(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("pt-BR");
}

// Folha de estilo do relatório. Definida por CLASSES (o normalizador do pipeline
// só reescala font-size INLINE; classes ficam com o tamanho que definimos aqui).
// Corpo em fonte sem serifa, 13.5px sobre 604px → ~12pt no A4; entrelinha 1.6.
const CSS = `
  .rel { font-family: Arial, Helvetica, sans-serif; color: #1f2430; font-size: 13.5px; line-height: 1.6; }
  .rel p { margin: 0 0 8px; }
  .cabecalho { background-color: #4f46e5; color: #ffffff; padding: 22px 24px; border-radius: 12px; margin-bottom: 6px; }
  .cabecalho .marca { font-size: 12px; letter-spacing: 2px; text-transform: uppercase; opacity: .85; margin: 0 0 4px; }
  .cabecalho .titular { font-size: 22px; font-weight: 800; margin: 0; }
  .cabecalho .datas { font-size: 11.5px; opacity: .9; margin: 6px 0 0; }
  .aviso { background-color: #eef2ff; border: 1px solid #c7d2fe; border-radius: 10px; padding: 12px 14px; margin: 10px 0; font-size: 12.5px; }
  .aviso .destaque { font-weight: 700; }
  .alerta { background-color: #fef2f2; border: 1px solid #fecaca; border-radius: 10px; padding: 12px 14px; margin: 10px 0; color: #991b1b; font-size: 12.5px; }
  h2.secao { color: #4338ca; font-size: 15.5px; font-weight: 800; margin: 22px 0 10px; padding-bottom: 6px; border-bottom: 2px solid #e0e7ff; }
  .frase { font-size: 15px; font-weight: 600; margin: 0 0 4px; }
  .rotulos { font-size: 11.5px; color: #6b7280; margin: 0 0 8px; }
  .linha { border-left: 3px solid #c7d2fe; background-color: #f5f3ff; padding: 9px 12px; border-radius: 8px; margin: 7px 0; }
  .linha.verde { border-left-color: #6ee7b7; background-color: #ecfdf5; }
  .linha.ambar { border-left-color: #fcd34d; background-color: #fffbeb; }
  .linha.rosa  { border-left-color: #fda4af; background-color: #fff1f2; }
  .linha .cond { font-weight: 700; }
  .linha .acao { color: #4b5563; font-size: 12.5px; margin-top: 2px; }
  .bloco-tit { font-weight: 800; color: #4338ca; margin: 12px 0 4px; }
  ol.passos { margin: 4px 0 8px 18px; padding: 0; }
  ol.passos li { margin: 0 0 6px; }
  .frase-lider { font-style: italic; background-color: #f8fafc; border: 1px dashed #cbd5e1; border-radius: 8px; padding: 8px 10px; margin: 6px 0; }
  .sub { color: #6b7280; }
  .nota { font-size: 11px; color: #6b7280; margin-top: 4px; }
  .rodape { margin-top: 20px; padding-top: 10px; border-top: 1px solid #e5e7eb; font-size: 10.5px; color: #9ca3af; }
`;

export async function gerarRelatorioMeuMapaPdf({ resultado, nome, concluidoEm, venceEm }: DadosRelatorioPdf) {
  const baixa = resultado.confiabilidade === "baixa";
  const primario = resultado.arquetipos[0];
  const secundario = resultado.arquetipos[1] ?? null;
  const lib = PERFIL_RELATORIO[primario];
  const intensidadeBaixa = resultado.foco.misto || resultado.ritmo.misto;
  const custos = intensidadeBaixa ? lib.precos.slice(0, 2) : lib.precos;
  const modoKey = resultado.modo.resultado as Modo | "misto";
  const emissao = new Date().toLocaleDateString("pt-BR");
  const titular = (nome ?? "").trim() || "Colaborador(a)";

  const rotulos =
    `${resultado.arquetipos.map((a) => ARQUETIPO_LABEL[a]).join(" · ")} · ` +
    `${resultado.motor.predominantes.map((m) => `Motor ${MOTOR_LABEL[m]}`).join(" e ")} · ` +
    `${resultado.modo.resultado === "misto" ? "Modo Misto" : `Modo ${MODO_LABEL[resultado.modo.resultado as Modo]}`}`;

  const secao = (titulo: string, corpo: string) => `<h2 class="secao">${esc(titulo)}</h2>${corpo}`;
  const cond = (classe: string, c: { condicao: string; acao: string }) =>
    `<div class="linha ${classe}"><div class="cond">${esc(c.condicao)}</div><div class="acao">→ ${esc(c.acao)}</div></div>`;

  const partes: string[] = [];

  // Cabeçalho
  partes.push(`
    <div class="cabecalho">
      <p class="marca">Mapa Comportamental</p>
      <p class="titular">Meu Mapa — ${esc(titular)}</p>
      <p class="datas">Emitido em ${esc(emissao)}${concluidoEm ? ` · respondido em ${esc(dataBR(concluidoEm))}` : ""}${venceEm ? ` · válido até ${esc(dataBR(venceEm))}` : ""}</p>
    </div>
  `);

  // Abertura + enquadramento
  partes.push(`<div class="aviso">${RELATORIO_ABERTURA.map((p, i) => `<p class="${i === 0 ? "destaque" : ""}" style="margin-bottom:6px">${esc(p)}</p>`).join("")}</div>`);

  if (baixa) {
    partes.push(`<div class="alerta"><span class="destaque">Atenção:</span> este resultado pode não refletir bem você — as respostas ficaram pouco consistentes. Vale refazer o mapa com calma. As seções de recomendação foram omitidas até uma nova aplicação.</div>`);
  }

  // 2 — Em uma frase
  partes.push(secao("Seu mapa em uma frase",
    `<p class="frase">${esc(lib.emUmaFrase)}</p><p class="rotulos">(${esc(rotulos)})</p>` +
    (secundario
      ? `<p class="nota">Seu perfil ficou entre <b>${esc(ARQUETIPO_LABEL[primario])}</b> e <b>${esc(ARQUETIPO_LABEL[secundario])}</b> — trate como flexibilidade, não indefinição. As orientações seguem o ${esc(ARQUETIPO_LABEL[primario])}; vale ler também com o ${esc(ARQUETIPO_LABEL[secundario])} em mente.</p>`
      : "")));

  // 3 — Como você tende a trabalhar
  partes.push(secao("Como você tende a trabalhar",
    `<p><b>Foco</b> (Pessoas ↔ Tarefas): ${esc(textoIntensidade(resultado.foco.intensidade))}</p>` +
    `<p><b>Ritmo</b> (Acelerado ↔ Ponderado): ${esc(textoIntensidade(resultado.ritmo.intensidade))}</p>` +
    resultado.motor.predominantes.map((m) => `<p><b>Motor ${esc(MOTOR_LABEL[m])}:</b> ${esc(MOTOR_RELATORIO[m])}</p>`).join("") +
    `<p><b>Modo ${esc(resultado.modo.resultado === "misto" ? "Misto" : MODO_LABEL[resultado.modo.resultado as Modo])}:</b> ${esc(MODO_RELATORIO[modoKey])}</p>`));

  // 4 — No dia a dia
  partes.push(secao("O que isso significa no dia a dia",
    `<p><b>Numa reunião:</b> ${esc(lib.noDiaADia.reuniao)}</p>` +
    `<p><b>Num prazo apertado:</b> ${esc(lib.noDiaADia.prazo)}</p>` +
    `<p><b>Num desacordo:</b> ${esc(lib.noDiaADia.desacordo)}</p>`));

  // 5 — Rende mais
  partes.push(secao("Onde você costuma render mais", lib.rendeMais.map((c) => cond("verde", c)).join("")));
  // 6 — Desgasta
  partes.push(secao("O que costuma te desgastar", lib.desgasta.map((c) => cond("ambar", c)).join("")));

  // 7 — Preço do estilo
  partes.push(secao("O preço do seu estilo",
    custos.map((c) => `<div class="linha rosa"><div class="cond">${esc(c.texto)}</div><div class="acao">Sinal de que está sendo pago agora: ${esc(c.sinal)}</div></div>`).join("")));

  // 8 — Como melhorar (suprimida em baixa confiabilidade)
  if (!baixa) {
    partes.push(secao("Como melhorar seu desempenho",
      `<p class="bloco-tit">Para começar esta semana</p>` +
      `<ol class="passos">${lib.ajustesImediatos.map((a) => `<li>${esc(a)}</li>`).join("")}</ol>` +
      `<p class="bloco-tit">Para desenvolver nos próximos meses</p>` +
      lib.contrapesos.map((c) =>
        `<div class="linha"><div class="cond">${esc(c.nome)}</div><div class="acao">Por que importa para você: ${esc(c.porque)}</div><div class="acao">Como treinar: ${esc(c.comoTreinar)}</div></div>`).join("") +
      `<p class="bloco-tit">O que pedir ao seu líder</p>` +
      `<p class="sub" style="font-size:12px">Use estas frases na próxima conversa, do jeito que estão:</p>` +
      lib.pedidosLider.map((f) => `<p class="frase-lider">“${esc(f)}”</p>`).join("")));
  }

  // 9 — Zona de conforto
  partes.push(secao("Sua zona de conforto",
    `<p>${esc(lib.zonaConforto.onde)}</p><p class="sub">${esc(lib.zonaConforto.saida)}</p>`));

  // 10 — Comunicação
  partes.push(secao("Como você se comunica",
    `<p>${esc(lib.comunicacao.entrega)}</p><p>${esc(lib.comunicacao.perde)}</p><p class="sub"><b>Ajuste:</b> ${esc(lib.comunicacao.ajuste)}</p>`));

  // 11 — Pressão e conflito
  partes.push(secao("Em pressão e em conflito", `<p>${esc(PRESSAO_POR_MODO[modoKey])}</p>`));

  // 12 — Outros perfis (suprimida em baixa confiabilidade)
  if (!baixa) {
    const blocos = OUTROS_PERFIS[primario];
    partes.push(secao("Trabalhando com os outros perfis",
      (Object.keys(blocos) as (keyof typeof ARQUETIPO_LABEL)[]).map((outro) => {
        const b = blocos[outro];
        if (!b) return "";
        return `<div class="linha"><div class="cond">Com ${esc(OUTRO_PERFIL_APRESENTACAO[outro])} (${esc(ARQUETIPO_LABEL[outro])})</div>` +
          `<div class="acao"><b>Como te vê:</b> ${esc(b.comoTeVe)}</div>` +
          `<div class="acao"><b>Onde atrita:</b> ${esc(b.atrito)}</div>` +
          `<div class="acao"><b>Ajuste:</b> ${esc(b.ajuste)}</div></div>`;
      }).join("")));
  }

  // 13 — Feedback
  partes.push(secao("Como pedir e receber feedback",
    `<p>${esc(lib.feedback.comoPedir)}</p><p class="sub">${esc(lib.feedback.reacaoHabitual)}</p>`));

  // 15 — Sobre este resultado
  partes.push(secao("Sobre este resultado",
    (venceEm ? `<p>Válido até ${esc(dataBR(venceEm))}. Depois disso, vale refazer — as pessoas mudam.</p>` : "") +
    RELATORIO_SOBRE.map((p) => `<p class="sub">${esc(p)}</p>`).join("")));

  // Rodapé (marca d'água textual + versão)
  partes.push(`<div class="rodape">Documento pessoal de ${esc(titular)} · emitido em ${esc(emissao)} · Mapa Comportamental — biblioteca ${esc(RELATORIO_BIBLIOTECA_VERSAO)} · algoritmo ${esc(resultado.algoritmoVersao)}</div>`);

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>${CSS}</style></head><body><div class="rel">${partes.join("\n")}</div></body></html>`;

  const { pdf, filename } = await generatePdfFromHtml({
    html,
    filenamePrefix: `meu-mapa-${titular}`,
  });
  pdf.save(filename);
}

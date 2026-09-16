/**
 * Documentos do 13º Salário — recibo da parcela e memória de cálculo.
 *
 * Requisito YE-DP-13-001, seção 16 e CA-008: todo documento produzido é
 * arquivado em Documentos com metadados. O recibo é o comprovante que a
 * empresa apresenta numa fiscalização ou reclamação; a memória é o que
 * torna o valor reproduzível (RNF-001/007).
 *
 * O HTML é o formato que o módulo Documentos já arquiva (mesmo caminho
 * do aviso e do recibo de férias).
 */

export interface Recibo13Data {
  empresaNome?: string;
  empresaCnpj?: string;
  colaboradorNome: string;
  colaboradorCpf?: string;
  cargo?: string;
  ano: number;
  parcela: 1 | 2;
  avos: number;
  remuneracaoBase: number;
  mediaVariaveis: number;
  valorBruto: number;
  valorPrimeiraParcela: number;
  valorInss: number;
  valorIrrf: number;
  valorFgts: number;
  totalLiquido: number;
  dataPrevista?: string | null;
  dataPagamento?: string | null;
  // Memória da apuração, como devolvida por decimo_terceiro_apurar.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  memoria?: any;
}

const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

const moeda = (v: number) =>
  (v || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

const dataBR = (d?: string | null) =>
  d ? new Date(String(d) + "T12:00:00").toLocaleDateString("pt-BR") : "—";

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, c =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));

const ESTILO = `
  body { font-family: Arial, Helvetica, sans-serif; color:#111; margin:0; padding:32px; font-size:13px; }
  h1 { font-size:17px; text-align:center; margin:0 0 4px; letter-spacing:.5px; }
  .lei { text-align:center; font-size:11px; color:#555; margin-bottom:22px; }
  .bloco { border:1px solid #ddd; border-radius:6px; padding:14px 16px; margin-bottom:16px; }
  .bloco h2 { font-size:12px; text-transform:uppercase; letter-spacing:.6px; color:#555;
              margin:0 0 10px; border-bottom:1px solid #eee; padding-bottom:6px; }
  table { width:100%; border-collapse:collapse; }
  td { padding:4px 0; vertical-align:top; }
  td.r { text-align:right; font-variant-numeric:tabular-nums; }
  .rot { color:#555; width:58%; }
  .tot { border-top:2px solid #333; font-weight:bold; font-size:15px; }
  .desc { color:#b00020; }
  .info { color:#555; font-size:11px; }
  .assin { margin-top:44px; text-align:center; }
  .linha { border-top:1px solid #333; width:320px; margin:0 auto 6px; }
  .rodape { margin-top:26px; font-size:10px; color:#777; text-align:center; line-height:1.5; }
  .mini { font-size:11px; }
  .mini td { padding:2px 0; }
  .fora { color:#999; text-decoration:line-through; }
`;

/** Recibo de pagamento da parcela — o comprovante que fica com a empresa. */
export function gerarRecibo13HTML(d: Recibo13Data): string {
  const ordinal = d.parcela === 1 ? "1ª" : "2ª";
  const proporcional = d.avos < 12;

  // Na 1ª parcela não há desconto: é adiantamento (Lei 4.749/1965, art. 2º).
  const linhasDesconto = d.parcela === 2
    ? `
      <tr><td class="rot">(−) Adiantamento da 1ª parcela</td>
          <td class="r desc">${moeda(d.valorPrimeiraParcela)}</td></tr>
      <tr><td class="rot">(−) INSS sobre o 13º <span class="info">(cálculo em separado da folha do mês)</span></td>
          <td class="r desc">${moeda(d.valorInss)}</td></tr>
      <tr><td class="rot">(−) IRRF <span class="info">(tributação exclusiva na fonte)</span></td>
          <td class="r desc">${moeda(d.valorIrrf)}</td></tr>`
    : `<tr><td class="rot" colspan="2"><span class="info">
         Adiantamento: sem desconto de INSS e IRRF, que incidem na 2ª parcela.
       </span></td></tr>`;

  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<title>Recibo 13º Salário — ${esc(d.colaboradorNome)}</title><style>${ESTILO}</style></head><body>

<h1>RECIBO DE PAGAMENTO — 13º SALÁRIO</h1>
<div class="lei">Gratificação de Natal · Lei 4.090/1962 e Lei 4.749/1965 · ${ordinal} parcela do ano-base ${d.ano}</div>

<div class="bloco">
  <h2>Empregador</h2>
  <table>
    <tr><td class="rot">Empresa</td><td class="r">${esc(d.empresaNome || "—")}</td></tr>
    ${d.empresaCnpj ? `<tr><td class="rot">CNPJ</td><td class="r">${esc(d.empresaCnpj)}</td></tr>` : ""}
  </table>
</div>

<div class="bloco">
  <h2>Empregado</h2>
  <table>
    <tr><td class="rot">Nome</td><td class="r">${esc(d.colaboradorNome)}</td></tr>
    ${d.colaboradorCpf ? `<tr><td class="rot">CPF</td><td class="r">${esc(d.colaboradorCpf)}</td></tr>` : ""}
    ${d.cargo ? `<tr><td class="rot">Cargo</td><td class="r">${esc(d.cargo)}</td></tr>` : ""}
  </table>
</div>

<div class="bloco">
  <h2>Apuração</h2>
  <table>
    <tr><td class="rot">Avos do ano-base</td>
        <td class="r">${d.avos}/12${proporcional ? " (proporcional)" : " (integral)"}</td></tr>
    <tr><td class="rot">Remuneração base</td><td class="r">${moeda(d.remuneracaoBase)}</td></tr>
    <tr><td class="rot">Média das variáveis</td><td class="r">${moeda(d.mediaVariaveis)}</td></tr>
    <tr><td class="rot"><b>13º integral apurado</b></td>
        <td class="r"><b>${moeda(d.valorBruto)}</b></td></tr>
    ${linhasDesconto}
    <tr class="tot"><td>Líquido desta parcela</td><td class="r">${moeda(d.totalLiquido)}</td></tr>
  </table>
  <p class="info" style="margin:10px 0 0">
    FGTS recolhido sobre esta parcela: ${moeda(d.valorFgts)} — encargo do empregador,
    não é desconto do empregado.
  </p>
</div>

<div class="bloco">
  <h2>Pagamento</h2>
  <table>
    <tr><td class="rot">Prazo legal</td><td class="r">${dataBR(d.dataPrevista)}</td></tr>
    <tr><td class="rot">Data do pagamento</td><td class="r">${dataBR(d.dataPagamento)}</td></tr>
  </table>
</div>

<p style="margin:18px 0 0">
  Declaro ter recebido a importância de <b>${moeda(d.totalLiquido)}</b>, referente à
  ${ordinal} parcela do 13º salário do ano-base ${d.ano}, dando plena quitação
  quanto ao valor ora recebido.
</p>

<div class="assin">
  <div class="linha"></div>
  ${esc(d.colaboradorNome)}${d.colaboradorCpf ? ` — CPF ${esc(d.colaboradorCpf)}` : ""}
</div>

<div class="rodape">
  Documento gerado pelo YourEyes em ${new Date().toLocaleString("pt-BR")}.<br>
  1ª parcela entre 1º de fevereiro e 30 de novembro; 2ª até 20 de dezembro (Lei 4.749/1965),
  antecipando quando a data cai em fim de semana ou feriado.
</div>

</body></html>`;
}

/** Memória de cálculo — é ela que torna o valor reproduzível e auditável. */
export function gerarMemoria13HTML(d: Recibo13Data): string {
  const mem = d.memoria || {};
  const avos = mem.memoria_avos || mem.apuracao?.memoria_avos || {};
  const media = mem.memoria_media || mem.apuracao?.memoria_media || {};
  const he = mem.memoria_horas_extras || mem.apuracao?.memoria_horas_extras || null;

  const linhasMeses = (avos.meses || [])
    .map((m: { mes: number; dias_vinculo: number; faltas: number; dias_inss: number; dias_computados: number; conta: boolean }) => `
      <tr class="${m.conta ? "" : "fora"}">
        <td>${MESES[m.mes - 1] ?? m.mes}</td>
        <td class="r">${m.dias_vinculo}</td>
        <td class="r">${m.faltas || 0}</td>
        <td class="r">${m.dias_inss || 0}</td>
        <td class="r">${m.dias_computados}</td>
        <td class="r">${m.conta ? "conta" : "não conta"}</td>
      </tr>`).join("");

  const linhasComp = (media.competencias || [])
    .map((c: { competencia: string; valor: number }) =>
      `<tr><td>${esc(c.competencia)}</td><td class="r">${moeda(c.valor)}</td></tr>`).join("");

  const linhasRub = (media.rubricas || [])
    .map((r: { descricao: string; valor: number }) =>
      `<tr><td>${esc(r.descricao)}</td><td class="r">${moeda(r.valor)}</td></tr>`).join("");

  const avisos = ([] as string[])
    .concat(avos.avisos || [], media.avisos || [])
    .map(a => `<li>${esc(a)}</li>`).join("");

  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<title>Memória de cálculo do 13º — ${esc(d.colaboradorNome)}</title><style>${ESTILO}</style></head><body>

<h1>MEMÓRIA DE CÁLCULO — 13º SALÁRIO</h1>
<div class="lei">${esc(d.colaboradorNome)}${d.colaboradorCpf ? ` · CPF ${esc(d.colaboradorCpf)}` : ""}
 · ano-base ${d.ano} · ${d.parcela === 1 ? "1ª" : "2ª"} parcela</div>

<div class="bloco">
  <h2>Avos — Lei 4.090/1962, art. 1º, § 2º (fração de 15 dias conta como mês)</h2>
  <table class="mini">
    <tr><td><b>Mês</b></td><td class="r"><b>Dias de vínculo</b></td><td class="r"><b>Faltas</b></td>
        <td class="r"><b>Dias por conta do INSS</b></td><td class="r"><b>Dias computados</b></td>
        <td class="r"><b>Resultado</b></td></tr>
    ${linhasMeses || `<tr><td colspan="6" class="info">Sem memória mês a mês registrada.</td></tr>`}
  </table>
  <p class="info" style="margin:10px 0 0">
    Total: <b>${d.avos}/12 avos</b>.
    ${avos.admissao ? `Admissão em ${dataBR(avos.admissao)}.` : ""}
    ${avos.desligamento ? `Desligamento em ${dataBR(avos.desligamento)}.` : ""}
    ${avos.tem_ponto === false ? " Sem registro de ponto no ano-base: os avos não descontaram faltas." : ""}
  </p>
</div>

<div class="bloco">
  <h2>Média das variáveis — Decreto 57.155/1965</h2>
  ${he && he.aplicavel ? `
  <p class="info" style="margin:0 0 10px">
    Horas extras pela <b>média física</b> (Súmula 347 do TST): ${he.horas_50 || 0}h a ${he.percentual_50 || 50}%
    e ${he.horas_100 || 0}h a ${he.percentual_100 || 100}%, ao valor da hora vigente de
    ${moeda(Number(he.valor_hora || 0))} — resultado ${moeda(Number(he.media || 0))}.
  </p>` : ""}
  <table class="mini">
    ${linhasRub ? `<tr><td colspan="2"><b>Rubricas somadas</b></td></tr>${linhasRub}` : ""}
    ${linhasComp ? `<tr><td colspan="2" style="padding-top:10px"><b>Competência a competência</b></td></tr>${linhasComp}` : ""}
    ${!linhasRub && !linhasComp ? `<tr><td class="info">Sem variáveis lançadas no ano-base.</td></tr>` : ""}
  </table>
  <p class="info" style="margin:10px 0 0">
    Média aplicada: <b>${moeda(d.mediaVariaveis)}</b>${media.meses_divisor ? ` (dividida por ${media.meses_divisor})` : ""}.
  </p>
</div>

<div class="bloco">
  <h2>Resultado</h2>
  <table>
    <tr><td class="rot">Remuneração base + média</td><td class="r">${moeda(d.remuneracaoBase + d.mediaVariaveis)}</td></tr>
    <tr><td class="rot">× ${d.avos}/12 avos</td><td class="r">${moeda(d.valorBruto)}</td></tr>
    ${d.parcela === 2 ? `
    <tr><td class="rot">(−) adiantamento</td><td class="r desc">${moeda(d.valorPrimeiraParcela)}</td></tr>
    <tr><td class="rot">(−) INSS</td><td class="r desc">${moeda(d.valorInss)}</td></tr>
    <tr><td class="rot">(−) IRRF</td><td class="r desc">${moeda(d.valorIrrf)}</td></tr>` : ""}
    <tr class="tot"><td>Líquido</td><td class="r">${moeda(d.totalLiquido)}</td></tr>
  </table>
</div>

${avisos ? `<div class="bloco"><h2>Avisos da apuração</h2><ul class="info">${avisos}</ul></div>` : ""}

<div class="rodape">
  Documento gerado pelo YourEyes em ${new Date().toLocaleString("pt-BR")}.<br>
  Esta memória reproduz o cálculo a partir das fontes (admissão, ponto, folha) e dos
  parâmetros vigentes na data da apuração.
</div>

</body></html>`;
}

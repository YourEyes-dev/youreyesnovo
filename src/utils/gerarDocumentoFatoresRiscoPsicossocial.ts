import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import type { ItemDiagnosticoPsicossocial } from "@/utils/inventarioDiagnosticoPsicossocial";
import type { NivelGRO15 } from "@/lib/groPsicossocial15";
import { NIVEL15_LABELS } from "@/lib/groPsicossocial15";

// Normaliza para WinAnsi (fontes padrão do jsPDF suportam Latin-1 acentuado)
const s = (t: string | null | undefined): string => (t || "").normalize("NFC");

export interface EmpresaDocumento {
  razao_social?: string | null;
  nome_fantasia?: string | null;
  cnpj?: string | null;
  endereco?: string | null;
  numero?: string | null;
  bairro?: string | null;
  cidade?: string | null;
  estado?: string | null;
  cnae_principal?: string | null;
  cnae_descricao?: string | null;
  grau_risco?: string | number | null;
}

export interface ResponsavelTecnicoDocumento {
  nome: string;
  ocupacao?: string | null;
  registro_profissional?: string | null;
}

export interface CampanhaDocumento {
  nome: string;
  data_inicio?: string | null;
  data_fim?: string | null;
  instrumento?: string | null;
  total_respostas?: number | null;
}

/** Ação do Plano de Ação PGR (tabela psicossocial_plano_acao) — 5W2H fiel ao módulo. */
export interface AcaoPlanoPGRDocumento {
  fator: string;
  ghe_nome?: string | null;
  nivel_gro?: string | null;
  o_que: string;
  quem?: string | null;
  onde?: string | null;
  por_que?: string | null;
  data_inicial?: string | null;
  ate_quando?: string | null;
  como?: string | null;
  quanto?: string | null;
}

/** Inventário estratificado por Grupo Homogêneo de Exposição (NR-01 / NR-17). */
export interface InventarioGHEDocumento {
  ghe_nome: string;
  ghe_codigo?: string | null;
  respondentes: number;
  elegiveis: number;
  /** Setores (departamentos) que compõem o GHE */
  setores?: string[];
  /** Funções (cargos) que compõem o GHE */
  funcoes?: string[];
  /** Composição detalhada Setor -> Funções */
  setorFuncoes?: { setor: string; funcoes: string[] }[];
  itens: ItemDiagnosticoPsicossocial[];
}

interface GerarDocumentoParams {
  empresa: EmpresaDocumento;
  responsavel: ResponsavelTecnicoDocumento;
  campanha: CampanhaDocumento;
  inventario: ItemDiagnosticoPsicossocial[];
  inventarioPorGHE?: InventarioGHEDocumento[];
  acoes: AcaoPlanoPGRDocumento[];
}

const NIVEL_CORES: Record<NivelGRO15, [number, number, number]> = {
  trivial: [90, 130, 150],
  baixo: [16, 150, 84],
  medio: [217, 158, 12],
  alto: [222, 107, 25],
  critico: [190, 30, 40],
};

const ROXO: [number, number, number] = [88, 28, 135];

const fmtData = (d?: string | null): string => {
  if (!d) return "";
  try {
    return format(new Date(d.slice(0, 10) + "T12:00:00"), "dd/MM/yyyy");
  } catch {
    return d;
  }
};

export async function gerarDocumentoFatoresRiscoPsicossocial({
  empresa,
  responsavel,
  campanha,
  inventario,
  inventarioPorGHE = [],
  acoes,
}: GerarDocumentoParams): Promise<void> {
  const doc = new jsPDF({ format: "a4", unit: "mm" });
  const pageW = doc.internal.pageSize.getWidth();
  const pageH = doc.internal.pageSize.getHeight();
  const marginX = 20;
  const marginTop = 30;
  const marginBottom = 22;
  const contentW = pageW - marginX * 2;
  let y = marginTop;

  const drawHeader = () => {
    doc.setFillColor(...ROXO);
    doc.rect(0, 0, pageW, 20, "F");
    doc.setTextColor(255, 255, 255);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(10);
    doc.text("YourEyes — Gestão Psicossocial NR-01", marginX, 9);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7.5);
    doc.text(s("Fatores de Risco Psicossociais Relacionados ao Trabalho — PGR / GRO"), marginX, 15);
    doc.text("NR-01 | NR-17 | ISO 45001 | ISO 45003", pageW - marginX, 15, { align: "right" });
    doc.setTextColor(30, 30, 30);
  };

  const ensureSpace = (needed: number) => {
    if (y + needed > pageH - marginBottom) {
      doc.addPage();
      drawHeader();
      y = marginTop;
    }
  };

  const writeTitle = (text: string, size = 12) => {
    ensureSpace(12);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(size);
    doc.setTextColor(...ROXO);
    const lines = doc.splitTextToSize(s(text), contentW) as string[];
    lines.forEach((ln) => {
      ensureSpace(6);
      doc.text(ln, marginX, y);
      y += 6;
    });
    doc.setDrawColor(...ROXO);
    doc.setLineWidth(0.4);
    doc.line(marginX, y - 3.5, marginX + contentW, y - 3.5);
    y += 2.5;
    doc.setTextColor(35, 35, 35);
  };

  const writeSubTitle = (text: string) => {
    ensureSpace(9);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(10.5);
    doc.setTextColor(60, 40, 110);
    const lines = doc.splitTextToSize(s(text), contentW) as string[];
    lines.forEach((ln) => {
      ensureSpace(5.5);
      doc.text(ln, marginX, y);
      y += 5.5;
    });
    y += 0.5;
    doc.setTextColor(35, 35, 35);
  };

  const writeParagraph = (text: string, fontSize = 9.5, lineHeight = 4.8) => {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(fontSize);
    doc.setTextColor(45, 45, 45);
    const lines = doc.splitTextToSize(s(text), contentW) as string[];
    lines.forEach((ln) => {
      ensureSpace(lineHeight);
      doc.text(ln, marginX, y);
      y += lineHeight;
    });
    y += 1.6;
  };

  const writeBullets = (items: string[], fontSize = 9, lineHeight = 4.6) => {
    doc.setFont("helvetica", "normal");
    doc.setFontSize(fontSize);
    doc.setTextColor(45, 45, 45);
    items.forEach((it) => {
      const indent = 5;
      const lines = doc.splitTextToSize(s(it), contentW - indent) as string[];
      ensureSpace(lineHeight);
      doc.text("•", marginX, y);
      lines.forEach((ln) => {
        ensureSpace(lineHeight);
        doc.text(ln, marginX + indent, y);
        y += lineHeight;
      });
      y += 0.6;
    });
    y += 1;
  };

  /** Fluxo de avaliação em etapas empilhadas (sem caracteres fora do WinAnsi). */
  const writeFluxo = (etapas: string[]) => {
    doc.setFontSize(9.5);
    etapas.forEach((etapa, i) => {
      ensureSpace(6.5);
      const label = s(`${i + 1}. ${etapa}`);
      doc.setFillColor(243, 235, 252);
      doc.setDrawColor(216, 204, 234);
      doc.setLineWidth(0.3);
      const boxW = 120;
      doc.roundedRect(marginX + 4, y - 3.8, boxW, 6.2, 1.2, 1.2, "FD");
      doc.setFont("helvetica", "bold");
      doc.setTextColor(...ROXO);
      doc.text(label, marginX + 8, y);
      y += 6.2;
      if (i < etapas.length - 1) {
        doc.setFillColor(150, 120, 190);
        doc.triangle(marginX + 9, y - 2.4, marginX + 13, y - 2.4, marginX + 11, y + 0.2, "F");
        y += 3.4;
      }
    });
    doc.setTextColor(45, 45, 45);
    y += 2;
  };

  const campoLinha = (rotulo: string, valor: string | null | undefined) => {
    ensureSpace(6);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(9.5);
    doc.setTextColor(35, 35, 35);
    doc.text(s(rotulo), marginX + 2, y);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(70, 70, 70);
    doc.text(s(valor || "—"), marginX + 55, y);
    y += 6;
  };

  const empresaNome = empresa.razao_social || empresa.nome_fantasia || "Empresa";
  const enderecoCompleto = [empresa.endereco, empresa.numero, empresa.bairro]
    .filter(Boolean)
    .join(", ");
  const periodo =
    campanha.data_inicio || campanha.data_fim
      ? `${campanha.data_inicio ? fmtData(campanha.data_inicio) : "—"} a ${campanha.data_fim ? fmtData(campanha.data_fim) : "em andamento"}`
      : null;

  // ═══════════════ CAPA ═══════════════
  drawHeader();
  y = 90;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(22);
  doc.setTextColor(...ROXO);
  const tituloCapa = doc.splitTextToSize(
    s("FATORES DE RISCO PSICOSSOCIAIS RELACIONADOS AO TRABALHO"),
    contentW
  ) as string[];
  tituloCapa.forEach((ln) => {
    doc.text(ln, pageW / 2, y, { align: "center" });
    y += 10;
  });
  y += 6;
  doc.setFont("helvetica", "normal");
  doc.setFontSize(13);
  doc.setTextColor(70, 70, 70);
  doc.text(s(empresaNome), pageW / 2, y, { align: "center" });
  y += 8;
  doc.setFontSize(11);
  doc.text(s(`Campanha: ${campanha.nome}`), pageW / 2, y, { align: "center" });
  y += 12;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(14);
  doc.setTextColor(...ROXO);
  doc.text(format(new Date(), "MM/yyyy"), pageW / 2, y, { align: "center" });

  doc.setFont("helvetica", "italic");
  doc.setFontSize(8.5);
  doc.setTextColor(120, 120, 120);
  doc.text(
    s("Documento integrante do Programa de Gerenciamento de Riscos (PGR / GRO) — NR-01 e NR-17"),
    pageW / 2,
    pageH - 30,
    { align: "center" }
  );

  // ═══════════════ 1. IDENTIFICAÇÃO ═══════════════
  doc.addPage();
  drawHeader();
  y = marginTop;

  writeTitle("1. IDENTIFICAÇÃO");
  y += 3;
  campoLinha("EMPRESA:", empresaNome);
  campoLinha("C.N.P.J.:", empresa.cnpj);
  campoLinha("ENDEREÇO:", enderecoCompleto || null);
  campoLinha("CIDADE:", empresa.cidade);
  campoLinha("ESTADO:", empresa.estado);
  campoLinha("CNAE:", empresa.cnae_principal);
  campoLinha("ATIVIDADE PRINCIPAL:", empresa.cnae_descricao);
  campoLinha("GRAU DE RISCO:", empresa.grau_risco != null ? String(empresa.grau_risco) : null);
  y += 2;

  writeSubTitle("RESPONSÁVEL TÉCNICO");
  campoLinha("NOME:", responsavel.nome);
  campoLinha("OCUPAÇÃO:", responsavel.ocupacao);
  campoLinha("REGISTRO PROFISSIONAL:", responsavel.registro_profissional);
  y += 2;

  writeSubTitle("CAMPANHA DE AVALIAÇÃO");
  campoLinha("CAMPANHA:", campanha.nome);
  if (periodo) campoLinha("PERÍODO:", periodo);
  if (campanha.instrumento) campoLinha("INSTRUMENTO:", campanha.instrumento.toUpperCase());
  if (campanha.total_respostas != null)
    campoLinha("PARTICIPAÇÕES:", String(campanha.total_respostas));
  y += 3;

  // ═══════════════ 2. INTRODUÇÃO ═══════════════
  writeTitle("2. INTRODUÇÃO");
  writeParagraph(
    "O presente documento integra a documentação técnica do Programa de Gerenciamento de Riscos (PGR / GRO), em estrita conformidade com as diretrizes da NR-01 (Gerenciamento de Riscos Ocupacionais) e da NR-17 (Ergonomia — Fatores Organizacionais e Psicossociais)."
  );
  writeParagraph(
    "Com a consolidação das normas regulamentadoras brasileiras, tornou-se mandatória a identificação, a avaliação e o controle contínuo dos fatores de risco psicossociais associados ao ambiente corporativo. Tais fatores envolvem as exigências quantitativas e cognitivas das tarefas, o ritmo de trabalho, a clareza de papéis, as relações interpessoais e a interface entre a organização do trabalho e a saúde mental do trabalhador."
  );
  writeParagraph("O objetivo deste relatório é:");
  writeBullets([
    "Identificar Fatores de Risco Psicossocial: mensurar a percepção dos colaboradores quanto às dimensões organizacionais e de saúde mental no trabalho.",
    "Classificar os Níveis de Risco (Matriz GRO): cruzar a probabilidade de ocorrência com a severidade do dano potencial para a priorização de medidas preventivas.",
    "Fundamentar o Plano de Ação (5W2H): estabelecer medidas de controle, responsabilidades corporativas e prazos operacionais para mitigar os riscos mapeados.",
  ]);

  // ═══════════════ 3. METODOLOGIA ═══════════════
  writeTitle("3. METODOLOGIA E FLUXO DE AVALIAÇÃO");
  writeParagraph(
    "A metodologia adotada para o mapeamento e a estruturação das ações alinha-se aos preceitos da ISO 45003:2021 (Gestão da Saúde Psicossocial no Trabalho) e da ISO 45001:2018 (Sistemas de Gestão de SST), operando por meio de um ciclo contínuo de gestão (PDCA)."
  );
  writeParagraph("Fluxo de Avaliação:");
  writeFluxo([
    "Mapeamento dos GHEs (Setor + Função)",
    "Coleta Multimodal",
    "Diagnóstico & Matriz GRO",
    "Plano de Ação (5W2H)",
  ]);

  writeSubTitle("3.1. Estruturação dos Grupos de Avaliação (NR-17 / NR-01)");
  writeParagraph(
    "Conforme exigência legal de rastreabilidade, a avaliação é estratificada por Grupos Homogêneos de Exposição (GHE), compostos pelas combinações de Setor + Função. Essa abordagem garante que cada risco identificado esteja atrelado à rotina e à realidade daquela específica atividade laboral."
  );

  writeSubTitle("3.2. Coleta de Dados e Garantia do Anonimato (LGPD e ISO 45003)");
  writeParagraph(
    "A etapa de diagnóstico psicossocial é operacionalizada por meio de três modalidades metodológicas padronizadas, definidas conforme o perfil da organização, a infraestrutura operacional e as especificidades de cada Grupo Homogêneo de Exposição (GHE):"
  );
  writeBullets([
    "Questionário Digital Estruturado: aplicação de instrumentos digitais padronizados (fundamentados nos modelos reconhecidos COPSOQ III e HSE), preenchidos de forma autônoma pelos colaboradores via dispositivos conectados.",
    "Entrevista Individual Guiada por IA: coleta qualitativa e quantitativa conduzida por um sistema interativo de Inteligência Artificial. A IA atua como agente facilitador de escuta, utilizando roteiros validados para orientar o colaborador de forma neutra, padronizada e sem viés. O sistema processa as interações, realiza a triagem estatística automatizada das respostas e sintetiza os indicadores de risco psicossocial sem expor dados individuais brutos.",
    "Entrevista Coletiva Guiada: aplicação de dinâmicas de escuta e diagnóstico em grupo, mediadas por roteiro direcionado, indicada para o mapeamento participativo das rotinas e processos organizacionais.",
  ]);
  writeParagraph("Governança dos Dados e Desdobramento dos Planos de Ação:");
  writeBullets([
    "Análise e Gestão Humana: os relatórios sintéticos gerados pelo sistema — independentemente da modalidade de coleta utilizada — são disponibilizados aos responsáveis técnicos pela gestão ocupacional (SST/RH). Cabe a esses profissionais a interpretação crítica dos diagnósticos e a elaboração técnica das medidas preventivas e corretivas no Plano de Ação (5W2H).",
    "Anonimização e Proteção de Dados: em estrito cumprimento à Lei Geral de Proteção de Dados (LGPD — Lei nº 13.709/18) e às orientações da ISO 45003 (§6.1.2), todas as interações e respostas coletadas são processadas com criptografia e sem qualquer vínculo nominativo ou de identificação individual dos colaboradores.",
    "Regra de Amostragem e Confidencialidade: para que os resultados por Função ou Setor sejam exibidos nos relatórios, exige-se uma amostragem mínima por grupo (mínimo de 5 respondentes). Em grupos com amostragem inferior, os dados são automaticamente consolidados em instâncias superiores (nível de Setor ou Geral da Empresa) para impedir qualquer possibilidade de identificação direta ou indireta.",
  ]);

  writeSubTitle("3.3. Matriz de Graduação de Risco Ocupacional (GRO / NR-01)");
  writeParagraph(
    "A severidade e a probabilidade são mensuradas para determinar a matriz final de risco do inventário, enquadrando os achados nos níveis operacionais: TRIVIAL, BAIXO, MÉDIO, ALTO e CRÍTICO. Nível de Risco (GRO) = Probabilidade x Severidade."
  );

  writeSubTitle("3.4. Integração com o Plano de Ação (GRO / PGR)");
  writeBullets([
    "Encaminhamento para o GRO/PGR: todos os fatores mapeados alimentam o inventário corporativo de riscos do PGR.",
    "Planos de Ação Obrigatórios: riscos classificados como ALTO ou CRÍTICO demandam a estruturação imediata de Planos de Ação 5W2H com prazos de intervenção prioritários (de 30 a 60 dias).",
  ]);

  // ═══════════════ 4. ESTRUTURA DOS ANEXOS ═══════════════
  writeTitle("4. ESTRUTURA DOS ANEXOS");
  writeParagraph(
    "A partir desta introdução e fundamentação metodológica, o presente relatório apresenta a seguinte documentação anexa:"
  );
  writeBullets([
    "ANEXO I: INVENTÁRIO DE RISCOS PSICOSSOCIAIS (GRO / NR-01).",
    "ANEXO II: PLANO DE AÇÃO ESTRATÉGICO PARA CONTROLE DE RISCOS PSICOSSOCIAIS (MODELO 5W2H).",
  ]);

  // ═══════════════ ANEXO I — INVENTÁRIO (Diagnóstico Psicossocial) ═══════════════
  doc.addPage();
  drawHeader();
  y = marginTop;
  writeTitle("ANEXO I — INVENTÁRIO DE RISCOS PSICOSSOCIAIS (GRO / NR-01)");

  const renderTabelaInventario = (itens: ItemDiagnosticoPsicossocial[]) => {
    autoTable(doc, {
      startY: y,
      margin: { left: marginX, right: marginX, top: marginTop, bottom: marginBottom },
      head: [["Fator de Risco", "Dimensões do Instrumento", "Base Normativa", "Score", "Probabilidade", "Severidade", "Grau de Risco"]],
      body: itens.map((item) => [
        s(item.fator),
        s(item.dimensoes.join(" • ")),
        s(item.norma),
        item.avaliado === false ? "—" : `${item.scoreReal}%`,
        s(item.probabilidadeLabel),
        s(item.severidadeLabel),
        s(item.nivelLabel),
      ]),
      styles: { font: "helvetica", fontSize: 7.4, cellPadding: 1.6, textColor: [45, 45, 45] },
      headStyles: { fillColor: ROXO, textColor: [255, 255, 255], fontStyle: "bold", fontSize: 7.6 },
      alternateRowStyles: { fillColor: [248, 245, 253] },
      columnStyles: {
        0: { cellWidth: 34 },
        1: { cellWidth: 36 },
        2: { cellWidth: 26 },
        3: { cellWidth: 12, halign: "center" },
        4: { cellWidth: 22 },
        5: { cellWidth: 20 },
        6: { cellWidth: 20, fontStyle: "bold" },
      },
      didParseCell: (data) => {
        if (data.section === "body" && data.column.index === 6) {
          const item = itens[data.row.index];
          if (item?.avaliado === false) {
            data.cell.styles.textColor = [120, 120, 120];
          } else if (item?.nivelKey && NIVEL_CORES[item.nivelKey]) {
            data.cell.styles.textColor = NIVEL_CORES[item.nivelKey];
          }
        }
      },
      didDrawPage: () => drawHeader(),
    });
    y = (doc as any).lastAutoTable.finalY + 6;
  };

  // Preferência do cliente: fatores sem cobertura no instrumento ("Não avaliada")
  // não devem constar nas tabelas do relatório.
  const somenteAvaliados = (itens: ItemDiagnosticoPsicossocial[]) =>
    itens.filter((i) => i.avaliado !== false);

  const escreverResumoNiveis = (itens: ItemDiagnosticoPsicossocial[]) => {
    const avaliados = somenteAvaliados(itens);
    const naoAvaliados = itens.length - avaliados.length;
    const contagem = (Object.keys(NIVEL15_LABELS) as NivelGRO15[]).reduce(
      (acc, nivel) => ({ ...acc, [nivel]: avaliados.filter((i) => i.nivelKey === nivel).length }),
      {} as Record<NivelGRO15, number>
    );
    ensureSpace(10);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(9);
    doc.setTextColor(35, 35, 35);
    const base = `Resumo: ${contagem.critico} crítico(s) · ${contagem.alto} alto(s) · ${contagem.medio} médio(s) · ${contagem.baixo} baixo(s) · ${contagem.trivial} trivial(is)`;
    doc.text(
      s(naoAvaliados > 0 ? `${base} · ${naoAvaliados} não avaliado(s)` : base),
      marginX,
      y
    );
    y += 8;
  };

  const temGHE = inventarioPorGHE.length > 0;

  if (temGHE) {
    writeSubTitle("I.1. Consolidado da campanha (todos os GHEs)");
  }
  const inventarioAvaliado = somenteAvaliados(inventario);
  const naoAvaliadosConsolidado = inventario.length - inventarioAvaliado.length;
  writeParagraph(
    `Diagnóstico psicossocial da campanha "${campanha.nome}": ${inventarioAvaliado.length} fator(es) do catálogo NR-01 / ISO 45003 avaliado(s) pelos itens do instrumento aplicado e inventariado(s) pela Matriz GRO (Probabilidade x Severidade), com severidade fixa do catálogo.` +
      (naoAvaliadosConsolidado > 0
        ? ` Os ${naoAvaliadosConsolidado} fator(es) restante(s) do catálogo são listados como "Não avaliado" porque o instrumento aplicado não possui item para eles — mantidos no inventário para rastreabilidade dos 13 fatores padrão (o instrumento não mede o que não pergunta; sua ausência não equivale a risco inexistente).`
        : "")
  );
  // Fase 0.6: listar os 13 fatores (os não cobertos marcados como "Não avaliado"),
  // em vez de omiti-los — inventário honesto e completo, sem fabricar medição.
  renderTabelaInventario(inventario);
  escreverResumoNiveis(inventario);


  // Estratificação obrigatória por GHE (NR-01 / NR-17): cada grupo tem o seu
  // próprio inventário, calculado apenas com as respostas daquele GHE.
  if (temGHE) {
    inventarioPorGHE.forEach((grupo, idx) => {
      doc.addPage();
      drawHeader();
      y = marginTop;
      const rotulo = [grupo.ghe_codigo, grupo.ghe_nome].filter(Boolean).join(" — ");
      writeSubTitle(`I.${idx + 2}. Inventário do GHE: ${rotulo}`);
      const itensGHE = somenteAvaliados(grupo.itens);
      writeParagraph(
        `Respondentes: ${grupo.respondentes}${grupo.elegiveis ? ` de ${grupo.elegiveis} elegível(is)` : ""} · ${itensGHE.length} fator(es) do catálogo avaliado(s) exclusivamente com as respostas deste Grupo Homogêneo de Exposição.`
      );

      // Composição cadastral do GHE (Setores x Funções) — exigência NR-01/NR-17
      const setorFuncoes = grupo.setorFuncoes ?? [];
      const setores = grupo.setores ?? [];
      const funcoes = grupo.funcoes ?? [];
      if (setorFuncoes.length > 0) {
        ensureSpace(20);
        autoTable(doc, {
          startY: y,
          margin: { left: marginX, right: marginX, top: marginTop, bottom: marginBottom },
          head: [["Setor / Departamento", "Funções (cargos)"]],
          body: setorFuncoes.map((sf) => [s(sf.setor || "—"), s((sf.funcoes || []).join(", ") || "—")]),
          styles: { font: "helvetica", fontSize: 7.6, cellPadding: 1.8, textColor: [45, 45, 45] },
          headStyles: { fillColor: ROXO, textColor: [255, 255, 255], fontStyle: "bold", fontSize: 7.8 },
          alternateRowStyles: { fillColor: [248, 245, 253] },
          columnStyles: { 0: { cellWidth: 55, fontStyle: "bold" }, 1: { cellWidth: contentW - 55 } },
          didDrawPage: () => drawHeader(),
        });
        y = (doc as any).lastAutoTable.finalY + 6;
      } else if (setores.length > 0 || funcoes.length > 0) {
        writeParagraph(
          `Composição do GHE — Setores: ${setores.join(", ") || "—"} · Funções: ${funcoes.join(", ") || "—"}.`
        );
      } else {
        writeParagraph("Composição do GHE não cadastrada (sem setores/funções vinculados).");
      }

      if (itensGHE.length === 0) {
        writeParagraph(
          "Sem resultados estratificados para este GHE até a data de emissão (amostragem insuficiente ou respostas ainda não vinculadas ao grupo)."
        );
        return;
      }
      renderTabelaInventario(itensGHE);
      escreverResumoNiveis(itensGHE);
    });
  }

  // ═══════════════ ANEXO II — PLANO DE AÇÃO PGR (5W2H) ═══════════════
  doc.addPage();
  drawHeader();
  y = marginTop;
  writeTitle("ANEXO II — PLANO DE AÇÃO ESTRATÉGICO (MODELO 5W2H)");

  if (acoes.length === 0) {
    writeParagraph(
      "Nenhuma ação registrada no Plano de Ação PGR para esta campanha até a data de emissão deste documento."
    );
  } else {
    writeParagraph(
      `Plano de Ação PGR da campanha, com ${acoes.length} medida(s) de controle estruturada(s) no modelo 5W2H.`
    );
    acoes.forEach((acao, idx) => {
      const cabecalho = [
        `AÇÃO ${idx + 1} — ${acao.fator}`,
        acao.ghe_nome ? `GHE: ${acao.ghe_nome}` : null,
        acao.nivel_gro ? NIVEL15_LABELS[acao.nivel_gro as NivelGRO15] || acao.nivel_gro : null,
      ]
        .filter(Boolean)
        .join("  ·  ");

      const linhas: [string, string][] = [
        ["O que (What)", acao.o_que || "—"],
        ["Por que (Why)", acao.por_que || "—"],
        ["Onde (Where)", acao.onde || "—"],
        ["Quem (Who)", acao.quem || "A definir"],
        ["Início (When)", acao.data_inicial ? fmtData(acao.data_inicial) : "A definir"],
        ["Até quando (When)", acao.ate_quando ? fmtData(acao.ate_quando) : "A definir"],
        ["Como (How)", acao.como || "—"],
        ["Quanto (How much)", acao.quanto || "—"],
      ];

      autoTable(doc, {
        startY: y,
        margin: { left: marginX, right: marginX, top: marginTop, bottom: marginBottom },
        head: [[{ content: s(cabecalho), colSpan: 2 }]],
        body: linhas.map(([k, v]) => [s(k), s(v)]),
        styles: { font: "helvetica", fontSize: 8.2, cellPadding: 1.8, textColor: [45, 45, 45] },
        headStyles: { fillColor: ROXO, textColor: [255, 255, 255], fontStyle: "bold", fontSize: 8.5 },
        columnStyles: { 0: { cellWidth: 40, fontStyle: "bold", fillColor: [248, 245, 253] } },
        didDrawPage: () => drawHeader(),
      });
      y = (doc as any).lastAutoTable.finalY + 5;
    });
  }

  // ═══════════════ ENCERRAMENTO E ASSINATURA ═══════════════
  ensureSpace(70);
  y += 8;
  writeParagraph(
    "Este documento foi elaborado com base nos dados coletados e consolidados pela plataforma YourEyes, cabendo ao responsável técnico a validação das informações e o acompanhamento da implementação das medidas previstas no plano de ação."
  );
  y += 6;

  ensureSpace(50);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(10);
  doc.setTextColor(45, 45, 45);
  const cidadeUf = [empresa.cidade, empresa.estado].filter(Boolean).join(" — ");
  doc.text(
    s(`${cidadeUf || "________________________"}, ${format(new Date(), "dd 'de' MMMM 'de' yyyy", { locale: ptBR })}.`),
    marginX,
    y
  );
  y += 26;

  const assinaturaW = 110;
  const assinaturaX = (pageW - assinaturaW) / 2;
  doc.setDrawColor(60, 60, 60);
  doc.setLineWidth(0.3);
  doc.line(assinaturaX, y, assinaturaX + assinaturaW, y);
  y += 5.5;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(10);
  doc.text(s(responsavel.nome), pageW / 2, y, { align: "center" });
  y += 5;
  doc.setFont("helvetica", "normal");
  doc.setFontSize(9);
  doc.setTextColor(80, 80, 80);
  if (responsavel.ocupacao) {
    doc.text(s(responsavel.ocupacao), pageW / 2, y, { align: "center" });
    y += 4.5;
  }
  if (responsavel.registro_profissional) {
    doc.text(s(`Registro profissional: ${responsavel.registro_profissional}`), pageW / 2, y, {
      align: "center",
    });
    y += 4.5;
  }
  doc.setFontSize(8.5);
  doc.text(s("Responsável Técnico"), pageW / 2, y, { align: "center" });

  // ═══════════════ RODAPÉ EM TODAS AS PÁGINAS ═══════════════
  const total = (doc as any).internal.getNumberOfPages();
  for (let i = 1; i <= total; i++) {
    doc.setPage(i);
    doc.setDrawColor(220, 220, 220);
    doc.setLineWidth(0.2);
    doc.line(marginX, pageH - 14, pageW - marginX, pageH - 14);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8);
    doc.setTextColor(120, 120, 120);
    doc.text(s("YourEyes — Segurança e Saúde no Trabalho"), marginX, pageH - 8);
    doc.text(`Pág. ${i} / ${total}`, pageW - marginX, pageH - 8, { align: "right" });
  }

  const safeEmpresa = (empresaNome || "empresa").replace(/[^a-zA-Z0-9]/g, "_").slice(0, 30);
  const safeCampanha = (campanha.nome || "campanha").replace(/[^a-zA-Z0-9]/g, "_").slice(0, 30);
  doc.save(`Fatores_Risco_Psicossociais_${safeEmpresa}_${safeCampanha}.pdf`);
}

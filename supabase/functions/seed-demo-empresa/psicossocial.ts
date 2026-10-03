// Psicossocial da empresa de demonstração: 2 campanhas SIPRO encerradas
// (março e setembro/2026), respostas fictícias com os indicadores
// calculados pelo mesmo código da tela (psicossocial-demo.ts), Índice de
// Confiabilidade e Plano de Ação PGR.
//
// O que cada painel lê (mapeado em 02/10/2026):
//  - Visão Geral / Histórico / Índices Derivados: colunas da campanha
//    (ips_score, radar_data, total_respostas, irps_score...), preenchidas pelo
//    gatilho trg_atualizar_ips_campanha a cada resposta inserida;
//  - Por GHE / Inventário PGR / Plano de Ação PGR: respostas com
//    ghe_id_snapshot (>= 5 por GHE) e o radar;
//  - Burnout & Boreout: radar_data da campanha;
//  - Confiabilidade: psicossocial_indice_confiabilidade da campanha mais recente.
//
// AJUSTE DELIBERADO (ver relatório do PR): para SIPRO, o questionário grava
// indicadores.IPS em escala de PROTEÇÃO (100 - IRP-S) e o gatilho tira a
// média disso; já a Visão Geral, o Histórico e a Análise Detalhada tratam o
// ips_score do SIPRO como IRP-S e mostram 100 - ips_score. Para a demo ficar
// coerente com o que as telas exibem hoje, depois das respostas a semeadura
// grava em ips_score a média do IRP-S (a classificação continua a do gatilho).

import { DEMO_EMPRESA_ID, DEMO_TENANT_ID, SETORES } from "./base.ts";
import { DEMO_PSICOSSOCIAL } from "./psicossocial-demo.ts";

export const CAMPANHA_ANTERIOR_ID = "d3e00000-0000-4000-8000-0000000000c1";
export const CAMPANHA_ATUAL_ID = "d3e00000-0000-4000-8000-0000000000c2";

// deno-lint-ignore no-explicit-any
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Admin = any;

interface CampanhaDef {
  id: string;
  nome: string;
  descricao: string;
  inicio: string;
  fim: string;
  criadaEm: string;
  respostas: readonly { ghe_codigo: string; respostas: Record<string, number>; indicadores: unknown; tempo_resposta_segundos: number }[];
}

const CAMPANHAS: CampanhaDef[] = [
  {
    id: CAMPANHA_ANTERIOR_ID,
    nome: "Avaliação Psicossocial NR-1 — 1º semestre 2026",
    descricao: "Primeira avaliação de riscos psicossociais da Metalúrgica Exemplo (empresa de demonstração).",
    inicio: "2026-03-02", fim: "2026-03-27", criadaEm: "2026-02-25T12:00:00Z",
    respostas: DEMO_PSICOSSOCIAL.anterior,
  },
  {
    id: CAMPANHA_ATUAL_ID,
    nome: "Avaliação Psicossocial NR-1 — 2º semestre 2026",
    descricao: "Reavaliação semestral após o plano de ação do 1º semestre (empresa de demonstração).",
    inicio: "2026-09-01", fim: "2026-09-26", criadaEm: "2026-08-26T12:00:00Z",
    respostas: DEMO_PSICOSSOCIAL.atual,
  },
];

function diaEntre(inicio: string, fim: string, fracao: number): string {
  const a = new Date(inicio + "T09:00:00Z").getTime();
  const b = new Date(fim + "T17:00:00Z").getTime();
  return new Date(a + (b - a) * fracao).toISOString();
}

export async function semearPsicossocial(admin: Admin, userId: string, ghes: Record<string, string>) {
  const resumo: Record<string, unknown> = {};
  const gheNome = Object.fromEntries(SETORES.map((s) => [s.ghe.codigo, s.ghe.nome]));
  const gheSetor = Object.fromEntries(SETORES.map((s) => [s.ghe.codigo, s.nome]));

  // Situações de trabalho (setor × função) — o Inventário PGR usa como escopo GRO.
  const { data: depts } = await admin.from("departamentos").select("id, nome").eq("tenant_id", DEMO_TENANT_ID);
  const { data: cargos } = await admin.from("cargos").select("id, nome, departamento_id").eq("tenant_id", DEMO_TENANT_ID);
  const deptNome = Object.fromEntries((depts ?? []).map((d: { id: string; nome: string }) => [d.id, d.nome]));
  const situacoes = (cargos ?? []).map((c: { id: string; nome: string; departamento_id: string }) => ({
    setorId: c.departamento_id, setorNome: deptNome[c.departamento_id] ?? "", funcaoId: c.id, funcaoNome: c.nome,
  }));

  for (const c of CAMPANHAS) {
    const { data: existe } = await admin.from("questionario_psicossocial_campanhas").select("id, total_respostas")
      .eq("id", c.id).maybeSingle();
    if (existe && (existe.total_respostas ?? 0) >= c.respostas.length) {
      resumo[c.nome] = "já existia";
      continue;
    }
    if (!existe) {
      const { error } = await admin.from("questionario_psicossocial_campanhas").insert({
        id: c.id, tenant_id: DEMO_TENANT_ID, empresa_id: DEMO_EMPRESA_ID,
        nome: c.nome, descricao: c.descricao,
        status: "encerrada", tipo: "regular", tipo_instrumento: "questionario", instrumento: "sipro",
        escopo: "empresa", anonimo: true, permite_identificacao_voluntaria: false,
        data_inicio: c.inicio, data_fim: c.fim,
        ghe_ids: Object.values(ghes),
        situacoes_trabalho: situacoes,
        blocos_dinamicos: [],
        criado_por: userId, criado_por_nome: "Ana Demonstração",
        created_at: c.criadaEm,
        token_publico: "demo_" + c.id.slice(-12),
      });
      if (error) throw new Error("campanha " + c.nome + ": " + error.message);
    }

    // Respostas: apaga as parciais (se uma execução anterior caiu no meio) e
    // insere de novo — o gatilho recalcula a campanha a cada linha.
    await admin.from("questionario_psicossocial_respostas").delete().eq("campanha_id", c.id);
    const linhas = c.respostas.map((r, i) => ({
      tenant_id: DEMO_TENANT_ID, campanha_id: c.id,
      respostas: r.respostas, indicadores: r.indicadores,
      ghe_id_snapshot: ghes[r.ghe_codigo] ?? null,
      ghe_nome_snapshot: gheNome[r.ghe_codigo] ?? null,
      setor_snapshot: gheSetor[r.ghe_codigo] ?? null,
      identificacao_voluntaria: false,
      tempo_resposta_segundos: r.tempo_resposta_segundos,
      concluido_em: diaEntre(c.inicio, c.fim, (i + 0.5) / c.respostas.length),
      created_at: diaEntre(c.inicio, c.fim, (i + 0.5) / c.respostas.length),
      user_agent: "seed-demo-empresa",
    }));
    const { error: rErr } = await admin.from("questionario_psicossocial_respostas").insert(linhas);
    if (rErr) throw new Error("respostas " + c.nome + ": " + rErr.message);

    // Ajuste da escala do SIPRO (ver cabeçalho): ips_score = média do IRP-S.
    const irps = c.respostas.map((r) => (r.indicadores as { IRP_S: number }).IRP_S);
    const mediaIrps = Math.round(irps.reduce((a, b) => a + b, 0) / irps.length);
    const { error: uErr } = await admin.from("questionario_psicossocial_campanhas")
      .update({ ips_score: mediaIrps }).eq("id", c.id);
    if (uErr) throw new Error("ajuste ips_score: " + uErr.message);
    resumo[c.nome] = { respostas: linhas.length, irps: mediaIrps, ips_exibido: 100 - mediaIrps };
  }

  // Índice de Confiabilidade da campanha atual (cruza com absenteísmo,
  // turnover etc. — aqui com números fictícios coerentes).
  const { data: ic } = await admin.from("psicossocial_indice_confiabilidade").select("id")
    .eq("campanha_id", CAMPANHA_ATUAL_ID).limit(1);
  if (!ic?.length) {
    const { error } = await admin.from("psicossocial_indice_confiabilidade").insert({
      tenant_id: DEMO_TENANT_ID, campanha_id: CAMPANHA_ATUAL_ID,
      indice_confiabilidade: 71, classificacao: "moderada",
      calculado_em: "2026-09-30T14:00:00Z", periodo_inicio: "2026-07-01", periodo_fim: "2026-09-30",
      total_colaboradores: 77,
      score_absenteismo: 68, score_acidentes: 80, score_turnover: 74,
      score_humor: 62, score_denuncias: 85, score_afastamentos: 58,
      detalhes: {
        absenteismo: { total: 41, descricao: "41 atestados no trimestre, concentrados em Produção e Manutenção" },
        acidentes: { total: 2, descricao: "2 ocorrências leves (sem afastamento) na Produção" },
        turnover: { total: 4, descricao: "4 desligamentos no trimestre (5,2%)" },
        humor: { total: 1180, descricao: "Humor médio 'neutro' com piora às segundas na Manutenção" },
        denuncias: { total: 1, descricao: "1 relato na Ouvidoria sobre sobrecarga de plantão" },
        afastamentos: { total: 3, descricao: "3 afastamentos acima de 15 dias (2 osteomusculares, 1 saúde mental)" },
      },
    });
    if (error) console.error("indice_confiabilidade:", error.message);
  }

  // Plano de Ação PGR (5W2H) para os GHEs com pontos de atenção.
  const { data: pa } = await admin.from("psicossocial_plano_acao").select("id")
    .eq("tenant_id", DEMO_TENANT_ID).limit(1);
  if (!pa?.length) {
    const campanhaIds = [CAMPANHA_ANTERIOR_ID, CAMPANHA_ATUAL_ID];
    const acao = (gheCod: string, fator: string, nivel: string, o_que: string, quem: string, como: string, ate: string, quanto: string, selecionada = true) => ({
      tenant_id: DEMO_TENANT_ID, empresa_id: DEMO_EMPRESA_ID, campanha_ids: campanhaIds,
      ghe_id: ghes[gheCod] ?? null, ghe_nome: gheNome[gheCod] ?? "Organização",
      fator_id: fator, fator, nivel_gro: nivel, o_que, quem, como,
      onde: gheSetor[gheCod] ?? "Toda a empresa",
      por_que: `Fator "${fator}" apontado na avaliação psicossocial (NR-1, GRO).`,
      data_inicial: "2026-10-05", ate_quando: ate, quanto, selecionada, origem: "manual", criado_por: userId,
    });
    const { error } = await admin.from("psicossocial_plano_acao").insert([
      acao("DEMO-GHE-MANUT", "Excesso de demandas (sobrecarga)", "alto",
        "Redimensionar a escala de sobreaviso da manutenção", "Supervisor de Manutenção",
        "Rodízio semanal com no máximo 1 sobreaviso por pessoa a cada 3 semanas e folga compensatória após acionamento noturno.",
        "2026-11-30", "R$ 6.000 (horas de sobreaviso redistribuídas)"),
      acao("DEMO-GHE-MANUT", "Falta de suporte no trabalho", "medio",
        "Criar par técnico de apoio nas manutenções corretivas críticas", "Supervisor de Manutenção",
        "Toda corretiva em equipamento crítico passa a ter dupla; registro no sistema de ordens de serviço.",
        "2026-12-15", "Sem custo adicional"),
      acao("DEMO-GHE-PROD", "Baixo controle no trabalho / Falta de autonomia", "alto",
        "Implantar reunião de início de turno com participação na definição do ritmo", "Líder de Produção",
        "10 minutos no início de cada turno para combinar metas do dia e pausas; operadores podem sinalizar gargalos.",
        "2026-11-15", "R$ 1.500 (quadro de gestão à vista)"),
      acao("DEMO-GHE-PROD", "Baixas recompensas e reconhecimento", "medio",
        "Programa mensal de reconhecimento por segurança e qualidade", "Analista de RH",
        "Indicação pelos pares e lideranças; reconhecimento público no mural e no app.",
        "2026-12-20", "R$ 800/mês"),
      acao("DEMO-GHE-LOG", "Baixa demanda de trabalho (subcarga)", "baixo",
        "Rodízio de funções entre recebimento e expedição", "Coordenador de Logística",
        "Rodízio quinzenal para reduzir monotonia, com treinamento cruzado registrado.",
        "2027-01-31", "Sem custo adicional", false),
    ]);
    if (error) console.error("psicossocial_plano_acao:", error.message);
  }

  return resumo;
}

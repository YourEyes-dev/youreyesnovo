/**
 * Programação Anual de Férias — grade (Fase 3A).
 *
 * Uma linha por colaborador com período aquisitivo em aberto. Junta:
 *   • Saldo e dias de direito reais — Fase 1 (ferias_periodos_aquisitivos)
 *   • Valor estimado do período — Fase 2 (feriasFinanceiro)
 *   • Limite concessivo e risco — feriasPeriodo
 *   • Programação editável (P1/P2/P3, abono) — ferias_programacao
 *
 * Saldo e valor NÃO são materializados na tabela de programação: vêm sempre do
 * motor, para não divergir das abas Saldos e Financeiro.
 */
import { useMemo } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useAuth } from "@/hooks/useAuth";
import { useFeriasPeriodos } from "@/hooks/useFeriasPeriodos";
import { limiteConcessivoDoPeriodo } from "@/lib/feriasPeriodo";
import {
  provisaoColaborador, ENCARGOS_PADRAO, type EncargosConfig,
} from "@/lib/feriasFinanceiro";
import { toast } from "sonner";

const EMPTY_FERIADOS: string[] = [];

export type EstadoProg =
  | "sugerido" | "planejado" | "confirmado" | "ciente"
  | "solicitado" | "aprovado" | "em_gozo" | "concluido" | "cancelado";

export interface SubPeriodo {
  inicio: string | null;
  fim: string | null;
  dias: number | null;
}

export interface LinhaProgramacao {
  // Identificação
  cpf: string;
  nome: string;
  colaboradorId: string | null;
  departamento: string;
  cargo: string;
  gestor: string;
  dataAdmissao: string;

  // Direito (Fase 1)
  aquisitivoInicio: string;
  aquisitivoFim: string;
  diasDireito: number;
  diasGozados: number;
  saldo: number;
  temPeriodosAnteriores: boolean;

  // Limite concessivo (feriasPeriodo)
  limiteConcessivo: string;
  /** Limite concessivo como Date, para o motor de regras. */
  limiteConcessivoDate: Date;
  diasParaVencimento: number;
  risco: "ok" | "alerta" | "vencido";

  // Programação (editável)
  progId: string | null;
  p1: SubPeriodo;
  p2: SubPeriodo;
  p3: SubPeriodo;
  abonoVender: boolean;
  abonoDias: number;
  adiantar13: boolean;
  estado: EstadoProg;
  /** Exceção ao limite concessivo autorizada pela diretoria (art. 134/137). */
  autorizadoExcecao: boolean;

  // Derivados
  diasProgramados: number;
  diasNaoProgramados: number;
  valorEstimado: number;

  // Contexto 3B-2 (para o motor de regras)
  feriados: string[];
  feriasFamiliares: { nome: string; inicio: string; fim: string }[];
  afastamentoReinicia: { motivo: string; diasTotais: number } | null;

  // Para conversão em solicitação (3C)
  salario: number;
}

interface AdmissaoInfo {
  id: string;
  nome: string;
  cargo: string;
  departamento: string;
  gestor: string;
  salario: number;
  dataAdmissao: string;
}

function estadoDe(v: unknown): EstadoProg {
  const s = String(v ?? "planejado");
  const ok: EstadoProg[] = ["sugerido","planejado","confirmado","ciente","solicitado","aprovado","em_gozo","concluido","cancelado"];
  return (ok as string[]).includes(s) ? (s as EstadoProg) : "planejado";
}

export function useFeriasProgramacao() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const { user } = useAuth();
  const qc = useQueryClient();
  const { periodos } = useFeriasPeriodos();

  // Admissões (dados de cadastro + salário para o valor estimado)
  const admissoesQuery = useQuery({
    queryKey: ["ferias-prog-admissoes", tenantId, empresaAtivaId],
    enabled: !!tenantId,
    queryFn: async () => {
      let q = fromTable("admissoes")
        .select("id, nome_completo, cpf, cargo, departamento, gestor_imediato, salario, data_admissao")
        .eq("tenant_id", tenantId).eq("status", "concluido");
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data } = await q;
      const map = new Map<string, AdmissaoInfo>();
      for (const a of data ?? []) {
        const cpf = String(a.cpf ?? "").replace(/\D/g, "");
        if (cpf) map.set(cpf, {
          id: a.id,
          nome: a.nome_completo,
          cargo: a.cargo || "",
          departamento: a.departamento || "",
          gestor: a.gestor_imediato || "",
          salario: Number(a.salario ?? 0),
          dataAdmissao: a.data_admissao || "",
        });
      }
      return map;
    },
  });

  // Encargos (para o valor estimado)
  const encargosQuery = useQuery({
    queryKey: ["ferias-encargos", tenantId, empresaAtivaId],
    enabled: !!tenantId,
    queryFn: async (): Promise<EncargosConfig> => {
      let q = fromTable("ferias_config").select("*").eq("tenant_id", tenantId);
      q = empresaAtivaId ? q.eq("empresa_id", empresaAtivaId) : q.is("empresa_id", null);
      const { data } = await q.maybeSingle();
      if (!data) return ENCARGOS_PADRAO;
      return {
        inssPatronal: Number(data.encargo_inss_patronal ?? 20),
        ratFap: Number(data.encargo_rat_fap ?? 2),
        terceiros: Number(data.encargo_terceiros ?? 5.8),
        fgts: Number(data.encargo_fgts ?? 8),
        simplesDispensaPatronal: !!data.simples_dispensa_patronal,
      };
    },
  });

  // Programações existentes
  const progQuery = useQuery({
    queryKey: ["ferias-programacao", tenantId, empresaAtivaId],
    enabled: !!tenantId,
    queryFn: async () => {
      let q = fromTable("ferias_programacao").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data } = await q;
      const map = new Map<string, Record<string, unknown>>();
      for (const p of data ?? []) {
        map.set(`${String(p.colaborador_cpf).replace(/\D/g,"")}|${p.aquisitivo_inicio}`, p);
      }
      return map;
    },
  });

  // Feriados (art. 134 §3º) — datas do ano corrente e do próximo
  const feriadosQuery = useQuery({
    queryKey: ["ferias-prog-feriados", tenantId],
    enabled: !!tenantId,
    queryFn: async (): Promise<string[]> => {
      const anoIni = `${new Date().getFullYear()}-01-01`;
      const anoFim = `${new Date().getFullYear() + 1}-12-31`;
      const { data } = await fromTable("feriados")
        .select("data, tipo")
        .gte("data", anoIni).lte("data", anoFim);
      // Só feriados de fato (não facultativos) contam para o art. 134 §3º.
      return (data ?? [])
        .filter((f: Record<string, unknown>) => f.tipo !== "facultativo")
        .map((f: Record<string, unknown>) => String(f.data));
    },
  });

  // Afastamentos longos (art. 133) por CPF — >30 dias reinicia o aquisitivo
  const afastQuery = useQuery({
    queryKey: ["ferias-prog-afastamentos", tenantId, empresaAtivaId],
    enabled: !!tenantId,
    queryFn: async () => {
      const { data } = await fromTable("afastamentos")
        .select("colaborador_cpf, motivo_principal, dias_totais, status")
        .eq("tenant_id", tenantId);
      const map = new Map<string, { motivo: string; diasTotais: number }>();
      for (const a of data ?? []) {
        const cpf = String(a.colaborador_cpf ?? "").replace(/\D/g, "");
        const dias = Number(a.dias_totais ?? 0);
        // Art. 133: licença remunerada > 30 dias reinicia o aquisitivo.
        if (cpf && dias > 30) {
          const cur = map.get(cpf);
          if (!cur || dias > cur.diasTotais) {
            map.set(cpf, { motivo: String(a.motivo_principal ?? "afastamento"), diasTotais: dias });
          }
        }
      }
      return map;
    },
  });

  // Vínculos familiares por CPF (art. 136)
  const vinculoQuery = useQuery({
    queryKey: ["ferias-prog-vinculos", tenantId, empresaAtivaId],
    enabled: !!tenantId,
    queryFn: async () => {
      let q = fromTable("ferias_vinculo_familiar").select("cpf_a, nome_a, cpf_b, nome_b").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data } = await q;
      // cpf -> lista de {cpf, nome} de parentes
      const map = new Map<string, { cpf: string; nome: string }[]>();
      const add = (cpf: string, parente: { cpf: string; nome: string }) => {
        const k = cpf.replace(/\D/g, "");
        (map.get(k) ?? map.set(k, []).get(k)!).push(parente);
      };
      for (const r of data ?? []) {
        const a = String(r.cpf_a).replace(/\D/g,""), b = String(r.cpf_b).replace(/\D/g,"");
        add(a, { cpf: b, nome: String(r.nome_b) });
        add(b, { cpf: a, nome: String(r.nome_a) });
      }
      return map;
    },
  });

  const admissoes = admissoesQuery.data;
  const encargos = encargosQuery.data ?? ENCARGOS_PADRAO;
  const progs = progQuery.data;
  const feriados = feriadosQuery.data ?? EMPTY_FERIADOS;
  const afastamentos = afastQuery.data;
  const vinculos = vinculoQuery.data;

  const linhas = useMemo<LinhaProgramacao[]>(() => {
    if (!admissoes) return [];

    // Agrupa períodos por CPF para saber quem tem mais de um em aberto.
    const porCpf = new Map<string, typeof periodos>();
    for (const p of periodos) {
      if (p.status === "encerrado") continue;
      const k = p.colaboradorCpf.replace(/\D/g, "");
      (porCpf.get(k) ?? porCpf.set(k, []).get(k)!).push(p);
    }

    const out: LinhaProgramacao[] = [];
    for (const [cpf, lista] of porCpf) {
      const info = admissoes.get(cpf);
      if (!info) continue;
      // Usa o período aquisitivo mais recente como o "programável" da linha.
      const periodo = lista.slice().sort((a, b) => a.aquisitivoInicio.localeCompare(b.aquisitivoInicio)).at(-1)!;

      // Limite concessivo do PERÍODO da linha (aquisitivo_fim + 12 meses), não
      // o derivado da admissão — que apontava para o período em curso e dava um
      // vencimento errado (otimista) quando a linha é de um período importado.
      const limiteReal = limiteConcessivoDoPeriodo(periodo.aquisitivoFim);

      const prog = progs?.get(`${cpf}|${periodo.aquisitivoInicio}`);

      const sub = (n: 1 | 2 | 3): SubPeriodo => ({
        inicio: (prog?.[`p${n}_inicio`] as string) ?? null,
        fim: (prog?.[`p${n}_fim`] as string) ?? null,
        dias: (prog?.[`p${n}_dias`] as number) ?? null,
      });
      const p1 = sub(1), p2 = sub(2), p3 = sub(3);
      const abonoDias = Number(prog?.abono_dias ?? 0);
      const diasProgramados = (p1.dias ?? 0) + (p2.dias ?? 0) + (p3.dias ?? 0) + abonoDias;

      const valorEstimado = info.salario > 0
        ? provisaoColaborador({
            cpf, nome: info.nome, remuneracaoMensal: info.salario,
            diasDireitoAcumulados: diasProgramados > 0 ? diasProgramados : periodo.diasSaldo,
            encargos,
          }).total
        : 0;

      out.push({
        cpf, nome: info.nome, colaboradorId: info.id,
        departamento: info.departamento, cargo: info.cargo, gestor: info.gestor,
        dataAdmissao: info.dataAdmissao,
        aquisitivoInicio: periodo.aquisitivoInicio,
        aquisitivoFim: periodo.aquisitivoFim,
        diasDireito: periodo.diasDireito,
        diasGozados: periodo.diasGozados,
        saldo: periodo.diasSaldo,
        temPeriodosAnteriores: lista.length > 1,
        limiteConcessivo: limiteReal.limiteLabel,
        limiteConcessivoDate: limiteReal.limite,
        diasParaVencimento: limiteReal.diasParaVencimento,
        risco: limiteReal.status,
        progId: (prog?.id as string) ?? null,
        p1, p2, p3,
        abonoVender: !!prog?.abono_vender,
        abonoDias,
        adiantar13: !!prog?.adiantar_13,
        estado: estadoDe(prog?.estado),
        autorizadoExcecao: !!prog?.autorizado_excecao,
        diasProgramados,
        diasNaoProgramados: Math.max(0, periodo.diasSaldo - diasProgramados),
        valorEstimado,
        feriados,
        feriasFamiliares: (vinculos?.get(cpf) ?? []).flatMap(parente => {
          // Férias já programadas (com P1) do parente.
          const prg = progs?.get(
            [...(progs?.keys() ?? [])].find(k => k.startsWith(`${parente.cpf.replace(/\D/g,"")}|`)) ?? "",
          );
          if (prg?.p1_inicio && prg?.p1_fim) {
            return [{ nome: parente.nome, inicio: String(prg.p1_inicio), fim: String(prg.p1_fim) }];
          }
          return [];
        }),
        afastamentoReinicia: afastamentos?.get(cpf) ?? null,
        salario: info.salario,
      });
    }

    return out.sort((a, b) => a.diasParaVencimento - b.diasParaVencimento);
  }, [admissoes, periodos, progs, encargos, feriados, afastamentos, vinculos]);

  // Salvar (upsert) uma linha de programação
  const salvar = useMutation({
    mutationFn: async (l: LinhaProgramacao) => {
      const payload = {
        tenant_id: tenantId,
        empresa_id: empresaAtivaId ?? null,
        colaborador_cpf: l.cpf,
        colaborador_nome: l.nome,
        colaborador_id: l.colaboradorId,
        aquisitivo_inicio: l.aquisitivoInicio,
        aquisitivo_fim: l.aquisitivoFim,
        p1_inicio: l.p1.inicio, p1_fim: l.p1.fim, p1_dias: l.p1.dias,
        p2_inicio: l.p2.inicio, p2_fim: l.p2.fim, p2_dias: l.p2.dias,
        p3_inicio: l.p3.inicio, p3_fim: l.p3.fim, p3_dias: l.p3.dias,
        abono_vender: l.abonoVender,
        abono_dias: l.abonoDias,
        adiantar_13: l.adiantar13,
        estado: l.estado,
        autorizado_excecao: l.autorizadoExcecao,
        criado_por: user?.id ?? null,
      };
      const { error } = await fromTable("ferias_programacao").upsert(payload, {
        onConflict: "tenant_id,colaborador_cpf,aquisitivo_inicio",
      });
      if (error) {
        // Trava do concessivo no banco (art. 134/137): mensagem clara em vez do erro cru.
        if (error.code === "23514" || /concessivo|alçada|alcada|diretoria/i.test(error.message ?? "")) {
          throw new Error("Programação além do limite concessivo exige autorização da diretoria (admin ou acima).");
        }
        throw error;
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ferias-programacao"] });
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : "Falha ao salvar programação"),
  });

  // Confirmar (gestor valida — trava a data)
  const confirmar = useMutation({
    mutationFn: async (progId: string) => {
      const { error } = await fromTable("ferias_programacao").update({
        estado: "confirmado",
        confirmado_por: user?.id ?? null,
        confirmado_em: new Date().toISOString(),
      }).eq("id", progId);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["ferias-programacao"] });
      toast.success("Programação confirmada.");
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : "Falha ao confirmar"),
  });

  // Converter em solicitação formal (3C) — sem redigitação.
  // Cada sub-período (P1/P2/P3) vira uma solicitação; a programação passa a
  // 'solicitado' e guarda a solicitação do P1 como referência.
  const converter = useMutation({
    mutationFn: async (l: LinhaProgramacao) => {
      if (!l.progId) throw new Error("Programação ainda não salva.");
      if (l.estado !== "confirmado") throw new Error("Só programações confirmadas podem ser convertidas.");

      const subs = [l.p1, l.p2, l.p3].filter(s => s.inicio && s.fim && (s.dias ?? 0) > 0);
      if (subs.length === 0) throw new Error("Nenhum período com datas para converter.");

      const salarioDia = l.salario / 30;
      let primeiraSolicitacaoId: string | null = null;

      for (let i = 0; i < subs.length; i++) {
        const s = subs[i];
        const dias = s.dias!;
        const valorFerias = salarioDia * dias;
        const valorTerco = valorFerias / 3;
        // O abono só entra na primeira solicitação, para não duplicar.
        const abono = i === 0 && l.abonoVender;
        const valorAbono = abono ? salarioDia * l.abonoDias : 0;

        const { data, error } = await fromTable("ferias_solicitacoes").insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId ?? null,
          colaborador_nome: l.nome,
          colaborador_cpf: l.cpf,
          // colaborador_id NÃO é enviado: a coluna é FK para auth.users(id), mas
          // l.colaboradorId vem de admissoes.id (outro domínio de UUID). Mandar
          // esse valor viola a FK. A solicitação se identifica por CPF.
          departamento: l.departamento || null,
          cargo: l.cargo || null,
          data_inicio: s.inicio,
          data_fim: s.fim,
          dias_solicitados: dias,
          saldo_dias: l.saldo,
          abono_pecuniario: abono,
          dias_abono: abono ? l.abonoDias : 0,
          salario_base: l.salario,
          periodo_aquisitivo_inicio: l.aquisitivoInicio,
          periodo_aquisitivo_fim: l.aquisitivoFim,
          valor_ferias: valorFerias,
          valor_terco: valorTerco,
          valor_abono: valorAbono,
          valor_total_bruto: valorFerias + valorTerco + valorAbono,
          status: "pendente",
          observacoes: `Gerada da Programação Anual${subs.length > 1 ? ` (período ${i + 1}/${subs.length})` : ""}.`,
        }).select("id").single();
        if (error) throw error;
        if (i === 0) primeiraSolicitacaoId = (data as { id: string })?.id ?? null;
      }

      // Programação passa a 'solicitado' e referencia a solicitação do P1.
      const { error: upErr } = await fromTable("ferias_programacao").update({
        estado: "solicitado",
        solicitacao_id: primeiraSolicitacaoId,
      }).eq("id", l.progId);
      if (upErr) throw upErr;

      return subs.length;
    },
    onSuccess: (qtd) => {
      qc.invalidateQueries({ queryKey: ["ferias-programacao"] });
      qc.invalidateQueries({ queryKey: ["ferias_solicitacoes"] });
      toast.success(
        qtd === 1
          ? "Programação convertida em solicitação."
          : `${qtd} solicitações geradas da programação.`,
        { description: "Veja na aba Solicitações para aprovar." },
      );
    },
    onError: (e) => toast.error("Falha ao converter", {
      description: e instanceof Error ? e.message : String(e),
    }),
  });

  return {
    linhas,
    isLoading: admissoesQuery.isLoading || progQuery.isLoading,
    temSaldos: periodos.some(p => p.status !== "encerrado"),
    salvar,
    confirmar,
    converter,
  };
}

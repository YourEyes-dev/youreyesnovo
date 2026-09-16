import { useQuery } from "@tanstack/react-query";
import { useMemo } from "react";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import type { RadarDimensao } from "@/types/psicossocial";

interface RespostaRow {
  id: string;
  campanha_id: string;
  ghe_id_snapshot: string | null;
  ghe_nome_snapshot: string | null;
  setor_snapshot: string | null;
  cargo_snapshot: string | null;
  indicadores: { radar?: RadarDimensao[]; IPS?: number } | null;
  /** Marca as linhas derivadas de entrevistas guiadas (não anônimas). */
  origem_entrevista?: boolean;
}

interface CampanhaGheRow {
  id: string;
  ghe_ids: string[] | null;
  empresa_id: string | null;
}

interface GheRow {
  id: string;
  nome: string;
  codigo?: string | null;
  empresa_id?: string | null;
}

interface GheCargoRow {
  ghe_id: string;
  cargo_id: string | null;
  departamento_id: string | null;
}

export interface EstratoGHE {
  nome: string;
  count: number;
  ipsMedio: number | null;
}

export interface SetorComposicao {
  setor: string;
  cargos: string[];
}

export interface ResultadoGHE {
  ghe_id: string | null;
  ghe_nome: string;
  ghe_codigo?: string | null;
  count: number;
  elegiveis: number;
  radar: RadarDimensao[];
  ipsMedio: number | null;
  campanhas: number;
  setores: EstratoGHE[];
  cargos: EstratoGHE[];
  composicaoSetores: string[];
  composicaoCargos: string[];
  composicaoSetorCargos: SetorComposicao[];
}


/**
 * Agrega respostas psicossociais por GHE.
 * Prioriza `ghe_id_snapshot` da resposta; quando ausente, usa o `ghe_ids`
 * da campanha (atribui a resposta a cada GHE vinculado à campanha).
 * Também carrega a composição cadastral do GHE (setores + cargos) via
 * `psicossocial_ghe_cargos` para exibir as informações básicas mesmo
 * quando os snapshots vierem vazios.
 */

interface EntrevistaRow {
  id: string;
  campanha_id: string;
  ghe_id_snapshot: string | null;
  resumo_ia: {
    riscos?: { risco_nome?: string; presente?: boolean; probabilidade?: number; severidade?: number }[];
  } | null;
}

/**
 * Converte entrevistas guiadas concluídas em "respostas" equivalentes:
 * cada risco vira um eixo do radar (P × S × 4, escala 0-100) e o IPS é o
 * índice protetivo (100 − risco médio) — mesma regra de
 * `useEntrevistasGuiadasAggregates`, porém por entrevista (individual),
 * para permitir a estratificação por GHE.
 */
function entrevistasParaRespostas(rows: EntrevistaRow[]): RespostaRow[] {
  return rows.map((e) => {
    const riscos = e.resumo_ia?.riscos ?? [];
    const radar: RadarDimensao[] = [];
    for (const r of riscos) {
      if (!r.risco_nome) continue;
      const prob = Number(r.probabilidade) || (r.presente === false ? 1 : 0);
      const sev = Number(r.severidade) || (r.presente === false ? 1 : 0);
      radar.push({
        subject: r.risco_nome,
        value: Math.min(100, Math.max(0, prob * sev * 4)),
        fullMark: 100,
      });
    }
    const riscoMedio = radar.length > 0
      ? radar.reduce((a, b) => a + b.value, 0) / radar.length
      : 0;
    return {
      id: e.id,
      campanha_id: e.campanha_id,
      ghe_id_snapshot: e.ghe_id_snapshot,
      ghe_nome_snapshot: null,
      setor_snapshot: null,
      cargo_snapshot: null,
      indicadores: radar.length > 0
        ? { radar, IPS: Math.round(100 - riscoMedio) }
        : null,
      origem_entrevista: true,
    };
  });
}


export function usePsicossocialResultadosGHE(campanhaIds: string[] | undefined) {
  const { tenantId } = useTenant();
  const idsKey = (campanhaIds ?? []).slice().sort().join(",");

  // Antes de agregar: preenche ghe_id_snapshot das respostas que ainda não têm,
  // cruzando cpf_hash -> admissão -> GHE no servidor (sem expor CPF). As funções
  // de gravação de resposta anônima não gravam o snapshot; sem este passo, as
  // respostas ficam sem GHE e o resultado é replicado igual em todos os GHEs.
  // A rotina é idempotente e reavalia os vínculos atuais antes da leitura.
  const preenchimentoQuery = useQuery({
    queryKey: ["psicossocial-preencher-ghe-snapshot-v2", tenantId, idsKey],
    enabled: !!tenantId && !!campanhaIds && campanhaIds.length > 0,
    staleTime: 0,
    refetchOnMount: "always",
    queryFn: async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rpc = supabase.rpc as any;
      const [respRes, entRes] = await Promise.all([
        rpc("preencher_ghe_snapshot_respostas", { p_campanha_ids: campanhaIds }),
        // Entrevistas guiadas individuais: sem este passo, ao vincular o GHE à
        // campanha as entrevistas já concluídas ficavam sem `ghe_id_snapshot` e
        // o painel por GHE aparecia zerado.
        rpc("preencher_ghe_snapshot_entrevistas", { p_campanha_ids: campanhaIds }),
      ]);
      if (respRes.error) throw respRes.error;
      if (entRes.error) throw entRes.error;
      return Number(respRes.data ?? 0) + Number(entRes.data ?? 0);
    },
  });



  const query = useQuery({
    queryKey: ["psicossocial-respostas-por-ghe-v3", tenantId, idsKey, preenchimentoQuery.data ?? 0],
    enabled: !!tenantId && !!campanhaIds && campanhaIds.length > 0 && !preenchimentoQuery.isLoading,
    queryFn: async () => {
      if (!tenantId || !campanhaIds || campanhaIds.length === 0) {
        return {
          respostas: [] as RespostaRow[],
          campanhasGhe: [] as CampanhaGheRow[],
          ghes: [] as GheRow[],
          composicaoPorGhe: new Map<string, { setores: string[]; cargos: string[]; setorCargos: Map<string, Set<string>> }>(),
          elegiveisPorGhe: new Map<string, number>(),
          entrevistasPorGhe: new Map<string, number>(),
        };
      }

      const [respRes, campRes, entRes] = await Promise.all([
        fromTable("questionario_psicossocial_respostas")
          .select("id, campanha_id, ghe_id_snapshot, ghe_nome_snapshot, setor_snapshot, cargo_snapshot, indicadores")
          .eq("tenant_id", tenantId)
          .in("campanha_id", campanhaIds)
          .not("indicadores", "is", null),

        fromTable("questionario_psicossocial_campanhas")
          .select("id, ghe_ids, empresa_id")
          .eq("tenant_id", tenantId)
          .in("id", campanhaIds),

        // Entrevistas guiadas individuais concluídas — viram "respostas"
        // equivalentes (radar/IPS derivados de resumo_ia) para entrar na
        // estratificação por GHE.
        fromTable("psicossocial_entrevistas")
          .select("id, campanha_id, ghe_id_snapshot, resumo_ia")
          .eq("tenant_id", tenantId)
          .in("campanha_id", campanhaIds)
          .eq("status", "concluida")
          .not("resumo_ia", "is", null),
      ]);

      if (respRes.error) throw respRes.error;
      if (campRes.error) throw campRes.error;
      if (entRes.error) throw entRes.error;

      const respostasQuestionario = (respRes.data ?? []) as unknown as RespostaRow[];
      const campanhasGhe = (campRes.data ?? []) as unknown as CampanhaGheRow[];
      const respostasEntrevista = entrevistasParaRespostas(
        (entRes.data ?? []) as unknown as EntrevistaRow[],
      );
      const respostas = [...respostasQuestionario, ...respostasEntrevista];
      const entrevistasPorGhe = new Map<string, number>();
      for (const e of respostasEntrevista) {
        if (!e.ghe_id_snapshot) continue;
        entrevistasPorGhe.set(e.ghe_id_snapshot, (entrevistasPorGhe.get(e.ghe_id_snapshot) ?? 0) + 1);
      }


      // Combina GHE ids da campanha + snapshots das respostas para carregar composição completa
      const allGheIds = Array.from(
        new Set([
          ...campanhasGhe.flatMap((c) => c.ghe_ids ?? []),
          ...respostas.map((r) => r.ghe_id_snapshot).filter(Boolean) as string[],
        ].filter(Boolean))
      );

      let ghes: GheRow[] = [];
      const composicaoPorGhe = new Map<string, { setores: string[]; cargos: string[]; setorCargos: Map<string, Set<string>> }>();
      const elegiveisPorGhe = new Map<string, number>();

      if (allGheIds.length > 0) {
        const [ghesRes, ghesCargosRes] = await Promise.all([
          fromTable("psicossocial_ghe")
            .select("id, nome, codigo, empresa_id")
            .in("id", allGheIds),
          fromTable("psicossocial_ghe_cargos")
            .select("ghe_id, cargo_id, departamento_id")
            .in("ghe_id", allGheIds),
        ]);

        if (ghesRes.error) throw ghesRes.error;
        if (ghesCargosRes.error) throw ghesCargosRes.error;

        // Isolamento por empresa: um snapshot antigo pode apontar para um GHE
        // de OUTRA empresa do mesmo tenant (nomes iguais, ex.: "GHE 01").
        // Só entram no relatório os GHEs da(s) empresa(s) das campanhas.
        const empresasCampanha = new Set(
          campanhasGhe.map((c) => c.empresa_id).filter(Boolean) as string[],
        );
        ghes = ((ghesRes.data ?? []) as unknown as GheRow[]).filter((g) => {
          if (empresasCampanha.size === 0) return true;
          if (!g.empresa_id) return true;
          return empresasCampanha.has(g.empresa_id);
        });
        const gheIdsValidos = new Set(ghes.map((g) => g.id));
        const gheCargos = ((ghesCargosRes.data ?? []) as unknown as GheCargoRow[])
          .filter((gc) => gheIdsValidos.has(gc.ghe_id));

        const cargoIds = Array.from(new Set(gheCargos.map((g) => g.cargo_id).filter(Boolean) as string[]));
        const deptIds = Array.from(new Set(gheCargos.map((g) => g.departamento_id).filter(Boolean) as string[]));

        const [cargosRes, deptsRes] = await Promise.all([
          cargoIds.length > 0
            ? fromTable("cargos").select("id, nome").in("id", cargoIds)
            : Promise.resolve({ data: [], error: null }),
          deptIds.length > 0
            ? fromTable("departamentos").select("id, nome").in("id", deptIds)
            : Promise.resolve({ data: [], error: null }),
        ]);

        if (cargosRes.error) throw cargosRes.error;
        if (deptsRes.error) throw deptsRes.error;

        const cargoNomeMap = new Map<string, string>(
          (cargosRes.data ?? []).map((c: { id: string; nome: string }) => [c.id, c.nome])
        );
        const deptNomeMap = new Map<string, string>(
          (deptsRes.data ?? []).map((d: { id: string; nome: string }) => [d.id, d.nome])
        );

        for (const gc of gheCargos) {
          const entry = composicaoPorGhe.get(gc.ghe_id) ?? {
            setores: [] as string[],
            cargos: [] as string[],
            setorCargos: new Map<string, Set<string>>(),
          };
          const setor = gc.departamento_id ? deptNomeMap.get(gc.departamento_id) : null;
          const cargo = gc.cargo_id ? cargoNomeMap.get(gc.cargo_id) : null;
          if (setor && !entry.setores.includes(setor)) entry.setores.push(setor);
          if (cargo && !entry.cargos.includes(cargo)) entry.cargos.push(cargo);
          if (setor) {
            const set = entry.setorCargos.get(setor) ?? new Set<string>();
            if (cargo) set.add(cargo);
            entry.setorCargos.set(setor, set);
          }
          composicaoPorGhe.set(gc.ghe_id, entry);
        }

        // Elegíveis por GHE — mesma regra da criação de GHE (GHEPanel):
        // admissões ATIVAS cujo (cargo|departamento) casa com a composição do
        // GHE. É este número que vai no PDF como "responderam X de Y", em vez
        // do bug antigo que repetia o total de respondentes nos dois lados.
        //
        // IMPORTANTE: filtrar por empresa_id das campanhas. Sem isso, contava
        // admissões de TODAS as empresas do tenant que casavam cargo/depto
        // (ex.: outros supermercados com "Operador de Caixa"), inflando o Y —
        // era o 49 no lugar de 25. O GHEPanel filtra por empresa_id; aqui
        // reproduzimos usando as empresas das campanhas do relatório.
        const empresaIds = Array.from(
          new Set(campanhasGhe.map((c) => c.empresa_id).filter(Boolean) as string[])
        );
        let admQuery = fromTable("admissoes")
          .select("cargo, departamento, status, empresa_id")
          .eq("tenant_id", tenantId);
        if (empresaIds.length > 0) {
          admQuery = admQuery.in("empresa_id", empresaIds);
        }
        const admRes = await admQuery;
        if (admRes.error) throw admRes.error;
        const ativos = (admRes.data ?? []).filter((a: any) => {
          const s = (a.status || "").toLowerCase();
          return !s || !["desligado", "demitido", "inativo"].includes(s);
        });

        // pares cargo|depto por GHE
        const paresPorGhe = new Map<string, Set<string>>();
        for (const gc of gheCargos) {
          const cargo = (gc.cargo_id ? cargoNomeMap.get(gc.cargo_id) : "") || "";
          const dept = (gc.departamento_id ? deptNomeMap.get(gc.departamento_id) : "") || "";
          const key = `${cargo.trim().toLowerCase()}|${dept.trim().toLowerCase()}`;
          const set = paresPorGhe.get(gc.ghe_id) ?? new Set<string>();
          set.add(key);
          paresPorGhe.set(gc.ghe_id, set);
        }
        for (const gId of allGheIds) {
          const pares = paresPorGhe.get(gId);
          if (!pares) { elegiveisPorGhe.set(gId, 0); continue; }
          const n = ativos.filter((a: any) => {
            const key = `${(a.cargo || "").trim().toLowerCase()}|${(a.departamento || "").trim().toLowerCase()}`;
            return pares.has(key);
          }).length;
          elegiveisPorGhe.set(gId, n);
        }
      }


      return { respostas, campanhasGhe, ghes, composicaoPorGhe, elegiveisPorGhe, entrevistasPorGhe };
    },
    staleTime: 0,
    refetchOnMount: "always",
  });

  // Respondentes REAIS por GHE — via função no servidor que cruza cpf_hash da
  // resposta com a admissão (cargo/setor) sem expor CPF. Substitui o count
  // inflado do agrupamento (que jogava cada resposta anônima em todos os GHE
  // da campanha, por falta de ghe_id_snapshot).
  const respondentesQuery = useQuery({
    queryKey: ["psicossocial-respondentes-por-ghe-v2", tenantId, idsKey, preenchimentoQuery.data ?? 0],
    enabled: !!tenantId && !!campanhaIds && campanhaIds.length > 0 && !preenchimentoQuery.isLoading,
    staleTime: 0,
    refetchOnMount: "always",
    queryFn: async () => {
      const { data, error } = await supabase.rpc("contar_respondentes_por_ghe", {
        p_campanha_ids: campanhaIds,
      });
      if (error) throw error;
      const map = new Map<string, number>();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (data ?? []).forEach((row: any) => {
        if (row.out_ghe_id) map.set(row.out_ghe_id, Number(row.out_respondentes) || 0);
      });
      return map;
    },
  });


  const resultadosPorGHE = useMemo<ResultadoGHE[]>(() => {
    const data = query.data;
    const respondentesReais = respondentesQuery.data ?? new Map<string, number>();
    const respostas = data?.respostas ?? [];
    const campanhasGhe = data?.campanhasGhe ?? [];
    const ghes = data?.ghes ?? [];
    const composicaoPorGhe = data?.composicaoPorGhe ?? new Map<string, { setores: string[]; cargos: string[]; setorCargos: Map<string, Set<string>> }>();
    const elegiveisPorGhe = data?.elegiveisPorGhe ?? new Map<string, number>();
    const entrevistasPorGhe = data?.entrevistasPorGhe ?? new Map<string, number>();

    const gheNomeMap = new Map(ghes.map((g) => [g.id, g.nome]));
    const gheCodigoMap = new Map(ghes.map((g) => [g.id, g.codigo ?? null]));
    // GHEs excluídos do cadastro não podem voltar via snapshot antigo da resposta.
    const gheExiste = (id: string) => gheNomeMap.has(id);
    // GHE excluído/mesclado: a resposta guarda o id antigo, mas o nome do
    // snapshot ainda casa com um GHE vivo (ex.: GHE 3 mesclado no GHE 01).
    // Sem esta resolução a resposta caía em "Sem GHE definido" E continuava
    // contada no GHE real (respondentes vêm por cpf_hash), inflando a soma
    // dos respondentes e repetindo as mesmas funções em dois blocos.
    const gheIdPorNome = new Map(
      ghes.map((g) => [(g.nome ?? "").trim().toLowerCase(), g.id]),
    );
    const resolverGhe = (r: RespostaRow): string | null => {
      if (r.ghe_id_snapshot && gheExiste(r.ghe_id_snapshot)) return r.ghe_id_snapshot;
      const porNome = gheIdPorNome.get((r.ghe_nome_snapshot ?? "").trim().toLowerCase());
      return porNome ?? null;
    };
    const campanhaGheMap = new Map(
      campanhasGhe.map((c) => [c.id, (c.ghe_ids ?? []).filter(Boolean)])
    );


    const grupos = new Map<string, {
      nome: string;
      count: number;
      /** Quantas das linhas do grupo vieram de entrevistas guiadas. */
      entrevistas: number;
      radarAcc: Map<string, { soma: number; n: number }>;
      ipsList: number[];
      campanhas: Set<string>;
      setoresAcc: Map<string, { count: number; ipsList: number[] }>;
      cargosAcc: Map<string, { count: number; ipsList: number[] }>;
    }>();

    const addToGrupo = (key: string, nome: string, r: RespostaRow) => {
      if (!grupos.has(key)) {
        grupos.set(key, {
          nome, count: 0, entrevistas: 0, radarAcc: new Map(), ipsList: [], campanhas: new Set(),
          setoresAcc: new Map(), cargosAcc: new Map(),
        });
      }
      const g = grupos.get(key)!;
      g.count += 1;
      if (r.origem_entrevista) g.entrevistas += 1;
      g.campanhas.add(r.campanha_id);
      const radar = (r.indicadores?.radar ?? []) as RadarDimensao[];
      for (const d of radar) {
        if (!d?.subject) continue;
        const value = Number(d.value);
        if (!Number.isFinite(value)) continue;
        const acc = g.radarAcc.get(d.subject) ?? { soma: 0, n: 0 };
        acc.soma += value;
        acc.n += 1;
        g.radarAcc.set(d.subject, acc);
      }
      const ips = Number(r.indicadores?.IPS);
      const ipsValid = Number.isFinite(ips);
      if (ipsValid) g.ipsList.push(ips);

      const setor = (r.setor_snapshot ?? "").trim() || "Não informado";
      const cargo = (r.cargo_snapshot ?? "").trim() || "Não informado";
      const sAcc = g.setoresAcc.get(setor) ?? { count: 0, ipsList: [] };
      sAcc.count += 1;
      if (ipsValid) sAcc.ipsList.push(ips);
      g.setoresAcc.set(setor, sAcc);
      const cAcc = g.cargosAcc.get(cargo) ?? { count: 0, ipsList: [] };
      cAcc.count += 1;
      if (ipsValid) cAcc.ipsList.push(ips);
      g.cargosAcc.set(cargo, cAcc);
    };

    for (const r of respostas) {
      const gheResolvido = resolverGhe(r);
      if (gheResolvido) {
        addToGrupo(
          gheResolvido,
          gheNomeMap.get(gheResolvido) ?? r.ghe_nome_snapshot ?? "GHE",
          r
        );
        continue;
      }


      // Fallback: só é seguro atribuir a resposta ao GHE da campanha quando a
      // campanha tem UM único GHE. Com vários GHEs, replicar a mesma resposta
      // em todos produzia scores idênticos em GHE 01, GHE 02 etc. — a mesma
      // média global repetida. Nesse caso a resposta fica fora da
      // estratificação até o snapshot ser resolvido no servidor.
      const ids = (campanhaGheMap.get(r.campanha_id) ?? []).filter(gheExiste);
      if (ids.length === 1) {
        addToGrupo(ids[0], gheNomeMap.get(ids[0]) ?? "GHE", r);
      } else {
        addToGrupo("__sem_ghe__", "Sem GHE definido", r);
      }
    }

    const estratoFrom = (m: Map<string, { count: number; ipsList: number[] }>): EstratoGHE[] =>
      Array.from(m.entries())
        .map(([nome, v]) => ({
          nome,
          count: v.count,
          ipsMedio: v.ipsList.length > 0
            ? Math.round(v.ipsList.reduce((a, b) => a + b, 0) / v.ipsList.length)
            : null,
        }))
        .sort((a, b) => b.count - a.count);

    return Array.from(grupos.entries()).map(([id, g]) => {
      const realGheId = id === "__sem_ghe__" ? null : id;
      const comp = realGheId ? composicaoPorGhe.get(realGheId) : undefined;
      return {
        ghe_id: realGheId,
        ghe_nome: g.nome,
        ghe_codigo: realGheId ? gheCodigoMap.get(realGheId) ?? null : null,
        // Respondentes = questionários (via cpf_hash) + entrevistas guiadas
        // do grupo. As entrevistas são contadas pelo agrupamento efetivo (que
        // já resolve o GHE por snapshot OU pelo GHE único da campanha), e não
        // apenas pelo `ghe_id_snapshot`: entrevistas concluídas antes do
        // vínculo do GHE ficam com snapshot nulo e o GHE aparecia com 0
        // respondentes, bloqueando o plano de ação.
        count: realGheId
          ? (respondentesReais.has(realGheId)
              ? Math.max(
                  respondentesReais.get(realGheId)! + Math.max(g.entrevistas, entrevistasPorGhe.get(realGheId) ?? 0),
                  g.count,
                )
              : Math.max(g.count, entrevistasPorGhe.get(realGheId) ?? 0))
          : g.count,
        elegiveis: realGheId ? (elegiveisPorGhe.get(realGheId) ?? 0) : 0,
        radar: Array.from(g.radarAcc.entries()).map(([subject, { soma, n }]) => ({
          subject,
          value: Math.round(soma / n),
          fullMark: 100,
        })),
        ipsMedio: g.ipsList.length > 0
          ? Math.round(g.ipsList.reduce((a, b) => a + b, 0) / g.ipsList.length)
          : null,
        campanhas: g.campanhas.size,
        setores: estratoFrom(g.setoresAcc),
        cargos: estratoFrom(g.cargosAcc),
        composicaoSetores: comp?.setores ?? [],
        composicaoCargos: comp?.cargos ?? [],
        composicaoSetorCargos: comp?.setorCargos
          ? Array.from(comp.setorCargos.entries())
              .map(([setor, cargos]) => ({ setor, cargos: Array.from(cargos).sort() }))
              .sort((a, b) => a.setor.localeCompare(b.setor))
          : [],
      };
    });
  }, [query.data, respondentesQuery.data]);



  return {
    resultadosPorGHE,
    isLoading: query.isLoading,
    isFetching: query.isFetching,
    error: query.error,
  };
}

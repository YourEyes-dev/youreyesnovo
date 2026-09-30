import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";

export interface Colaborador {
  id: string;
  nome_completo: string;
  cpf: string;
  cargo: string;
  cargo_id?: string | null;
  departamento: string | null;
  email: string | null;
  celular: string | null;
  filial: string | null;
  data_admissao: string | null;
  empresa_id?: string | null;
  gestor_imediato?: string | null;
  foto_url?: string | null;
  bate_ponto?: boolean | null;
  inativo?: boolean | null;
}

/** CPF (só dígitos) que aparece em admissões com nomes DIFERENTES — sinal de
 *  erro de cadastro: pessoas distintas gravadas com o mesmo CPF. Como o sistema
 *  usa o CPF como identidade do colaborador, elas colapsam em uma só. */
export interface CpfConflito {
  cpf: string;
  nomes: string[];
}

/** Detecta CPFs compartilhados por nomes distintos entre as linhas informadas.
 *  Puro (sem I/O) para ser testável. Ignora CPF vazio e nome vazio. */
export function detectarCpfsConflitantes(
  rows: Array<{ cpf?: string | null; nome_completo?: string | null }>
): CpfConflito[] {
  const porCpf = new Map<string, Map<string, string>>(); // cpfDigitos -> (nomeLower -> nomeOriginal)
  for (const r of rows) {
    const cpf = (r.cpf || "").toString().replace(/\D/g, "");
    const nome = (r.nome_completo || "").toString().trim();
    if (!cpf || !nome) continue;
    const nomes = porCpf.get(cpf) ?? new Map<string, string>();
    const chave = nome.toLowerCase();
    if (!nomes.has(chave)) nomes.set(chave, nome);
    porCpf.set(cpf, nomes);
  }
  return Array.from(porCpf.entries())
    .filter(([, nomes]) => nomes.size >= 2)
    .map(([cpf, nomes]) => ({ cpf, nomes: Array.from(nomes.values()) }));
}

interface UseColaboradoresOptions {
  /** Exclui contratos PJ/Pró-labore/Terceiros (usado em módulos exclusivos CLT como Ponto e Férias). */
  excluirPJ?: boolean;
  /** Mantém apenas colaboradores marcados como "bate ponto" (usado no módulo Ponto). */
  apenasBatePonto?: boolean;
  /** Exclui colaboradores inativos. */
  excluirInativos?: boolean;
}

export function useColaboradores(options: UseColaboradoresOptions = {}) {
  const { excluirPJ = false, apenasBatePonto = false, excluirInativos = true } = options;
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ["colaboradores", tenantId, empresaAtivaId, excluirPJ, apenasBatePonto, excluirInativos],
    queryFn: async (): Promise<{ lista: Colaborador[]; cpfsConflitantes: CpfConflito[] }> => {
      if (!tenantId) return { lista: [], cpfsConflitantes: [] };

      let query = supabase
        .from("admissoes")
        .select("id, nome_completo, cpf, cargo, cargo_id, departamento, email, celular, filial, data_admissao, empresa_id, gestor_imediato, foto_url, tipo_contrato, bate_ponto, inativo")
        .eq("tenant_id", tenantId)
        .eq("status", "concluido");

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query.order("data_admissao", { ascending: false });

      if (error) throw error;

      let rows = data || [];
      if (excluirPJ) {
        // Mantém apenas vínculos CLT (exclui PJ, pró-labore e terceiros).
        const naoCLT = new Set(["pj", "prolabore", "pro_labore", "terceiro", "terceirizado", "autonomo"]);
        rows = rows.filter((r: any) => {
          const tc = (r.tipo_contrato || "").toString().trim().toLowerCase();
          return !naoCLT.has(tc);
        });
      }

      if (apenasBatePonto) {
        rows = rows.filter((r: any) => r.bate_ponto !== false);
      }

      if (excluirInativos) {
        rows = rows.filter((r: any) => r.inativo !== true);
      }

      // Deduplica por CPF (normalizado em apenas dígitos), mantendo a admissão mais recente.
      // Fallback para nome+empresa quando o CPF estiver vazio.
      const seen = new Set<string>();
      const deduped: any[] = [];
      for (const r of rows) {
        const cpfDigits = (r.cpf || "").toString().replace(/\D/g, "");
        const key = cpfDigits
          ? `cpf:${cpfDigits}`
          : `nome:${(r.nome_completo || "").trim().toLowerCase()}|emp:${r.empresa_id || ""}`;
        if (seen.has(key)) continue;
        seen.add(key);
        deduped.push(r);
      }

      // Ordena alfabeticamente pelo nome após a deduplicação.
      deduped.sort((a, b) =>
        (a.nome_completo || "").localeCompare(b.nome_completo || "", "pt-BR", { sensitivity: "base" })
      );

      // Detecta CPFs repetidos com nomes distintos sobre as MESMAS linhas
      // filtradas (antes da dedup) — é o que colapsa a lista de colaboradores.
      const cpfsConflitantes = detectarCpfsConflitantes(rows);

      // Remove campo auxiliar para manter o tipo público estável.
      const lista = deduped.map(({ tipo_contrato, ...rest }: any) => rest) as Colaborador[];
      return { lista, cpfsConflitantes };
    },
    enabled: !!tenantId,
  });

  return {
    colaboradores: data?.lista ?? [],
    cpfsConflitantes: data?.cpfsConflitantes ?? [],
    isLoading,
    error: error?.message || null,
    refetch,
  };
}

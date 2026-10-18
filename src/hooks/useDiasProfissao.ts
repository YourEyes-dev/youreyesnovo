import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { normalizarCargo, type DiaProfissaoEmpresa } from "@/lib/diasProfissao";

export interface DiaProfissaoRegistro extends DiaProfissaoEmpresa {
  id: string;
  cargo_exemplo: string;
  origem: "ia" | "manual";
  confianca: string | null;
  base: string | null;
}

export const CHAVE_DIAS_PROFISSAO = "cultura-dias-profissao";

/** Decisões da empresa sobre o dia da profissão de cada cargo (aprovadas, rejeitadas ou manuais). */
export function useDiasProfissao() {
  const { tenantId, user } = useAuth();
  const qc = useQueryClient();

  const { data: registros = [], isLoading } = useQuery({
    queryKey: [CHAVE_DIAS_PROFISSAO, tenantId],
    queryFn: async (): Promise<DiaProfissaoRegistro[]> => {
      const { data, error } = await fromTable("cultura_dias_profissao")
        .select("id, cargo_chave, cargo_exemplo, nome_data, mes, dia, status, origem, confianca, base")
        .eq("tenant_id", tenantId)
        .order("cargo_exemplo");
      if (error) throw error;
      return (data || []) as DiaProfissaoRegistro[];
    },
    enabled: !!tenantId,
    retry: false, // sem a tabela (ambiente ainda sem o script), não insiste
  });

  const invalidar = () => qc.invalidateQueries({ queryKey: [CHAVE_DIAS_PROFISSAO] });

  /** Grava (ou troca) a decisão sobre um cargo. */
  const decidir = async (d: {
    cargo: string;
    status: "aprovado" | "rejeitado";
    origem: "ia" | "manual";
    nome_data?: string | null;
    mes?: number | null;
    dia?: number | null;
    confianca?: string | null;
    base?: string | null;
  }) => {
    if (!tenantId) return;
    const { error } = await fromTable("cultura_dias_profissao").upsert(
      {
        tenant_id: tenantId,
        cargo_chave: normalizarCargo(d.cargo),
        cargo_exemplo: d.cargo,
        status: d.status,
        origem: d.origem,
        nome_data: d.status === "aprovado" ? d.nome_data ?? null : null,
        mes: d.status === "aprovado" ? d.mes ?? null : null,
        dia: d.status === "aprovado" ? d.dia ?? null : null,
        confianca: d.confianca ?? null,
        base: d.base ?? null,
        criado_por: user?.id ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "tenant_id,cargo_chave" },
    );
    if (error) { toast.error("Não foi possível salvar"); throw error; }
    invalidar();
  };

  /** Remove a decisão: o cargo volta ao catálogo padrão. */
  const remover = async (id: string) => {
    const { error } = await fromTable("cultura_dias_profissao").delete().eq("id", id);
    if (error) { toast.error("Não foi possível remover"); throw error; }
    invalidar();
  };

  return { registros, isLoading, decidir, remover };
}

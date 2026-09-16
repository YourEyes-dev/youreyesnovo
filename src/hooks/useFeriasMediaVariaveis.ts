/**
 * Média das variáveis do art. 142 (RF-004 / CA-006 do YE-DP-FERIAS-001).
 *
 * Chama a apuração do banco (`ferias_media_variaveis`), que soma apenas as
 * rubricas marcadas como integrantes das férias no cadastro de rubricas e
 * devolve a MEMÓRIA competência a competência — é ela que torna o valor
 * reproduzível depois.
 *
 * Somente leitura: nada é gravado pela apuração.
 */
import { useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";

export interface MediaCompetencia {
  competencia: string;
  valor: number;
}

export interface MediaRubrica {
  codigo: string | null;
  descricao: string;
  valor: number;
}

export interface MediaVariaveis {
  media: number;
  total: number;
  meses_divisor: number;
  meses_com_folha: number;
  meses_com_valor: number;
  base: string;
  divisor_regra: string;
  janela_inicio: string;
  janela_fim: string;
  parametros_vigencia: string;
  fundamento: string;
  apurado_em: string;
  competencias: MediaCompetencia[];
  rubricas: MediaRubrica[];
  avisos: string[];
}

export interface ApurarMediaParams {
  cpf: string;
  aquisitivoInicio: string;
  aquisitivoFim: string;
  inicioGozo?: string;
}

export function useFeriasMediaVariaveis() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [apurando, setApurando] = useState(false);

  const apurar = useCallback(
    async (p: ApurarMediaParams): Promise<MediaVariaveis | null> => {
      if (!tenantId) return null;
      setApurando(true);
      try {
        // A função é nova: ainda não está no schema tipado gerado pelo Supabase.
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const rpc = (supabase as any).rpc.bind(supabase);
        const { data, error } = await rpc("ferias_media_variaveis", {
          p_tenant: tenantId,
          p_cpf: p.cpf,
          p_aquisitivo_inicio: p.aquisitivoInicio,
          p_aquisitivo_fim: p.aquisitivoFim,
          p_inicio_gozo: p.inicioGozo || null,
          p_empresa: empresaAtivaId || null,
        });
        if (error) throw error;
        const bruto = (data || {}) as Record<string, unknown>;
        return {
          media: Number(bruto.media ?? 0),
          total: Number(bruto.total ?? 0),
          meses_divisor: Number(bruto.meses_divisor ?? 0),
          meses_com_folha: Number(bruto.meses_com_folha ?? 0),
          meses_com_valor: Number(bruto.meses_com_valor ?? 0),
          base: String(bruto.base ?? "aquisitivo"),
          divisor_regra: String(bruto.divisor_regra ?? "meses_do_periodo"),
          janela_inicio: String(bruto.janela_inicio ?? ""),
          janela_fim: String(bruto.janela_fim ?? ""),
          parametros_vigencia: String(bruto.parametros_vigencia ?? ""),
          fundamento: String(bruto.fundamento ?? "CLT art. 142"),
          apurado_em: String(bruto.apurado_em ?? ""),
          competencias: (bruto.competencias as MediaCompetencia[]) ?? [],
          rubricas: (bruto.rubricas as MediaRubrica[]) ?? [],
          avisos: (bruto.avisos as string[]) ?? [],
        };
      } finally {
        setApurando(false);
      }
    },
    [tenantId, empresaAtivaId],
  );

  return { apurar, apurando };
}

/** Frase curta que explica de onde veio o valor, para a tela e para a memória. */
export function descreverMedia(m: MediaVariaveis): string {
  const janela = `${m.janela_inicio} a ${m.janela_fim}`;
  const divisor =
    m.divisor_regra === "meses_com_valor"
      ? `${m.meses_divisor} mês(es) com valor`
      : `${m.meses_divisor} mês(es) do período`;
  return `Soma de R$ ${m.total.toLocaleString("pt-BR", { minimumFractionDigits: 2 })} nas competências ${janela}, dividida por ${divisor}.`;
}

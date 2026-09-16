/**
 * eSocial do 13º salário (RF-005 / RN-010 / CA-007 do YE-DP-13-001).
 *
 * O 13º não entra na folha mensal do eSocial: ele é declarado numa
 * apuração ANUAL própria (S-1200 com indApuracao = 2, período AAAA) e os
 * pagamentos das parcelas vão no S-1210.
 *
 * São dois passos, nessa ordem:
 *   1. `validar` — confere CPF, vínculo, valor e situação de cada cálculo.
 *      É aqui que se evita a rejeição, ANTES de montar qualquer evento.
 *   2. `gerar` — monta o XML e grava como 'pendente'.
 *
 * IMPORTANTE: nada é TRANSMITIDO. A transmissão depende de certificado
 * digital, procuração eletrônica e ambiente definidos pelo cliente. O que
 * o sistema entrega é o evento montado e conferido, pronto para o envio.
 */
import { useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";

export interface ProblemaESocial13 {
  calculo_id: string;
  colaborador: string;
  parcela: number;
  problema: string;
}

export interface ValidacaoESocial13 {
  ano: number;
  aptos: number;
  com_problema: number;
  problemas: ProblemaESocial13[];
  pode_transmitir: boolean;
}

export interface GeracaoESocial13 {
  ano: number;
  tipo: string;
  leiaute: string;
  eventos_gerados: number;
  ja_existiam: number;
  situacao: string;
  aviso: string;
}

export function useDecimoTerceiroESocial() {
  const { tenantId } = useTenant();
  const [ocupado, setOcupado] = useState(false);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rpc = () => (supabase as any).rpc.bind(supabase);

  const validar = useCallback(
    async (ano: number): Promise<ValidacaoESocial13 | null> => {
      if (!tenantId) return null;
      setOcupado(true);
      try {
        const { data, error } = await rpc()("decimo_terceiro_esocial_validar", {
          p_tenant: tenantId, p_ano: ano,
        });
        if (error) throw error;
        const b = (data || {}) as Record<string, unknown>;
        if (b.erro) throw new Error(String(b.erro));
        return {
          ano: Number(b.ano ?? ano),
          aptos: Number(b.aptos ?? 0),
          com_problema: Number(b.com_problema ?? 0),
          problemas: (b.problemas as ProblemaESocial13[]) ?? [],
          pode_transmitir: Boolean(b.pode_transmitir),
        };
      } finally { setOcupado(false); }
    }, [tenantId]);

  const gerar = useCallback(
    async (ano: number, tipo: "S-1200" | "S-1210", leiaute = "S-1.3"): Promise<GeracaoESocial13> => {
      if (!tenantId) throw new Error("Empresa não identificada.");
      setOcupado(true);
      try {
        const { data, error } = await rpc()("decimo_terceiro_esocial_gerar", {
          p_tenant: tenantId, p_ano: ano, p_tipo: tipo, p_leiaute: leiaute,
        });
        if (error) throw error;
        const b = (data || {}) as Record<string, unknown>;
        if (b.erro) throw new Error(String(b.erro));
        return {
          ano: Number(b.ano ?? ano),
          tipo: String(b.tipo ?? tipo),
          leiaute: String(b.leiaute ?? leiaute),
          eventos_gerados: Number(b.eventos_gerados ?? 0),
          ja_existiam: Number(b.ja_existiam ?? 0),
          situacao: String(b.situacao ?? ""),
          aviso: String(b.aviso ?? ""),
        };
      } finally { setOcupado(false); }
    }, [tenantId]);

  return { validar, gerar, ocupado };
}

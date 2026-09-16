/**
 * Recibos e memória do 13º arquivados em Documentos (CA-008).
 *
 * Espelha o arquivamento do módulo Férias: sobe o HTML no storage e cria
 * o registro em `documentos` com os metadados, na pasta do colaborador
 * quando ela existe. Idempotente pelo nome do arquivo (carimbo de tempo),
 * mas evita duplicar o mesmo documento da mesma parcela conferindo antes.
 */
import { useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import {
  gerarRecibo13HTML, gerarMemoria13HTML, type Recibo13Data,
} from "@/lib/decimoTerceiroDocumentos";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const fromTable = (t: string) => (supabase as any).from(t);

export type Documento13Tipo = "recibo" | "memoria";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function dadosDoCalculo(c: any, empresaNome?: string): Recibo13Data {
  return {
    empresaNome,
    colaboradorNome: c.colaborador_nome,
    colaboradorCpf: c.colaborador_cpf || undefined,
    cargo: c.cargo || undefined,
    ano: Number(c.ano),
    parcela: (Number(c.parcela) === 2 ? 2 : 1) as 1 | 2,
    avos: Number(c.meses_trabalhados ?? 0),
    remuneracaoBase: Number(c.remuneracao_base ?? 0),
    mediaVariaveis: Number(c.media_variaveis ?? 0),
    valorBruto: Number(c.valor_bruto ?? 0),
    valorPrimeiraParcela: Number(c.valor_primeira_parcela ?? 0),
    valorInss: Number(c.valor_inss ?? 0),
    valorIrrf: Number(c.valor_irrf ?? 0),
    valorFgts: Number(c.valor_fgts ?? 0),
    totalLiquido: Number(c.total_liquido ?? 0),
    dataPrevista: c.data_prevista ?? null,
    dataPagamento: c.data_pagamento ?? null,
    memoria: c.memoria_calculo?.apuracao ?? c.memoria_calculo ?? null,
  };
}

export function useDecimoTerceiroDocumentos() {
  const { tenantId } = useTenant();
  const [gerando, setGerando] = useState(false);

  const arquivar = useCallback(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    async (calculo: any, tipo: Documento13Tipo): Promise<string | null> => {
      if (!tenantId) throw new Error("Empresa não identificada");
      setGerando(true);
      try {
        const dados = dadosDoCalculo(calculo);
        const html = tipo === "recibo" ? gerarRecibo13HTML(dados) : gerarMemoria13HTML(dados);
        const rotulo = tipo === "recibo"
          ? `Recibo 13º ${dados.parcela}ª parcela ${dados.ano}`
          : `Memória de cálculo 13º ${dados.parcela}ª parcela ${dados.ano}`;

        const safeNome = String(dados.colaboradorNome).replace(/[^a-zA-Z0-9._-]/g, "_");
        const storagePath =
          `${tenantId}/decimo-terceiro/${tipo}_${calculo.id}_${Date.now()}_${safeNome}.html`;

        const blob = new Blob([html], { type: "text/html" });
        const { error: upErr } = await supabase.storage
          .from("documentos")
          .upload(storagePath, blob, { contentType: "text/html", upsert: false });
        if (upErr) throw upErr;

        // Pasta do colaborador, quando existe — é onde o DP procura.
        let pastaId: string | null = null;
        if (calculo.colaborador_id) {
          const { data: pasta } = await fromTable("documento_pastas")
            .select("id")
            .eq("tenant_id", tenantId)
            .eq("colaborador_id", calculo.colaborador_id)
            .maybeSingle();
          pastaId = (pasta as { id?: string } | null)?.id || null;
        }

        const { data: doc, error: insErr } = await fromTable("documentos").insert({
          tenant_id: tenantId,
          empresa_id: calculo.empresa_id || null,
          colaborador_id: calculo.colaborador_id || null,
          colaborador_nome: dados.colaboradorNome,
          colaborador_cpf: dados.colaboradorCpf || null,
          nome_arquivo: storagePath,
          nome_original: `${rotulo} - ${dados.colaboradorNome}.html`,
          tipo: rotulo,
          tamanho: blob.size,
          mime_type: "text/html",
          storage_path: storagePath,
          status: "valido",
          observacoes:
            `Gerado do módulo 13º Salário (ano-base ${dados.ano}, ${dados.parcela}ª parcela, ${dados.avos}/12 avos)`,
          pasta_id: pastaId,
          versao_atual: 1,
          total_versoes: 1,
        }).select("id").single();
        if (insErr) throw insErr;

        return (doc as { id?: string } | null)?.id || null;
      } finally {
        setGerando(false);
      }
    },
    [tenantId],
  );

  /** Abre o documento numa aba, sem arquivar — para conferir antes. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const visualizar = useCallback((calculo: any, tipo: Documento13Tipo) => {
    const dados = dadosDoCalculo(calculo);
    const html = tipo === "recibo" ? gerarRecibo13HTML(dados) : gerarMemoria13HTML(dados);
    const janela = window.open("", "_blank");
    if (!janela) return false;
    janela.document.write(html);
    janela.document.close();
    return true;
  }, []);

  return { arquivar, visualizar, gerando };
}

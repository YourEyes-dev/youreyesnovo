import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { FolderArchive, Download, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";

/**
 * Dossiê de fiscalização (Portaria MTP 671/2021) — o pacote que se entrega ao
 * Auditor-Fiscal: AEJ, comprovantes, espelhos e AFD importado da competência,
 * com índice, contagens e hashes de verificação. Montado e arquivado pelo
 * banco; aqui só se pede, se acompanha e se leva o índice.
 */
const PECA_LABEL: Record<string, string> = {
  aej: "AEJ — jornada tratada",
  comprovantes: "Comprovantes de marcação",
  espelhos: "Espelhos de ponto",
  afd_importado: "AFD importado de REP-C",
};

export function PontoDossieTab() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));
  const [gerando, setGerando] = useState(false);

  const { data: dossies = [], isLoading } = useQuery({
    queryKey: ["ponto-dossies", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_dossies_fiscalizacao").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q.order("gerado_em", { ascending: false }).limit(24) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const doCompetencia = dossies.find((d: any) => d.competencia === competencia);

  const gerar = async () => {
    if (!tenantId) return;
    setGerando(true);
    try {
      const { error } = await (supabase.rpc as any)("ponto_gerar_dossie_fiscalizacao", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_competencia: competencia,
      });
      if (error) throw error;
      qc.invalidateQueries({ queryKey: ["ponto-dossies"] });
      toast.success(`Dossiê da competência ${competencia} montado e arquivado.`);
    } catch (e: any) {
      toast.error("Não foi possível montar o dossiê: " + (e?.message || ""));
    } finally {
      setGerando(false);
    }
  };

  const baixarIndice = (d: any) => {
    const linhas = [
      `Dossie de fiscalizacao — competencia ${d.competencia}`,
      `Gerado em: ${d.gerado_em ? format(new Date(d.gerado_em), "dd/MM/yyyy HH:mm") : "—"}`,
      `Periodo: ${d.periodo_ini || "—"} a ${d.periodo_fim || "—"}`,
      `Hash do pacote: ${d.hash_pacote || "—"}`,
      "",
      "Peca;Quantidade;Hash",
      ...(Array.isArray(d.indice) ? d.indice : []).map(
        (p: any) => `${PECA_LABEL[p.peca] || p.peca};${p.quantidade ?? ""};${p.hash ?? ""}`,
      ),
    ];
    const blob = new Blob(["﻿" + linhas.join("\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `dossie-fiscalizacao_${d.competencia}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <FolderArchive className="w-5 h-5 text-primary" /> Dossiê de fiscalização
          </h3>
          <p className="text-sm text-muted-foreground max-w-3xl">
            Reúne, numa competência, as peças que o Auditor-Fiscal pede — AEJ, comprovantes,
            espelhos e o AFD importado —, com índice, contagens e as assinaturas (hashes) que
            permitem conferir que nada foi trocado. O pacote fica arquivado no módulo Documentos.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <CompetenciaInput value={competencia} onChange={setCompetencia} className="w-[180px]" />
          <Button onClick={gerar} disabled={gerando}>
            <RefreshCw className={`w-4 h-4 mr-2 ${gerando ? "animate-spin" : ""}`} />
            {gerando ? "Montando..." : doCompetencia ? "Montar de novo" : "Montar dossiê"}
          </Button>
        </div>
      </div>

      {/* Índice do dossiê da competência escolhida */}
      {doCompetencia && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium flex items-center justify-between gap-4">
              <span>Competência {doCompetencia.competencia} · {doCompetencia.total_pecas} peça(s)</span>
              <Button variant="outline" size="sm" onClick={() => baixarIndice(doCompetencia)}>
                <Download className="w-4 h-4 mr-2" /> Baixar índice
              </Button>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Peça</TableHead>
                  <TableHead className="text-center">Quantidade</TableHead>
                  <TableHead>Assinatura (hash)</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(Array.isArray(doCompetencia.indice) ? doCompetencia.indice : []).map((p: any, i: number) => (
                  <TableRow key={i}>
                    <TableCell className="font-medium">{PECA_LABEL[p.peca] || p.peca}</TableCell>
                    <TableCell className="text-center">
                      {Number(p.quantidade) > 0
                        ? p.quantidade
                        : <Badge variant="outline" className="text-muted-foreground">nenhuma</Badge>}
                    </TableCell>
                    <TableCell className="font-mono text-[10px] break-all max-w-[280px]">{p.hash || "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            <div>
              <p className="text-xs text-muted-foreground">Assinatura do pacote</p>
              <p className="font-mono text-[11px] break-all">{doCompetencia.hash_pacote || "—"}</p>
            </div>
            <p className="text-xs text-muted-foreground">
              Peça com quantidade zero significa que ela não existe nesta competência — por
              exemplo, AEJ que ainda não foi gerado ou AFD que não foi importado. Vale montar o
              dossiê de novo depois de completar o que faltar.
            </p>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Dossiês montados</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Competência</TableHead>
                <TableHead className="text-center">Peças</TableHead>
                <TableHead className="text-center">Período</TableHead>
                <TableHead>Gerado em</TableHead>
                <TableHead className="text-center">Índice</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={5} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : dossies.length === 0 ? (
                <TableRow><TableCell colSpan={5} className="text-center py-8 text-muted-foreground">
                  Nenhum dossiê montado ainda.
                </TableCell></TableRow>
              ) : dossies.map((d: any) => (
                <TableRow key={d.id}>
                  <TableCell className="font-medium">{d.competencia}</TableCell>
                  <TableCell className="text-center">{d.total_pecas}</TableCell>
                  <TableCell className="text-center text-sm">
                    {d.periodo_ini ? format(new Date(`${d.periodo_ini}T00:00:00`), "dd/MM/yy") : "—"}
                    {" — "}
                    {d.periodo_fim ? format(new Date(`${d.periodo_fim}T00:00:00`), "dd/MM/yy") : "—"}
                  </TableCell>
                  <TableCell className="text-sm">
                    {d.gerado_em ? format(new Date(d.gerado_em), "dd/MM/yyyy 'às' HH:mm") : "—"}
                  </TableCell>
                  <TableCell className="text-center">
                    <Button variant="ghost" size="icon" onClick={() => baixarIndice(d)} title="Baixar índice">
                      <Download className="w-4 h-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}

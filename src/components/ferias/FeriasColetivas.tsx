/**
 * Férias coletivas (RF-007). Programa por setor (até 2 períodos, mín. 10
 * dias — validado no banco), mostra os colaboradores abrangidos com a marca
 * do art. 140 (novatos proporcionais) e gera os comunicados (MTE, sindicato,
 * empregados) como documentos arquivados, com o prazo de 15 dias.
 */
import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from "@/components/ui/dialog";
import { Users, Plus, FileWarning, CalendarRange, Download } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useColaboradores } from "@/hooks/useColaboradores";
import {
  useFeriasColetivas, type FeriasColetiva, type ColetivaComunicado,
} from "@/hooks/useFeriasColetivas";
import { gerarComunicadoColetivasHTML } from "@/lib/feriasColetivasDocumentos";
import { toast } from "sonner";

const fmtData = (s: string | null) => (s ? new Date(s + "T12:00:00").toLocaleDateString("pt-BR") : "—");
const destinoLabel: Record<string, string> = {
  mte: "Órgão do MTE", sindicato: "Sindicato", empregados: "Empregados (afixação)",
};

export function FeriasColetivas() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const { colaboradores } = useColaboradores({ excluirPJ: true });
  const { coletivas, isLoading, programar, useAfetados, useComunicados, qc } = useFeriasColetivas();

  const [showForm, setShowForm] = useState(false);
  const [aberta, setAberta] = useState<FeriasColetiva | null>(null);
  const [form, setForm] = useState({
    departamento: "", ano: new Date().getFullYear(),
    p1_inicio: "", p1_fim: "", p2_inicio: "", p2_fim: "",
  });

  const departamentos = Array.from(
    new Set(colaboradores.map((c: { departamento?: string }) => c.departamento).filter(Boolean)),
  ) as string[];

  const afetadosQ = useAfetados(aberta?.id ?? null);
  const comunicadosQ = useComunicados(aberta?.id ?? null);

  const handleProgramar = async () => {
    if (!form.departamento || !form.p1_inicio || !form.p1_fim) {
      return toast.error("Informe o setor e o período 1");
    }
    await programar.mutateAsync({
      departamento: form.departamento, ano: form.ano,
      p1_inicio: form.p1_inicio, p1_fim: form.p1_fim,
      p2_inicio: form.p2_inicio || null, p2_fim: form.p2_fim || null,
    });
    setShowForm(false);
    setForm({ departamento: "", ano: new Date().getFullYear(), p1_inicio: "", p1_fim: "", p2_inicio: "", p2_fim: "" });
  };

  // Gera o comunicado como documento arquivado e marca o registro.
  const gerarComunicado = async (com: ColetivaComunicado) => {
    if (!aberta || !tenantId) return;
    try {
      const html = gerarComunicadoColetivasHTML(com.destino, {
        departamento: aberta.departamento, ano: aberta.ano,
        p1Inicio: aberta.p1_inicio, p1Fim: aberta.p1_fim,
        p2Inicio: aberta.p2_inicio, p2Fim: aberta.p2_fim,
        totalColaboradores: afetadosQ.data?.length,
      });
      const path = `${tenantId}/ferias/coletiva_${aberta.id}_${com.destino}_${Date.now()}.html`;
      const { error: upErr } = await supabase.storage
        .from("documentos")
        .upload(path, new Blob([html], { type: "text/html" }), { contentType: "text/html", upsert: false });
      if (upErr) throw upErr;

      const { data: doc, error: insErr } = await fromTable("documentos").insert({
        tenant_id: tenantId, empresa_id: empresaAtivaId || null,
        colaborador_nome: `Coletivas ${aberta.departamento}`,
        nome_arquivo: path, nome_original: `Comunicado ${destinoLabel[com.destino]} - ${aberta.departamento}.html`,
        tipo: "comunicado_ferias_coletivas", tamanho: new Blob([html]).size, mime_type: "text/html",
        storage_path: path, status: "valido",
        observacoes: `Ferias coletivas ${aberta.ano} — prazo ${fmtData(com.prazo_limite)}`,
        versao_atual: 1, total_versoes: 1,
      } as Record<string, unknown>).select("id").single();
      if (insErr) throw insErr;

      await fromTable("ferias_coletivas_comunicados")
        .update({ status: "gerado", documento_id: (doc as { id: string }).id } as Record<string, unknown>)
        .eq("id", com.id);

      qc.invalidateQueries({ queryKey: ["ferias-coletiva-comunicados", aberta.id] });
      toast.success(`Comunicado (${destinoLabel[com.destino]}) gerado e arquivado em Documentos.`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Erro ao gerar o comunicado");
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <CalendarRange className="w-5 h-5 text-primary" /> Férias coletivas
          </h3>
          <p className="text-sm text-muted-foreground">
            Por setor, até 2 períodos de no mínimo 10 dias, com comunicações ao MTE, sindicato e empregados (15 dias). Arts. 139-141.
          </p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4 mr-2" /> Programar coletiva
        </Button>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-muted-foreground">
            {isLoading ? "Carregando..." : `${coletivas.length} programa(s)`}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {!isLoading && coletivas.length === 0 && (
            <p className="text-sm text-muted-foreground py-6 text-center">Nenhuma coletiva programada.</p>
          )}
          {coletivas.map((c) => (
            <button key={c.id} onClick={() => setAberta(c)}
              className="w-full text-left flex flex-wrap items-center gap-3 rounded-lg border p-3 hover:bg-muted/40">
              <Badge variant="outline">{c.departamento}</Badge>
              <span className="text-sm">
                {fmtData(c.p1_inicio)} a {fmtData(c.p1_fim)}
                {c.p2_inicio ? ` · ${fmtData(c.p2_inicio)} a ${fmtData(c.p2_fim)}` : ""}
              </span>
              <span className="text-xs text-muted-foreground ml-auto capitalize">{c.estado}</span>
            </button>
          ))}
        </CardContent>
      </Card>

      {/* Programar */}
      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Programar férias coletivas</DialogTitle>
            <DialogDescription>O período 1 é obrigatório; o 2 é opcional. Mínimo de 10 dias cada.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Setor *</Label>
                <Input list="deptos-coletivas" value={form.departamento}
                  onChange={(e) => setForm((p) => ({ ...p, departamento: e.target.value }))} placeholder="Ex.: Produção" />
                <datalist id="deptos-coletivas">
                  {departamentos.map((d) => <option key={d} value={d} />)}
                </datalist>
              </div>
              <div className="space-y-2">
                <Label>Ano</Label>
                <Input type="number" value={form.ano} onChange={(e) => setForm((p) => ({ ...p, ano: Number(e.target.value) }))} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2"><Label>Período 1 — início *</Label>
                <Input type="date" value={form.p1_inicio} onChange={(e) => setForm((p) => ({ ...p, p1_inicio: e.target.value }))} /></div>
              <div className="space-y-2"><Label>Período 1 — fim *</Label>
                <Input type="date" value={form.p1_fim} onChange={(e) => setForm((p) => ({ ...p, p1_fim: e.target.value }))} /></div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2"><Label>Período 2 — início</Label>
                <Input type="date" value={form.p2_inicio} onChange={(e) => setForm((p) => ({ ...p, p2_inicio: e.target.value }))} /></div>
              <div className="space-y-2"><Label>Período 2 — fim</Label>
                <Input type="date" value={form.p2_fim} onChange={(e) => setForm((p) => ({ ...p, p2_fim: e.target.value }))} /></div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowForm(false)}>Cancelar</Button>
            <Button onClick={handleProgramar} disabled={programar.isPending}>
              {programar.isPending ? "Programando..." : "Programar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Detalhe */}
      <Dialog open={!!aberta} onOpenChange={() => setAberta(null)}>
        <DialogContent className="sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Coletiva — {aberta?.departamento} ({aberta?.ano})</DialogTitle>
          </DialogHeader>
          {aberta && (
            <div className="space-y-5 text-sm">
              {/* Comunicados */}
              <div>
                <p className="font-medium mb-2">Comunicações obrigatórias (prazo de 15 dias)</p>
                <div className="space-y-2">
                  {(comunicadosQ.data ?? []).map((com) => (
                    <div key={com.id} className="flex items-center gap-3 rounded-lg border p-2.5">
                      <span className="flex-1">{destinoLabel[com.destino]}</span>
                      <span className="text-xs text-muted-foreground">até {fmtData(com.prazo_limite)}</span>
                      {com.status === "pendente" ? (
                        <Button size="sm" variant="outline" onClick={() => gerarComunicado(com)}>
                          <Download className="w-3.5 h-3.5 mr-1" /> Gerar
                        </Button>
                      ) : (
                        <Badge variant="secondary">✓ Arquivado</Badge>
                      )}
                    </div>
                  ))}
                </div>
              </div>

              {/* Afetados */}
              <div>
                <p className="font-medium mb-2 flex items-center gap-1.5">
                  <Users className="w-4 h-4" /> Colaboradores abrangidos ({afetadosQ.data?.length ?? 0})
                </p>
                <div className="max-h-64 overflow-y-auto space-y-1">
                  {(afetadosQ.data ?? []).map((a) => (
                    <div key={a.colaborador_cpf} className="flex items-center gap-2 rounded border p-2 text-xs">
                      <span className="flex-1">{a.colaborador_nome}</span>
                      <span className="text-muted-foreground">{a.meses_de_casa} meses</span>
                      {a.art_140 && (
                        <Badge variant="outline" className="text-amber-600 border-amber-500/30">
                          <FileWarning className="w-3 h-3 mr-1" /> Art. 140 — {a.dias_proporcionais}d proporcionais
                        </Badge>
                      )}
                    </div>
                  ))}
                  {afetadosQ.data?.length === 0 && (
                    <p className="text-muted-foreground text-xs">Nenhum colaborador ativo neste setor.</p>
                  )}
                </div>
                <p className="text-xs text-muted-foreground mt-2">
                  Quem tem menos de 12 meses entra com férias proporcionais e novo período aquisitivo (art. 140).
                </p>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

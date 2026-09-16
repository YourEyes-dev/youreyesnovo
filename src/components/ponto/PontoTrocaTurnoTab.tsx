import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { ArrowLeftRight, Plus, AlertTriangle, Check, X, PlayCircle } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";

/**
 * Troca de turno entre dois colaboradores (ESC-020).
 *
 * Trocar turno não é editar duas linhas de escala: precisa de aprovação do
 * gestor, registro de quem trocou com quem, e conferência da interjornada de
 * 11h (CLT art. 66) — que pode ficar abaixo do mínimo para um dos dois ao
 * assumir o turno do outro. O banco simula esse risco na solicitação e só
 * efetiva depois de aprovada; aqui está o caminho para o RH usar isso.
 */
const STATUS: Record<string, { label: string; cor: "default" | "secondary" | "destructive" | "outline" }> = {
  solicitada: { label: "Aguardando aprovação", cor: "secondary" },
  aprovada: { label: "Aprovada", cor: "default" },
  efetivada: { label: "Efetivada", cor: "default" },
  recusada: { label: "Recusada", cor: "destructive" },
  cancelada: { label: "Cancelada", cor: "outline" },
};

export function PontoTrocaTurnoTab() {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();

  const [open, setOpen] = useState(false);
  const [atribA, setAtribA] = useState("");
  const [atribB, setAtribB] = useState("");
  const [dataTroca, setDataTroca] = useState(format(new Date(), "yyyy-MM-dd"));
  const [dataFim, setDataFim] = useState("");
  const [motivo, setMotivo] = useState("");
  const [salvando, setSalvando] = useState(false);

  // Atribuições vigentes: são elas que se cruzam na troca.
  const { data: atribuicoes = [] } = useQuery({
    queryKey: ["ponto-atribuicoes-vigentes", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      const hoje = format(new Date(), "yyyy-MM-dd");
      let q = fromTable("ponto_escala_atribuicoes")
        .select("id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, ativa")
        .eq("tenant_id", tenantId)
        .lte("data_inicio", hoje);
      const { data } = await q.order("colaborador_nome") as { data: any[] | null };
      return (data || []).filter(
        (a: any) => (a.ativa ?? true) && (!a.data_fim || a.data_fim >= hoje),
      );
    },
    enabled: !!tenantId,
  });

  const { data: escalas = [] } = useQuery({
    queryKey: ["ponto-escalas-list", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_escalas").select("id,nome,tipo").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const nomeEscala = (id: string) => escalas.find((e: any) => e.id === id)?.nome || "escala";

  const { data: trocas = [], isLoading } = useQuery({
    queryKey: ["ponto-trocas-turno", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_troca_turno").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q.order("solicitada_em", { ascending: false }).limit(50) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const opcoesB = useMemo(
    () => atribuicoes.filter((a: any) => a.id !== atribA),
    [atribuicoes, atribA],
  );

  const rotuloAtribuicao = (a: any) =>
    `${a.colaborador_nome} — ${nomeEscala(a.escala_id)}`;

  const limpar = () => {
    setAtribA(""); setAtribB(""); setMotivo("");
    setDataTroca(format(new Date(), "yyyy-MM-dd")); setDataFim("");
  };

  const solicitar = async () => {
    if (!tenantId) return;
    if (!atribA || !atribB) { toast.error("Escolha os dois colaboradores"); return; }
    if (atribA === atribB) { toast.error("Escolha colaboradores diferentes"); return; }
    if (!dataTroca) { toast.error("Informe o dia da troca"); return; }
    if (dataFim && dataFim < dataTroca) { toast.error("O fim da troca não pode ser antes do início"); return; }

    setSalvando(true);
    try {
      const { error } = await (supabase.rpc as any)("ponto_troca_turno_solicitar", {
        p_tenant_id: tenantId,
        p_atribuicao_a_id: atribA,
        p_atribuicao_b_id: atribB,
        p_data_troca: dataTroca,
        p_data_fim_troca: dataFim || null,
        p_solicitante_id: user?.id || null,
        p_solicitante_nome: profile?.nome_completo || null,
        p_motivo: motivo || null,
      });
      if (error) throw error;
      qc.invalidateQueries({ queryKey: ["ponto-trocas-turno"] });
      setOpen(false);
      limpar();
      toast.success("Troca registrada e enviada para aprovação.");
    } catch (e: any) {
      toast.error("Não foi possível registrar a troca: " + (e?.message || ""));
    } finally {
      setSalvando(false);
    }
  };

  const aprovar = async (t: any) => {
    if (t.risco_interjornada) {
      const ok = await confirmDialog({
        title: "Aprovar troca com risco de interjornada",
        description:
          `${t.risco_detalhe || "A troca deixa a interjornada abaixo de 11h."} ` +
          "A CLT (art. 66) exige 11 horas entre duas jornadas. Aprovar assim mesmo? " +
          "Digite APROVAR para confirmar.",
        requiredWord: "APROVAR",
        variant: "destructive",
      });
      if (!ok) return;
    }
    const { error } = await (supabase.rpc as any)("ponto_troca_turno_aprovar", {
      p_troca_id: t.id,
      p_aprovador_id: user?.id || null,
      p_aprovador_nome: profile?.nome_completo || null,
    });
    if (error) { toast.error(error.message); return; }
    qc.invalidateQueries({ queryKey: ["ponto-trocas-turno"] });
    toast.success("Troca aprovada. Falta efetivar para valer na escala.");
  };

  const recusar = async (t: any) => {
    const ok = await confirmDialog({
      title: "Recusar troca",
      description: `Confirma recusar a troca entre ${t.colaborador_a_nome} e ${t.colaborador_b_nome}?`,
    });
    if (!ok) return;
    const { error } = await (supabase.rpc as any)("ponto_troca_turno_recusar", {
      p_troca_id: t.id,
      p_aprovador_id: user?.id || null,
      p_aprovador_nome: profile?.nome_completo || null,
      p_motivo_recusa: null,
    });
    if (error) { toast.error(error.message); return; }
    qc.invalidateQueries({ queryKey: ["ponto-trocas-turno"] });
    toast.success("Troca recusada.");
  };

  const efetivar = async (t: any) => {
    const ok = await confirmDialog({
      title: "Efetivar troca na escala",
      description:
        `A escala de ${t.colaborador_a_nome} e ${t.colaborador_b_nome} passa a valer trocada a partir de ` +
        `${format(new Date(`${t.data_troca}T00:00:00`), "dd/MM/yyyy")}` +
        (t.data_fim_troca ? ` até ${format(new Date(`${t.data_fim_troca}T00:00:00`), "dd/MM/yyyy")}` : "") +
        ". O histórico anterior é preservado. Confirma?",
    });
    if (!ok) return;
    const { error } = await (supabase.rpc as any)("ponto_troca_turno_efetivar", { p_troca_id: t.id });
    if (error) { toast.error(error.message); return; }
    qc.invalidateQueries({ queryKey: ["ponto-trocas-turno"] });
    qc.invalidateQueries({ queryKey: ["ponto-atribuicoes-vigentes"] });
    toast.success("Troca efetivada na escala.");
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <ArrowLeftRight className="w-5 h-5 text-primary" /> Troca de turno
          </h3>
          <p className="text-sm text-muted-foreground max-w-3xl">
            Dois colaboradores trocam de turno com registro e aprovação. Ao solicitar, o sistema
            confere a interjornada dos dois (mínimo de 11 horas entre jornadas, CLT art. 66) e
            avisa quando a troca deixa alguém abaixo disso. A escala só muda quando a troca é
            efetivada — e o histórico anterior é preservado.
          </p>
        </div>
        <Button onClick={() => { limpar(); setOpen(true); }} className="shrink-0">
          <Plus className="w-4 h-4 mr-2" /> Nova troca
        </Button>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Trocas registradas</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Quem troca com quem</TableHead>
                <TableHead className="text-center">Período</TableHead>
                <TableHead className="text-center">Interjornada</TableHead>
                <TableHead className="text-center">Situação</TableHead>
                <TableHead>Solicitada por</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : trocas.length === 0 ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">
                  Nenhuma troca registrada.
                </TableCell></TableRow>
              ) : trocas.map((t: any) => {
                const st = STATUS[t.status] || STATUS.solicitada;
                return (
                  <TableRow key={t.id}>
                    <TableCell className="font-medium">
                      {t.colaborador_a_nome} ⇄ {t.colaborador_b_nome}
                      {t.motivo && <p className="text-xs text-muted-foreground font-normal">{t.motivo}</p>}
                    </TableCell>
                    <TableCell className="text-center text-sm">
                      {t.data_troca ? format(new Date(`${t.data_troca}T00:00:00`), "dd/MM/yy") : "—"}
                      {t.data_fim_troca ? ` — ${format(new Date(`${t.data_fim_troca}T00:00:00`), "dd/MM/yy")}` : " — sem fim"}
                    </TableCell>
                    <TableCell className="text-center">
                      {t.risco_interjornada ? (
                        <Badge variant="destructive" className="gap-1" title={t.risco_detalhe || ""}>
                          <AlertTriangle className="w-3 h-3" /> abaixo de 11h
                        </Badge>
                      ) : (
                        <Badge variant="outline">ok</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-center"><Badge variant={st.cor}>{st.label}</Badge></TableCell>
                    <TableCell className="text-sm">{t.solicitante_nome || "—"}</TableCell>
                    <TableCell className="text-center">
                      <div className="flex items-center justify-center gap-1">
                        {t.status === "solicitada" && (
                          <>
                            <Button variant="ghost" size="icon" title="Aprovar" onClick={() => aprovar(t)}>
                              <Check className="w-4 h-4 text-emerald-600" />
                            </Button>
                            <Button variant="ghost" size="icon" title="Recusar" onClick={() => recusar(t)}>
                              <X className="w-4 h-4 text-destructive" />
                            </Button>
                          </>
                        )}
                        {t.status === "aprovada" && (
                          <Button variant="outline" size="sm" onClick={() => efetivar(t)}>
                            <PlayCircle className="w-4 h-4 mr-1" /> Efetivar
                          </Button>
                        )}
                        {["efetivada", "recusada", "cancelada"].includes(t.status) && (
                          <span className="text-xs text-muted-foreground">—</span>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle>Nova troca de turno</DialogTitle>
            <DialogDescription>
              A troca fica registrada e vai para aprovação. A escala só muda depois de efetivada.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Colaborador A *</Label>
              <Select value={atribA} onValueChange={setAtribA}>
                <SelectTrigger><SelectValue placeholder="Quem sai do próprio turno" /></SelectTrigger>
                <SelectContent>
                  {atribuicoes.map((a: any) => (
                    <SelectItem key={a.id} value={a.id}>{rotuloAtribuicao(a)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Colaborador B *</Label>
              <Select value={atribB} onValueChange={setAtribB}>
                <SelectTrigger><SelectValue placeholder="Com quem vai trocar" /></SelectTrigger>
                <SelectContent>
                  {opcoesB.map((a: any) => (
                    <SelectItem key={a.id} value={a.id}>{rotuloAtribuicao(a)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {atribuicoes.length === 0 && (
                <p className="text-xs text-muted-foreground">
                  Nenhuma escala atribuída e vigente hoje — atribua as escalas antes de trocar turnos.
                </p>
              )}
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>A partir de *</Label>
                <Input type="date" value={dataTroca} onChange={(e) => setDataTroca(e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Até</Label>
                <Input type="date" value={dataFim} onChange={(e) => setDataFim(e.target.value)} />
                <p className="text-xs text-muted-foreground">Em branco: troca permanente.</p>
              </div>
            </div>

            <div className="space-y-2">
              <Label>Motivo</Label>
              <Textarea rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)}
                placeholder="Ex: acerto entre os dois para compromisso pessoal" />
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>Cancelar</Button>
            <Button onClick={solicitar} disabled={salvando}>
              {salvando ? "Registrando..." : "Registrar troca"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useColaboradores } from "@/hooks/useColaboradores";
import { Coffee, Plus, Edit, Trash2, AlertTriangle, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";

// Declaração formal do intervalo pré-assinalado (Súmula 338, III do TST;
// Portaria MTP 671/2021). Alvo: uma escala inteira ou um colaborador —
// a declaração do colaborador prevalece sobre a da escala.
type Alvo = "escala" | "colaborador";

interface PreAssinalacaoForm {
  alvo: Alvo;
  escala_id: string;
  colaborador_cpf: string;
  intervalo_minutos: string;
  intervalo_inicio: string;
  intervalo_fim: string;
  data_inicio: string;
  data_fim: string;
  lastro: string;
  observacao: string;
  ativa: boolean;
}

const defaultForm: PreAssinalacaoForm = {
  alvo: "escala",
  escala_id: "",
  colaborador_cpf: "",
  intervalo_minutos: "60",
  intervalo_inicio: "",
  intervalo_fim: "",
  data_inicio: "",
  data_fim: "",
  lastro: "",
  observacao: "",
  ativa: true,
};

const soDigitos = (v: string) => (v || "").replace(/\D/g, "");
const formatarCpf = (v: string) => {
  const d = soDigitos(v);
  if (d.length !== 11) return v || "—";
  return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
};

export function PontoPreAssinalacaoTab() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const { colaboradores } = useColaboradores({ excluirPJ: true, apenasBatePonto: true, excluirInativos: true });

  const [open, setOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<PreAssinalacaoForm>(defaultForm);
  const [saving, setSaving] = useState(false);

  // Reprocessamento da competência. A declaração vale a partir da vigência,
  // mas ela é aplicada quando o DIA é consolidado — quem cadastra depois do
  // mês corrido precisa mandar os dias já apurados serem reconsiderados.
  // As duas telas sempre avisaram disso; faltava o meio de fazer.
  const [reprocOpen, setReprocOpen] = useState(false);
  const [reprocComp, setReprocComp] = useState(() => {
    const d = new Date();
    d.setMonth(d.getMonth() - 1); // o caso comum é regularizar o mês que fechou
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
  });
  const [reprocessando, setReprocessando] = useState(false);

  const { data: declaracoes = [], isLoading } = useQuery({
    queryKey: ["ponto-pre-assinalacao", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_pre_assinalacao").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q.order("data_inicio", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const { data: escalas = [] } = useQuery({
    queryKey: ["ponto-escalas-list", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_escalas").select("id,nome,tipo,jornada_diaria_minutos").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const nomeEscala = (id: string) => escalas.find((e: any) => e.id === id)?.nome || "—";
  const nomeColaborador = (cpf: string) => {
    const d = soDigitos(cpf);
    return colaboradores.find((c) => soDigitos(c.cpf) === d)?.nome_completo || formatarCpf(cpf);
  };

  const upd = (k: keyof PreAssinalacaoForm, v: any) => setForm((p) => ({ ...p, [k]: v }));

  // Mínimo legal por faixa de jornada (CLT art. 71): até 4h nenhum;
  // acima de 4h e até 6h, 15 min; acima de 6h, 60 min. Espelha a função
  // ponto_intervalo_minimo_faixa do banco — aqui só para avisar o RH.
  const minimoLegal = useMemo(() => {
    if (form.alvo !== "escala" || !form.escala_id) return null;
    const jornada = escalas.find((e: any) => e.id === form.escala_id)?.jornada_diaria_minutos;
    if (jornada == null) return null;
    if (jornada <= 240) return 0;
    if (jornada <= 360) return 15;
    return 60;
  }, [form.alvo, form.escala_id, escalas]);

  const minutosInformados = Number(form.intervalo_minutos);
  const abaixoDoMinimo =
    minimoLegal != null && Number.isFinite(minutosInformados) && minutosInformados < minimoLegal;

  const onNovo = () => { setForm(defaultForm); setEditId(null); setOpen(true); };

  const onEditar = (d: any) => {
    setForm({
      alvo: d.colaborador_cpf ? "colaborador" : "escala",
      escala_id: d.escala_id || "",
      colaborador_cpf: d.colaborador_cpf || "",
      intervalo_minutos: String(d.intervalo_minutos ?? ""),
      intervalo_inicio: (d.intervalo_inicio || "").slice(0, 5),
      intervalo_fim: (d.intervalo_fim || "").slice(0, 5),
      data_inicio: d.data_inicio || "",
      data_fim: d.data_fim || "",
      lastro: d.lastro || "",
      observacao: d.observacao || "",
      ativa: d.ativa ?? true,
    });
    setEditId(d.id);
    setOpen(true);
  };

  const onSalvar = async () => {
    if (!tenantId) return;
    if (form.alvo === "escala" && !form.escala_id) { toast.error("Escolha a escala da declaração"); return; }
    if (form.alvo === "colaborador" && !form.colaborador_cpf) { toast.error("Escolha o colaborador da declaração"); return; }
    if (!Number.isFinite(minutosInformados) || minutosInformados < 0) { toast.error("Informe os minutos de intervalo"); return; }
    if (!form.data_inicio) { toast.error("Informe o início da vigência"); return; }
    if (form.data_fim && form.data_fim < form.data_inicio) { toast.error("O fim da vigência não pode ser antes do início"); return; }
    if (form.intervalo_inicio && form.intervalo_fim && form.intervalo_fim <= form.intervalo_inicio) {
      toast.error("O fim da janela precisa ser depois do início"); return;
    }
    if (!form.lastro.trim()) { toast.error("Informe o lastro (CCT, acordo ou política interna)"); return; }

    setSaving(true);
    try {
      const payload = {
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        escala_id: form.alvo === "escala" ? form.escala_id : null,
        colaborador_cpf: form.alvo === "colaborador" ? soDigitos(form.colaborador_cpf) : null,
        intervalo_minutos: minutosInformados,
        intervalo_inicio: form.intervalo_inicio || null,
        intervalo_fim: form.intervalo_fim || null,
        data_inicio: form.data_inicio,
        data_fim: form.data_fim || null,
        lastro: form.lastro.trim(),
        observacao: form.observacao || null,
        ativa: form.ativa,
      };
      if (editId) {
        const { error } = await fromTable("ponto_pre_assinalacao")
          .update({ ...payload, updated_at: new Date().toISOString() } as any).eq("id", editId);
        if (error) throw error;
        toast.success("Declaração atualizada");
      } else {
        const { error } = await fromTable("ponto_pre_assinalacao").insert(payload as any);
        if (error) throw error;
        toast.success("Declaração cadastrada");
      }
      qc.invalidateQueries({ queryKey: ["ponto-pre-assinalacao"] });
      setOpen(false);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  const onExcluir = async (d: any) => {
    const alvo = d.colaborador_cpf ? nomeColaborador(d.colaborador_cpf) : nomeEscala(d.escala_id);
    const ok = await confirmDialog({
      title: "Excluir declaração",
      description: `Confirma excluir a pré-assinalação de "${alvo}"? Os dias já apurados só mudam quando forem reconsolidados. Digite EXCLUIR para confirmar.`,
      requiredWord: "EXCLUIR",
      variant: "destructive",
    });
    if (!ok) return;
    const { error } = await fromTable("ponto_pre_assinalacao").delete().eq("id", d.id);
    if (error) { toast.error(error.message); return; }
    qc.invalidateQueries({ queryKey: ["ponto-pre-assinalacao"] });
    toast.success("Declaração removida");
  };

  const onReprocessar = async () => {
    if (!tenantId) return;
    setReprocessando(true);
    try {
      const { data, error } = await supabase.rpc("ponto_reprocessar_pre_assinalacao" as any, {
        p_tenant_id: tenantId,
        p_competencia: reprocComp,
        p_empresa_id: empresaAtivaId || null,
      });
      if (error) throw error;
      const r = data as any;
      if (r?.error) { toast.error(r.error); return; }
      if (r?.dias_reprocessados === 0) {
        toast.info(r?.aviso || "Nada a reprocessar nesta competência.");
      } else {
        toast.success(
          `${r.dias_reprocessados} dia(s) reconsiderado(s); ${r.dias_pre_assinalados} com intervalo pré-assinalado` +
          (r.alertas_removidos ? `; ${r.alertas_removidos} alerta(s) de intervalo suprimido retirado(s)` : "") + "."
        );
      }
      setReprocOpen(false);
      qc.invalidateQueries({ queryKey: ["ponto-diario"] });
      qc.invalidateQueries({ queryKey: ["ponto-alertas"] });
    } catch (e: any) {
      toast.error(e.message || "Erro ao reprocessar");
    } finally {
      setReprocessando(false);
    }
  };

  const janela = (d: any) =>
    d.intervalo_inicio && d.intervalo_fim
      ? `${String(d.intervalo_inicio).slice(0, 5)} — ${String(d.intervalo_fim).slice(0, 5)}`
      : "—";

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Coffee className="w-5 h-5 text-primary" /> Intervalo pré-assinalado
          </h3>
          <p className="text-sm text-muted-foreground max-w-3xl">
            Declare formalmente o intervalo de descanso de quem bate só entrada e saída. Sem esta
            declaração, o dia de duas batidas aparece como intervalo suprimido. Com ela, o intervalo
            declarado conta como gozado (Súmula 338 do TST; Portaria MTP 671/2021). A declaração de
            um colaborador prevalece sobre a da escala, e uma batida real de almoço sempre vence o
            que foi declarado.
          </p>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <Button variant="outline" onClick={() => setReprocOpen(true)}>
            <RefreshCw className="w-4 h-4 mr-2" /> Reprocessar competência
          </Button>
          <Button onClick={onNovo}><Plus className="w-4 h-4 mr-2" /> Nova declaração</Button>
        </div>
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Alcance</TableHead>
                <TableHead>Quem</TableHead>
                <TableHead className="text-center">Intervalo</TableHead>
                <TableHead className="text-center">Janela prevista</TableHead>
                <TableHead className="text-center">Vigência</TableHead>
                <TableHead>Lastro</TableHead>
                <TableHead className="text-center">Situação</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : declaracoes.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">
                  Nenhuma declaração cadastrada.
                </TableCell></TableRow>
              ) : declaracoes.map((d: any) => (
                <TableRow key={d.id}>
                  <TableCell>
                    <Badge variant={d.colaborador_cpf ? "secondary" : "outline"}>
                      {d.colaborador_cpf ? "Colaborador" : "Escala"}
                    </Badge>
                  </TableCell>
                  <TableCell className="font-medium">
                    {d.colaborador_cpf ? nomeColaborador(d.colaborador_cpf) : nomeEscala(d.escala_id)}
                  </TableCell>
                  <TableCell className="text-center">{d.intervalo_minutos} min</TableCell>
                  <TableCell className="text-center text-sm">{janela(d)}</TableCell>
                  <TableCell className="text-center text-sm">
                    {format(new Date(`${d.data_inicio}T00:00:00`), "dd/MM/yy")}
                    {d.data_fim
                      ? ` — ${format(new Date(`${d.data_fim}T00:00:00`), "dd/MM/yy")}`
                      : " — sem prazo"}
                  </TableCell>
                  <TableCell className="text-sm max-w-[220px] truncate" title={d.lastro}>{d.lastro}</TableCell>
                  <TableCell className="text-center">
                    {d.ativa ? <Badge>Ativa</Badge> : <Badge variant="outline">Inativa</Badge>}
                  </TableCell>
                  <TableCell className="text-center">
                    <div className="flex items-center justify-center gap-1">
                      <Button variant="ghost" size="icon" onClick={() => onEditar(d)}><Edit className="w-4 h-4" /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => onExcluir(d)}><Trash2 className="w-4 h-4" /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editId ? "Editar declaração" : "Nova declaração de intervalo"}</DialogTitle>
            <DialogDescription>
              Vale a partir da vigência informada. Dias já apurados só passam a mostrar o intervalo
              declarado quando forem reconsolidados.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Alcance *</Label>
                <Select value={form.alvo} onValueChange={(v: Alvo) => setForm((p) => ({ ...p, alvo: v, escala_id: "", colaborador_cpf: "" }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="escala">Escala inteira</SelectItem>
                    <SelectItem value="colaborador">Um colaborador</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2 flex items-end gap-2">
                <Switch id="pa-ativa" checked={form.ativa} onCheckedChange={(v) => upd("ativa", v)} />
                <Label htmlFor="pa-ativa">Ativa</Label>
              </div>
            </div>

            {form.alvo === "escala" ? (
              <div className="space-y-2">
                <Label>Escala *</Label>
                <Select value={form.escala_id} onValueChange={(v) => upd("escala_id", v)}>
                  <SelectTrigger><SelectValue placeholder="Escolha a escala" /></SelectTrigger>
                  <SelectContent>
                    {escalas.map((e: any) => (
                      <SelectItem key={e.id} value={e.id}>{e.nome}{e.tipo ? ` — ${e.tipo}` : ""}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            ) : (
              <div className="space-y-2">
                <Label>Colaborador *</Label>
                <Select value={form.colaborador_cpf} onValueChange={(v) => upd("colaborador_cpf", v)}>
                  <SelectTrigger><SelectValue placeholder="Escolha o colaborador" /></SelectTrigger>
                  <SelectContent>
                    {colaboradores
                      .filter((c) => soDigitos(c.cpf).length === 11)
                      .map((c) => (
                        <SelectItem key={c.id} value={soDigitos(c.cpf)}>
                          {c.nome_completo} — {formatarCpf(c.cpf)}
                        </SelectItem>
                      ))}
                  </SelectContent>
                </Select>
              </div>
            )}

            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Intervalo (minutos) *</Label>
                <Input type="number" min={0} value={form.intervalo_minutos} onChange={(e) => upd("intervalo_minutos", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Janela — início</Label>
                <Input type="time" value={form.intervalo_inicio} onChange={(e) => upd("intervalo_inicio", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Janela — fim</Label>
                <Input type="time" value={form.intervalo_fim} onChange={(e) => upd("intervalo_fim", e.target.value)} />
              </div>
            </div>

            {abaixoDoMinimo && (
              <div className="flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
                <span>
                  A jornada dessa escala exige no mínimo <strong>{minimoLegal} minutos</strong> de
                  intervalo (CLT art. 71). Declarando menos, a diferença continua contando como
                  intervalo suprimido na apuração.
                </span>
              </div>
            )}

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Vigência — início *</Label>
                <Input type="date" value={form.data_inicio} onChange={(e) => upd("data_inicio", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Vigência — fim</Label>
                <Input type="date" value={form.data_fim} onChange={(e) => upd("data_fim", e.target.value)} />
                <p className="text-xs text-muted-foreground">Em branco: vale por prazo indeterminado.</p>
              </div>
            </div>

            <div className="space-y-2">
              <Label>Lastro *</Label>
              <Input value={form.lastro} onChange={(e) => upd("lastro", e.target.value)} placeholder="Ex: CCT 2026/2027, cláusula 12ª" />
              <p className="text-xs text-muted-foreground">
                O documento que sustenta a pré-assinalação: convenção, acordo coletivo, acordo
                individual ou política interna.
              </p>
            </div>

            <div className="space-y-2">
              <Label>Observações</Label>
              <Textarea rows={3} value={form.observacao} onChange={(e) => upd("observacao", e.target.value)} />
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>Cancelar</Button>
            <Button onClick={onSalvar} disabled={saving}>{saving ? "Salvando..." : "Salvar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={reprocOpen} onOpenChange={setReprocOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Reprocessar competência</DialogTitle>
            <DialogDescription>
              Aplica as declarações vigentes aos dias que já foram apurados. Use depois de
              cadastrar uma pré-assinalação com vigência retroativa — sem isto, o mês que já
              passou continua mostrando o intervalo como suprimido.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Competência</Label>
              <Input type="month" value={reprocComp} onChange={(e) => setReprocComp(e.target.value)} />
            </div>

            <div className="flex gap-2 p-3 rounded-lg border bg-muted/30 text-xs text-muted-foreground">
              <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
              <div className="space-y-1">
                <p>
                  Só mexe no intervalo: horas trabalhadas, horas extras, batidas e situação do dia
                  ficam exatamente como estão.
                </p>
                <p>
                  Uma batida real de almoço continua vencendo o que foi declarado, e a competência
                  já fechada não é alterada — reabra antes, se for o caso.
                </p>
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setReprocOpen(false)}>Cancelar</Button>
            <Button onClick={onReprocessar} disabled={reprocessando || !reprocComp}>
              {reprocessando ? "Reprocessando..." : "Reprocessar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

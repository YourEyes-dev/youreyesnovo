import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Settings2, Plus, Edit, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";

interface BHForm {
  tipo: "sem_banco" | "semanal" | "mensal" | "individual" | "coletivo";
  prazo_compensacao_dias: number;
  permite_saldo_positivo: boolean;
  permite_saldo_negativo: boolean;
  limite_acumulo_horas: number;
  forma_compensacao: string;
  forma_pagamento_vencer: string;
  exige_acordo_individual: boolean;
  exige_cct_act: boolean;
  acordo_id: string | null;
  escala_id: string | null;
  data_inicio: string | null;
  ativo: boolean;
}

const defaultForm: BHForm = {
  tipo: "mensal",
  prazo_compensacao_dias: 180,
  permite_saldo_positivo: true,
  permite_saldo_negativo: false,
  limite_acumulo_horas: 60,
  forma_compensacao: "folga",
  forma_pagamento_vencer: "horas_extras",
  exige_acordo_individual: false,
  exige_cct_act: false,
  acordo_id: null,
  escala_id: null,
  data_inicio: null,
  ativo: true,
};

export function PontoBancoHorasConfigTab() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<BHForm>(defaultForm);
  const [saving, setSaving] = useState(false);

  const { data: configs = [], isLoading } = useQuery({
    queryKey: ["ponto-bh-config", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_banco_horas_config").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q.order("created_at", { ascending: false }) as { data: any[] | null };
      return data || [];
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

  const { data: acordos = [] } = useQuery({
    queryKey: ["ponto-acordos-list", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_acordos").select("id,titulo,tipo").eq("tenant_id", tenantId).eq("ativo", true);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const upd = (k: keyof BHForm, v: any) => setForm(p => ({ ...p, [k]: v }));

  const onNovo = () => { setForm(defaultForm); setEditId(null); setOpen(true); };
  const onEditar = (c: any) => {
    setForm({
      tipo: c.tipo,
      prazo_compensacao_dias: c.prazo_compensacao_dias ?? 180,
      permite_saldo_positivo: c.permite_saldo_positivo ?? true,
      permite_saldo_negativo: c.permite_saldo_negativo ?? false,
      limite_acumulo_horas: Number(c.limite_acumulo_horas ?? 60),
      forma_compensacao: c.forma_compensacao || "folga",
      forma_pagamento_vencer: c.forma_pagamento_vencer || "horas_extras",
      exige_acordo_individual: c.exige_acordo_individual ?? false,
      exige_cct_act: c.exige_cct_act ?? false,
      acordo_id: c.acordo_id || null,
      escala_id: c.escala_id || null,
      data_inicio: c.data_inicio ? String(c.data_inicio).slice(0, 10) : null,
      ativo: c.ativo ?? true,
    });
    setEditId(c.id);
    setOpen(true);
  };

  const onSalvar = async () => {
    if (!tenantId) return;
    setSaving(true);
    try {
      const payload = { ...form, data_inicio: form.data_inicio || null, tenant_id: tenantId, empresa_id: empresaAtivaId || null };
      if (editId) {
        await fromTable("ponto_banco_horas_config").update(payload as any).eq("id", editId);
        toast.success("Configuração atualizada");
      } else {
        await fromTable("ponto_banco_horas_config").insert(payload as any);
        toast.success("Configuração criada");
      }
      qc.invalidateQueries({ queryKey: ["ponto-bh-config"] });
      setOpen(false);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  const onExcluir = async (c: any) => {
    const ok = await confirmDialog({
      title: "Excluir configuração",
      description: `Confirma exclusão? Digite EXCLUIR para confirmar.`,
      requiredWord: "EXCLUIR",
      variant: "destructive",
    });
    if (!ok) return;
    await fromTable("ponto_banco_horas_config").delete().eq("id", c.id);
    qc.invalidateQueries({ queryKey: ["ponto-bh-config"] });
    toast.success("Removido");
  };

  const tipoLabel = (t: string) => ({
    sem_banco: "Sem Banco",
    semanal: "Semanal",
    mensal: "Mensal",
    individual: "Individual",
    coletivo: "Coletivo",
  } as any)[t] || t;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Settings2 className="w-5 h-5 text-primary" /> Configurações de Banco de Horas
          </h3>
          <p className="text-sm text-muted-foreground">
            Defina regras por escala: tipo, prazo de compensação, limites e vínculo com acordo.
          </p>
        </div>
        <Button onClick={onNovo}><Plus className="w-4 h-4 mr-2" /> Nova Configuração</Button>
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tipo</TableHead>
                <TableHead>Escala</TableHead>
                <TableHead className="text-center">Início</TableHead>
                <TableHead className="text-center">Prazo (dias)</TableHead>
                <TableHead className="text-center">Limite (h)</TableHead>
                <TableHead className="text-center">Acordo</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : configs.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Nenhuma configuração. Use os padrões CLT.</TableCell></TableRow>
              ) : configs.map((c: any) => {
                const esc = escalas.find((e: any) => e.id === c.escala_id);
                const ac = acordos.find((a: any) => a.id === c.acordo_id);
                return (
                  <TableRow key={c.id}>
                    <TableCell><Badge variant="outline">{tipoLabel(c.tipo)}</Badge></TableCell>
                    <TableCell>{esc?.nome || <span className="text-muted-foreground text-xs">Todas</span>}</TableCell>
                    <TableCell className="text-center text-xs">
                      {c.data_inicio
                        ? String(c.data_inicio).slice(0, 10).split("-").reverse().join("/")
                        : <span className="text-muted-foreground">—</span>}
                    </TableCell>
                    <TableCell className="text-center">{c.prazo_compensacao_dias}</TableCell>
                    <TableCell className="text-center">{c.limite_acumulo_horas}</TableCell>
                    <TableCell className="text-center text-xs">{ac?.titulo || "—"}</TableCell>
                    <TableCell className="text-center">{c.ativo ? <Badge>Ativo</Badge> : <Badge variant="outline">Inativo</Badge>}</TableCell>
                    <TableCell className="text-center">
                      <div className="flex items-center justify-center gap-1">
                        <Button variant="ghost" size="icon" onClick={() => onEditar(c)}><Edit className="w-4 h-4" /></Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => onExcluir(c)}><Trash2 className="w-4 h-4" /></Button>
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
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editId ? "Editar Configuração" : "Nova Configuração de Banco de Horas"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo *</Label>
                <Select value={form.tipo} onValueChange={(v: any) => upd("tipo", v)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="sem_banco">Sem Banco de Horas</SelectItem>
                    <SelectItem value="semanal">Semanal</SelectItem>
                    <SelectItem value="mensal">Mensal</SelectItem>
                    <SelectItem value="individual">Individual</SelectItem>
                    <SelectItem value="coletivo">Coletivo</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2 flex items-end gap-2">
                <Switch checked={form.ativo} onCheckedChange={v => upd("ativo", v)} id="bh-ativo" />
                <Label htmlFor="bh-ativo">Ativo</Label>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Escala (opcional)</Label>
                <Select value={form.escala_id || "todas"} onValueChange={v => upd("escala_id", v === "todas" ? null : v)}>
                  <SelectTrigger><SelectValue placeholder="Todas" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="todas">Todas as escalas</SelectItem>
                    {escalas.map((e: any) => <SelectItem key={e.id} value={e.id}>{e.nome}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Acordo Vinculado (opcional)</Label>
                <Select value={form.acordo_id || "nenhum"} onValueChange={v => upd("acordo_id", v === "nenhum" ? null : v)}>
                  <SelectTrigger><SelectValue placeholder="Nenhum" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="nenhum">Nenhum</SelectItem>
                    {acordos.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.titulo}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Data de início (opcional)</Label>
                <Input
                  type="date"
                  value={form.data_inicio || ""}
                  onChange={e => upd("data_inicio", e.target.value || null)}
                />
                <p className="text-xs text-muted-foreground">
                  O banco só acumula a partir desta data. Antes dela, as horas vão
                  para a folha. Em branco = vale para todas as competências. Depois
                  de definir, reapure as competências para aplicar (Banco de Horas →
                  "Apurar agora" / "Reapurar fechadas").
                </p>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Prazo de Compensação (dias)</Label>
                <Input type="number" value={form.prazo_compensacao_dias} onChange={e => upd("prazo_compensacao_dias", Number(e.target.value))} />
              </div>
              <div className="space-y-2">
                <Label>Limite Acúmulo (horas)</Label>
                <Input type="number" value={form.limite_acumulo_horas} onChange={e => upd("limite_acumulo_horas", Number(e.target.value))} />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Forma de Compensação</Label>
                <Select value={form.forma_compensacao} onValueChange={v => upd("forma_compensacao", v)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="folga">Folga</SelectItem>
                    <SelectItem value="reducao_jornada">Redução de jornada</SelectItem>
                    <SelectItem value="ferias">Antecipação de férias</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Forma de Pgto. ao Vencer</Label>
                <Select value={form.forma_pagamento_vencer} onValueChange={v => upd("forma_pagamento_vencer", v)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="horas_extras">Pagar como Horas Extras</SelectItem>
                    <SelectItem value="rescisao">Liquidar na rescisão</SelectItem>
                    <SelectItem value="zerar">Zerar (com aviso)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="flex items-center gap-2"><Switch checked={form.permite_saldo_positivo} onCheckedChange={v => upd("permite_saldo_positivo", v)} /><Label>Permite saldo positivo</Label></div>
              <div className="flex items-center gap-2"><Switch checked={form.permite_saldo_negativo} onCheckedChange={v => upd("permite_saldo_negativo", v)} /><Label>Permite saldo negativo</Label></div>
              <div className="flex items-center gap-2"><Switch checked={form.exige_acordo_individual} onCheckedChange={v => upd("exige_acordo_individual", v)} /><Label>Exige acordo individual</Label></div>
              <div className="flex items-center gap-2"><Switch checked={form.exige_cct_act} onCheckedChange={v => upd("exige_cct_act", v)} /><Label>Exige CCT/ACT</Label></div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>Cancelar</Button>
            <Button onClick={onSalvar} disabled={saving}>{saving ? "Salvando..." : "Salvar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

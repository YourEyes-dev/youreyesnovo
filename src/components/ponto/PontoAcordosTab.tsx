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
import { Textarea } from "@/components/ui/textarea";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { FileText, Plus, Edit, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";

interface AcordoForm {
  tipo: "individual" | "act" | "cct";
  titulo: string;
  vigencia_inicio: string;
  vigencia_fim: string;
  documento_url: string;
  observacoes: string;
  ativo: boolean;
  permite_compensacao_falta: boolean;
  colaborador_cpf: string;
}

const defaultForm: AcordoForm = {
  tipo: "individual",
  titulo: "",
  vigencia_inicio: "",
  vigencia_fim: "",
  documento_url: "",
  observacoes: "",
  ativo: true,
  permite_compensacao_falta: false,
  colaborador_cpf: "",
};

export function PontoAcordosTab() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<AcordoForm>(defaultForm);
  const [saving, setSaving] = useState(false);

  const { data: acordos = [], isLoading } = useQuery({
    queryKey: ["ponto-acordos", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_acordos").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) {
        q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      }
      const { data } = await q.order("created_at", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const upd = (k: keyof AcordoForm, v: any) => setForm(p => ({ ...p, [k]: v }));

  const onNovo = () => { setForm(defaultForm); setEditId(null); setOpen(true); };
  const onEditar = (a: any) => {
    setForm({
      tipo: a.tipo,
      titulo: a.titulo || "",
      vigencia_inicio: a.vigencia_inicio || "",
      vigencia_fim: a.vigencia_fim || "",
      documento_url: a.documento_url || "",
      observacoes: a.observacoes || "",
      ativo: a.ativo ?? true,
      permite_compensacao_falta: a.permite_compensacao_falta ?? false,
      colaborador_cpf: a.colaborador_cpf || "",
    });
    setEditId(a.id);
    setOpen(true);
  };

  const onSalvar = async () => {
    if (!form.titulo || !tenantId) { toast.error("Título obrigatório"); return; }
    setSaving(true);
    try {
      const payload = {
        ...form,
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        vigencia_inicio: form.vigencia_inicio || null,
        vigencia_fim: form.vigencia_fim || null,
        colaborador_cpf: form.colaborador_cpf ? form.colaborador_cpf.replace(/\D/g, "") : null,
      };
      if (editId) {
        await fromTable("ponto_acordos").update(payload as any).eq("id", editId);
        toast.success("Acordo atualizado");
      } else {
        await fromTable("ponto_acordos").insert(payload as any);
        toast.success("Acordo cadastrado");
      }
      qc.invalidateQueries({ queryKey: ["ponto-acordos"] });
      setOpen(false);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  const onExcluir = async (a: any) => {
    const ok = await confirmDialog({
      title: "Excluir acordo",
      description: `Confirma exclusão de "${a.titulo}"? Digite EXCLUIR para confirmar.`,
      requiredWord: "EXCLUIR",
      variant: "destructive",
    });
    if (!ok) return;
    await fromTable("ponto_acordos").delete().eq("id", a.id);
    qc.invalidateQueries({ queryKey: ["ponto-acordos"] });
    toast.success("Acordo removido");
  };

  const tipoLabel = (t: string) => t === "individual" ? "Acordo Individual" : t === "act" ? "ACT" : "CCT";
  const tipoColor = (t: string) => t === "cct" ? "default" : t === "act" ? "secondary" : "outline";

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <FileText className="w-5 h-5 text-primary" /> Acordos & Convenções
          </h3>
          <p className="text-sm text-muted-foreground">
            Vincule acordos individuais, ACT ou CCT às escalas e ao banco de horas.
          </p>
        </div>
        <Button onClick={onNovo}><Plus className="w-4 h-4 mr-2" /> Novo Acordo</Button>
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tipo</TableHead>
                <TableHead>Título</TableHead>
                <TableHead className="text-center">Vigência</TableHead>
                <TableHead className="text-center">Documento</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : acordos.length === 0 ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Nenhum acordo cadastrado.</TableCell></TableRow>
              ) : acordos.map((a: any) => (
                <TableRow key={a.id}>
                  <TableCell><Badge variant={tipoColor(a.tipo) as any}>{tipoLabel(a.tipo)}</Badge></TableCell>
                  <TableCell className="font-medium">{a.titulo}</TableCell>
                  <TableCell className="text-center text-sm">
                    {a.vigencia_inicio && a.vigencia_fim
                      ? `${format(new Date(a.vigencia_inicio), "dd/MM/yy")} — ${format(new Date(a.vigencia_fim), "dd/MM/yy")}`
                      : <span className="text-muted-foreground">—</span>}
                  </TableCell>
                  <TableCell className="text-center">
                    {a.documento_url
                      ? <a href={a.documento_url} target="_blank" rel="noreferrer" className="text-primary text-sm underline">Ver</a>
                      : <span className="text-muted-foreground text-xs">—</span>}
                  </TableCell>
                  <TableCell className="text-center">
                    {a.ativo ? <Badge>Ativo</Badge> : <Badge variant="outline">Inativo</Badge>}
                  </TableCell>
                  <TableCell className="text-center">
                    <div className="flex items-center justify-center gap-1">
                      <Button variant="ghost" size="icon" onClick={() => onEditar(a)}><Edit className="w-4 h-4" /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => onExcluir(a)}><Trash2 className="w-4 h-4" /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle>{editId ? "Editar Acordo" : "Novo Acordo"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo *</Label>
                <Select value={form.tipo} onValueChange={(v: any) => upd("tipo", v)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="individual">Acordo Individual</SelectItem>
                    <SelectItem value="act">ACT — Acordo Coletivo</SelectItem>
                    <SelectItem value="cct">CCT — Convenção Coletiva</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2 flex items-end gap-2">
                <Switch checked={form.ativo} onCheckedChange={v => upd("ativo", v)} id="ativo" />
                <Label htmlFor="ativo">Ativo</Label>
              </div>
            </div>
            <div className="space-y-2">
              <Label>Título *</Label>
              <Input value={form.titulo} onChange={e => upd("titulo", e.target.value)} placeholder="Ex: ACT Compensação 6x1 — 2025" />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Vigência Início</Label>
                <Input type="date" value={form.vigencia_inicio} onChange={e => upd("vigencia_inicio", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Vigência Fim</Label>
                <Input type="date" value={form.vigencia_fim} onChange={e => upd("vigencia_fim", e.target.value)} />
              </div>
            </div>
            <div className="space-y-2">
              <Label>URL do Documento</Label>
              <Input value={form.documento_url} onChange={e => upd("documento_url", e.target.value)} placeholder="https://..." />
            </div>
            <div className="space-y-2">
              <Label>Observações</Label>
              <Textarea value={form.observacoes} onChange={e => upd("observacoes", e.target.value)} rows={3} />
            </div>

            <div className="rounded-md border p-3 space-y-3 bg-muted/30">
              <div className="flex items-center gap-2">
                <Switch
                  id="permite_compensacao_falta"
                  checked={form.permite_compensacao_falta}
                  onCheckedChange={v => upd("permite_compensacao_falta", v)}
                />
                <Label htmlFor="permite_compensacao_falta" className="cursor-pointer">
                  Autoriza compensação de falta
                </Label>
              </div>
              <p className="text-[11px] text-muted-foreground -mt-1">
                Permite converter falta injustificada em débito do banco de horas (CLT art. 462). É
                instituto distinto do acordo de banco — marque só em acordo que preveja essa cláusula.
              </p>
              {form.permite_compensacao_falta && (
                <div className="space-y-2">
                  <Label>CPF do colaborador (acordo individual)</Label>
                  <Input
                    value={form.colaborador_cpf}
                    onChange={e => upd("colaborador_cpf", e.target.value)}
                    placeholder="Só dígitos — deixe vazio para valer p/ toda a empresa (coletivo)"
                  />
                  <p className="text-[11px] text-muted-foreground -mt-1">
                    Preenchido: o acordo vale só para este colaborador. Vazio: vale para todos os
                    vínculos da empresa (use em ACT/CCT).
                  </p>
                </div>
              )}
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

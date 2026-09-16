import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { ShieldCheck, Plus, Edit, Trash2, AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import { format, differenceInCalendarDays } from "date-fns";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";

/**
 * Certificado digital (ICP-Brasil) que assina o AFD e o AEJ — Portaria MTP
 * 671/2021. Aqui ficam apenas os METADADOS de vigência: a chave privada não
 * entra no sistema. Certificado vencido paralisa a emissão assinada justamente
 * na hora da fiscalização, por isso a vigência é vigiada com antecedência.
 */
interface CertificadoForm {
  certificado_digital_tipo: "A1" | "A3";
  icp_brasil: boolean;
  titular_nome: string;
  titular_documento: string;
  numero_serie: string;
  emissor: string;
  fingerprint: string;
  valido_de: string;
  valido_ate: string;
  alerta_antecedencia_dias: string;
  arquivo_url: string;
  ativo: boolean;
}

const defaultForm: CertificadoForm = {
  certificado_digital_tipo: "A1",
  icp_brasil: true,
  titular_nome: "",
  titular_documento: "",
  numero_serie: "",
  emissor: "",
  fingerprint: "",
  valido_de: "",
  valido_ate: "",
  alerta_antecedencia_dias: "30",
  arquivo_url: "",
  ativo: true,
};

export function PontoCertificadoTab() {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<CertificadoForm>(defaultForm);
  const [saving, setSaving] = useState(false);

  const { data: certificados = [], isLoading } = useQuery({
    queryKey: ["ponto-certificados", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let q = fromTable("ponto_certificados_digitais").select("*").eq("tenant_id", tenantId);
      if (empresaAtivaId) q = q.or(`empresa_id.eq.${empresaAtivaId},empresa_id.is.null`);
      const { data } = await q.order("valido_ate", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const upd = (k: keyof CertificadoForm, v: any) => setForm((p) => ({ ...p, [k]: v }));

  const situacao = (c: any) => {
    if (!c.ativo) return { label: "Inativo", cor: "outline" as const, dias: null as number | null };
    if (!c.valido_ate) return { label: "Sem vencimento informado", cor: "outline" as const, dias: null };
    const dias = differenceInCalendarDays(new Date(`${c.valido_ate}T00:00:00`), new Date());
    if (dias < 0) return { label: "VENCIDO", cor: "destructive" as const, dias };
    if (dias <= (Number(c.alerta_antecedencia_dias) || 30))
      return { label: `Vence em ${dias} dia(s)`, cor: "secondary" as const, dias };
    return { label: "Vigente", cor: "default" as const, dias };
  };

  // O que assina hoje: ativo, dentro da vigência e com o vencimento mais longe.
  const vigente = certificados
    .filter((c: any) => {
      if (!c.ativo) return false;
      const de = c.valido_de ? new Date(`${c.valido_de}T00:00:00`) : null;
      const ate = c.valido_ate ? new Date(`${c.valido_ate}T00:00:00`) : null;
      const hoje = new Date();
      return (!de || de <= hoje) && (!ate || ate >= hoje);
    })
    .sort((a: any, b: any) => String(b.valido_ate || "").localeCompare(String(a.valido_ate || "")))[0];

  const onNovo = () => { setForm(defaultForm); setEditId(null); setOpen(true); };

  const onEditar = (c: any) => {
    setForm({
      certificado_digital_tipo: c.certificado_digital_tipo === "A3" ? "A3" : "A1",
      icp_brasil: c.icp_brasil ?? true,
      titular_nome: c.titular_nome || "",
      titular_documento: c.titular_documento || "",
      numero_serie: c.numero_serie || "",
      emissor: c.emissor || "",
      fingerprint: c.fingerprint || "",
      valido_de: c.valido_de || "",
      valido_ate: c.valido_ate || "",
      alerta_antecedencia_dias: String(c.alerta_antecedencia_dias ?? 30),
      arquivo_url: c.arquivo_url || "",
      ativo: c.ativo ?? true,
    });
    setEditId(c.id);
    setOpen(true);
  };

  const onSalvar = async () => {
    if (!tenantId) return;
    if (!form.titular_nome.trim()) { toast.error("Informe o titular do certificado"); return; }
    if (!form.valido_ate) { toast.error("Informe a data de vencimento"); return; }
    if (form.valido_de && form.valido_ate < form.valido_de) {
      toast.error("O vencimento não pode ser antes do início da validade"); return;
    }
    const dias = Number(form.alerta_antecedencia_dias);
    if (!Number.isFinite(dias) || dias < 0) { toast.error("Antecedência do alerta inválida"); return; }

    setSaving(true);
    try {
      const payload = {
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        certificado_digital_tipo: form.certificado_digital_tipo,
        icp_brasil: form.icp_brasil,
        titular_nome: form.titular_nome.trim(),
        titular_documento: form.titular_documento.replace(/\D/g, "") || null,
        numero_serie: form.numero_serie || null,
        emissor: form.emissor || null,
        fingerprint: form.fingerprint || null,
        valido_de: form.valido_de || null,
        valido_ate: form.valido_ate,
        alerta_antecedencia_dias: dias,
        arquivo_url: form.arquivo_url || null,
        ativo: form.ativo,
      };
      if (editId) {
        const { error } = await fromTable("ponto_certificados_digitais")
          .update({ ...payload, updated_at: new Date().toISOString() } as any).eq("id", editId);
        if (error) throw error;
        toast.success("Certificado atualizado");
      } else {
        const { error } = await fromTable("ponto_certificados_digitais").insert(payload as any);
        if (error) throw error;
        toast.success("Certificado cadastrado");
      }
      qc.invalidateQueries({ queryKey: ["ponto-certificados"] });
      setOpen(false);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  const onExcluir = async (c: any) => {
    const ok = await confirmDialog({
      title: "Excluir certificado",
      description: `Confirma excluir o certificado de "${c.titular_nome || "sem titular"}"? Digite EXCLUIR para confirmar.`,
      requiredWord: "EXCLUIR",
      variant: "destructive",
    });
    if (!ok) return;
    const { error } = await fromTable("ponto_certificados_digitais").delete().eq("id", c.id);
    if (error) { toast.error(error.message); return; }
    qc.invalidateQueries({ queryKey: ["ponto-certificados"] });
    toast.success("Certificado removido");
  };

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <ShieldCheck className="w-5 h-5 text-primary" /> Certificado digital (ICP-Brasil)
          </h3>
          <p className="text-sm text-muted-foreground max-w-3xl">
            É o certificado que assina o AFD e o AEJ entregues à fiscalização (Portaria MTP
            671/2021). Aqui ficam só os dados de vigência para acompanhamento —
            <strong> a chave privada não é guardada no sistema</strong>. Certificado vencido
            paralisa a emissão assinada bem na hora da auditoria, por isso o vencimento é
            avisado com antecedência.
          </p>
        </div>
        <Button onClick={onNovo} className="shrink-0"><Plus className="w-4 h-4 mr-2" /> Novo certificado</Button>
      </div>

      {/* O que assina hoje */}
      <Card className={vigente ? "" : "border-amber-300"}>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Certificado em uso hoje</CardTitle>
        </CardHeader>
        <CardContent className="p-4 pt-0">
          {vigente ? (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
              <div>
                <p className="text-xs text-muted-foreground">Titular</p>
                <p className="font-medium">{vigente.titular_nome || "—"}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Tipo</p>
                <p className="font-medium">
                  {vigente.certificado_digital_tipo}
                  {vigente.icp_brasil ? " · ICP-Brasil" : " · fora da ICP-Brasil"}
                </p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Emissor</p>
                <p className="font-medium">{vigente.emissor || "—"}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Vence em</p>
                <p className="font-medium">
                  {vigente.valido_ate
                    ? format(new Date(`${vigente.valido_ate}T00:00:00`), "dd/MM/yyyy")
                    : "—"}
                </p>
              </div>
            </div>
          ) : (
            <div className="flex items-start gap-2 text-sm text-amber-900">
              <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
              <span>
                Nenhum certificado vigente cadastrado. Sem ele, o AFD e o AEJ não têm com que ser
                assinados — cadastre antes da próxima entrega à fiscalização.
              </span>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Titular</TableHead>
                <TableHead className="text-center">Tipo</TableHead>
                <TableHead>Emissor</TableHead>
                <TableHead className="text-center">Nº de série</TableHead>
                <TableHead className="text-center">Validade</TableHead>
                <TableHead className="text-center">Situação</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={7} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : certificados.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                  Nenhum certificado cadastrado.
                </TableCell></TableRow>
              ) : certificados.map((c: any) => {
                const s = situacao(c);
                return (
                  <TableRow key={c.id}>
                    <TableCell className="font-medium">{c.titular_nome || "—"}</TableCell>
                    <TableCell className="text-center">{c.certificado_digital_tipo}</TableCell>
                    <TableCell className="text-sm">{c.emissor || "—"}</TableCell>
                    <TableCell className="text-center font-mono text-xs">{c.numero_serie || "—"}</TableCell>
                    <TableCell className="text-center text-sm">
                      {c.valido_de ? format(new Date(`${c.valido_de}T00:00:00`), "dd/MM/yy") : "—"}
                      {" — "}
                      {c.valido_ate ? format(new Date(`${c.valido_ate}T00:00:00`), "dd/MM/yy") : "—"}
                    </TableCell>
                    <TableCell className="text-center">
                      <Badge variant={s.cor}>{s.label}</Badge>
                    </TableCell>
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
        <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editId ? "Editar certificado" : "Novo certificado digital"}</DialogTitle>
            <DialogDescription>
              Dados de acompanhamento da vigência. Não envie senha nem arquivo de chave privada.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo *</Label>
                <Select value={form.certificado_digital_tipo} onValueChange={(v: "A1" | "A3") => upd("certificado_digital_tipo", v)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="A1">A1 — arquivo, validade de 1 ano</SelectItem>
                    <SelectItem value="A3">A3 — cartão/token, validade de até 5 anos</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2 flex items-end gap-4">
                <div className="flex items-center gap-2">
                  <Switch id="cert-icp" checked={form.icp_brasil} onCheckedChange={(v) => upd("icp_brasil", v)} />
                  <Label htmlFor="cert-icp">ICP-Brasil</Label>
                </div>
                <div className="flex items-center gap-2">
                  <Switch id="cert-ativo" checked={form.ativo} onCheckedChange={(v) => upd("ativo", v)} />
                  <Label htmlFor="cert-ativo">Ativo</Label>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Titular *</Label>
                <Input value={form.titular_nome} onChange={(e) => upd("titular_nome", e.target.value)} placeholder="Razão social ou nome do titular" />
              </div>
              <div className="space-y-2">
                <Label>CPF/CNPJ do titular</Label>
                <Input value={form.titular_documento} onChange={(e) => upd("titular_documento", e.target.value)} placeholder="Somente números" />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Emissor (Autoridade Certificadora)</Label>
                <Input value={form.emissor} onChange={(e) => upd("emissor", e.target.value)} placeholder="Ex: AC Certisign RFB G5" />
              </div>
              <div className="space-y-2">
                <Label>Número de série</Label>
                <Input value={form.numero_serie} onChange={(e) => upd("numero_serie", e.target.value)} />
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Válido de</Label>
                <Input type="date" value={form.valido_de} onChange={(e) => upd("valido_de", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Vence em *</Label>
                <Input type="date" value={form.valido_ate} onChange={(e) => upd("valido_ate", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Avisar com (dias)</Label>
                <Input type="number" min={0} value={form.alerta_antecedencia_dias} onChange={(e) => upd("alerta_antecedencia_dias", e.target.value)} />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Impressão digital (fingerprint)</Label>
              <Input value={form.fingerprint} onChange={(e) => upd("fingerprint", e.target.value)} placeholder="Opcional — ajuda a identificar o certificado" />
            </div>

            <div className="space-y-2">
              <Label>Onde o arquivo está guardado</Label>
              <Input value={form.arquivo_url} onChange={(e) => upd("arquivo_url", e.target.value)} placeholder="Referência interna (opcional)" />
              <p className="text-xs text-muted-foreground">
                Só uma referência de onde o certificado fica guardado. Nunca coloque aqui a senha
                nem o arquivo com a chave privada.
              </p>
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

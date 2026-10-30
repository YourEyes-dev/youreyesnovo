import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Textarea } from "@/components/ui/textarea";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { FileText, Plus, Edit, Trash2, Users, Paperclip, AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";
import { PontoInstrumentoVinculosDialog } from "./PontoInstrumentoVinculosDialog";

/**
 * Convenções e acordos (Banco de horas configurável — Fatia 1).
 *
 * Cadastro de N instrumentos por conta (CCT, ACT e modelo de acordo individual),
 * ligados a uma ou mais empresas, com sindicatos, abrangência, categoria e anexo.
 * Mesma tabela que o sistema já consulta (ponto_acordos): o que vale hoje para
 * 12x36, registro alternativo e compensação de falta continua valendo.
 */

type Tipo = "individual" | "act" | "cct";

interface AcordoForm {
  tipo: Tipo;
  titulo: string;
  vigencia_inicio: string;
  vigencia_fim: string;
  documento_url: string;
  anexo_path: string;
  observacoes: string;
  ativo: boolean;
  permite_compensacao_falta: boolean;
  colaborador_cpf: string;
  sindicato_laboral: string;
  sindicato_patronal: string;
  abrangencia_uf: string;
  abrangencia_municipio: string;
  abrangencia_texto: string;
  categoria: "preponderante" | "diferenciada";
  empresa_representada: boolean;
  cbos_categoria: string;
  cargos_categoria: string;
  empresas: string[];
}

const defaultForm: AcordoForm = {
  tipo: "cct",
  titulo: "",
  vigencia_inicio: "",
  vigencia_fim: "",
  documento_url: "",
  anexo_path: "",
  observacoes: "",
  ativo: true,
  permite_compensacao_falta: false,
  colaborador_cpf: "",
  sindicato_laboral: "",
  sindicato_patronal: "",
  abrangencia_uf: "",
  abrangencia_municipio: "",
  abrangencia_texto: "",
  categoria: "preponderante",
  empresa_representada: true,
  cbos_categoria: "",
  cargos_categoria: "",
  empresas: [],
};

const lista = (s: string) => s.split(/[,;\n]/).map(x => x.trim()).filter(Boolean);
const dataBr = (d?: string | null) => (d ? String(d).slice(0, 10).split("-").reverse().join("/") : "");

export function PontoAcordosTab() {
  const { tenantId } = useTenant();
  const { empresaAtivaId, empresas: empresasCtx } = useEmpresaAtiva();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<AcordoForm>(defaultForm);
  const [saving, setSaving] = useState(false);
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [vinculosDe, setVinculosDe] = useState<any | null>(null);

  const empresas = (empresasCtx || []) as any[];
  const nomeEmpresa = (id: string) => {
    const e = empresas.find((x: any) => x.id === id);
    return e ? (e.nome_fantasia || e.razao_social || "Empresa") : "Empresa";
  };

  const { data: acordos = [], isLoading } = useQuery({
    queryKey: ["ponto-acordos", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("ponto_acordos").select("*").eq("tenant_id", tenantId)
        .order("created_at", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const { data: vinculosEmpresa = [] } = useQuery({
    queryKey: ["ponto-acordo-empresas", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("ponto_acordo_empresas").select("acordo_id, empresa_id")
        .eq("tenant_id", tenantId) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const empresasDo = (a: any): string[] => {
    const ids = new Set<string>(vinculosEmpresa.filter((v: any) => v.acordo_id === a.id).map((v: any) => v.empresa_id));
    if (a.empresa_id) ids.add(a.empresa_id);
    return Array.from(ids);
  };

  // Na lista, mostra os instrumentos da empresa ativa e os que valem para todas.
  const visiveis = acordos.filter((a: any) => {
    if (!empresaAtivaId) return true;
    const emps = empresasDo(a);
    return emps.length === 0 || emps.includes(empresaAtivaId);
  });

  const upd = <K extends keyof AcordoForm>(k: K, v: AcordoForm[K]) => setForm(p => ({ ...p, [k]: v }));

  const onNovo = () => {
    setForm({ ...defaultForm, empresas: empresaAtivaId ? [empresaAtivaId] : [] });
    setArquivo(null);
    setEditId(null);
    setOpen(true);
  };

  const onEditar = (a: any) => {
    setForm({
      tipo: a.tipo,
      titulo: a.titulo || "",
      vigencia_inicio: a.vigencia_inicio || "",
      vigencia_fim: a.vigencia_fim || "",
      documento_url: a.documento_url || "",
      anexo_path: a.anexo_path || "",
      observacoes: a.observacoes || "",
      ativo: a.ativo ?? true,
      permite_compensacao_falta: a.permite_compensacao_falta ?? false,
      colaborador_cpf: a.colaborador_cpf || "",
      sindicato_laboral: a.sindicato_laboral || "",
      sindicato_patronal: a.sindicato_patronal || "",
      abrangencia_uf: a.abrangencia_uf || "",
      abrangencia_municipio: a.abrangencia_municipio || "",
      abrangencia_texto: a.abrangencia_texto || "",
      categoria: a.categoria || "preponderante",
      empresa_representada: a.empresa_representada ?? true,
      cbos_categoria: (a.cbos_categoria || []).join(", "),
      cargos_categoria: (a.cargos_categoria || []).join(", "),
      empresas: empresasDo(a),
    });
    setArquivo(null);
    setEditId(a.id);
    setOpen(true);
  };

  const onSalvar = async () => {
    if (!form.titulo.trim() || !tenantId) { toast.error("Informe o nome do instrumento"); return; }
    if (form.vigencia_inicio && form.vigencia_fim && form.vigencia_fim < form.vigencia_inicio) {
      toast.error("O fim da vigência não pode ser antes do início"); return;
    }
    setSaving(true);
    try {
      const id = editId || crypto.randomUUID();
      let anexo = form.anexo_path || null;
      if (arquivo) {
        const nomeSeguro = arquivo.name.replace(/[^a-zA-Z0-9._-]/g, "_");
        const path = `${tenantId}/instrumentos/${id}/${Date.now()}-${nomeSeguro}`;
        const { error: upErr } = await supabase.storage.from("jornada-documentos").upload(path, arquivo);
        if (upErr) throw upErr;
        anexo = path;
      }
      const coletivo = form.tipo !== "individual";
      // Empresa principal fica em empresa_id só quando há exatamente uma; com
      // várias, a lista vai para ponto_acordo_empresas.
      const payload = {
        tenant_id: tenantId,
        tipo: form.tipo,
        titulo: form.titulo.trim(),
        vigencia_inicio: form.vigencia_inicio || null,
        vigencia_fim: form.vigencia_fim || null,
        documento_url: form.documento_url || null,
        anexo_path: anexo,
        observacoes: form.observacoes || null,
        ativo: form.ativo,
        permite_compensacao_falta: form.permite_compensacao_falta,
        colaborador_cpf: !coletivo && form.colaborador_cpf ? form.colaborador_cpf.replace(/\D/g, "") : null,
        sindicato_laboral: coletivo ? form.sindicato_laboral || null : null,
        sindicato_patronal: coletivo ? form.sindicato_patronal || null : null,
        abrangencia_uf: coletivo ? (form.abrangencia_uf || "").toUpperCase().slice(0, 2) || null : null,
        abrangencia_municipio: coletivo ? form.abrangencia_municipio || null : null,
        abrangencia_texto: coletivo ? form.abrangencia_texto || null : null,
        categoria: coletivo ? form.categoria : "preponderante",
        empresa_representada: coletivo ? form.empresa_representada : true,
        cbos_categoria: coletivo ? lista(form.cbos_categoria) : [],
        cargos_categoria: coletivo ? lista(form.cargos_categoria) : [],
        empresa_id: form.empresas.length === 1 ? form.empresas[0] : null,
      };
      if (editId) {
        const { error } = await fromTable("ponto_acordos").update(payload).eq("id", editId);
        if (error) throw error;
      } else {
        const { error } = await fromTable("ponto_acordos").insert({ id, ...payload });
        if (error) throw error;
      }
      // Empresas abrangidas (N:N): regrava a lista.
      const { error: delErr } = await fromTable("ponto_acordo_empresas").delete().eq("acordo_id", id);
      if (delErr) throw delErr;
      if (form.empresas.length > 1) {
        const { error: insErr } = await fromTable("ponto_acordo_empresas")
          .insert(form.empresas.map(e => ({ tenant_id: tenantId, acordo_id: id, empresa_id: e })));
        if (insErr) throw insErr;
      }
      toast.success(editId ? "Instrumento atualizado" : "Instrumento cadastrado");
      qc.invalidateQueries({ queryKey: ["ponto-acordos"] });
      qc.invalidateQueries({ queryKey: ["ponto-acordo-empresas"] });
      qc.invalidateQueries({ queryKey: ["ponto-acordos-list"] });
      setOpen(false);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  const onExcluir = async (a: any) => {
    const ok = await confirmDialog({
      title: "Excluir instrumento",
      description: `Confirma a exclusão de "${a.titulo}"? Os vínculos de colaboradores a ele também serão apagados. Prefira desativar se ele já foi usado. Digite EXCLUIR para confirmar.`,
      requiredWord: "EXCLUIR",
      variant: "destructive",
    });
    if (!ok) return;
    const { error } = await fromTable("ponto_acordos").delete().eq("id", a.id);
    if (error) { toast.error(error.message); return; }
    qc.invalidateQueries({ queryKey: ["ponto-acordos"] });
    toast.success("Instrumento removido");
  };

  const verAnexo = async (path: string) => {
    const { data, error } = await supabase.storage.from("jornada-documentos").createSignedUrl(path, 60);
    if (error || !data?.signedUrl) { toast.error("Não foi possível abrir o anexo"); return; }
    window.open(data.signedUrl, "_blank", "noopener");
  };

  const tipoLabel = (a: any) =>
    a.tipo === "act" ? "ACT" : a.tipo === "cct" ? "CCT" : a.colaborador_cpf ? "Acordo individual" : "Acordo individual (modelo)";
  const tipoColor = (t: string) => (t === "cct" ? "default" : t === "act" ? "secondary" : "outline");
  const coletivo = form.tipo !== "individual";

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <FileText className="w-5 h-5 text-primary" /> Convenções e acordos
          </h3>
          <p className="text-sm text-muted-foreground">
            Cadastre todas as convenções (CCT), acordos coletivos (ACT) e o modelo de acordo individual da conta.
            Uma empresa pode ter mais de uma: por exemplo, a da atividade principal e a de uma categoria diferenciada.
          </p>
        </div>
        <Button onClick={onNovo}><Plus className="w-4 h-4 mr-2" /> Novo instrumento</Button>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tipo</TableHead>
                <TableHead>Nome</TableHead>
                <TableHead>Categoria</TableHead>
                <TableHead>Empresas</TableHead>
                <TableHead className="text-center">Vigência</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={7} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : visiveis.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="text-center py-8 text-muted-foreground">Nenhum instrumento cadastrado.</TableCell></TableRow>
              ) : visiveis.map((a: any) => {
                const emps = empresasDo(a);
                const semRepr = a.tipo !== "individual" && a.categoria === "diferenciada" && a.empresa_representada === false;
                return (
                  <TableRow key={a.id}>
                    <TableCell><Badge variant={tipoColor(a.tipo) as any}>{tipoLabel(a)}</Badge></TableCell>
                    <TableCell className="font-medium">
                      <div>{a.titulo}</div>
                      {(a.sindicato_laboral || a.abrangencia_uf || a.abrangencia_texto) && (
                        <div className="text-xs text-muted-foreground">
                          {[a.sindicato_laboral, [a.abrangencia_municipio, a.abrangencia_uf].filter(Boolean).join("/"), a.abrangencia_texto]
                            .filter(Boolean).join(" · ")}
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="text-sm">
                      {a.tipo === "individual" ? "—" : a.categoria === "diferenciada" ? "Diferenciada" : "Atividade principal"}
                      {semRepr && (
                        <Badge variant="outline" className="ml-1 border-amber-500 text-amber-700" title="Súmula 374 do TST">
                          empresa não representada
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-xs">
                      {emps.length === 0 ? <span className="text-muted-foreground">Todas</span> : emps.map(nomeEmpresa).join(", ")}
                    </TableCell>
                    <TableCell className="text-center text-sm">
                      {a.vigencia_inicio || a.vigencia_fim
                        ? `${dataBr(a.vigencia_inicio) || "…"} — ${dataBr(a.vigencia_fim) || "sem fim"}`
                        : <span className="text-muted-foreground">—</span>}
                    </TableCell>
                    <TableCell className="text-center">
                      {a.ativo ? <Badge>Ativo</Badge> : <Badge variant="outline">Inativo</Badge>}
                    </TableCell>
                    <TableCell className="text-center">
                      <div className="flex items-center justify-center gap-1">
                        {a.anexo_path && (
                          <Button variant="ghost" size="icon" title="Ver documento" onClick={() => verAnexo(a.anexo_path)}>
                            <Paperclip className="w-4 h-4" />
                          </Button>
                        )}
                        {a.tipo !== "individual" && (
                          <Button variant="ghost" size="icon" title="Colaboradores vinculados" onClick={() => setVinculosDe(a)}>
                            <Users className="w-4 h-4" />
                          </Button>
                        )}
                        <Button variant="ghost" size="icon" title="Editar" onClick={() => onEditar(a)}><Edit className="w-4 h-4" /></Button>
                        <Button variant="ghost" size="icon" title="Excluir" className="text-destructive" onClick={() => onExcluir(a)}><Trash2 className="w-4 h-4" /></Button>
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <p className="text-xs text-muted-foreground">
        Qual convenção vale para cada colaborador: acordo coletivo da empresa (ACT) &gt; convenção vinculada ao colaborador
        &gt; convenção da atividade principal da empresa (CLT arts. 511, 581 e 620). Nesta etapa o cadastro já fica pronto,
        mas as regras de cálculo ainda não leem a convenção de cada colaborador <Badge variant="outline" className="ml-1">em breve no cálculo</Badge>
      </p>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editId ? "Editar instrumento" : "Novo instrumento"}</DialogTitle>
            <DialogDescription>Dados do documento como estão escritos nele.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo *</Label>
                <Select value={form.tipo} onValueChange={(v: Tipo) => upd("tipo", v)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="cct">Convenção coletiva (CCT)</SelectItem>
                    <SelectItem value="act">Acordo coletivo da empresa (ACT)</SelectItem>
                    <SelectItem value="individual">Acordo individual (modelo ou de um colaborador)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2 flex items-end gap-2">
                <Switch checked={form.ativo} onCheckedChange={v => upd("ativo", v)} id="instr-ativo" />
                <Label htmlFor="instr-ativo">Ativo</Label>
              </div>
            </div>

            <div className="space-y-2">
              <Label>Nome *</Label>
              <Input value={form.titulo} onChange={e => upd("titulo", e.target.value)} placeholder="Ex.: CCT Comércio 2026/2027" />
            </div>

            {coletivo && (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Sindicato dos trabalhadores</Label>
                    <Input value={form.sindicato_laboral} onChange={e => upd("sindicato_laboral", e.target.value)} />
                  </div>
                  <div className="space-y-2">
                    <Label>Sindicato das empresas</Label>
                    <Input value={form.sindicato_patronal} onChange={e => upd("sindicato_patronal", e.target.value)}
                      placeholder={form.tipo === "act" ? "No ACT, a própria empresa" : ""} />
                  </div>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <div className="space-y-2">
                    <Label>UF</Label>
                    <Input maxLength={2} value={form.abrangencia_uf} onChange={e => upd("abrangencia_uf", e.target.value.toUpperCase())} />
                  </div>
                  <div className="space-y-2 sm:col-span-2">
                    <Label>Município(s)</Label>
                    <Input value={form.abrangencia_municipio} onChange={e => upd("abrangencia_municipio", e.target.value)} />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Abrangência (como está no documento)</Label>
                  <Input value={form.abrangencia_texto} onChange={e => upd("abrangencia_texto", e.target.value)}
                    placeholder="Ex.: base territorial do sindicato" />
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Categoria</Label>
                    <Select value={form.categoria} onValueChange={(v: any) => upd("categoria", v)}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="preponderante">Atividade principal da empresa</SelectItem>
                        <SelectItem value="diferenciada">Categoria diferenciada (profissão com estatuto próprio)</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-2 flex items-end gap-2">
                    <Switch checked={form.empresa_representada} onCheckedChange={v => upd("empresa_representada", v)} id="instr-repr" />
                    <Label htmlFor="instr-repr">A empresa (ou o sindicato dela) participou da negociação</Label>
                  </div>
                </div>
                {form.categoria === "diferenciada" && !form.empresa_representada && (
                  <Alert className="border-amber-500/50 bg-amber-50 dark:bg-amber-950/20">
                    <AlertTriangle className="h-4 w-4 text-amber-600" />
                    <AlertDescription className="text-sm">
                      Convenção de categoria diferenciada sem a empresa na negociação não obriga a empresa: a Justiça
                      aplica a convenção da atividade principal. Você pode cadastrar e vincular mesmo assim, mas confira
                      com o jurídico. <span className="text-xs text-muted-foreground">(Súmula 374 do TST)</span>
                    </AlertDescription>
                  </Alert>
                )}
                <div className="space-y-2">
                  <Label>Empresas abrangidas</Label>
                  <div className="rounded-md border p-2 max-h-40 overflow-y-auto space-y-1">
                    {empresas.length === 0 && <p className="text-xs text-muted-foreground">Nenhuma empresa cadastrada.</p>}
                    {empresas.map((e: any) => (
                      <label key={e.id} className="flex items-center gap-2 text-sm cursor-pointer">
                        <Checkbox
                          checked={form.empresas.includes(e.id)}
                          onCheckedChange={(c) => upd("empresas", c ? [...form.empresas, e.id] : form.empresas.filter(x => x !== e.id))}
                        />
                        {e.nome_fantasia || e.razao_social}
                      </label>
                    ))}
                  </div>
                  <p className="text-[11px] text-muted-foreground">Nenhuma marcada = vale para todas as empresas da conta.</p>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>CBOs da categoria (para sugerir colaboradores)</Label>
                    <Input value={form.cbos_categoria} onChange={e => upd("cbos_categoria", e.target.value)} placeholder="Ex.: 3516, 2235" />
                  </div>
                  <div className="space-y-2">
                    <Label>Palavras do cargo (para sugerir colaboradores)</Label>
                    <Input value={form.cargos_categoria} onChange={e => upd("cargos_categoria", e.target.value)} placeholder="Ex.: técnico de segurança, enfermeiro" />
                  </div>
                </div>
              </>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Início da vigência</Label>
                <Input type="date" value={form.vigencia_inicio} onChange={e => upd("vigencia_inicio", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Fim da vigência</Label>
                <Input type="date" value={form.vigencia_fim} onChange={e => upd("vigencia_fim", e.target.value)} />
              </div>
            </div>

            <div className="space-y-2">
              <Label>Documento (PDF)</Label>
              <Input type="file" accept="application/pdf,image/*" onChange={e => setArquivo(e.target.files?.[0] || null)} />
              {form.anexo_path && !arquivo && (
                <Button variant="link" size="sm" className="px-0" onClick={() => verAnexo(form.anexo_path)}>Ver documento atual</Button>
              )}
              <p className="text-[11px] text-muted-foreground">Guardado em pasta privada da conta; abre só por link temporário.</p>
            </div>
            {form.documento_url && (
              <div className="space-y-2">
                <Label>Link antigo do documento</Label>
                <Input value={form.documento_url} onChange={e => upd("documento_url", e.target.value)} />
              </div>
            )}
            <div className="space-y-2">
              <Label>Observações</Label>
              <Textarea value={form.observacoes} onChange={e => upd("observacoes", e.target.value)} rows={2} />
            </div>

            <div className="rounded-md border p-3 space-y-3 bg-muted/30">
              <div className="flex items-center gap-2">
                <Switch id="permite_compensacao_falta" checked={form.permite_compensacao_falta}
                  onCheckedChange={v => upd("permite_compensacao_falta", v)} />
                <Label htmlFor="permite_compensacao_falta" className="cursor-pointer">Autoriza compensação de falta</Label>
              </div>
              <p className="text-[11px] text-muted-foreground -mt-1">
                Permite converter falta injustificada em débito do banco de horas (CLT art. 462). Marque só se o documento tiver essa cláusula.
              </p>
              {!coletivo && (
                <div className="space-y-2">
                  <Label>CPF do colaborador</Label>
                  <Input value={form.colaborador_cpf} onChange={e => upd("colaborador_cpf", e.target.value)}
                    placeholder="Vazio = modelo de acordo para todos os colaboradores" />
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

      {vinculosDe && (
        <PontoInstrumentoVinculosDialog
          instrumento={vinculosDe}
          open={!!vinculosDe}
          onOpenChange={(o) => { if (!o) setVinculosDe(null); }}
        />
      )}
    </div>
  );
}

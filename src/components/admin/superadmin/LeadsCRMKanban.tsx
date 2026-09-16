import { useState, useEffect } from "react";
import { useLeads, Lead, LeadStatus, enviarWhatsAppSuperAdmin } from "@/hooks/useSuperAdminPainel";
import { useParceirosOpcoes, useSugestaoParceiros, encaminharLeadAoParceiro, PARCEIRO_TIPO_LABEL } from "@/hooks/useParceiros";
import { useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Plus, MessageSquare, Mail, Phone, Trash2, Edit, Building, DollarSign } from "lucide-react";
import { confirm } from "@/components/ui/confirm-dialog";
import { toast } from "sonner";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";

const STATUS_LABELS: Record<LeadStatus, { label: string; color: string }> = {
  novo: { label: "Novo", color: "bg-slate-500" },
  contatado: { label: "Contatado", color: "bg-blue-500" },
  qualificado: { label: "Qualificado", color: "bg-cyan-500" },
  proposta: { label: "Proposta", color: "bg-amber-500" },
  negociacao: { label: "Negociação", color: "bg-orange-500" },
  convertido: { label: "Convertido", color: "bg-emerald-500" },
  perdido: { label: "Perdido", color: "bg-rose-500" },
};

const COLUNAS: LeadStatus[] = ["novo", "contatado", "qualificado", "proposta", "negociacao", "convertido", "perdido"];

export function LeadsCRMKanban() {
  const { data: leads = [], isLoading, createLead, updateLead, deleteLead } = useLeads();
  const [editing, setEditing] = useState<Lead | null>(null);
  const [creating, setCreating] = useState(false);
  const [whatsappTo, setWhatsappTo] = useState<Lead | null>(null);

  const onDrop = (leadId: string, status: LeadStatus) => {
    updateLead.mutate({ id: leadId, status });
  };

  if (isLoading) return <div className="p-8 text-center text-muted-foreground">Carregando leads...</div>;

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <div>
          <CardTitle>Pipeline Comercial (Kanban)</CardTitle>
          <p className="text-sm text-muted-foreground mt-1">
            {leads.length} leads · Arraste para mover entre etapas
          </p>
        </div>
        <Button onClick={() => setCreating(true)}>
          <Plus className="w-4 h-4 mr-2" /> Novo Lead
        </Button>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-7 gap-3 overflow-x-auto">
          {COLUNAS.map((status) => {
            const items = leads.filter((l) => l.status === status);
            const total = items.reduce((acc, l) => acc + (Number(l.valor_estimado) || 0), 0);
            return (
              <div
                key={status}
                onDragOver={(e) => e.preventDefault()}
                onDrop={(e) => {
                  const id = e.dataTransfer.getData("text/plain");
                  if (id) onDrop(id, status);
                }}
                className="bg-muted/40 rounded-lg p-2 min-h-[400px]"
              >
                <div className="flex items-center justify-between mb-2 px-1">
                  <div className="flex items-center gap-2">
                    <span className={`w-2 h-2 rounded-full ${STATUS_LABELS[status].color}`} />
                    <span className="text-xs font-semibold uppercase">{STATUS_LABELS[status].label}</span>
                  </div>
                  <Badge variant="outline" className="text-[10px]">{items.length}</Badge>
                </div>
                {total > 0 && (
                  <div className="text-[10px] text-muted-foreground mb-2 px-1">
                    R$ {total.toLocaleString("pt-BR")}
                  </div>
                )}
                <div className="space-y-2">
                  {items.map((lead) => (
                    <div
                      key={lead.id}
                      draggable
                      onDragStart={(e) => e.dataTransfer.setData("text/plain", lead.id)}
                      className="bg-background border rounded-md p-2 cursor-move hover:shadow-md transition-shadow group"
                    >
                      <div className="font-medium text-sm">{lead.nome}</div>
                      {lead.empresa && (
                        <div className="text-xs text-muted-foreground flex items-center gap-1 mt-1">
                          <Building className="w-3 h-3" /> {lead.empresa}
                        </div>
                      )}
                      {lead.valor_estimado && (
                        <div className="text-xs text-emerald-600 flex items-center gap-1 mt-1">
                          <DollarSign className="w-3 h-3" /> R$ {Number(lead.valor_estimado).toLocaleString("pt-BR")}
                        </div>
                      )}
                      <div className="flex items-center gap-1 mt-2 opacity-0 group-hover:opacity-100 transition-opacity">
                        {lead.telefone && (
                          <Button size="icon" variant="ghost" className="h-6 w-6"
                            onClick={() => setWhatsappTo(lead)} title="WhatsApp">
                            <MessageSquare className="w-3 h-3" />
                          </Button>
                        )}
                        {lead.email && (
                          <Button size="icon" variant="ghost" className="h-6 w-6" asChild title="E-mail">
                            <a href={`mailto:${lead.email}`}><Mail className="w-3 h-3" /></a>
                          </Button>
                        )}
                        <Button size="icon" variant="ghost" className="h-6 w-6" onClick={() => setEditing(lead)} title="Editar">
                          <Edit className="w-3 h-3" />
                        </Button>
                        <Button size="icon" variant="ghost" className="h-6 w-6 text-destructive"
                          onClick={async () => {
                            const ok = await confirm({
                              title: "Excluir lead",
                              description: `Tem certeza que deseja excluir o lead "${lead.nome}"? Esta ação não pode ser desfeita.`,
                              variant: "destructive",
                              confirmLabel: "Excluir",
                            });
                            if (ok) deleteLead.mutate(lead.id);
                          }} title="Excluir">
                          <Trash2 className="w-3 h-3" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </CardContent>

      <LeadFormDialog
        open={creating || !!editing}
        lead={editing}
        onClose={() => { setCreating(false); setEditing(null); }}
        onSubmit={async (data) => {
          if (editing) await updateLead.mutateAsync({ id: editing.id, ...data });
          else await createLead.mutateAsync(data);
          setCreating(false); setEditing(null);
        }}
      />

      <WhatsAppDialog
        lead={whatsappTo}
        onClose={() => setWhatsappTo(null)}
      />
    </Card>
  );
}

function LeadFormDialog({ open, lead, onClose, onSubmit }: {
  open: boolean; lead: Lead | null; onClose: () => void; onSubmit: (d: Partial<Lead>) => Promise<void>;
}) {
  const [form, setForm] = useState<Partial<Lead>>({});
  const isEdit = !!lead;
  const { data: parceiros = [] } = useParceirosOpcoes();
  const SEM_PARCEIRO = "__nenhum__";
  const [mostrarSugestao, setMostrarSugestao] = useState(false);
  const { data: sugestoes = [], isLoading: carregandoSugestao } = useSugestaoParceiros(mostrarSugestao && lead ? lead.id : null);
  const qc = useQueryClient();
  const encaminhar = async (parceiroId: string) => {
    if (!lead) return;
    try {
      await encaminharLeadAoParceiro(lead.id, parceiroId);
      setForm((f) => ({ ...f, parceiro_id: parceiroId, atribuicao: "casa" }));
      qc.invalidateQueries({ queryKey: ["superadmin", "leads"] });
      toast.success("Lead encaminhado ao parceiro");
    } catch (e) { toast.error(e instanceof Error ? e.message : "Não foi possível encaminhar"); }
  };

  // reset on open / quando o lead muda
  useEffect(() => {
    if (open) setForm(lead ? { ...lead } : { status: "novo", origem: "prospect_manual" });
  }, [open, lead]);

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Editar Lead" : "Novo Lead"}</DialogTitle>
          <DialogDescription>Preencha as informações do lead</DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="col-span-2"><Label>Nome*</Label>
            <Input value={form.nome || ""} onChange={(e) => setForm({ ...form, nome: e.target.value })} /></div>
          <div><Label>Empresa</Label>
            <Input value={form.empresa || ""} onChange={(e) => setForm({ ...form, empresa: e.target.value })} /></div>
          <div><Label>Cargo</Label>
            <Input value={form.cargo || ""} onChange={(e) => setForm({ ...form, cargo: e.target.value })} /></div>
          <div><Label>E-mail</Label>
            <Input type="email" value={form.email || ""} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
          <div><Label>Telefone</Label>
            <Input value={form.telefone || ""} onChange={(e) => setForm({ ...form, telefone: e.target.value })} placeholder="(11) 99999-9999" /></div>
          <div><Label>Cidade</Label>
            <Input value={form.cidade || ""} onChange={(e) => setForm({ ...form, cidade: e.target.value })} placeholder="para sugerir parceiro por região" /></div>
          <div><Label>UF</Label>
            <Input maxLength={2} className="uppercase" value={form.uf || ""} onChange={(e) => setForm({ ...form, uf: e.target.value.toUpperCase() })} /></div>
          <div><Label>Origem</Label>
            <Select value={form.origem} onValueChange={(v) => setForm({ ...form, origem: v as any })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="landing_page">Landing Page</SelectItem>
                <SelectItem value="meta_ads">Meta Ads (tráfego pago)</SelectItem>
                <SelectItem value="indicacao">Indicação</SelectItem>
                <SelectItem value="prospect_manual">Prospect Manual</SelectItem>
                <SelectItem value="linkedin">LinkedIn</SelectItem>
                <SelectItem value="whatsapp">WhatsApp</SelectItem>
                <SelectItem value="evento">Evento</SelectItem>
                <SelectItem value="outro">Outro</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div><Label>Status</Label>
            <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v as any })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {COLUNAS.map(s => <SelectItem key={s} value={s}>{STATUS_LABELS[s].label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="col-span-2"><Label>Parceiro (quem indicou ou vai atender)</Label>
            <Select value={form.parceiro_id || SEM_PARCEIRO}
              onValueChange={(v) => setForm({ ...form, parceiro_id: v === SEM_PARCEIRO ? null : v, atribuicao: v === SEM_PARCEIRO ? null : (form.atribuicao || "casa"), ...(v !== SEM_PARCEIRO && form.origem === "prospect_manual" ? { origem: "indicacao" as const } : {}) })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value={SEM_PARCEIRO}>— sem parceiro —</SelectItem>
                {parceiros.filter(p => p.status === "ativo" || p.id === form.parceiro_id).map(p => (
                  <SelectItem key={p.id} value={p.id}>{p.nome} · {PARCEIRO_TIPO_LABEL[p.tipo_parceiro]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {form.parceiro_id && <p className="text-xs text-muted-foreground mt-1">Atribuição: {form.atribuicao === "link" ? "chegou pelo link do parceiro" : "encaminhado pela casa"}</p>}
            {isEdit && !form.parceiro_id && (
              <div className="mt-2">
                {!mostrarSugestao ? (
                  <Button type="button" size="sm" variant="outline" onClick={() => setMostrarSugestao(true)} data-testid="lead-sugerir-parceiro">Sugerir parceiro por localidade</Button>
                ) : carregandoSugestao ? <p className="text-xs text-muted-foreground">Procurando parceiros perto de {form.cidade || form.uf || "…"}</p> : sugestoes.length === 0 ? (
                  <p className="text-xs text-muted-foreground">Nenhum parceiro ativo para sugerir. Preencha cidade/UF do lead e cadastre parceiros na região.</p>
                ) : (
                  <ul className="space-y-1">
                    {sugestoes.map((s) => (
                      <li key={s.id} className="flex items-center justify-between rounded-md border px-2 py-1.5 text-sm">
                        <span><span className="font-medium">{s.nome}</span> <span className="text-xs text-muted-foreground">· {PARCEIRO_TIPO_LABEL[s.tipo_parceiro]} · {[s.cidade, s.uf].filter(Boolean).join("/") || "sem região"} · {s.motivo}{s.nivel ? ` · ${s.nivel}` : ""} · {s.clientes} cliente(s)</span></span>
                        <Button type="button" size="sm" variant="secondary" onClick={() => encaminhar(s.id)}>Encaminhar</Button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </div>
          <div><Label>Valor Estimado (R$)</Label>
            <Input type="number" step="0.01" value={form.valor_estimado ?? ""}
              onChange={(e) => setForm({ ...form, valor_estimado: e.target.value ? Number(e.target.value) : null })} /></div>
          <div><Label>Próxima Ação (data)</Label>
            <Input type="date" value={form.proxima_acao_data || ""}
              onChange={(e) => setForm({ ...form, proxima_acao_data: e.target.value || null })} /></div>
          <div className="col-span-2"><Label>Próxima Ação</Label>
            <Input value={form.proxima_acao_descricao || ""}
              onChange={(e) => setForm({ ...form, proxima_acao_descricao: e.target.value })} /></div>
          <div className="col-span-2"><Label>Notas</Label>
            <Textarea rows={3} value={form.notas || ""} onChange={(e) => setForm({ ...form, notas: e.target.value })} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button onClick={() => onSubmit(form)} disabled={!form.nome}>Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function WhatsAppDialog({ lead, onClose }: { lead: Lead | null; onClose: () => void }) {
  const [mensagem, setMensagem] = useState("");
  const [enviando, setEnviando] = useState(false);

  const enviar = async () => {
    if (!lead?.telefone || !mensagem) return;
    setEnviando(true);
    try {
      await enviarWhatsAppSuperAdmin({ telefone: lead.telefone, mensagem, lead_id: lead.id });
      toast.success("Mensagem enviada!");
      setMensagem(""); onClose();
    } catch (e: any) {
      toast.error(e.message || "Erro ao enviar");
    } finally {
      setEnviando(false);
    }
  };

  return (
    <Dialog open={!!lead} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <MessageSquare className="w-5 h-5 text-emerald-500" />
            Enviar WhatsApp · {lead?.nome}
          </DialogTitle>
          <DialogDescription>{lead?.telefone}</DialogDescription>
        </DialogHeader>
        <Textarea
          rows={6}
          value={mensagem}
          onChange={(e) => setMensagem(e.target.value)}
          placeholder="Olá! Tudo bem? Sou da YourEyes..."
        />
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button onClick={enviar} disabled={!mensagem || enviando}>
            {enviando ? "Enviando..." : "Enviar"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

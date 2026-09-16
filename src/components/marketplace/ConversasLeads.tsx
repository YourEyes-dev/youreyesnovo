import { useEffect, useRef, useState } from "react";
import { MessageSquare, Unlock, CheckCircle2, XCircle, Star, Phone, Mail, Globe, Target, Sparkles, Paperclip, Loader2, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useMarketYEAcoes, useMarketYELeads, useMarketYEMensagens, LEAD_STATUS_LABEL, type MarketYELead } from "@/hooks/useMarketYE";
import { marketyeIA } from "@/hooks/useMarketYEPortal";
import { AvaliacaoCriteriosModal, CRITERIOS_ESPECIALISTA } from "./AvaliacaoCriteriosModal";
import { CriarAcaoAlertaModal } from "@/components/shared/CriarAcaoAlertaModal";

const statusCor: Record<string, string> = {
  novo: "bg-blue-50 text-blue-700", respondido: "bg-indigo-50 text-indigo-700", qualificado: "bg-emerald-50 text-emerald-700",
  ganho: "bg-emerald-100 text-emerald-800", perdido: "bg-slate-100 text-slate-600", encerrado: "bg-slate-100 text-slate-600",
};

export function ConversasLeads() {
  const { data: leads = [], isLoading } = useMarketYELeads();
  const [selecionado, setSelecionado] = useState<MarketYELead | null>(null);
  useEffect(() => { if (selecionado) { const atual = leads.find((l) => l.id === selecionado.id); if (atual && atual !== selecionado) setSelecionado(atual); } }, [leads, selecionado]);

  if (isLoading) return <div className="text-center py-12 text-muted-foreground text-sm">Carregando conversas...</div>;
  if (leads.length === 0) {
    return (
      <div className="text-center py-16">
        <MessageSquare className="h-12 w-12 mx-auto text-muted-foreground/30 mb-3" />
        <p className="text-muted-foreground">Nenhuma conversa ainda.</p>
        <p className="text-xs text-muted-foreground mt-1">Clique em "Falar com o especialista" num anúncio para abrir a primeira.</p>
      </div>
    );
  }
  return (
    <div className="grid md:grid-cols-[320px_1fr] gap-4">
      <div className="space-y-2 max-h-[70vh] overflow-y-auto pr-1" data-testid="marketye-conversas">
        {leads.map((l) => (
          <button key={l.id} onClick={() => setSelecionado(l)} className={`w-full text-left rounded-xl border p-3 transition ${selecionado?.id === l.id ? "border-indigo-300 bg-indigo-50/50" : "border-border hover:bg-muted/40"}`}>
            <div className="flex items-center justify-between gap-2">
              <span className="font-medium text-sm truncate">{l.profissional?.nome_completo ?? "Especialista"}</span>
              <Badge variant="secondary" className={`text-[10px] ${statusCor[l.status] ?? ""}`}>{LEAD_STATUS_LABEL[l.status] ?? l.status}</Badge>
            </div>
            <p className="text-xs text-muted-foreground truncate">{l.servico?.nome ?? "Contato direto"}</p>
            <p className="text-[10px] text-muted-foreground mt-1">{l.ultima_mensagem_em ? format(new Date(l.ultima_mensagem_em), "dd/MM HH:mm", { locale: ptBR }) : ""}</p>
          </button>
        ))}
      </div>
      <div className="rounded-2xl border border-border p-4 min-h-[300px]">
        {selecionado ? <ConversaThread lead={selecionado} papel="cliente" /> : <p className="text-sm text-muted-foreground">Selecione uma conversa.</p>}
      </div>
    </div>
  );
}

interface ThreadProps {
  lead: MarketYELead | { id: string; status: string; contato_liberado: boolean; ganho_em?: string | null; profissional?: MarketYELead["profissional"]; servico?: MarketYELead["servico"]; profissional_id?: string; obrigacao_legal?: string | null; origem_modulo?: string | null };
  papel: "cliente";
}

export function ConversaThread({ lead }: ThreadProps) {
  const { data: mensagens = [] } = useMarketYEMensagens(lead.id);
  const { enviarMensagem, liberarContato, mudarStatus, avaliar, contato, vincularDocumento } = useMarketYEAcoes();
  const { tenantId, user, profile } = useAuth();
  const [texto, setTexto] = useState("");
  const [contatoInfo, setContatoInfo] = useState<{ liberado: boolean; nome?: string; email?: string; telefone?: string; site_url?: string } | null>(null);
  const [avaliando, setAvaliando] = useState(false);
  const [acaoAberta, setAcaoAberta] = useState(false);
  const [resumoIA, setResumoIA] = useState<string | null>(null);
  const [carregandoIA, setCarregandoIA] = useState(false);
  const [anexando, setAnexando] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const fim = useRef<HTMLDivElement>(null);
  useEffect(() => { fim.current?.scrollIntoView({ behavior: "smooth" }); }, [mensagens.length]);
  useEffect(() => { setContatoInfo(null); setResumoIA(null); }, [lead.id]);

  const encerrado = lead.status === "perdido" || lead.status === "encerrado";
  const podeAvaliar = lead.status === "ganho";

  const verContato = async () => {
    try { setContatoInfo(await contato(lead.id)); } catch (e) { toast.error(e instanceof Error ? e.message : "Não foi possível obter o contato"); }
  };
  const analisarIA = async () => {
    setCarregandoIA(true);
    try {
      const r = await marketyeIA<{ resumo: string }>("resumo_avaliacoes", { conversa: mensagens.map((m) => `${m.autor_tipo}: ${m.texto}`).join("\n"), contexto: "Resuma a conversa entre a empresa e o especialista, aponte o que falta combinar (escopo, prazo, valor) e sugira a próxima mensagem da empresa." });
      setResumoIA(r.resumo);
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); } finally { setCarregandoIA(false); }
  };
  const anexar = async (file: File) => {
    if (!tenantId) return;
    setAnexando(true);
    try {
      const safe = file.name.replace(/[^\w.-]+/g, "_");
      const path = `${tenantId}/marketye/${lead.id}/${Date.now()}_${safe}`;
      const { error: upErr } = await supabase.storage.from("documentos").upload(path, file);
      if (upErr) throw upErr;
      const { data: doc, error: docErr } = await supabase.from("documentos").insert({
        tenant_id: tenantId, colaborador_nome: lead.profissional?.nome_completo ?? "Especialista MarketYE", nome_arquivo: safe, nome_original: file.name,
        tipo: "proposta_especialista", tamanho: file.size, mime_type: file.type || "application/octet-stream", storage_path: path,
        observacoes: `MarketYE · conversa ${lead.id}${lead.servico?.nome ? ` · ${lead.servico.nome}` : ""}`, criado_por: user?.id ?? null, criado_por_nome: profile?.nome_completo ?? null,
      }).select("id").single();
      if (docErr) throw docErr;
      await vincularDocumento.mutateAsync({ lead_id: lead.id, documento_id: doc.id, tipo: "proposta" });
    } catch (e) { toast.error(e instanceof Error ? e.message : "Não foi possível arquivar o documento"); } finally { setAnexando(false); if (fileRef.current) fileRef.current.value = ""; }
  };

  return (
    <div className="flex flex-col h-full gap-3">
      <div className="flex items-start justify-between gap-2 flex-wrap">
        <div>
          <p className="font-semibold">{lead.profissional?.nome_completo ?? "Especialista"}</p>
          <p className="text-xs text-muted-foreground">{lead.servico?.nome ?? "Contato direto"} · {LEAD_STATUS_LABEL[lead.status] ?? lead.status}</p>
        </div>
        <div className="flex gap-1.5 flex-wrap">
          {!lead.contato_liberado && !encerrado && (
            <Button size="sm" variant="outline" onClick={() => liberarContato.mutate(lead.id)} disabled={liberarContato.isPending}><Unlock className="h-3.5 w-3.5 mr-1" />Liberar contato</Button>
          )}
          {lead.contato_liberado && <Button size="sm" variant="outline" onClick={verContato}><Phone className="h-3.5 w-3.5 mr-1" />Ver contato</Button>}
          {!encerrado && lead.status !== "ganho" && (
            <>
              <Button size="sm" variant="outline" className="text-emerald-700" onClick={() => mudarStatus.mutate({ lead_id: lead.id, status: "ganho" })}><CheckCircle2 className="h-3.5 w-3.5 mr-1" />Serviço combinado</Button>
              <Button size="sm" variant="ghost" className="text-muted-foreground" onClick={() => mudarStatus.mutate({ lead_id: lead.id, status: "perdido" })}><XCircle className="h-3.5 w-3.5 mr-1" />Encerrar</Button>
            </>
          )}
          {podeAvaliar && <Button size="sm" className="bg-amber-500 hover:bg-amber-600 text-white" onClick={() => setAvaliando(true)}><Star className="h-3.5 w-3.5 mr-1" />Avaliar</Button>}
        </div>
      </div>

      {contatoInfo && contatoInfo.liberado && (
        <div className="rounded-xl bg-emerald-50 border border-emerald-200 p-3 text-sm space-y-1">
          <p className="font-medium text-emerald-800">Contato de {contatoInfo.nome}</p>
          {contatoInfo.email && <p className="flex items-center gap-1.5"><Mail className="h-3.5 w-3.5" /><a className="underline" href={`mailto:${contatoInfo.email}`}>{contatoInfo.email}</a></p>}
          {contatoInfo.telefone && <p className="flex items-center gap-1.5"><Phone className="h-3.5 w-3.5" />{contatoInfo.telefone}</p>}
          {contatoInfo.site_url && <p className="flex items-center gap-1.5"><Globe className="h-3.5 w-3.5" /><a className="underline" href={contatoInfo.site_url} target="_blank" rel="noreferrer">{contatoInfo.site_url}</a></p>}
        </div>
      )}

      <div className="flex-1 overflow-y-auto space-y-2 max-h-[40vh] pr-1">
        {mensagens.map((m) => (
          <div key={m.id} className={`text-sm rounded-xl px-3 py-2 max-w-[85%] ${m.autor_tipo === "cliente" ? "ml-auto bg-indigo-50 text-indigo-900" : m.autor_tipo === "especialista" ? "bg-muted" : "mx-auto bg-amber-50 text-amber-800 text-xs text-center"}`}>
            <p className="whitespace-pre-wrap">{m.texto}</p>
            <p className="text-[10px] opacity-60 mt-0.5">{format(new Date(m.created_at), "dd/MM HH:mm", { locale: ptBR })}{m.mascarada ? " · contato oculto até a liberação" : ""}</p>
          </div>
        ))}
        <div ref={fim} />
      </div>

      {resumoIA && <div className="rounded-xl bg-violet-50 border border-violet-200 p-3 text-sm whitespace-pre-wrap"><p className="text-[10px] uppercase tracking-wide text-violet-700 font-semibold mb-1">Análise com IA</p>{resumoIA}</div>}

      {!encerrado && (
        <div className="space-y-2">
          <Textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={2} placeholder="Escreva sua mensagem..." />
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <div className="flex gap-1.5 flex-wrap">
              <Button size="sm" variant="ghost" onClick={analisarIA} disabled={carregandoIA || mensagens.length === 0}>{carregandoIA ? <Loader2 className="h-3.5 w-3.5 mr-1 animate-spin" /> : <Sparkles className="h-3.5 w-3.5 mr-1" />}Analisar com IA</Button>
              <Button size="sm" variant="ghost" onClick={() => setAcaoAberta(true)}><Target className="h-3.5 w-3.5 mr-1" />Criar ação no Plano de Ação</Button>
              <Button size="sm" variant="ghost" onClick={() => fileRef.current?.click()} disabled={anexando}>{anexando ? <Loader2 className="h-3.5 w-3.5 mr-1 animate-spin" /> : <Paperclip className="h-3.5 w-3.5 mr-1" />}Arquivar proposta/contrato</Button>
              <input ref={fileRef} type="file" className="hidden" accept=".pdf,.doc,.docx,.png,.jpg,.jpeg" onChange={(e) => { const f = e.target.files?.[0]; if (f) void anexar(f); }} />
            </div>
            <Button size="sm" disabled={enviarMensagem.isPending || texto.trim().length === 0} onClick={() => { enviarMensagem.mutate({ lead_id: lead.id, texto: texto.trim() }); setTexto(""); }}>Enviar</Button>
          </div>
          {!lead.contato_liberado && <p className="text-[11px] text-muted-foreground flex items-center gap-1"><ShieldAlert className="h-3 w-3" />Telefones e e-mails ficam ocultos até você liberar o contato.</p>}
        </div>
      )}

      <AvaliacaoCriteriosModal
        open={avaliando} onClose={() => setAvaliando(false)} titulo="Avaliar o especialista" criterios={CRITERIOS_ESPECIALISTA}
        subtitulo={`${lead.profissional?.nome_completo ?? ""}${lead.servico?.nome ? ` · ${lead.servico.nome}` : ""}`}
        isLoading={avaliar.isPending}
        onEnviar={(notas, comentario) => avaliar.mutate({ ref_tipo: "lead", ref_id: lead.id, notas, comentario }, { onSuccess: () => setAvaliando(false) })}
      />
      <CriarAcaoAlertaModal
        open={acaoAberta} onOpenChange={setAcaoAberta} origemModulo="marketplace" origemId={lead.id}
        alertaTitulo={`Contratação de especialista: ${lead.servico?.nome ?? lead.profissional?.nome_completo ?? "MarketYE"}`}
        alertaDescricao={`Conversa no MarketYE com ${lead.profissional?.nome_completo ?? "especialista"}${lead.obrigacao_legal ? ` para atender ${lead.obrigacao_legal}` : ""}. Última situação: ${LEAD_STATUS_LABEL[lead.status] ?? lead.status}.`}
        contextoExtra={mensagens.slice(-6).map((m) => `${m.autor_tipo}: ${m.texto}`).join("\n")}
      />
    </div>
  );
}

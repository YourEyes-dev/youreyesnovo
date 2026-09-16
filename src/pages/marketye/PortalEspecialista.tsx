import { useEffect, useRef, useState } from "react";
import { Link, Navigate } from "react-router-dom";
import { Loader2, Sparkles, Star, MessageSquare, FileText, Activity, ShieldCheck, Gavel, Ticket, Download, Trash2, Send, Eye, PauseCircle, PlayCircle, Pencil, CheckCircle2, AlertTriangle, Clock, Phone, Mail, Building2, Circle, ArrowRight, Wand2, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Checkbox } from "@/components/ui/checkbox";
import { MarketYELayout } from "@/components/marketye/MarketYELayout";
import { useMarketYEPortal, usePortalMensagens, marketyeIA, TERMO_LABEL, type PortalAnuncio, type PortalLead, type PortalDados } from "@/hooks/useMarketYEPortal";
import { useMarketYECategorias, NIVEL_LABEL, LEAD_STATUS_LABEL } from "@/hooks/useMarketYE";
import { AvaliacaoCriteriosModal, CRITERIOS_EMPRESA } from "@/components/marketplace/AvaliacaoCriteriosModal";

type Aba = "caminho" | "servicos" | "conversas" | "reputacao" | "perfil" | "cupons" | "conta";

const statusPerfil: Record<string, { label: string; cor: string; texto: string }> = {
  pendente: { label: "Em análise", cor: "bg-amber-500/20 text-amber-200", texto: "Nossa equipe está conferindo seus dados. Enquanto isso, prepare seu perfil e seus serviços: eles entram na vitrine assim que aprovarmos." },
  ativo: { label: "Na vitrine", cor: "bg-emerald-500/20 text-emerald-200", texto: "Seu perfil está visível para as empresas." },
  suspenso: { label: "Pausado pela equipe", cor: "bg-red-500/20 text-red-200", texto: "Seu perfil está fora da vitrine por enquanto. Se discordar, peça revisão em Conta e privacidade." },
  bloqueado: { label: "Fora da vitrine", cor: "bg-slate-500/20 text-slate-200", texto: "Seu cadastro não foi aprovado ou foi encerrado. Veja o motivo abaixo e, se discordar, peça revisão." },
};
const saudeCor: Record<string, string> = { verde: "bg-emerald-500", amarelo: "bg-amber-400", vermelho: "bg-red-500", cinza: "bg-slate-400" };
const saudeTexto: Record<string, string> = { verde: "atendimento em dia", amarelo: "atendimento pede atenção", vermelho: "atendimento precisa melhorar", cinza: "ainda sem histórico" };
const inputCls = "bg-black/20 border-white/15 text-white";

export default function PortalEspecialista() {
  const { portal, aceitarTermos, exportar, excluir } = useMarketYEPortal();
  const d = portal.data;
  const [aba, setAba] = useState<Aba>("caminho");
  const [confirmExcluir, setConfirmExcluir] = useState("");
  const [excluirAberto, setExcluirAberto] = useState(false);
  const [novoServico, setNovoServico] = useState(false);

  if (portal.isError) {
    // Nunca deixar a pessoa olhando um círculo girando: o cadastro dela está
    // guardado; o que falhou foi a leitura do portal.
    return (
      <MarketYELayout titulo="Meu portal">
        <div className="max-w-lg mx-auto text-center py-16 space-y-4" data-testid="portal-erro">
          <AlertTriangle className="w-10 h-10 mx-auto text-amber-400" />
          <h1 className="text-xl font-bold text-white">Não conseguimos abrir o seu portal agora</h1>
          <p className="text-sm text-slate-300">Seu cadastro está guardado. Tente de novo em instantes; se continuar, fale com a gente em contato@youreyes.com.br.</p>
          <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" onClick={() => portal.refetch()}>Tentar de novo</Button>
        </div>
      </MarketYELayout>
    );
  }
  if (portal.isSuccess && d === null) return <Navigate to="/marketye/cadastro" replace />;
  if (!d) {
    return <MarketYELayout titulo="Meu portal"><div className="py-20 flex justify-center"><Loader2 className="w-8 h-8 animate-spin text-[#60ABEF]" /></div></MarketYELayout>;
  }
  const st = statusPerfil[d.perfil.status] ?? statusPerfil.pendente;
  const rep = d.reputacao;

  return (
    <MarketYELayout titulo="Meu portal">
      <div className="space-y-6" data-testid="portal-especialista">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div className="flex items-center gap-4">
            {d.perfil.foto_url ? <img src={d.perfil.foto_url} alt="" className="w-16 h-16 rounded-2xl object-cover" /> : <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-indigo-500 to-violet-600 flex items-center justify-center text-2xl font-bold">{d.perfil.nome_completo.charAt(0)}</div>}
            <div>
              <h1 className="text-2xl font-bold text-white" data-testid="portal-especialista-nome">Olá, {d.perfil.nome_completo.split(" ")[0]}</h1>
              <div className="flex items-center gap-2 flex-wrap mt-1">
                <Badge className={st.cor}>{st.label}</Badge>
                {d.perfil.selo_verificado && <Badge className="bg-emerald-500/20 text-emerald-200"><ShieldCheck className="w-3 h-3 mr-1" />dados verificados</Badge>}
                <Badge className="bg-white/10 text-slate-200">Nível {NIVEL_LABEL[d.nivel.atual] ?? d.nivel.atual}</Badge>
                {rep && <span className="inline-flex items-center gap-1 text-xs text-slate-300"><span className={`w-2 h-2 rounded-full ${saudeCor[rep.saude_cor]}`} />{saudeTexto[rep.saude_cor] ?? ""}</span>}
              </div>
            </div>
          </div>
          <div className="text-right text-xs text-slate-400">
            <p>Perfil {d.completude}% completo</p>
            <div className="w-40 h-2 bg-white/10 rounded-full mt-1 overflow-hidden"><div className="h-full bg-[#60ABEF]" style={{ width: `${d.completude}%` }} /></div>
          </div>
        </div>
        <p className="text-sm text-slate-300">{st.texto}{d.perfil.moderacao_motivo && d.perfil.status !== "ativo" ? ` Motivo informado pela equipe: ${d.perfil.moderacao_motivo}` : ""}</p>

        {d.termos_pendentes.length > 0 && (
          <div className="rounded-2xl border border-amber-400/30 bg-amber-500/10 p-4 space-y-2">
            <p className="text-sm text-amber-100 font-medium flex items-center gap-2"><AlertTriangle className="w-4 h-4" />Temos uma versão nova dos termos para você aceitar</p>
            <div className="flex gap-2 flex-wrap">{d.termos_pendentes.map((t) => <Button key={t.tipo} size="sm" variant="outline" className="border-amber-300/40 text-amber-100 hover:bg-amber-500/20" onClick={() => aceitarTermos.mutate({ tipo: t.tipo, versao: t.versao })}>Aceitar {TERMO_LABEL[t.tipo] ?? t.tipo}</Button>)}</div>
          </div>
        )}
        {d.nivel.aviso_em && (
          <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 text-sm text-slate-200"><Clock className="w-4 h-4 inline mr-1 text-amber-300" />Seus resultados recentes ficaram abaixo do seu nível atual. Você tem um prazo para recuperar antes de qualquer mudança, e a mudança só altera sua posição na vitrine: você continua atendendo normalmente.</div>
        )}

        <Tabs value={aba} onValueChange={(v) => setAba(v as Aba)}>
          <TabsList className="bg-white/5 flex-wrap h-auto">
            <TabsTrigger value="caminho"><ArrowRight className="w-4 h-4 mr-1" />Meu caminho</TabsTrigger>
            <TabsTrigger value="servicos"><FileText className="w-4 h-4 mr-1" />Meus serviços</TabsTrigger>
            <TabsTrigger value="conversas"><MessageSquare className="w-4 h-4 mr-1" />Conversas{d.metricas.sem_resposta > 0 && <span className="ml-1 rounded-full bg-[#FF8A00] text-white text-[10px] px-1.5">{d.metricas.sem_resposta}</span>}</TabsTrigger>
            <TabsTrigger value="reputacao"><Activity className="w-4 h-4 mr-1" />Minha reputação</TabsTrigger>
            <TabsTrigger value="perfil"><Pencil className="w-4 h-4 mr-1" />Meu perfil</TabsTrigger>
            <TabsTrigger value="cupons"><Ticket className="w-4 h-4 mr-1" />Cupons</TabsTrigger>
            <TabsTrigger value="conta"><Gavel className="w-4 h-4 mr-1" />Conta e privacidade</TabsTrigger>
          </TabsList>
          <TabsContent value="caminho" className="mt-4"><CaminhoTab d={d} irPara={setAba} novoServico={() => { setAba("servicos"); setNovoServico(true); }} /></TabsContent>
          <TabsContent value="servicos" className="mt-4"><ServicosTab anuncios={d.anuncios} perfilAtivo={d.perfil.status === "ativo"} abrirNovo={novoServico} onNovoAberto={() => setNovoServico(false)} /></TabsContent>
          <TabsContent value="conversas" className="mt-4"><ConversasTab leads={d.leads} onAtualizar={() => void portal.refetch()} atualizando={portal.isFetching} /></TabsContent>
          <TabsContent value="reputacao" className="mt-4"><ReputacaoTab d={d} /></TabsContent>
          <TabsContent value="perfil" className="mt-4"><PerfilTab d={d} /></TabsContent>
          <TabsContent value="cupons" className="mt-4"><CuponsTab cupons={d.cupons} /></TabsContent>
          <TabsContent value="conta" className="mt-4">
            <ContaTab d={d} onExportar={async () => { try { const j = await exportar(); const blob = new Blob([JSON.stringify(j, null, 2)], { type: "application/json" }); const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "meus-dados-marketye.json"; a.click(); } catch (e) { toast.error(e instanceof Error ? e.message : "Falha ao exportar"); } }} onExcluir={() => setExcluirAberto(true)} />
          </TabsContent>
        </Tabs>
      </div>

      <Dialog open={excluirAberto} onOpenChange={setExcluirAberto}>
        <DialogContent>
          <DialogHeader><DialogTitle>Excluir meu perfil do MarketYE</DialogTitle></DialogHeader>
          <p className="text-sm text-muted-foreground">Seu perfil sai da vitrine e seus dados pessoais (nome, e-mail, documento, foto) são apagados do cadastro. O histórico de conversas e avaliações fica guardado pelo prazo que a lei pede, sem o seu nome. Digite <b>EXCLUIR</b> para confirmar.</p>
          <Input value={confirmExcluir} onChange={(e) => setConfirmExcluir(e.target.value)} />
          <Button variant="destructive" disabled={confirmExcluir !== "EXCLUIR" || excluir.isPending} onClick={() => excluir.mutate(confirmExcluir, { onSuccess: () => { setExcluirAberto(false); window.location.assign(`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketye`); } })}><Trash2 className="w-4 h-4 mr-1" />Excluir definitivamente</Button>
        </DialogContent>
      </Dialog>
    </MarketYELayout>
  );
}

// ---------------------------------------------------------------------
// Meu caminho: a sequência evidente, do cadastro ao primeiro serviço.
// ---------------------------------------------------------------------
function CaminhoTab({ d, irPara, novoServico }: { d: PortalDados; irPara: (a: Aba) => void; novoServico: () => void }) {
  const perfilOk = !!d.perfil.bio && !!d.perfil.cidade;
  const aprovado = d.perfil.status === "ativo";
  const temServico = d.anuncios.some((a) => a.status !== "removido");
  const publicado = d.anuncios.some((a) => a.status === "publicado");
  const recebeuContato = d.leads.length > 0;
  const fechou = d.leads.some((l) => l.status === "ganho");
  const passos: { titulo: string; texto: string; feito: boolean; acao?: { label: string; onClick: () => void }; espera?: string }[] = [
    { titulo: "Conte o que você faz", texto: "Uma apresentação curta, sua cidade e como atende. É o que a empresa lê primeiro.", feito: perfilOk, acao: { label: perfilOk ? "Revisar perfil" : "Completar perfil", onClick: () => irPara("perfil") } },
    { titulo: "Aprovação dos seus dados", texto: "Nossa equipe confere seus dados e registro (quando a área exige). Você recebe o selo \"dados verificados\".", feito: aprovado, espera: aprovado ? undefined : d.perfil.status === "pendente" ? "Em análise pela equipe. Você não precisa fazer nada." : "Veja o motivo no topo e, se discordar, peça revisão em Conta e privacidade." },
    { titulo: "Cadastre seu primeiro serviço", texto: "Diga em uma frase o que oferece e a IA monta o anúncio com sugestão de preço. Você revisa.", feito: temServico, acao: { label: temServico ? "Ver meus serviços" : "Criar com a IA", onClick: temServico ? () => irPara("servicos") : novoServico } },
    { titulo: "Publique na vitrine", texto: aprovado ? "Com o cadastro aprovado, clique em Publicar no serviço." : "Fica disponível assim que seus dados forem aprovados.", feito: publicado, acao: temServico && aprovado && !publicado ? { label: "Publicar", onClick: () => irPara("servicos") } : undefined },
    { titulo: "Responda às empresas", texto: "As empresas escrevem por aqui. Responder rápido ajuda você a aparecer melhor. Telefone e e-mail só aparecem quando a empresa liberar.", feito: recebeuContato && d.metricas.sem_resposta === 0, acao: recebeuContato ? { label: d.metricas.sem_resposta > 0 ? `Responder (${d.metricas.sem_resposta})` : "Ver conversas", onClick: () => irPara("conversas") } : undefined, espera: recebeuContato ? undefined : publicado ? "Aguardando o primeiro contato. Quanto mais completo o perfil, mais chances." : undefined },
    { titulo: "Combine, faça o serviço e avalie", texto: "Quando fechar com a empresa, marque \"Serviço combinado\" na conversa. Depois disso vocês dois podem se avaliar, e sua reputação cresce.", feito: fechou, acao: recebeuContato ? { label: "Ir às conversas", onClick: () => irPara("conversas") } : undefined },
  ];
  const proximo = passos.findIndex((p) => !p.feito);
  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4">
        <p className="text-sm text-slate-200">É simples: você conta o que faz, a gente confere seus dados, você publica seus serviços e as empresas entram em contato por aqui. Preço, prazo e combinado são sempre seus.</p>
      </div>
      <ol className="space-y-3">
        {passos.map((p, i) => (
          <li key={p.titulo} className={`rounded-2xl border p-4 flex gap-4 ${i === proximo ? "border-[#FF8A00]/60 bg-[#FF8A00]/5" : "border-white/10 bg-white/[0.03]"}`}>
            <div className="shrink-0 mt-0.5">{p.feito ? <CheckCircle2 className="w-6 h-6 text-emerald-400" /> : <Circle className={`w-6 h-6 ${i === proximo ? "text-[#FF8A00]" : "text-slate-500"}`} />}</div>
            <div className="flex-1 min-w-0">
              <p className={`font-semibold ${p.feito ? "text-slate-300 line-through decoration-slate-500" : "text-white"}`}>{i + 1}. {p.titulo}</p>
              <p className="text-xs text-slate-400 mt-0.5">{p.texto}</p>
              {p.espera && !p.feito && <p className="text-xs text-amber-200 mt-1">{p.espera}</p>}
            </div>
            {p.acao && <Button size="sm" className={i === proximo ? "bg-[#FF8A00] hover:bg-[#e67a00] text-white" : "bg-white/10 hover:bg-white/20 text-white"} onClick={p.acao.onClick}>{p.acao.label}<ArrowRight className="w-3.5 h-3.5 ml-1" /></Button>}
          </li>
        ))}
      </ol>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Kpi label="Empresas que entraram em contato (30 dias)" value={d.metricas.leads_30d} />
        <Kpi label="Serviços combinados (30 dias)" value={d.metricas.leads_ganhos_30d} />
        <Kpi label="Aguardando sua resposta" value={d.metricas.sem_resposta} destaque={d.metricas.sem_resposta > 0} />
        <Kpi label="Avaliações recebidas" value={`${d.metricas.avaliacoes}${d.perfil.total_avaliacoes ? ` · nota ${Number(d.perfil.nota_media).toFixed(1)}` : ""}`} />
      </div>
    </div>
  );
}

function Kpi({ label, value, destaque }: { label: string; value: string | number; destaque?: boolean }) {
  return <div className={`rounded-2xl border p-4 ${destaque ? "border-[#FF8A00]/50 bg-[#FF8A00]/10" : "border-white/10 bg-white/[0.04]"}`}><p className="text-xs text-slate-400">{label}</p><p className="text-2xl font-bold text-white">{value}</p></div>;
}

// ---------------------------------------------------------------------
// Meus serviços
// ---------------------------------------------------------------------
function ServicosTab({ anuncios, perfilAtivo, abrirNovo, onNovoAberto }: { anuncios: PortalAnuncio[]; perfilAtivo: boolean; abrirNovo: boolean; onNovoAberto: () => void }) {
  const { publicarAnuncio, statusAnuncio } = useMarketYEPortal();
  const [editando, setEditando] = useState<PortalAnuncio | null | "novo">(null);
  useEffect(() => { if (abrirNovo) { setEditando("novo"); onNovoAberto(); } }, [abrirNovo, onNovoAberto]);
  const statusLabel: Record<string, { t: string; c: string }> = { rascunho: { t: "Ainda não publicado", c: "bg-white/10 text-slate-200" }, publicado: { t: "Na vitrine", c: "bg-emerald-500/20 text-emerald-200" }, pausado: { t: "Pausado", c: "bg-amber-500/20 text-amber-200" }, removido: { t: "Removido", c: "bg-white/10 text-slate-400" } };
  const precoTexto = (a: PortalAnuncio) => a.tipo_preco === "sob_orcamento" ? "Preço combinado com a empresa" : `R$ ${Number(a.preco_referencia ?? 0).toFixed(2)} ${({ hora: "por hora", visita: "por visita", pacote: "o pacote", mensal: "por mês" } as Record<string, string>)[a.tipo_preco] ?? ""}`;
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <p className="text-sm text-slate-300">Cada serviço é um anúncio na vitrine. Você decide preço, prazo e condições.</p>
        <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" onClick={() => setEditando("novo")} data-testid="portal-novo-anuncio"><Sparkles className="w-4 h-4 mr-1" />Novo serviço</Button>
      </div>
      {!perfilAtivo && <p className="text-xs text-amber-200">Seu cadastro ainda está em análise: pode criar os serviços agora e publicar assim que for aprovado.</p>}
      {anuncios.length === 0 ? <p className="text-sm text-slate-400 py-8 text-center">Nenhum serviço ainda. Clique em "Novo serviço": uma frase basta, a IA monta o resto.</p> : (
        <div className="grid md:grid-cols-2 gap-3">
          {anuncios.map((a) => (
            <div key={a.id} className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <div><p className="font-semibold text-white">{a.nome}</p><p className="text-xs text-slate-400">{a.categoria_nome ?? "Área não informada"} · {({ presencial: "presencial", online: "remoto", hibrido: "presencial ou remoto" } as Record<string, string>)[a.modalidade]}</p></div>
                <Badge className={statusLabel[a.status]?.c}>{statusLabel[a.status]?.t ?? a.status}</Badge>
              </div>
              <p className="text-sm text-slate-300 line-clamp-2">{a.descricao}</p>
              <p className="text-xs text-slate-400">{precoTexto(a)}{a.promocao_percentual ? ` · promoção de ${a.promocao_percentual}%` : ""}</p>
              <div className="flex gap-2 flex-wrap">
                <Button size="sm" variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={() => setEditando(a)}><Pencil className="w-3.5 h-3.5 mr-1" />Editar</Button>
                {a.status !== "publicado" && <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={publicarAnuncio.isPending} onClick={() => publicarAnuncio.mutate(a.id)}><Eye className="w-3.5 h-3.5 mr-1" />Publicar</Button>}
                {a.status === "publicado" && <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => statusAnuncio.mutate({ id: a.id, status: "pausado" })}><PauseCircle className="w-3.5 h-3.5 mr-1" />Pausar</Button>}
                {a.status === "pausado" && <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => publicarAnuncio.mutate(a.id)}><PlayCircle className="w-3.5 h-3.5 mr-1" />Voltar à vitrine</Button>}
                <Button size="sm" variant="ghost" className="text-slate-400" onClick={() => statusAnuncio.mutate({ id: a.id, status: "removido" })} title="Remover"><Trash2 className="w-3.5 h-3.5" /></Button>
              </div>
            </div>
          ))}
        </div>
      )}
      {editando && <AnuncioEditor anuncio={editando === "novo" ? null : editando} onClose={() => setEditando(null)} />}
    </div>
  );
}

function AnuncioEditor({ anuncio, onClose }: { anuncio: PortalAnuncio | null; onClose: () => void }) {
  const { salvarAnuncio, publicarAnuncio, portal } = useMarketYEPortal();
  const { data: cats } = useMarketYECategorias();
  const [f, setF] = useState({
    nome: anuncio?.nome ?? "", descricao: anuncio?.descricao ?? "", categoria_id: anuncio?.categoria_id ?? "", modalidade: anuncio?.modalidade ?? "presencial",
    tipo_preco: anuncio?.tipo_preco ?? "sob_orcamento", preco_referencia: anuncio?.preco_referencia?.toString() ?? "", preco_minimo: anuncio?.preco_minimo?.toString() ?? "", preco_maximo: anuncio?.preco_maximo?.toString() ?? "",
    prazo_tipico: anuncio?.prazo_tipico ?? "", politica_cancelamento: anuncio?.politica_cancelamento ?? "", tags: (anuncio?.tags ?? []).join(", "), base_legal: anuncio?.base_legal ?? "",
    promocao_percentual: anuncio?.promocao_percentual?.toString() ?? "", promocao_fim: anuncio?.promocao_fim ?? "", promocao_descricao: anuncio?.promocao_descricao ?? "",
    publico_alvo: anuncio?.publico_alvo ?? "", gerado_por_ia: anuncio?.gerado_por_ia ?? false,
  });
  const [ia, setIa] = useState({ oque: "", carregando: false, sugestaoPreco: "" });
  const [maisOpcoes, setMaisOpcoes] = useState(!!anuncio);
  const set = (k: keyof typeof f, v: unknown) => setF((x) => ({ ...x, [k]: v }));
  const cat = cats?.todas.find((c) => c.id === f.categoria_id);

  const gerarIA = async () => {
    if (!ia.oque && !f.nome) return toast.error("Escreva em uma frase o que você oferece");
    setIa((s) => ({ ...s, carregando: true }));
    try {
      const r = await marketyeIA<{ titulo: string; descricao: string; tags: string[]; categoria_slug?: string; tipo_preco?: string; preco_sugerido?: number; preco_minimo?: number; preco_maximo?: number; justificativa_preco?: string; base_legal?: string; publico_alvo?: string }>("gerar_anuncio", {
        o_que_faz: ia.oque || f.nome, categoria: cat?.nome, conselho: portal.data?.perfil.conselho, cidade: portal.data?.perfil.cidade, uf: portal.data?.perfil.estado, modalidade: f.modalidade,
        categorias: (cats?.raizes ?? []).map((c) => ({ slug: c.slug, nome: c.nome, obrigacao_legal: c.obrigacao_legal })),
      });
      const catBruta = r.categoria_slug ? cats?.todas.find((c) => c.slug === r.categoria_slug) : undefined;
      const catSug = catBruta?.pai_id ? cats?.todas.find((c) => c.id === catBruta.pai_id) : catBruta;
      setF((x) => ({
        ...x, nome: r.titulo || x.nome, descricao: r.descricao || x.descricao, tags: (r.tags ?? []).join(", ") || x.tags, categoria_id: x.categoria_id || catSug?.id || "",
        tipo_preco: r.tipo_preco || x.tipo_preco, preco_referencia: r.preco_sugerido != null ? String(r.preco_sugerido) : x.preco_referencia,
        preco_minimo: r.preco_minimo != null ? String(r.preco_minimo) : x.preco_minimo, preco_maximo: r.preco_maximo != null ? String(r.preco_maximo) : x.preco_maximo,
        base_legal: r.base_legal || x.base_legal, publico_alvo: r.publico_alvo || x.publico_alvo, gerado_por_ia: true,
      }));
      setIa((s) => ({ ...s, sugestaoPreco: r.justificativa_preco ?? "" }));
      toast.success("Pronto: revise o texto, ajuste o preço se quiser e publique.");
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); } finally { setIa((s) => ({ ...s, carregando: false })); }
  };

  const montar = () => ({
    id: anuncio?.id, nome: f.nome, descricao: f.descricao, categoria_id: f.categoria_id || null, modalidade: f.modalidade, tipo_preco: f.tipo_preco,
    preco_referencia: f.preco_referencia ? Number(f.preco_referencia) : null, preco_minimo: f.preco_minimo ? Number(f.preco_minimo) : null, preco_maximo: f.preco_maximo ? Number(f.preco_maximo) : null,
    prazo_tipico: f.prazo_tipico || null, politica_cancelamento: f.politica_cancelamento || null, tags: f.tags.split(",").map((t) => t.trim()).filter(Boolean), base_legal: f.base_legal || null,
    promocao_percentual: f.promocao_percentual ? Number(f.promocao_percentual) : null, promocao_inicio: f.promocao_percentual ? format(new Date(), "yyyy-MM-dd") : null, promocao_fim: f.promocao_fim || null,
    promocao_descricao: f.promocao_descricao || null, publico_alvo: f.publico_alvo || null, gerado_por_ia: f.gerado_por_ia,
  });
  const salvar = async (publicar: boolean) => {
    try {
      const r = await salvarAnuncio.mutateAsync(montar());
      if (publicar) await publicarAnuncio.mutateAsync(r.id);
      onClose();
    } catch { /* avisos já mostrados */ }
  };

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>{anuncio ? "Editar serviço" : "Novo serviço"}</DialogTitle></DialogHeader>
        <div className="space-y-4">
          {!anuncio && (
            <div className="rounded-xl border border-violet-200 bg-violet-50 p-3 space-y-2">
              <Label className="text-violet-900 flex items-center gap-1"><Sparkles className="w-4 h-4" />Passo 1 — em uma frase, o que você oferece?</Label>
              <div className="flex gap-2">
                <Input value={ia.oque} onChange={(e) => setIa((s) => ({ ...s, oque: e.target.value }))} placeholder="Ex.: treinamento de NR-35 na empresa, para até 20 pessoas, em Curitiba e região" />
                <Button type="button" onClick={gerarIA} disabled={ia.carregando}>{ia.carregando ? <Loader2 className="w-4 h-4 animate-spin" /> : "Montar anúncio"}</Button>
              </div>
              <p className="text-[11px] text-violet-800">A IA escreve o título, a descrição, escolhe a área mais próxima e sugere um preço. Você revisa tudo no passo 2. O preço final é sempre seu.</p>
            </div>
          )}
          <p className="text-xs text-muted-foreground font-medium">{anuncio ? "Revise e salve" : "Passo 2 — revise e publique"}</p>
          <div className="grid sm:grid-cols-2 gap-3">
            <div className="sm:col-span-2"><Label>Nome do serviço*</Label><Input value={f.nome} onChange={(e) => set("nome", e.target.value)} placeholder="Ex.: Treinamento de NR-35 na sua empresa" /></div>
            <div className="sm:col-span-2"><Label>Descrição* (sem telefone, e-mail ou site; o contato é por aqui)</Label><Textarea rows={5} value={f.descricao} onChange={(e) => set("descricao", e.target.value)} placeholder="O que a empresa recebe, como funciona, para quem serve." /></div>
            <div><Label>Área (opcional, ajuda a empresa a encontrar você)</Label>
              <Select value={f.categoria_id || "nenhuma"} onValueChange={(v) => set("categoria_id", v === "nenhuma" ? "" : v)}><SelectTrigger><SelectValue placeholder="Escolha, se quiser" /></SelectTrigger>
                <SelectContent><SelectItem value="nenhuma">Sem área definida</SelectItem>{(cats?.raizes ?? []).map((r) => <SelectItem key={r.id} value={r.id}>{r.nome}</SelectItem>)}{cat?.pai_id && <SelectItem value={cat.id}>{cat.nome}</SelectItem>}</SelectContent>
              </Select>
              {cat?.obrigacao_legal?.length ? <p className="text-[11px] text-muted-foreground mt-1">Esta área atende {cat.obrigacao_legal.join(", ")}: as empresas com essa pendência veem você primeiro.</p> : null}
            </div>
            <div><Label>Como você atende</Label>
              <Select value={f.modalidade} onValueChange={(v) => set("modalidade", v)}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="presencial">Na empresa (presencial)</SelectItem><SelectItem value="online">A distância (remoto)</SelectItem><SelectItem value="hibrido">Dos dois jeitos</SelectItem></SelectContent></Select>
            </div>
            <div><Label>Como você cobra</Label>
              <Select value={f.tipo_preco} onValueChange={(v) => set("tipo_preco", v)}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="sob_orcamento">Combino com a empresa (orçamento)</SelectItem><SelectItem value="hora">Por hora</SelectItem><SelectItem value="visita">Por visita ou serviço</SelectItem><SelectItem value="pacote">Pacote fechado</SelectItem><SelectItem value="mensal">Por mês</SelectItem></SelectContent></Select>
            </div>
            <div><Label>Preço (R$)</Label><Input type="number" value={f.preco_referencia} onChange={(e) => set("preco_referencia", e.target.value)} disabled={f.tipo_preco === "sob_orcamento"} placeholder={f.tipo_preco === "sob_orcamento" ? "combinado com a empresa" : ""} /></div>
            {ia.sugestaoPreco && <p className="sm:col-span-2 text-[11px] text-muted-foreground">Sugestão da IA: {ia.sugestaoPreco}</p>}
            <div className="sm:col-span-2"><Button type="button" variant="link" size="sm" className="px-0 h-auto" onClick={() => setMaisOpcoes((v) => !v)}>{maisOpcoes ? "Esconder opções extras" : "Mais opções (faixa de preço, prazo, promoção, palavras-chave)"}</Button></div>
            {maisOpcoes && (
              <>
                <div><Label>De (R$)</Label><Input type="number" value={f.preco_minimo} onChange={(e) => set("preco_minimo", e.target.value)} /></div>
                <div><Label>Até (R$)</Label><Input type="number" value={f.preco_maximo} onChange={(e) => set("preco_maximo", e.target.value)} /></div>
                <div><Label>Prazo que costuma levar</Label><Input value={f.prazo_tipico} onChange={(e) => set("prazo_tipico", e.target.value)} placeholder="Ex.: 10 dias úteis" /></div>
                <div><Label>Norma que este serviço atende (se houver)</Label><Input value={f.base_legal} onChange={(e) => set("base_legal", e.target.value)} placeholder="Ex.: NR-35" /></div>
                <div className="sm:col-span-2"><Label>Palavras-chave (separe por vírgula)</Label><Input value={f.tags} onChange={(e) => set("tags", e.target.value)} placeholder="Ex.: altura, NR-35, brigada" /></div>
                <div className="sm:col-span-2"><Label>Regras de cancelamento (opcional)</Label><Input value={f.politica_cancelamento} onChange={(e) => set("politica_cancelamento", e.target.value)} /></div>
                <div><Label>Promoção (% de desconto)</Label><Input type="number" value={f.promocao_percentual} onChange={(e) => set("promocao_percentual", e.target.value)} /></div>
                <div><Label>Promoção válida até</Label><Input type="date" value={f.promocao_fim} onChange={(e) => set("promocao_fim", e.target.value)} /></div>
                <div className="sm:col-span-2"><Label>Texto da promoção</Label><Input value={f.promocao_descricao} onChange={(e) => set("promocao_descricao", e.target.value)} placeholder="Ex.: 10% na primeira contratação" /></div>
              </>
            )}
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" disabled={salvarAnuncio.isPending} onClick={() => salvar(false)}>Salvar sem publicar</Button>
            <Button className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={salvarAnuncio.isPending || publicarAnuncio.isPending} onClick={() => salvar(true)}>Salvar e publicar</Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------
// Conversas com empresas
// ---------------------------------------------------------------------
// A lista se atualiza sozinha (a cada 30 s e ao voltar à aba); o botão é para
// quem não quer esperar.
function ConversasTab({ leads, onAtualizar, atualizando }: { leads: PortalLead[]; onAtualizar: () => void; atualizando: boolean }) {
  const [sel, setSel] = useState<PortalLead | null>(null);
  useEffect(() => { if (sel) { const a = leads.find((l) => l.id === sel.id); if (a && a !== sel) setSel(a); } }, [leads, sel]);
  const botaoAtualizar = (
    <Button size="sm" variant="ghost" className="text-slate-300 hover:text-white hover:bg-white/10" onClick={onAtualizar} disabled={atualizando} data-testid="portal-conversas-atualizar">
      <RefreshCw className={`w-3.5 h-3.5 mr-1 ${atualizando ? "animate-spin" : ""}`} />Atualizar
    </Button>
  );
  if (leads.length === 0) {
    return (
      <div className="py-8 text-center space-y-2">
        <p className="text-sm text-slate-400">Nenhuma empresa entrou em contato ainda. Publique seus serviços e complete o perfil: é assim que as empresas encontram você.</p>
        {botaoAtualizar}
      </div>
    );
  }
  return (
    <div className="grid md:grid-cols-[320px_1fr] gap-4">
      <div className="space-y-2 max-h-[70vh] overflow-y-auto pr-1">
        <div className="flex justify-end">{botaoAtualizar}</div>
        {leads.map((l) => (
          <button key={l.id} onClick={() => setSel(l)} className={`w-full text-left rounded-xl border p-3 transition ${sel?.id === l.id ? "border-[#60ABEF] bg-white/10" : "border-white/10 hover:bg-white/5"}`}>
            <div className="flex items-center justify-between gap-2"><span className="font-medium text-sm text-white truncate">{l.empresa_nome ?? "Empresa"}</span><Badge className="bg-white/10 text-slate-200 text-[10px]">{LEAD_STATUS_LABEL[l.status] ?? l.status}</Badge></div>
            <p className="text-xs text-slate-400 truncate">{l.servico_nome ?? "Contato direto"}{l.obrigacao_legal ? ` · ${l.obrigacao_legal}` : ""}</p>
            <p className="text-xs text-slate-500 truncate mt-1">{l.ultima_mensagem}</p>
            {l.status === "novo" && <p className="text-[10px] text-[#FF8A00] mt-1">aguardando sua resposta</p>}
          </button>
        ))}
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-4 min-h-[300px]">{sel ? <ThreadEspecialista lead={sel} /> : <p className="text-sm text-slate-400">Escolha uma conversa ao lado.</p>}</div>
    </div>
  );
}

function ThreadEspecialista({ lead }: { lead: PortalLead }) {
  const { data: mensagens = [] } = usePortalMensagens(lead.id);
  const { enviarMensagem, statusLead, avaliarEmpresa, contato } = useMarketYEPortal();
  const [texto, setTexto] = useState("");
  const [rascunhoIA, setRascunhoIA] = useState(false);
  const [avaliando, setAvaliando] = useState(false);
  const [contatoInfo, setContatoInfo] = useState<{ liberado: boolean; empresa?: string; solicitante?: string; email?: string; telefone?: string } | null>(null);
  const fim = useRef<HTMLDivElement>(null);
  useEffect(() => { fim.current?.scrollIntoView({ behavior: "smooth" }); }, [mensagens.length]);
  useEffect(() => { setContatoInfo(null); }, [lead.id]);
  const encerrado = lead.status === "perdido" || lead.status === "encerrado";

  const sugerirResposta = async () => {
    setRascunhoIA(true);
    try {
      const r = await marketyeIA<{ resposta: string }>("rascunho_resposta", { conversa: mensagens.map((m) => `${m.autor_tipo}: ${m.texto}`).join("\n"), servico: lead.servico_nome, obrigacao: lead.obrigacao_legal });
      setTexto(r.resposta);
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); } finally { setRascunhoIA(false); }
  };
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-start justify-between gap-2 flex-wrap">
        <div>
          <p className="font-semibold text-white flex items-center gap-2"><Building2 className="w-4 h-4" />{lead.empresa_nome ?? "Empresa"}</p>
          <p className="text-xs text-slate-400">{lead.servico_nome ?? "Contato direto"} · {LEAD_STATUS_LABEL[lead.status] ?? lead.status}{lead.reputacao_empresa?.media ? ` · esta empresa tem nota ${lead.reputacao_empresa.media} com outros especialistas` : ""}{lead.cupom_codigo ? ` · a empresa recebeu o cupom ${lead.cupom_codigo}` : ""}</p>
        </div>
        <div className="flex gap-1.5 flex-wrap">
          {lead.contato_liberado && <Button size="sm" variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={async () => { try { setContatoInfo(await contato(lead.id)); } catch (e) { toast.error(e instanceof Error ? e.message : "Erro"); } }}><Phone className="w-3.5 h-3.5 mr-1" />Ver contato</Button>}
          {!encerrado && lead.status !== "ganho" && <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" onClick={() => statusLead.mutate({ lead_id: lead.id, status: "ganho" })}><CheckCircle2 className="w-3.5 h-3.5 mr-1" />Serviço combinado</Button>}
          {!encerrado && <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => statusLead.mutate({ lead_id: lead.id, status: "encerrado", motivo: "O especialista encerrou a conversa." })}>Não vou atender</Button>}
          {lead.status === "ganho" && !lead.avaliei && <Button size="sm" className="bg-amber-500 hover:bg-amber-600 text-white" onClick={() => setAvaliando(true)}><Star className="w-3.5 h-3.5 mr-1" />Avaliar a empresa</Button>}
        </div>
      </div>
      {contatoInfo?.liberado && (
        <div className="rounded-xl bg-emerald-500/10 border border-emerald-400/30 p-3 text-sm space-y-1 text-emerald-100">
          <p className="font-medium">{contatoInfo.empresa}{contatoInfo.solicitante ? ` · ${contatoInfo.solicitante}` : ""}</p>
          {contatoInfo.email && <p className="flex items-center gap-1.5"><Mail className="w-3.5 h-3.5" />{contatoInfo.email}</p>}
          {contatoInfo.telefone && <p className="flex items-center gap-1.5"><Phone className="w-3.5 h-3.5" />{contatoInfo.telefone}</p>}
        </div>
      )}
      <div className="space-y-2 max-h-[40vh] overflow-y-auto pr-1">
        {mensagens.map((m) => (
          <div key={m.id} className={`text-sm rounded-xl px-3 py-2 max-w-[85%] ${m.autor_tipo === "especialista" ? "ml-auto bg-[#60ABEF]/20 text-white" : m.autor_tipo === "cliente" ? "bg-white/10 text-slate-100" : "mx-auto bg-amber-500/10 text-amber-100 text-xs text-center"}`}>
            <p className="whitespace-pre-wrap">{m.texto}</p>
            <p className="text-[10px] opacity-60 mt-0.5">{format(new Date(m.created_at), "dd/MM HH:mm", { locale: ptBR })}</p>
          </div>
        ))}
        <div ref={fim} />
      </div>
      {!encerrado && (
        <div className="space-y-2">
          <Textarea className={inputCls} value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} placeholder="Responda com o que você oferece, prazo e valor. Seu telefone e e-mail só aparecem quando a empresa liberar." />
          <div className="flex justify-between gap-2 flex-wrap">
            <Button size="sm" variant="ghost" className="text-slate-300" onClick={sugerirResposta} disabled={rascunhoIA}>{rascunhoIA ? <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" /> : <Sparkles className="w-3.5 h-3.5 mr-1" />}Escrever com a IA</Button>
            <Button size="sm" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={enviarMensagem.isPending || !texto.trim()} onClick={() => { enviarMensagem.mutate({ lead_id: lead.id, texto: texto.trim() }); setTexto(""); }}><Send className="w-3.5 h-3.5 mr-1" />Enviar</Button>
          </div>
          <p className="text-[11px] text-slate-500">Responder rápido ajuda você a aparecer melhor na vitrine. Não responder não gera nenhuma penalidade.</p>
        </div>
      )}
      <AvaliacaoCriteriosModal open={avaliando} onClose={() => setAvaliando(false)} titulo="Avaliar a empresa" subtitulo={lead.empresa_nome ?? undefined} criterios={CRITERIOS_EMPRESA} isLoading={avaliarEmpresa.isPending}
        onEnviar={(notas, comentario) => avaliarEmpresa.mutate({ lead_id: lead.id, notas, comentario }, { onSuccess: () => setAvaliando(false) })} />
    </div>
  );
}

// ---------------------------------------------------------------------
// Minha reputação
// ---------------------------------------------------------------------
function ReputacaoTab({ d }: { d: PortalDados }) {
  const { responderAvaliacao, contestar } = useMarketYEPortal();
  const rep = d.reputacao;
  const req = d.nivel.requisitos_proximo;
  const [resp, setResp] = useState<Record<string, string>>({});
  const reqLabel: Record<string, string> = { servicos: "Serviços combinados", clientes_unicos: "Empresas diferentes atendidas", media: "Nota média", taxa_resposta: "Contatos respondidos", ocorrencias: "Ocorrências no período" };
  const fmtReq = (k: string, v: number) => k === "taxa_resposta" ? `${Math.round(v * 100)}%` : String(v);
  const atual: Record<string, string> = {
    servicos: String(rep?.servicos_concluidos_total ?? 0), clientes_unicos: String(rep?.clientes_unicos_total ?? 0), media: Number(d.perfil.nota_media ?? 0).toFixed(1),
    taxa_resposta: rep?.taxa_resposta_90d != null ? `${Math.round(Number(rep.taxa_resposta_90d) * 100)}%` : "sem contatos ainda", ocorrencias: String(rep?.ocorrencias_90d ?? 0),
  };
  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 text-sm text-slate-200">Sua reputação tem duas partes: <b className="text-white">como está seu atendimento agora</b> (últimos 90 dias) e <b className="text-white">seu nível</b> (o que você já construiu). Nada disso impede você de trabalhar ou de cobrar o que quiser: muda só a posição na vitrine.</div>
      <div className="grid md:grid-cols-2 gap-4">
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
          <h3 className="font-semibold text-white flex items-center gap-2"><Activity className="w-4 h-4" />Seu atendimento nos últimos 90 dias</h3>
          <div className="flex items-center gap-3"><span className={`w-3 h-3 rounded-full ${saudeCor[rep?.saude_cor ?? "cinza"]}`} /><span className="text-white font-medium">{saudeTexto[rep?.saude_cor ?? "cinza"]}</span></div>
          <ul className="text-xs text-slate-300 space-y-1">
            <li>Nota recente: {rep?.media_90d ?? "—"} ({rep?.avaliacoes_90d ?? 0} avaliações)</li>
            <li>Contatos respondidos: {rep?.taxa_resposta_90d != null ? `${Math.round(Number(rep.taxa_resposta_90d) * 100)}%` : "nenhum contato no período"}</li>
            <li>Tempo para responder: {rep?.tempo_resposta_mediano_min != null ? `${Math.round(rep.tempo_resposta_mediano_min)} min` : "—"}</li>
            <li>Cancelamentos: {rep?.taxa_cancelamento_90d != null ? `${Math.round(Number(rep.taxa_cancelamento_90d) * 100)}%` : "—"} · Ocorrências: {rep?.ocorrencias_90d ?? 0}</li>
            {rep?.abaixo_piso && <li className="text-amber-200">Sua nota média está abaixo do mínimo: por enquanto seus serviços aparecem mais abaixo na vitrine. Você continua atendendo normalmente.</li>}
            {rep?.protegido_ate && new Date(rep.protegido_ate) > new Date() && <li className="text-[#60ABEF]">Boas-vindas até {format(new Date(rep.protegido_ate), "dd/MM/yyyy")}: seus serviços ganham um empurrão na vitrine.</li>}
          </ul>
        </div>
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
          <h3 className="font-semibold text-white flex items-center gap-2"><Star className="w-4 h-4" />Seu nível: {NIVEL_LABEL[d.nivel.atual] ?? d.nivel.atual}</h3>
          {req ? (
            <>
              <p className="text-xs text-slate-400">Para chegar a {NIVEL_LABEL[d.nivel.proximo ?? ""] ?? d.nivel.proximo}, é preciso ter tudo isto ao mesmo tempo:</p>
              <table className="w-full text-xs"><tbody>{Object.entries(req).map(([k, v]) => <tr key={k} className="border-t border-white/10"><td className="py-1 text-slate-300">{reqLabel[k] ?? k}</td><td className="py-1 text-right text-white">{atual[k] ?? "—"} <span className="text-slate-500">/ {k === "ocorrencias" ? `no máximo ${v}` : `pelo menos ${fmtReq(k, v)}`}</span></td></tr>)}</tbody></table>
            </>
          ) : <p className="text-xs text-slate-300">Você está no nível máximo.</p>}
          <p className="text-[11px] text-slate-500">Níveis: {d.nivel.ordem.map((n) => NIVEL_LABEL[n] ?? n).join(" → ")}.</p>
        </div>
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-3">
        <h3 className="font-semibold text-white flex items-center gap-2"><Star className="w-4 h-4 text-amber-400" />O que as empresas disseram</h3>
        {d.avaliacoes.length === 0 ? <p className="text-xs text-slate-400">Nenhuma avaliação ainda. Elas chegam depois do primeiro serviço combinado.</p> : d.avaliacoes.map((a) => (
          <div key={a.id} className="border-t border-white/10 pt-2 space-y-1">
            <p className="text-sm text-white">Nota {Number(a.nota_geral).toFixed(1)} <span className="text-xs text-slate-400">· {format(new Date(a.created_at), "dd/MM/yyyy")}</span></p>
            {a.comentario && <p className="text-sm text-slate-300">{a.comentario}</p>}
            {a.resposta ? <p className="text-xs text-slate-400 border-l-2 border-white/20 pl-2">Sua resposta: {a.resposta}</p> : (
              <div className="flex gap-2 flex-wrap"><Input className={inputCls} placeholder="Responder publicamente (opcional)" value={resp[a.id] ?? ""} onChange={(e) => setResp((r) => ({ ...r, [a.id]: e.target.value }))} /><Button size="sm" variant="outline" className="border-white/20 bg-transparent text-slate-100" disabled={!(resp[a.id] ?? "").trim()} onClick={() => responderAvaliacao.mutate({ id: a.id, resposta: resp[a.id] })}>Responder</Button>
                <Button size="sm" variant="ghost" className="text-slate-400" onClick={() => contestar.mutate({ tipo: "avaliacao", referencia_id: a.id, motivo: `Peço revisão desta avaliação: ` + (resp[a.id] || "ela não trata do serviço prestado ou é ofensiva.") })}>Pedir revisão</Button></div>
            )}
          </div>
        ))}
      </div>
      {d.ocorrencias.length > 0 && (
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
          <h3 className="font-semibold text-white">Ocorrências registradas</h3>
          <p className="text-xs text-slate-400">Registros feitos pela equipe a partir de denúncias procedentes. Se discordar, peça revisão.</p>
          {d.ocorrencias.map((o) => <div key={o.id} className="text-xs text-slate-300 flex items-center justify-between gap-2 border-t border-white/10 pt-2"><span>{o.tipo}: {o.descricao ?? ""} · {format(new Date(o.created_at), "dd/MM/yyyy")}</span><Button size="sm" variant="ghost" className="text-slate-400" onClick={() => contestar.mutate({ tipo: "reflexo_visibilidade", referencia_id: o.id, motivo: `Peço revisão desta ocorrência: discordo do registro.` })}>Pedir revisão</Button></div>)}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------
// Meu perfil (com apresentação escrita pela IA)
// ---------------------------------------------------------------------
function PerfilTab({ d }: { d: PortalDados }) {
  const { salvarPerfil } = useMarketYEPortal();
  const { data: cats } = useMarketYECategorias();
  const p = d.perfil;
  const [f, setF] = useState({
    telefone: p.telefone ?? "", bio: p.bio ?? "", formacao_academica: p.formacao_academica ?? "", registro_profissional: p.registro_profissional ?? "", conselho: p.conselho ?? "", uf_registro: p.uf_registro ?? "",
    registro_validade: p.registro_validade ?? "", especialidades: (p.especialidades ?? []).join(", "), certificacoes: (p.certificacoes ?? []).join(", "), cidade: p.cidade ?? "", estado: p.estado ?? "",
    modalidades: p.modalidades_atendimento ?? [], atende_remoto: p.atende_remoto, raio_atendimento_km: String(p.raio_atendimento_km ?? 100), politicas: p.politicas ?? "", site_url: p.site_url ?? "", video_url: p.video_url ?? "", foto_url: p.foto_url ?? "",
    disponibilidade: (p.disponibilidade as { dias?: string; horario?: string })?.dias ?? "", horario: (p.disponibilidade as { dias?: string; horario?: string })?.horario ?? "",
  });
  const [oque, setOque] = useState("");
  const [gerando, setGerando] = useState(false);
  const set = (k: keyof typeof f, v: unknown) => setF((x) => ({ ...x, [k]: v }));
  const toggleMod = (m: string) => set("modalidades", f.modalidades.includes(m) ? f.modalidades.filter((x) => x !== m) : [...f.modalidades, m]);
  const gerarBio = async () => {
    if (!oque.trim() && !f.bio) return toast.error("Conte em uma frase o que você faz");
    setGerando(true);
    try {
      const r = await marketyeIA<{ bio: string; especialidades: string[] }>("gerar_bio", { o_que_faz: oque || f.bio, registro: f.conselho ? `${f.conselho} ${f.registro_profissional}` : null, cidade: f.cidade, uf: f.estado, categorias: (cats?.raizes ?? []).map((c) => ({ slug: c.slug, nome: c.nome })) });
      setF((x) => ({ ...x, bio: r.bio || x.bio, especialidades: x.especialidades || (r.especialidades ?? []).join(", ") }));
      toast.success("Apresentação escrita. Ajuste o que quiser e salve.");
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); } finally { setGerando(false); }
  };
  return (
    <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-5 grid sm:grid-cols-2 gap-4">
      <p className="sm:col-span-2 text-xs text-slate-400">Seu e-mail ({p.email}) e {p.tipo_pessoa === "pj" ? "CNPJ" : "CPF"} ({p.cpf_cnpj ?? "—"}) não mudam por aqui; se precisar, fale com o atendimento. Preço, horários e regras são sempre seus.</p>
      <div className="sm:col-span-2 rounded-xl border border-white/10 bg-black/20 p-3 space-y-2">
        <Label className="text-slate-200 flex items-center gap-1"><Wand2 className="w-4 h-4 text-[#60ABEF]" />Quer ajuda para escrever sua apresentação? Conte em uma frase o que você faz</Label>
        <div className="flex gap-2 flex-wrap"><Input className={`${inputCls} flex-1 min-w-[220px]`} value={oque} onChange={(e) => setOque(e.target.value)} placeholder="Ex.: sou contadora, cuido de folha e eSocial de pequenas empresas há 10 anos" /><Button type="button" variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={gerarBio} disabled={gerando}>{gerando ? <Loader2 className="w-4 h-4 animate-spin" /> : "Escrever com a IA"}</Button></div>
      </div>
      <div className="sm:col-span-2"><Label className="text-slate-300">Apresentação (o que a empresa lê primeiro)</Label><Textarea className={inputCls} rows={4} value={f.bio} onChange={(e) => set("bio", e.target.value)} /></div>
      <div><Label className="text-slate-300">Telefone / WhatsApp (só aparece quando a empresa liberar)</Label><Input className={inputCls} value={f.telefone} onChange={(e) => set("telefone", e.target.value)} /></div>
      <div><Label className="text-slate-300">Foto (endereço da imagem)</Label><Input className={inputCls} value={f.foto_url} onChange={(e) => set("foto_url", e.target.value)} /></div>
      <div><Label className="text-slate-300">Cidade</Label><Input className={inputCls} value={f.cidade} onChange={(e) => set("cidade", e.target.value)} /></div>
      <div><Label className="text-slate-300">Estado (UF)</Label><Input className={inputCls} maxLength={2} value={f.estado} onChange={(e) => set("estado", e.target.value.toUpperCase())} /></div>
      <div className="sm:col-span-2">
        <Label className="text-slate-300">Como você atende</Label>
        <div className="flex gap-2 mt-1 flex-wrap items-center">
          {[["presencial", "Na empresa"], ["online", "A distância"], ["hibrido", "Dos dois jeitos"]].map(([m, l]) => <button key={m} type="button" onClick={() => toggleMod(m)} className={`px-3 py-1.5 rounded-lg border text-sm ${f.modalidades.includes(m) ? "border-[#FF8A00] bg-[#FF8A00]/10 text-white" : "border-white/15 text-slate-300"}`}>{l}</button>)}
          <label className="flex items-center gap-2 text-sm text-slate-300 ml-2"><Checkbox checked={f.atende_remoto} onCheckedChange={(v) => set("atende_remoto", v === true)} className="border-white/40" />Atendo qualquer lugar do país a distância</label>
        </div>
      </div>
      <div><Label className="text-slate-300">Até quantos km você vai (presencial)</Label><Input type="number" className={inputCls} value={f.raio_atendimento_km} onChange={(e) => set("raio_atendimento_km", e.target.value)} /></div>
      <div><Label className="text-slate-300">Dias em que atende</Label><Input className={inputCls} value={f.disponibilidade} onChange={(e) => set("disponibilidade", e.target.value)} placeholder="Ex.: segunda a sexta" /></div>
      <div><Label className="text-slate-300">Horário</Label><Input className={inputCls} value={f.horario} onChange={(e) => set("horario", e.target.value)} placeholder="Ex.: 8h às 18h" /></div>
      <div><Label className="text-slate-300">O que você faz (palavras-chave, separe por vírgula)</Label><Input className={inputCls} value={f.especialidades} onChange={(e) => set("especialidades", e.target.value)} placeholder="Ex.: palestras, SIPAT, liderança" /></div>
      <div><Label className="text-slate-300">Formação (opcional)</Label><Input className={inputCls} value={f.formacao_academica} onChange={(e) => set("formacao_academica", e.target.value)} /></div>
      <div><Label className="text-slate-300">Cursos e certificações (opcional)</Label><Input className={inputCls} value={f.certificacoes} onChange={(e) => set("certificacoes", e.target.value)} /></div>
      <div className="sm:col-span-2 grid grid-cols-[1fr_1fr_70px_1fr] gap-2">
        <div><Label className="text-slate-300">Registro profissional (se a sua área tiver)</Label><Input className={inputCls} value={f.conselho} onChange={(e) => set("conselho", e.target.value)} placeholder="Ex.: CRM, CREA, CRP, CRC" /></div>
        <div><Label className="text-slate-300">Número</Label><Input className={inputCls} value={f.registro_profissional} onChange={(e) => set("registro_profissional", e.target.value)} /></div>
        <div><Label className="text-slate-300">UF</Label><Input className={inputCls} maxLength={2} value={f.uf_registro} onChange={(e) => set("uf_registro", e.target.value.toUpperCase())} /></div>
        <div><Label className="text-slate-300">Válido até</Label><Input type="date" className={inputCls} value={f.registro_validade} onChange={(e) => set("registro_validade", e.target.value)} /></div>
      </div>
      <div><Label className="text-slate-300">Site (opcional)</Label><Input className={inputCls} value={f.site_url} onChange={(e) => set("site_url", e.target.value)} /></div>
      <div><Label className="text-slate-300">Vídeo de apresentação (opcional)</Label><Input className={inputCls} value={f.video_url} onChange={(e) => set("video_url", e.target.value)} /></div>
      <div className="sm:col-span-2"><Label className="text-slate-300">Suas regras (cancelamento, deslocamento, pagamento) — opcional</Label><Textarea className={inputCls} rows={2} value={f.politicas} onChange={(e) => set("politicas", e.target.value)} /></div>
      <div className="sm:col-span-2 flex justify-end">
        <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={salvarPerfil.isPending} onClick={() => salvarPerfil.mutate({
          telefone: f.telefone, bio: f.bio, formacao_academica: f.formacao_academica, registro_profissional: f.registro_profissional, conselho: f.conselho, uf_registro: f.uf_registro, registro_validade: f.registro_validade || null,
          especialidades: f.especialidades.split(",").map((s) => s.trim()).filter(Boolean), certificacoes: f.certificacoes.split(",").map((s) => s.trim()).filter(Boolean), cidade: f.cidade, estado: f.estado,
          modalidades: f.modalidades, atende_remoto: f.atende_remoto, raio_atendimento_km: Number(f.raio_atendimento_km) || 100, politicas: f.politicas, site_url: f.site_url, video_url: f.video_url, foto_url: f.foto_url,
          disponibilidade: { dias: f.disponibilidade, horario: f.horario },
        })}>Salvar perfil</Button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
// Cupons
// ---------------------------------------------------------------------
function CuponsTab({ cupons }: { cupons: PortalDados["cupons"] }) {
  const { salvarCupom } = useMarketYEPortal();
  const [f, setF] = useState({ codigo: "", descricao: "", desconto_percentual: "10", validade: "", limite_uso: "" });
  return (
    <div className="grid md:grid-cols-2 gap-4">
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-3">
        <h3 className="font-semibold text-white">Criar um cupom</h3>
        <p className="text-xs text-slate-400">A empresa vê o código quando abre uma conversa com você. É um jeito de estimular a primeira contratação. Cupons não mudam sua posição na vitrine.</p>
        <div><Label className="text-slate-300">Código</Label><Input className={inputCls} value={f.codigo} onChange={(e) => setF({ ...f, codigo: e.target.value.toUpperCase() })} placeholder="PRIMEIRA10" /></div>
        <div><Label className="text-slate-300">O que o cupom dá</Label><Input className={inputCls} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} placeholder="Ex.: 10% na primeira contratação" /></div>
        <div className="grid grid-cols-3 gap-2">
          <div><Label className="text-slate-300">Desconto (%)</Label><Input type="number" className={inputCls} value={f.desconto_percentual} onChange={(e) => setF({ ...f, desconto_percentual: e.target.value })} /></div>
          <div><Label className="text-slate-300">Válido até</Label><Input type="date" className={inputCls} value={f.validade} onChange={(e) => setF({ ...f, validade: e.target.value })} /></div>
          <div><Label className="text-slate-300">Quantas vezes</Label><Input type="number" className={inputCls} value={f.limite_uso} onChange={(e) => setF({ ...f, limite_uso: e.target.value })} /></div>
        </div>
        <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={!f.codigo || salvarCupom.isPending} onClick={() => salvarCupom.mutate({ codigo: f.codigo, descricao: f.descricao || null, desconto_percentual: Number(f.desconto_percentual), validade: f.validade || null, limite_uso: f.limite_uso ? Number(f.limite_uso) : null })}>Salvar cupom</Button>
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
        <h3 className="font-semibold text-white">Meus cupons</h3>
        {cupons.length === 0 ? <p className="text-xs text-slate-400">Nenhum cupom criado.</p> : cupons.map((c) => (
          <div key={c.id} className="flex items-center justify-between gap-2 border-t border-white/10 pt-2 text-sm">
            <div><p className="text-white font-mono">{c.codigo} <span className="text-xs text-slate-400">-{c.desconto_percentual}%</span></p><p className="text-xs text-slate-400">{c.descricao ?? ""}{c.validade ? ` · até ${format(new Date(c.validade), "dd/MM/yyyy")}` : ""} · usado {c.usos} vez(es){c.limite_uso ? ` de ${c.limite_uso}` : ""}</p></div>
            <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => salvarCupom.mutate({ codigo: c.codigo, descricao: c.descricao, desconto_percentual: c.desconto_percentual, validade: c.validade, limite_uso: c.limite_uso, ativo: !c.ativo })}>{c.ativo ? "Desativar" : "Reativar"}</Button>
          </div>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
// Conta e privacidade
// ---------------------------------------------------------------------
function ContaTab({ d, onExportar, onExcluir }: { d: PortalDados; onExportar: () => void; onExcluir: () => void }) {
  const { contestar } = useMarketYEPortal();
  const [motivo, setMotivo] = useState("");
  const podeContestarCadastro = d.perfil.moderacao_resultado === "rejeitado" || d.perfil.status === "suspenso";
  const tipoLabel: Record<string, string> = { rejeicao_cadastro: "Cadastro não aprovado", suspensao: "Perfil pausado", remocao_anuncio: "Serviço retirado", ajuste_nivel: "Mudança de nível", reflexo_visibilidade: "Ocorrência", avaliacao: "Avaliação", outro: "Outro" };
  const statusLabel: Record<string, string> = { aberta: "enviado, aguardando", em_analise: "em análise", deferida: "aceito", indeferida: "decisão mantida" };
  return (
    <div className="grid md:grid-cols-2 gap-4">
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
        <h3 className="font-semibold text-white flex items-center gap-2"><ShieldCheck className="w-4 h-4" />O que você aceitou</h3>
        <ul className="text-xs text-slate-300 space-y-1">{d.consentimentos.map((c) => <li key={c.id}>{TERMO_LABEL[c.tipo] ?? c.tipo} · versão {c.versao} · {format(new Date(c.aceito_em), "dd/MM/yyyy HH:mm")}</li>)}</ul>
        <p className="text-[11px] text-slate-500">Resumo do combinado: sem exclusividade; você define preço, horários e regras; pode atender fora do MarketYE e recusar contatos sem nenhum reflexo. O YourEyes faz o encontro; o serviço é seu.</p>
        {d.parceiro && <p className="text-xs text-[#60ABEF]">Você também participa do Programa de Parceiros (indicações): <Link to="/parceiro" className="underline">abrir a Área do Parceiro</Link>. As duas coisas ficam separadas.</p>}
        {!d.parceiro && <p className="text-xs text-slate-400">Quer também indicar empresas para o YourEyes e receber comissão? Veja o <Link to="/parceiros" className="underline">Programa de Parceiros</Link> (usa a mesma conta).</p>}
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
        <h3 className="font-semibold text-white flex items-center gap-2"><Gavel className="w-4 h-4" />Pedir revisão de uma decisão</h3>
        <p className="text-xs text-slate-400">Se discordar de alguma decisão sobre o seu perfil (cadastro não aprovado, pausa, ocorrência, avaliação), conte aqui. Uma pessoa da equipe lê, decide e responde neste mesmo lugar.</p>
        {podeContestarCadastro && (
          <div className="space-y-2">
            <Textarea className={inputCls} rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Explique por que discorda e o que pode comprovar." />
            <Button size="sm" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={motivo.trim().length < 10 || contestar.isPending} onClick={() => contestar.mutate({ tipo: d.perfil.status === "suspenso" ? "suspensao" : "rejeicao_cadastro", referencia_id: d.perfil.id, motivo }, { onSuccess: () => setMotivo("") })}>Enviar pedido de revisão</Button>
          </div>
        )}
        {d.contestacoes.length === 0 ? <p className="text-xs text-slate-500">Nenhum pedido de revisão.</p> : d.contestacoes.map((c) => (
          <div key={c.id} className="border-t border-white/10 pt-2 text-xs text-slate-300">
            <p><b className="text-white">{tipoLabel[c.decisao_tipo] ?? c.decisao_tipo}</b> · {statusLabel[c.status] ?? c.status} · {format(new Date(c.created_at), "dd/MM/yyyy")}</p>
            <p>{c.motivo}</p>
            {c.resposta && <p className="text-slate-400 border-l-2 border-white/20 pl-2 mt-1">Resposta da equipe: {c.resposta}</p>}
          </div>
        ))}
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-3 md:col-span-2">
        <h3 className="font-semibold text-white">Seus dados</h3>
        <p className="text-xs text-slate-400">Você pode baixar uma cópia de tudo o que o MarketYE guarda sobre você e pode pedir a exclusão do seu perfil quando quiser.</p>
        <div className="flex gap-2 flex-wrap">
          <Button variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={onExportar}><Download className="w-4 h-4 mr-1" />Baixar meus dados</Button>
          <Button variant="outline" className="border-red-400/40 bg-transparent text-red-200 hover:bg-red-500/10" onClick={onExcluir}><Trash2 className="w-4 h-4 mr-1" />Excluir meu perfil</Button>
        </div>
      </div>
    </div>
  );
}

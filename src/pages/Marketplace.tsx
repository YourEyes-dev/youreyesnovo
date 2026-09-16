import { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { motion } from "framer-motion";
import { Search, Store, MessageSquare, History, Locate, Sparkles, Bell, X, Loader2, UserPlus, Package, Shield, ShieldCheck } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { useAuthContext } from "@/contexts/AuthContext";
import { useMarketplace, type MarketplaceContratacao } from "@/hooks/useMarketplace";
import { useMarketYEBusca, useMarketYECategorias, useMarketYEAcoes, type MarketYEAnuncio, type MarketYEFiltros } from "@/hooks/useMarketYE";
import { marketyeIA } from "@/hooks/useMarketYEPortal";
import { AnuncioCard } from "@/components/marketplace/AnuncioCard";
import { LeadModal } from "@/components/marketplace/LeadModal";
import { ConversasLeads } from "@/components/marketplace/ConversasLeads";
import { ContratacoesList } from "@/components/marketplace/ContratacoesList";
import { ConfirmacaoExecucaoModal } from "@/components/marketplace/ConfirmacaoExecucaoModal";
import { AvaliacaoModal } from "@/components/marketplace/AvaliacaoModal";
import { DenunciaForm } from "@/components/marketplace/DenunciaForm";
import { PacotesServicos } from "@/components/marketplace/PacotesServicos";
import { ProfissionalFormModal } from "@/components/marketplace/ProfissionalFormModal";

const UFS = ["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"];
const RELAX_LABEL: Record<string, string> = { raio: "ampliamos o raio", cidade: "incluímos outras cidades", modalidade: "incluímos atendimento remoto", uf: "incluímos outros estados", nota_min: "relaxamos a nota mínima" };

export default function Marketplace() {
  const queryClient = useQueryClient();
  const { isSuperAdmin, especialistaId, tenantId } = useAuthContext();
  const [params, setParams] = useSearchParams();
  const { data: cats } = useMarketYECategorias();
  const { abrirLead, registrarBusca } = useMarketYEAcoes();
  const { contratacoes } = useMarketplace();

  const [activeTab, setActiveTab] = useState(params.get("aba") || "vitrine");
  const [busca, setBusca] = useState(params.get("q") || "");
  const [filtros, setFiltros] = useState<MarketYEFiltros>(() => {
    const f: MarketYEFiltros = {};
    if (params.get("categoria")) f.categoria_slug = params.get("categoria")!;
    if (params.get("obrigacao")) f.obrigacoes = [params.get("obrigacao")!];
    if (params.get("q")) f.q = params.get("q")!;
    return f;
  });
  const origem = useMemo(() => ({ modulo: params.get("origem"), id: params.get("origem_id"), obrigacao: params.get("obrigacao") }), [params]);
  const [anuncioSel, setAnuncioSel] = useState<MarketYEAnuncio | null>(null);
  const [denunciaTarget, setDenunciaTarget] = useState<{ id: string; nome: string } | null>(null);
  const [showProfissionalForm, setShowProfissionalForm] = useState(false);
  const [contratacaoParaConfirmar, setContratacaoParaConfirmar] = useState<MarketplaceContratacao | null>(null);
  const [contratacaoParaAvaliar, setContratacaoParaAvaliar] = useState<MarketplaceContratacao | null>(null);
  const [localizando, setLocalizando] = useState(false);
  const [interpretando, setInterpretando] = useState(false);
  const [avisoPedido, setAvisoPedido] = useState(false);

  const { data: resultado, isLoading, isFetching, isError: buscaFalhou, error: buscaErro, refetch: buscarDeNovo } = useMarketYEBusca(filtros, activeTab === "vitrine");
  const resultados = resultado?.resultados ?? [];

  // Busca vazia/rala vira sinal de demanda latente (RN-023 / 6.3).
  useEffect(() => {
    if (!resultado || !tenantId) return;
    if (resultado.oferta_insuficiente && (filtros.categoria_id || filtros.categoria_slug || filtros.q)) {
      const catId = filtros.categoria_id ?? cats?.todas.find((c) => c.slug === filtros.categoria_slug)?.id ?? null;
      registrarBusca.mutate({ categoria_id: catId, uf: filtros.uf ?? (resultado.filtros_aplicados.uf as string | undefined) ?? null, cidade: filtros.cidade ?? null, termos: filtros.q ?? null, resultados: resultado.total });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resultado?.total, resultado?.oferta_insuficiente]);

  const aplicarBusca = () => setFiltros((f) => ({ ...f, q: busca.trim() || undefined }));
  const set = (k: keyof MarketYEFiltros, v: unknown) => setFiltros((f) => ({ ...f, [k]: v === "" || v === "todos" ? undefined : v }));
  const limpar = () => { setFiltros({}); setBusca(""); setParams({}); };

  const interpretarIA = async () => {
    if (!busca.trim()) return;
    setInterpretando(true);
    try {
      const r = await marketyeIA<{ categoria_slug?: string; modalidade?: string; uf?: string; cidade?: string; termos?: string; somente_remoto?: boolean; obrigacoes?: string[] }>("interpretar_busca", { texto: busca, categorias: (cats?.raizes ?? []).map((c) => ({ slug: c.slug, nome: c.nome, obrigacao_legal: c.obrigacao_legal })) });
      setFiltros((f) => ({ ...f, q: r.termos || undefined, categoria_slug: r.categoria_slug || f.categoria_slug, modalidade: r.modalidade || f.modalidade, uf: r.uf || f.uf, cidade: r.cidade || f.cidade, somente_remoto: r.somente_remoto ?? f.somente_remoto, obrigacoes: r.obrigacoes?.length ? r.obrigacoes : f.obrigacoes }));
      toast.success("Entendi o pedido e apliquei os filtros.");
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); aplicarBusca(); } finally { setInterpretando(false); }
  };

  const ativarLocalizacao = () => {
    if (!navigator.geolocation) return toast.error("Seu navegador não suporta geolocalização");
    setLocalizando(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => { setFiltros((f) => ({ ...f, lat: pos.coords.latitude, lng: pos.coords.longitude, raio_km: f.raio_km ?? 100 })); setLocalizando(false); toast.success("Proximidade ativada a partir da sua posição."); },
      () => { setLocalizando(false); toast.error("Não foi possível obter sua localização"); },
    );
  };

  const pedirAviso = () => {
    const catId = filtros.categoria_id ?? cats?.todas.find((c) => c.slug === filtros.categoria_slug)?.id ?? null;
    registrarBusca.mutate({ categoria_id: catId, uf: filtros.uf ?? null, cidade: filtros.cidade ?? null, termos: filtros.q ?? null, resultados: resultado?.total ?? 0, avisar: true }, { onSuccess: () => { setAvisoPedido(true); toast.success("Combinado: avisaremos quando houver especialista para isso na sua região."); } });
  };

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ["marketye-busca"] });
    queryClient.invalidateQueries({ queryKey: ["marketplace-contratacoes"] });
  };
  const categoriaAtual = cats?.todas.find((c) => c.id === filtros.categoria_id || (filtros.categoria_slug && c.slug === filtros.categoria_slug));

  return (
    <div className="space-y-6" data-testid="marketye-vitrine">
      <motion.div initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-slate-900 via-indigo-950 to-violet-950 p-8 text-white">
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <div className="absolute -top-32 -right-32 w-64 h-64 bg-indigo-500/10 rounded-full blur-3xl animate-pulse" />
          <div className="absolute -bottom-20 -left-20 w-48 h-48 bg-violet-500/10 rounded-full blur-3xl animate-pulse [animation-delay:1s]" />
        </div>
        <div className="relative z-10">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-indigo-500 to-violet-600 flex items-center justify-center shadow-lg shadow-indigo-500/30"><Store className="h-6 w-6" /></div>
            <div>
              <h1 className="text-2xl font-bold bg-gradient-to-r from-white to-indigo-200 bg-clip-text text-transparent" data-testid="marketye-titulo">MarketYE</h1>
              <p className="text-indigo-300/80 text-sm">Encontre quem presta serviço para a sua empresa: treinamentos, consultorias, saúde, segurança, contabilidade, manutenção e mais</p>
            </div>
          </div>
          <p className="text-sm text-indigo-200/60 mt-3 max-w-2xl">
            Escreva o que você precisa, escolha um especialista e converse por aqui. A lista é ordenada pelo que faz mais sentido para a sua empresa; a conversa fica registrada e, quando o serviço estiver combinado, você avalia. Quem faz o serviço é o especialista; o YourEyes faz o encontro.
          </p>
          <div className="flex gap-2 mt-4 flex-wrap">
            {!especialistaId && <Button size="sm" onClick={() => setShowProfissionalForm(true)} className="bg-white/10 text-white border border-white/20 hover:bg-white/20"><UserPlus className="h-4 w-4 mr-1.5" />Sou especialista: quero me cadastrar</Button>}
            {especialistaId && <Button asChild size="sm" className="bg-white/10 text-white border border-white/20 hover:bg-white/20"><a href={`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketye/portal`}>Meu portal de especialista</a></Button>}
            <Button asChild size="sm" variant="ghost" className="text-indigo-200 hover:text-white hover:bg-white/10"><a href={`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketye`} target="_blank" rel="noreferrer">Conheço um especialista: indicar o MarketYE</a></Button>
          </div>
        </div>
      </motion.div>

      {isSuperAdmin && (
        <div className="mb-3 text-xs text-muted-foreground flex items-center gap-2" data-testid="marketye-aviso-admin">
          <Shield className="h-3.5 w-3.5" />Aqui você vê o MarketYE como uma empresa cliente. A administração (aprovar cadastros, denúncias, ajustes) fica em <Link to="/admin/marketye" className="underline underline-offset-2 font-medium">Super Admin → MarketYE</Link>.
        </div>
      )}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList className="flex-wrap">
          <TabsTrigger value="vitrine" className="gap-1.5"><Search className="h-4 w-4" /> Encontrar especialista</TabsTrigger>
          <TabsTrigger value="conversas" className="gap-1.5" data-testid="aba-conversas"><MessageSquare className="h-4 w-4" /> Minhas conversas</TabsTrigger>
          <TabsTrigger value="contratacoes" className="gap-1.5"><History className="h-4 w-4" /> Serviços contratados</TabsTrigger>
          <TabsTrigger value="pacotes" className="gap-1.5"><Package className="h-4 w-4" /> Pacotes</TabsTrigger>
        </TabsList>

        <TabsContent value="vitrine" className="mt-4 space-y-4">
          <div className="flex gap-2 flex-wrap">
            <div className="relative flex-1 min-w-[240px]">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input placeholder='Diga o que precisa: "preciso de um treinamento de NR-35" ou "manutenção de ar-condicionado"' value={busca} onChange={(e) => setBusca(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") aplicarBusca(); }} className="pl-10" data-testid="marketye-busca" />
            </div>
            <Button variant="outline" onClick={aplicarBusca} data-testid="marketye-buscar">Buscar</Button>
            <Button variant="outline" onClick={interpretarIA} disabled={interpretando || !busca.trim()} title="A IA traduz o pedido em categoria e filtros">{interpretando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Sparkles className="h-4 w-4" />}<span className="ml-1.5 hidden sm:inline">Entender com IA</span></Button>
            <Button variant={filtros.lat ? "default" : "outline"} onClick={ativarLocalizacao} disabled={localizando} className="gap-1.5"><Locate className="h-4 w-4" />{localizando ? "Localizando..." : filtros.lat ? "Perto de mim" : "Perto de mim"}</Button>
          </div>

          <div className="flex gap-2 flex-wrap items-center" data-testid="marketye-filtros">
            <Select value={filtros.categoria_slug ?? categoriaAtual?.slug ?? "todos"} onValueChange={(v) => { set("categoria_id", undefined); set("categoria_slug", v); }}>
              <SelectTrigger className="w-[220px]" data-testid="filtro-categoria"><SelectValue placeholder="Área" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todos">Todas as áreas</SelectItem>
                {(cats?.raizes ?? []).map((r) => <SelectItem key={r.id} value={r.slug ?? r.id}>{r.nome}</SelectItem>)}
                {categoriaAtual?.pai_id && <SelectItem value={categoriaAtual.slug ?? categoriaAtual.id}>{categoriaAtual.nome}</SelectItem>}
              </SelectContent>
            </Select>
            <Select value={filtros.modalidade ?? "todos"} onValueChange={(v) => set("modalidade", v)}>
              <SelectTrigger className="w-[150px]"><SelectValue placeholder="Modalidade" /></SelectTrigger>
              <SelectContent><SelectItem value="todos">Qualquer modalidade</SelectItem><SelectItem value="presencial">Presencial</SelectItem><SelectItem value="online">Remoto</SelectItem><SelectItem value="hibrido">Híbrido</SelectItem></SelectContent>
            </Select>
            <Select value={filtros.uf ?? "todos"} onValueChange={(v) => setFiltros((f) => ({ ...f, uf: v === "todos" ? undefined : v, ignorar_uf_padrao: v === "todos" ? true : undefined }))}>
              <SelectTrigger className="w-[110px]"><SelectValue placeholder="UF" /></SelectTrigger>
              <SelectContent><SelectItem value="todos">Todo o país</SelectItem>{UFS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
            </Select>
            <Select value={filtros.nota_min ? String(filtros.nota_min) : "todos"} onValueChange={(v) => set("nota_min", v === "todos" ? undefined : Number(v))}>
              <SelectTrigger className="w-[140px]"><SelectValue placeholder="Nota mínima" /></SelectTrigger>
              <SelectContent><SelectItem value="todos">Qualquer nota</SelectItem><SelectItem value="4.5">4,5+</SelectItem><SelectItem value="4">4,0+</SelectItem><SelectItem value="3.5">3,5+</SelectItem></SelectContent>
            </Select>
            <Select value={filtros.nivel_min ?? "todos"} onValueChange={(v) => set("nivel_min", v)}>
              <SelectTrigger className="w-[170px]"><SelectValue placeholder="Experiência" /></SelectTrigger>
              <SelectContent><SelectItem value="todos">Qualquer experiência aqui</SelectItem><SelectItem value="bronze">Bronze ou mais</SelectItem><SelectItem value="prata">Prata ou mais</SelectItem><SelectItem value="ouro">Ouro ou mais</SelectItem><SelectItem value="top">Só Especialista Top</SelectItem></SelectContent>
            </Select>
            <Button variant={filtros.selo ? "default" : "outline"} size="sm" onClick={() => set("selo", !filtros.selo)}><ShieldCheck className="h-4 w-4 mr-1" />Só com dados verificados</Button>
            <Button variant={filtros.somente_remoto ? "default" : "outline"} size="sm" onClick={() => set("somente_remoto", !filtros.somente_remoto)}>Atende remoto</Button>
            <Input type="number" placeholder="Preço máx." className="w-[120px]" value={filtros.preco_max ?? ""} onChange={(e) => set("preco_max", e.target.value ? Number(e.target.value) : undefined)} />
            {(Object.keys(filtros).length > 0 || busca) && <Button variant="ghost" size="sm" onClick={limpar}><X className="h-4 w-4 mr-1" />Limpar</Button>}
          </div>

          {filtros.obrigacoes?.length ? (
            <div className="rounded-xl bg-indigo-50 border border-indigo-200 p-3 text-sm text-indigo-900 flex items-center gap-2 flex-wrap">
              <Sparkles className="h-4 w-4" /> Priorizando especialistas para <b>{filtros.obrigacoes.join(", ")}</b>{origem.modulo ? ` (vindo de ${origem.modulo})` : ""}.
              <Button variant="link" size="sm" className="h-auto p-0" onClick={() => set("obrigacoes", undefined)}>remover</Button>
            </div>
          ) : null}

          {resultado && resultado.relaxamentos.length > 0 && (
            <div className="rounded-xl bg-amber-50 border border-amber-200 p-3 text-sm text-amber-900" data-testid="marketye-relaxamento">
              Poucos resultados com os filtros exatos: {resultado.relaxamentos.map((r) => RELAX_LABEL[r] ?? r).join(", ")} para mostrar mais opções.
            </div>
          )}

          {isLoading ? (
            <div className="text-center py-12 text-muted-foreground text-sm">Buscando especialistas...</div>
          ) : buscaFalhou ? (
            // Erro de busca não pode parecer "não tem ninguém": mostra o motivo e deixa tentar de novo.
            <div className="rounded-2xl border border-amber-200 bg-amber-50 p-6 text-center space-y-2" data-testid="marketye-erro">
              <p className="font-medium text-amber-900">Não conseguimos buscar agora.</p>
              <p className="text-xs text-amber-800 break-words">{buscaErro instanceof Error ? buscaErro.message : String((buscaErro as { message?: string })?.message ?? buscaErro ?? "")}</p>
              <Button variant="outline" size="sm" onClick={() => buscarDeNovo()}>Tentar de novo</Button>
            </div>
          ) : resultados.length === 0 ? (
            <div className="rounded-2xl border border-dashed p-8 text-center space-y-3" data-testid="marketye-vazio">
              <Store className="h-12 w-12 mx-auto text-muted-foreground/30" />
              <p className="font-medium">Ainda não temos {categoriaAtual ? categoriaAtual.nome : "essa oferta"}{filtros.uf ? ` em ${filtros.uf}` : ""} com esses filtros.</p>
              <p className="text-sm text-muted-foreground">Sua busca já nos avisou que falta gente nessa área. Quer receber um aviso quando alguém entrar?</p>
              <div className="flex gap-2 justify-center flex-wrap">
                <Button variant="outline" onClick={pedirAviso} disabled={avisoPedido || !tenantId} data-testid="marketye-avise-me"><Bell className="h-4 w-4 mr-1.5" />{avisoPedido ? "Aviso registrado" : "Avise-me quando houver"}</Button>
                {!filtros.somente_remoto && <Button variant="outline" onClick={() => setFiltros((f) => ({ ...f, somente_remoto: true, uf: undefined, ignorar_uf_padrao: true, cidade: undefined }))}>Ver quem atende remoto</Button>}
                {(filtros.categoria_slug || filtros.categoria_id) && <Button variant="ghost" onClick={() => { set("categoria_slug", undefined); set("categoria_id", undefined); }}>Ver todas as categorias</Button>}
              </div>
              {resultado && resultado.categorias_adjacentes.length > 0 && (
                <div className="text-xs text-muted-foreground">Áreas parecidas: {resultado.categorias_adjacentes.map((c) => <Button key={c.id} variant="link" size="sm" className="h-auto p-0 px-1 text-xs" onClick={() => set("categoria_slug", c.slug)}>{c.nome}</Button>)}</div>
              )}
            </div>
          ) : (
            <>
              <div className="flex items-center justify-between text-xs text-muted-foreground">
                <span>{resultado?.total} serviço(s) · os mais indicados para a sua empresa primeiro{isFetching ? " · atualizando..." : ""}</span>
                {resultado?.oferta_insuficiente && <Badge variant="outline" className="text-[10px]">ainda temos poucos especialistas nesta área</Badge>}
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4" data-testid="marketye-resultados">
                {resultados.map((a) => <AnuncioCard key={a.servico_id} anuncio={a} onContatar={setAnuncioSel} onDenunciar={(id, nome) => setDenunciaTarget({ id, nome })} />)}
              </div>
              {resultado?.oferta_insuficiente && (
                <div className="rounded-xl border border-dashed p-4 text-sm flex items-center justify-between gap-3 flex-wrap">
                  <span className="text-muted-foreground">Poucas opções nesta área. Quer ser avisado quando entrarem novos especialistas?</span>
                  <Button variant="outline" size="sm" onClick={pedirAviso} disabled={avisoPedido || !tenantId}><Bell className="h-4 w-4 mr-1.5" />{avisoPedido ? "Aviso registrado" : "Avise-me"}</Button>
                </div>
              )}
            </>
          )}
        </TabsContent>

        <TabsContent value="conversas" className="mt-4"><ConversasLeads /></TabsContent>
        <TabsContent value="contratacoes" className="mt-4"><ContratacoesList contratacoes={contratacoes} onConfirmarExecucao={setContratacaoParaConfirmar} onAvaliar={setContratacaoParaAvaliar} /></TabsContent>
        <TabsContent value="pacotes" className="mt-4"><PacotesServicos /></TabsContent>
      </Tabs>

      <div className="mt-6 rounded-xl border border-dashed p-4 flex flex-wrap items-center justify-between gap-3" data-testid="marketplace-convite-parceiro">
        <div>
          <div className="font-semibold">Especialista? Você também pode ser parceiro do canal de vendas</div>
          <div className="text-sm text-muted-foreground">Uma identidade, dois papéis: indicar empresas dá comissão no Programa de Parceiros; ofertar serviços é aqui no MarketYE. Contas e ganhos ficam separados.</div>
        </div>
        <Button asChild variant="outline"><a href={`${import.meta.env.BASE_URL.replace(/\/$/, "")}/parceiros`}>Conhecer o Programa de Parceiros</a></Button>
      </div>

      <LeadModal anuncio={anuncioSel} open={!!anuncioSel} onClose={() => setAnuncioSel(null)} isLoading={abrirLead.isPending} origem={origem}
        onEnviar={(mensagem) => anuncioSel && abrirLead.mutate({ profissional_id: anuncioSel.profissional.id, servico_id: anuncioSel.servico_id, mensagem, origem_modulo: origem.modulo, origem_id: origem.id, obrigacao: origem.obrigacao ?? anuncioSel.obrigacao_legal?.[0] ?? null }, { onSuccess: () => { setAnuncioSel(null); setActiveTab("conversas"); } })} />
      <ProfissionalFormModal open={showProfissionalForm} onClose={() => setShowProfissionalForm(false)} onSuccess={invalidateAll} />
      <ConfirmacaoExecucaoModal contratacao={contratacaoParaConfirmar} open={!!contratacaoParaConfirmar} onClose={() => setContratacaoParaConfirmar(null)} onSuccess={invalidateAll} />
      <AvaliacaoModal contratacao={contratacaoParaAvaliar} open={!!contratacaoParaAvaliar} onClose={() => setContratacaoParaAvaliar(null)} onSuccess={invalidateAll} />
      {denunciaTarget && <DenunciaForm profissionalId={denunciaTarget.id} profissionalNome={denunciaTarget.nome} open={!!denunciaTarget} onClose={() => setDenunciaTarget(null)} onSuccess={invalidateAll} />}
    </div>
  );
}

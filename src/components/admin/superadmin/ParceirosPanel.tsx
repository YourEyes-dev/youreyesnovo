import { useEffect, useMemo, useState } from "react";
import {
  useParceiros, useParceiroDetalhe, useParceiroComissoes, linkDoParceiro,
  PARCEIRO_TIPO_LABEL, PARCEIRO_STATUS_LABEL, PARCEIRO_TRILHA_LABEL, TRILHA_PADRAO,
  type Parceiro, type ParceiroTipo, type ParceiroStatus, type ParceiroNivel, type ParceiroEventoRemuneracao,
} from "@/hooks/useParceiros";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { confirm } from "@/components/ui/confirm-dialog";
import { toast } from "sonner";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import {
  Handshake, Plus, Search, CheckCircle, PauseCircle, XCircle, Link2, Copy, Users, Building2,
  Target, Settings2, Save, Loader2, MapPin, RotateCcw, Wallet, Play, Lock,
} from "lucide-react";
import { Textarea as TextareaUi } from "@/components/ui/textarea";
import type { ParceiroComissao } from "@/hooks/useParceiros";

const STATUS_VARIANT: Record<ParceiroStatus, "default" | "secondary" | "destructive" | "outline"> = {
  ativo: "default", pendente: "secondary", suspenso: "outline", encerrado: "destructive",
};
const TIPOS = Object.keys(PARCEIRO_TIPO_LABEL) as ParceiroTipo[];
const UFS = ["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"];

function centsToReais(c: number) { return (Number(c || 0) / 100).toFixed(2).replace(".", ","); }
function reaisToCents(s: string) {
  const n = parseFloat((s || "").replace(/\./g, "").replace(",", "."));
  return Number.isFinite(n) ? Math.max(Math.round(n * 100), 0) : 0;
}
function dataBr(d?: string | null) { return d ? format(new Date(d), "dd/MM/yyyy", { locale: ptBR }) : "—"; }

// ─────────────────────────────────────────────────────────────────────────────
export function ParceirosPanel() {
  const { parceiros, isLoading, isError, mudarStatus } = useParceiros();
  const [busca, setBusca] = useState("");
  const [filtroStatus, setFiltroStatus] = useState<string>("todos");
  const [editando, setEditando] = useState<Parceiro | null | undefined>(undefined); // undefined = fechado; null = novo
  const [detalheId, setDetalheId] = useState<string | null>(null);

  const filtrados = useMemo(() => {
    const q = busca.trim().toLowerCase();
    return parceiros.filter((p) =>
      (filtroStatus === "todos" || p.status === filtroStatus) &&
      (!q || p.nome.toLowerCase().includes(q) || p.codigo.toLowerCase().includes(q) ||
        (p.cidade || "").toLowerCase().includes(q) || (p.email || "").toLowerCase().includes(q)));
  }, [parceiros, busca, filtroStatus]);

  const pendentes = parceiros.filter((p) => p.status === "pendente").length;

  const aprovar = async (p: Parceiro) => {
    if (await confirm({ title: `Aprovar ${p.nome}?`, description: "O contrato de parceria é gerado na hora e o parceiro recebe um e-mail para assinar. O link de indicação só é liberado depois da assinatura." }))
      mudarStatus.mutate({ id: p.id, status: "ativo", email: p.email, nome: p.nome });
  };
  const recusar = async (p: Parceiro) => {
    if (await confirm({ title: `Recusar o cadastro de ${p.nome}?`, description: "O cadastro é encerrado e o parceiro recebe um e-mail informando. Ele pode falar com a equipe para reavaliar." }))
      mudarStatus.mutate({ id: p.id, status: "encerrado", motivo: "Cadastro não aprovado pela equipe YourEyes", email: p.email, nome: p.nome });
  };
  const suspender = async (p: Parceiro) => {
    if (await confirm({ title: `Suspender ${p.nome}?`, description: "O parceiro deixa de ser sugerido e de gerar comissão nova. A carteira dele fica preservada." }))
      mudarStatus.mutate({ id: p.id, status: "suspenso", motivo: "Suspenso pelo SuperAdmin", email: p.email, nome: p.nome });
  };
  const encerrar = async (p: Parceiro) => {
    if (await confirm({ title: `Encerrar ${p.nome}?`, description: "Encerramento é definitivo para o programa. Os clientes que ele originou continuam existindo normalmente." }))
      mudarStatus.mutate({ id: p.id, status: "encerrado", motivo: "Encerrado pelo SuperAdmin", email: p.email, nome: p.nome });
  };
  const reativar = (p: Parceiro) => mudarStatus.mutate({ id: p.id, status: "ativo", email: p.email, nome: p.nome });

  return (
    <div className="space-y-6" data-testid="parceiros-panel">
      <Tabs defaultValue="lista">
        <TabsList>
          <TabsTrigger value="lista"><Handshake className="w-4 h-4 mr-2" />Parceiros{pendentes > 0 && <Badge variant="secondary" className="ml-2">{pendentes} pendente{pendentes > 1 ? "s" : ""}</Badge>}</TabsTrigger>
          <TabsTrigger value="empresas"><Building2 className="w-4 h-4 mr-2" />Origem das empresas</TabsTrigger>
          <TabsTrigger value="config"><Settings2 className="w-4 h-4 mr-2" />Níveis e remuneração</TabsTrigger>
          <TabsTrigger value="comissoes" data-testid="tab-comissoes"><Wallet className="w-4 h-4 mr-2" />Comissões</TabsTrigger>
        </TabsList>

        <TabsContent value="lista" className="mt-4">
          <Card>
            <CardHeader>
              <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
                <div>
                  <CardTitle>Programa de Parceiros</CardTitle>
                  <CardDescription>Indicadores, representantes, implantadores, clínicas e contabilidades que trazem e atendem clientes.</CardDescription>
                </div>
                <Button onClick={() => setEditando(null)}><Plus className="w-4 h-4 mr-2" />Novo parceiro</Button>
              </div>
              <div className="flex flex-col sm:flex-row gap-2 mt-3">
                <div className="relative flex-1">
                  <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
                  <Input className="pl-9" placeholder="Buscar por nome, código, cidade ou e-mail" value={busca} onChange={(e) => setBusca(e.target.value)} />
                </div>
                <Select value={filtroStatus} onValueChange={setFiltroStatus}>
                  <SelectTrigger className="w-full sm:w-44"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="todos">Todos os status</SelectItem>
                    {(Object.keys(PARCEIRO_STATUS_LABEL) as ParceiroStatus[]).map((s) => <SelectItem key={s} value={s}>{PARCEIRO_STATUS_LABEL[s]}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </CardHeader>
            <CardContent>
              {isLoading ? (
                <div className="space-y-2">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-10 w-full" />)}</div>
              ) : isError ? (
                <p className="text-sm text-destructive">Não foi possível carregar os parceiros. A estrutura do programa já foi aplicada neste ambiente?</p>
              ) : filtrados.length === 0 ? (
                <p className="text-sm text-muted-foreground py-8 text-center">Nenhum parceiro {parceiros.length ? "com esse filtro" : "cadastrado ainda"}.</p>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Parceiro</TableHead>
                        <TableHead>Tipo</TableHead>
                        <TableHead>Região</TableHead>
                        <TableHead>Nível</TableHead>
                        <TableHead className="text-right">Clientes</TableHead>
                        <TableHead className="text-right">Leads</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Ações</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filtrados.map((p) => (
                        <TableRow key={p.id} className="cursor-pointer" onClick={() => setDetalheId(p.id)} data-testid="parceiro-linha">
                          <TableCell>
                            <div className="font-medium">{p.nome}</div>
                            <div className="text-xs text-muted-foreground font-mono">{p.codigo}{p.usuarios ? ` · ${p.usuarios}` : ""}</div>
                          </TableCell>
                          <TableCell>{PARCEIRO_TIPO_LABEL[p.tipo_parceiro]}<div className="text-[11px] text-muted-foreground">trilha {PARCEIRO_TRILHA_LABEL[p.trilha] ?? p.trilha}</div></TableCell>
                          <TableCell className="text-sm">{[p.cidade, p.uf].filter(Boolean).join(" / ") || "—"}</TableCell>
                          <TableCell className="text-sm">{p.nivel_nome || "—"}</TableCell>
                          <TableCell className="text-right">{p.total_clientes}{p.total_implantacoes ? <span className="text-xs text-muted-foreground"> +{p.total_implantacoes} impl.</span> : null}</TableCell>
                          <TableCell className="text-right">{p.total_leads}</TableCell>
                          <TableCell><Badge variant={STATUS_VARIANT[p.status]}>{PARCEIRO_STATUS_LABEL[p.status]}</Badge></TableCell>
                          <TableCell className="text-right" onClick={(e) => e.stopPropagation()}>
                            <div className="flex justify-end gap-1">
                              {p.status === "pendente" && <Button size="sm" onClick={() => aprovar(p)} data-testid="parceiro-aprovar"><CheckCircle className="w-4 h-4 mr-1" />Aprovar</Button>}
                              {p.status === "pendente" && <Button size="sm" variant="outline" onClick={() => recusar(p)} data-testid="parceiro-recusar">Recusar</Button>}
                              {p.status === "ativo" && <Button size="sm" variant="ghost" title="Suspender" onClick={() => suspender(p)}><PauseCircle className="w-4 h-4" /></Button>}
                              {(p.status === "suspenso") && <Button size="sm" variant="ghost" title="Reativar" onClick={() => reativar(p)}><RotateCcw className="w-4 h-4" /></Button>}
                              {p.status !== "encerrado" && <Button size="sm" variant="ghost" title="Encerrar" onClick={() => encerrar(p)}><XCircle className="w-4 h-4 text-destructive" /></Button>}
                              <Button size="sm" variant="outline" onClick={() => setEditando(p)}>Editar</Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="empresas" className="mt-4"><OrigemEmpresas /></TabsContent>
        <TabsContent value="config" className="mt-4"><ConfiguracaoPrograma /></TabsContent>
        <TabsContent value="comissoes" className="mt-4"><ComissoesPainel /></TabsContent>
      </Tabs>

      <ParceiroFormDialog open={editando !== undefined} parceiro={editando ?? null} onClose={() => setEditando(undefined)} />
      <ParceiroDetalheSheet parceiro={parceiros.find((p) => p.id === detalheId) ?? null} onClose={() => setDetalheId(null)} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
function ParceiroFormDialog({ open, parceiro, onClose }: { open: boolean; parceiro: Parceiro | null; onClose: () => void }) {
  const { salvar, niveis } = useParceiros();
  const [form, setForm] = useState<Partial<Parceiro>>({});
  useEffect(() => {
    if (open) setForm(parceiro ? { ...parceiro } : { tipo_parceiro: "indicador", tipo_pessoa: "pj", trilha: "indicador", raio_atuacao_km: 50 });
  }, [open, parceiro]);
  const set = <K extends keyof Parceiro>(k: K, v: Parceiro[K]) => setForm((f) => ({ ...f, [k]: v }));
  const novoIndicador = !parceiro && form.tipo_parceiro === "indicador" && (form.trilha ?? "indicador") === "indicador";

  const submit = async () => {
    if (!form.nome?.trim()) return toast.error("Informe o nome");
    await salvar.mutateAsync(form);
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{parceiro ? "Editar parceiro" : "Novo parceiro"}</DialogTitle>
          <DialogDescription>
            {novoIndicador
              ? "Indicador entra ativo automaticamente. Os demais tipos nascem pendentes e esperam a sua aprovação."
              : "Representante e Operador nascem pendentes e esperam aprovação e certificação."}
          </DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="col-span-2"><Label>Nome*</Label><Input data-testid="parceiro-nome" value={form.nome || ""} onChange={(e) => set("nome", e.target.value)} /></div>
          <div><Label>Tipo de parceiro</Label>
            <Select value={form.tipo_parceiro} onValueChange={(v) => set("tipo_parceiro", v as ParceiroTipo)}>
              <SelectTrigger data-testid="parceiro-tipo"><SelectValue /></SelectTrigger>
              <SelectContent>{TIPOS.map((t) => <SelectItem key={t} value={t}>{PARCEIRO_TIPO_LABEL[t]}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div><Label>Código do link {parceiro ? "" : "(opcional, gerado do nome)"}</Label>
            <Input className="font-mono uppercase" disabled={!!parceiro} value={form.codigo || ""} onChange={(e) => set("codigo", e.target.value.toUpperCase())} placeholder="CLINICAVIDA" /></div>
          <div><Label>Pessoa</Label>
            <Select value={form.tipo_pessoa} onValueChange={(v) => set("tipo_pessoa", v as "pf" | "pj")}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value="pj">Jurídica (CNPJ)</SelectItem><SelectItem value="pf">Física (CPF)</SelectItem></SelectContent>
            </Select>
          </div>
          <div><Label>{form.tipo_pessoa === "pf" ? "CPF" : "CNPJ"}</Label><Input value={form.documento || ""} onChange={(e) => set("documento", e.target.value)} /></div>
          <div><Label>E-mail</Label><Input type="email" value={form.email || ""} onChange={(e) => set("email", e.target.value)} /></div>
          <div><Label>Telefone</Label><Input value={form.telefone || ""} onChange={(e) => set("telefone", e.target.value)} /></div>
          <div><Label>Cidade</Label><Input value={form.cidade || ""} onChange={(e) => set("cidade", e.target.value)} /></div>
          <div className="grid grid-cols-2 gap-2">
            <div><Label>UF</Label>
              <Select value={form.uf || ""} onValueChange={(v) => set("uf", v)}>
                <SelectTrigger><SelectValue placeholder="UF" /></SelectTrigger>
                <SelectContent>{UFS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div><Label>CEP</Label><Input value={form.cep || ""} onChange={(e) => set("cep", e.target.value)} /></div>
          </div>
          <div><Label>Raio de atuação (km)</Label><Input type="number" min={0} value={form.raio_atuacao_km ?? 50} onChange={(e) => set("raio_atuacao_km", Number(e.target.value))} /></div>
          <div><Label>Trilha (define a matriz de comissão)</Label>
            <Select value={form.trilha || TRILHA_PADRAO[form.tipo_parceiro ?? "indicador"]} onValueChange={(v) => set("trilha", v as Parceiro["trilha"])}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{(Object.keys(PARCEIRO_TRILHA_LABEL) as Parceiro["trilha"][]).map((t) => <SelectItem key={t} value={t}>{PARCEIRO_TRILHA_LABEL[t]}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          {parceiro && (
            <div><Label>Nível</Label>
              <Select value={form.nivel_id || ""} onValueChange={(v) => set("nivel_id", v)}>
                <SelectTrigger><SelectValue placeholder="Automático" /></SelectTrigger>
                <SelectContent>{niveis.filter((n) => n.trilha === (form.trilha || "operador")).map((n) => <SelectItem key={n.id} value={n.id!}>{n.nome}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          )}
          <div><Label>% de comissão (override, opcional)</Label><Input type="number" step="0.01" value={form.percentual_comissao ?? ""} onChange={(e) => set("percentual_comissao", e.target.value === "" ? null : Number(e.target.value))} placeholder="usa o do nível" /></div>
          <div><Label>Chave PIX (pagamento)</Label><Input value={form.pix_chave || ""} onChange={(e) => set("pix_chave", e.target.value)} /></div>
          <div className="col-span-2"><Label>Observações</Label><Textarea rows={2} value={form.observacoes || ""} onChange={(e) => set("observacoes", e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button onClick={submit} disabled={salvar.isPending} data-testid="parceiro-salvar">{salvar.isPending && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
function ParceiroDetalheSheet({ parceiro, onClose }: { parceiro: Parceiro | null; onClose: () => void }) {
  const { data, isLoading } = useParceiroDetalhe(parceiro?.id ?? null);
  const { vincularUsuario, desvincularUsuario, criarLink, alternarLink, vincularTenant, tenants } = useParceiros();
  const [email, setEmail] = useState("");
  const [campanha, setCampanha] = useState("");
  const [tenantId, setTenantId] = useState("");
  useEffect(() => { setEmail(""); setCampanha(""); setTenantId(""); }, [parceiro?.id]);

  const copiar = (codigo: string) => {
    navigator.clipboard?.writeText(linkDoParceiro(codigo));
    toast.success("Link copiado");
  };
  const semParceiro = tenants.filter((t) => !t.parceiro_id);

  return (
    <Sheet open={!!parceiro} onOpenChange={(o) => !o && onClose()}>
      <SheetContent className="w-full sm:max-w-2xl overflow-y-auto">
        {parceiro && (
          <>
            <SheetHeader>
              <SheetTitle className="flex items-center gap-2">{parceiro.nome} <Badge variant={STATUS_VARIANT[parceiro.status]}>{PARCEIRO_STATUS_LABEL[parceiro.status]}</Badge></SheetTitle>
              <SheetDescription>
                {PARCEIRO_TIPO_LABEL[parceiro.tipo_parceiro]} · trilha {PARCEIRO_TRILHA_LABEL[parceiro.trilha] ?? parceiro.trilha} · nível {parceiro.nivel_nome || "—"} · parceiro desde {dataBr(parceiro.parceiro_desde)}
                {parceiro.cidade && <span className="inline-flex items-center gap-1 ml-2"><MapPin className="w-3 h-3" />{parceiro.cidade}/{parceiro.uf} · {parceiro.raio_atuacao_km} km</span>}
                <span className="block mt-1">Contrato de Parceria: {parceiro.contrato?.pendente ? <Badge variant="outline" className="text-amber-600 border-amber-400">aceite pendente (v{parceiro.contrato?.versao_vigente ?? "?"})</Badge> : <Badge variant="secondary">v{parceiro.contrato?.versao_aceita ?? "?"} aceito em {dataBr(parceiro.contrato?.aceito_em)}</Badge>}</span>
              </SheetDescription>
            </SheetHeader>

            {isLoading || !data ? <Skeleton className="h-40 w-full mt-4" /> : (
              <div className="space-y-6 mt-4">
                <section>
                  <h3 className="text-sm font-semibold flex items-center gap-2 mb-2"><Link2 className="w-4 h-4" />Links de indicação</h3>
                  <div className="space-y-1">
                    {data.links.map((l) => (
                      <div key={l.id} className="flex items-center justify-between gap-2 border rounded-md px-3 py-2 text-sm">
                        <div className="min-w-0">
                          <code className="font-mono text-xs bg-muted px-1.5 py-0.5 rounded">?ref={l.codigo}</code>
                          <span className="text-muted-foreground ml-2">{l.campanha}</span>
                          <div className="text-xs text-muted-foreground">{l.cliques} cliques · {l.leads} leads</div>
                        </div>
                        <div className="flex items-center gap-1 shrink-0">
                          <Button size="sm" variant="ghost" onClick={() => copiar(l.codigo)} title="Copiar link"><Copy className="w-4 h-4" /></Button>
                          {l.campanha !== "principal" && <Switch checked={l.ativo} onCheckedChange={(v) => alternarLink.mutate({ linkId: l.id, ativo: v })} />}
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="flex gap-2 mt-2">
                    <Input placeholder="Nova campanha (ex.: PGR)" value={campanha} onChange={(e) => setCampanha(e.target.value)} />
                    <Button variant="outline" disabled={!campanha.trim() || criarLink.isPending} onClick={() => { criarLink.mutate({ id: parceiro.id, campanha }); setCampanha(""); }}>Gerar link</Button>
                  </div>
                </section>

                <section>
                  <h3 className="text-sm font-semibold flex items-center gap-2 mb-2"><Users className="w-4 h-4" />Acesso à Área do Parceiro</h3>
                  {data.usuarios.length === 0 && <p className="text-xs text-muted-foreground mb-2">Nenhum usuário vinculado. Vincule o e-mail de uma conta existente; a autocadastro pelo site chega na próxima etapa.</p>}
                  <div className="space-y-1">
                    {data.usuarios.map((u) => (
                      <div key={u.user_id} className="flex items-center justify-between border rounded-md px-3 py-1.5 text-sm">
                        <span>{u.email} <span className="text-xs text-muted-foreground">({u.papel})</span></span>
                        <Button size="sm" variant="ghost" onClick={() => desvincularUsuario.mutate(u.user_id)}><XCircle className="w-4 h-4" /></Button>
                      </div>
                    ))}
                  </div>
                  <div className="flex gap-2 mt-2">
                    <Input type="email" placeholder="e-mail de uma conta já existente" value={email} onChange={(e) => setEmail(e.target.value)} />
                    <Button variant="outline" disabled={!email.trim() || vincularUsuario.isPending} onClick={() => { vincularUsuario.mutate({ id: parceiro.id, email }); setEmail(""); }}>Vincular</Button>
                  </div>
                </section>

                <section>
                  <h3 className="text-sm font-semibold flex items-center gap-2 mb-2"><Building2 className="w-4 h-4" />Carteira ({data.clientes.length})</h3>
                  {data.clientes.length === 0 ? <p className="text-xs text-muted-foreground">Nenhuma empresa vinculada ainda.</p> : (
                    <Table>
                      <TableHeader><TableRow><TableHead>Empresa</TableHead><TableHead>Plano</TableHead><TableHead>Assinatura</TableHead><TableHead>Papel</TableHead><TableHead>Desde</TableHead></TableRow></TableHeader>
                      <TableBody>
                        {data.clientes.map((c) => (
                          <TableRow key={c.id}>
                            <TableCell className="font-medium">{c.nome}</TableCell>
                            <TableCell>{c.plano || "—"}</TableCell>
                            <TableCell>{c.status_assinatura || "—"}</TableCell>
                            <TableCell className="text-xs">{c.papel === "origem" ? "Indicou" : c.papel === "implantacao" ? "Implanta" : "Indicou e implanta"}</TableCell>
                            <TableCell className="text-xs">{dataBr(c.originado_em)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  )}
                  <div className="flex gap-2 mt-2">
                    <Select value={tenantId} onValueChange={setTenantId}>
                      <SelectTrigger data-testid="parceiro-vincular-empresa"><SelectValue placeholder="Vincular empresa sem parceiro de origem…" /></SelectTrigger>
                      <SelectContent>{semParceiro.map((t) => <SelectItem key={t.id} value={t.id}>{t.nome}</SelectItem>)}</SelectContent>
                    </Select>
                    <Button variant="outline" disabled={!tenantId || vincularTenant.isPending}
                      onClick={() => { vincularTenant.mutate({ tenantId, parceiroId: parceiro.id, implantadorId: tenants.find((t) => t.id === tenantId)?.implantador_parceiro_id ?? null }); setTenantId(""); }}>
                      Vincular
                    </Button>
                  </div>
                </section>

                <section>
                  <h3 className="text-sm font-semibold flex items-center gap-2 mb-2"><Target className="w-4 h-4" />Leads ({data.leads.length})</h3>
                  {data.leads.length === 0 ? <p className="text-xs text-muted-foreground">Nenhum lead atribuído. Atribua pelo Kanban de Leads (campo Parceiro).</p> : (
                    <ul className="text-sm space-y-1">
                      {data.leads.map((l) => <li key={l.id} className="flex justify-between border-b py-1"><span>{l.nome}{l.empresa ? ` · ${l.empresa}` : ""}</span><span className="text-xs text-muted-foreground">{l.status} · {l.atribuicao || "—"}</span></li>)}
                    </ul>
                  )}
                </section>
              </div>
            )}
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
function OrigemEmpresas() {
  const { tenants, parceiros, vincularTenant } = useParceiros();
  const [busca, setBusca] = useState("");
  const ativos = parceiros.filter((p) => p.status === "ativo" || p.status === "pendente");
  const implantadores = ativos.filter((p) => ["implantador", "clinica", "contabilidade", "representante"].includes(p.tipo_parceiro));
  const lista = tenants.filter((t) => !busca || t.nome.toLowerCase().includes(busca.toLowerCase()));
  const NENHUM = "__nenhum__";

  return (
    <Card>
      <CardHeader>
        <CardTitle>Origem e implantação de cada empresa</CardTitle>
        <CardDescription>Quem indicou (origem) e quem implanta cada cliente. A origem também é preenchida sozinha quando o cliente chega por link (próximas etapas).</CardDescription>
        <Input className="mt-2 max-w-sm" placeholder="Buscar empresa" value={busca} onChange={(e) => setBusca(e.target.value)} />
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <Table>
          <TableHeader><TableRow><TableHead>Empresa</TableHead><TableHead>Parceiro de origem</TableHead><TableHead>Implantador</TableHead><TableHead>Desde</TableHead></TableRow></TableHeader>
          <TableBody>
            {lista.map((t) => (
              <TableRow key={t.id}>
                <TableCell className="font-medium">{t.nome}{!t.ativo && <Badge variant="outline" className="ml-2">inativa</Badge>}</TableCell>
                <TableCell>
                  <Select value={t.parceiro_id ?? NENHUM} onValueChange={(v) => vincularTenant.mutate({ tenantId: t.id, parceiroId: v === NENHUM ? null : v, implantadorId: t.implantador_parceiro_id })}>
                    <SelectTrigger className="w-56"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={NENHUM}>— sem parceiro —</SelectItem>
                      {ativos.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </TableCell>
                <TableCell>
                  <Select value={t.implantador_parceiro_id ?? NENHUM} onValueChange={(v) => vincularTenant.mutate({ tenantId: t.id, parceiroId: t.parceiro_id, implantadorId: v === NENHUM ? null : v })}>
                    <SelectTrigger className="w-56"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={NENHUM}>— a própria casa —</SelectItem>
                      {implantadores.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </TableCell>
                <TableCell className="text-xs">{dataBr(t.originado_em)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
function ConfiguracaoPrograma() {
  const { niveis, eventos, config, salvarNiveis, salvarEventos, salvarConfig } = useParceiros();
  const [nv, setNv] = useState<ParceiroNivel[]>([]);
  const [ev, setEv] = useState<ParceiroEventoRemuneracao[]>([]);
  const [cfg, setCfg] = useState<Record<string, string>>({});
  useEffect(() => setNv(niveis.map((n) => ({ ...n }))), [niveis]);
  useEffect(() => setEv(eventos.map((e) => ({ ...e }))), [eventos]);
  useEffect(() => { const m: Record<string, string> = {}; for (const c of config) m[c.chave] = c.valor; setCfg(m); }, [config]);

  const setNivel = <K extends keyof ParceiroNivel>(id: string | undefined, k: K, v: ParceiroNivel[K]) => setNv((a) => a.map((n) => (n.id === id ? { ...n, [k]: v } : n)));
  const setEvento = <K extends keyof ParceiroEventoRemuneracao>(i: number, k: K, v: ParceiroEventoRemuneracao[K]) => setEv((a) => a.map((e, j) => (j === i ? { ...e, [k]: v } : e)));
  const TRILHAS: { key: string; label: string; quem: string }[] = [
    { key: "indicador", label: "Indicador", quem: "apresenta o contato; a YourEyes vende e implanta" },
    { key: "representante", label: "Representante", quem: "prospecta e fecha; a YourEyes implanta" },
    { key: "operador", label: "Operador", quem: "vende, implanta, treina e atende; fatura o setup direto" },
  ];
  const EVENTO_LABEL: Record<string, string> = { setup_concluido: "Setup concluído (legado)", go_live: "Go-live (legado)", renovacao: "Renovação", bonus_retencao_90d: "Bônus de retenção 90 dias", fast_start: "Fast Start", bonus_volume: "Bônus de volume", bonus_velocidade: "Bônus de velocidade", decimo_terceiro: "13º da carteira" };
  const GRUPO_LABEL: Record<string, string> = { ciclo: "Ciclo e renovação", niveis: "Níveis", base: "Base de cálculo", pagamento: "Fechamento e pagamento", setup: "Setup em parcelas", bonus: "Bônus", qualidade: "Qualidade e homologação", clawback: "Clawback", atribuicao: "Atribuição e atividade", governanca: "Governança e contrato", master: "Master Regional" };
  const grupos = Array.from(new Set(config.map((c) => c.grupo)));
  const fmtValor = (c: { tipo: string; chave: string }) => (cfg[c.chave] ?? "");
  const setValor = (chave: string, v: string) => setCfg((m) => ({ ...m, [chave]: v }));

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Matriz por trilha e nível</CardTitle>
          <CardDescription>Valores pré-preenchidos conforme a Política de Parceiros (jul/2026). Percentual sobre a mensalidade recebida e participação no setup pago pelo cliente. Edite e salve; vale para contas novas, nunca reduz ciclo em curso.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          {TRILHAS.map((t) => (
            <div key={t.key}>
              <div className="flex items-baseline gap-2 mb-2"><h3 className="font-semibold">{t.label}</h3><span className="text-xs text-muted-foreground">{t.quem}</span></div>
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader><TableRow><TableHead>Nível</TableHead><TableHead>MRR de (R$)</TableHead><TableHead>até (R$)</TableHead><TableHead>% mensalidade (link)</TableHead><TableHead>% mensalidade (lead da casa)</TableHead><TableHead>% do setup</TableHead><TableHead>Bônus renovação (×)</TableHead><TableHead>Ativo</TableHead></TableRow></TableHeader>
                  <TableBody>
                    {nv.filter((n) => n.trilha === t.key).sort((a, b) => a.ordem - b.ordem).map((n) => (
                      <TableRow key={n.id ?? n.nome}>
                        <TableCell className="font-medium">{n.nome}<div className="text-[11px] text-muted-foreground max-w-[220px]">{n.beneficios}</div></TableCell>
                        <TableCell><Input className="w-28" value={centsToReais(n.mrr_minimo_cents)} onChange={(e) => setNivel(n.id, "mrr_minimo_cents", reaisToCents(e.target.value))} /></TableCell>
                        <TableCell><Input className="w-28" value={n.mrr_maximo_cents != null ? centsToReais(n.mrr_maximo_cents) : ""} placeholder="sem teto" onChange={(e) => setNivel(n.id, "mrr_maximo_cents", e.target.value.trim() ? reaisToCents(e.target.value) : null)} /></TableCell>
                        <TableCell><Input className="w-20" type="number" step="0.5" value={n.percentual_link} onChange={(e) => setNivel(n.id, "percentual_link", Number(e.target.value))} /></TableCell>
                        <TableCell><Input className="w-20" type="number" step="0.5" value={n.percentual_casa} onChange={(e) => setNivel(n.id, "percentual_casa", Number(e.target.value))} /></TableCell>
                        <TableCell><Input className="w-20" type="number" step="5" value={n.setup_participacao_pct ?? 0} onChange={(e) => setNivel(n.id, "setup_participacao_pct", Number(e.target.value))} /></TableCell>
                        <TableCell><Input className="w-16" type="number" step="0.5" value={n.bonus_renovacao_multiplicador} onChange={(e) => setNivel(n.id, "bonus_renovacao_multiplicador", Number(e.target.value))} /></TableCell>
                        <TableCell><Switch checked={n.ativo} onCheckedChange={(v) => setNivel(n.id, "ativo", v)} /></TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </div>
          ))}
          <div className="flex justify-end"><Button onClick={() => salvarNiveis.mutate(nv)} disabled={salvarNiveis.isPending} data-testid="salvar-matriz"><Save className="w-4 h-4 mr-2" />Salvar matriz</Button></div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Parâmetros do programa</CardTitle>
          <CardDescription>Ciclo de 24 meses, setup em 30/40/30, retenção 90 dias, clawback, inadimplência, não aliciamento… Pré-preenchidos pela política; o motor de fechamento e o contrato leem daqui. Valores em R$ para os itens de dinheiro.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          {grupos.map((g) => (
            <div key={g}>
              <h3 className="font-semibold text-sm mb-2">{GRUPO_LABEL[g] ?? g}</h3>
              <div className="grid md:grid-cols-2 gap-3">
                {config.filter((c) => c.grupo === g).map((c) => (
                  <div key={c.chave} className="rounded-lg border p-3">
                    <Label className="text-xs">{c.rotulo}</Label>
                    <div className="flex items-center gap-2 mt-1">
                      {c.tipo === "centavos" ? (
                        <><span className="text-sm text-muted-foreground">R$</span><Input className="w-32" value={centsToReais(Number(fmtValor(c) || 0))} onChange={(e) => setValor(c.chave, String(reaisToCents(e.target.value)))} /></>
                      ) : c.tipo === "booleano" ? (
                        <Switch checked={fmtValor(c) === "true"} onCheckedChange={(v) => setValor(c.chave, v ? "true" : "false")} />
                      ) : (
                        <><Input className="w-28" value={fmtValor(c)} onChange={(e) => setValor(c.chave, e.target.value)} /><span className="text-xs text-muted-foreground">{c.tipo === "percentual" ? "%" : c.tipo === "dias" ? "dias" : c.tipo === "meses" ? "meses" : ""}</span></>
                      )}
                    </div>
                    {c.descricao && <p className="text-[11px] text-muted-foreground mt-1">{c.descricao}</p>}
                  </div>
                ))}
              </div>
            </div>
          ))}
          <div className="flex justify-end"><Button onClick={() => salvarConfig.mutate(Object.entries(cfg).map(([chave, valor]) => ({ chave, valor })))} disabled={salvarConfig.isPending} data-testid="salvar-parametros"><Save className="w-4 h-4 mr-2" />Salvar parâmetros</Button></div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Bônus por trilha</CardTitle>
          <CardDescription>Retenção 90 dias, Fast Start, volume e velocidade. Percentuais incidem sobre o setup; o valor fixo vale para o Fast Start.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {TRILHAS.map((t) => (
            <div key={t.key}>
              <h3 className="font-semibold text-sm mb-1">{t.label}</h3>
              <div className="grid md:grid-cols-2 gap-2">
                {ev.map((e, i) => e.trilha === t.key && !["setup_concluido", "go_live", "renovacao"].includes(e.evento) ? (
                  <div key={`${e.trilha}-${e.evento}`} className="border rounded-md p-3 grid grid-cols-2 gap-2 text-sm">
                    <div className="col-span-2 flex items-center justify-between"><span className="font-medium">{EVENTO_LABEL[e.evento] ?? e.evento}</span><Switch checked={e.ativo} onCheckedChange={(v) => setEvento(i, "ativo", v)} /></div>
                    <div><Label className="text-xs">Valor fixo (R$)</Label><Input value={centsToReais(e.valor_fixo_cents)} onChange={(ev2) => setEvento(i, "valor_fixo_cents", reaisToCents(ev2.target.value))} /></div>
                    <div><Label className="text-xs">% do setup</Label><Input type="number" step="1" value={(e as ParceiroEventoRemuneracao & { percentual_setup?: number }).percentual_setup ?? 0} onChange={(ev2) => setEvento(i, "percentual_setup" as keyof ParceiroEventoRemuneracao, Number(ev2.target.value) as never)} /></div>
                  </div>
                ) : null)}
              </div>
            </div>
          ))}
          <div className="flex justify-end"><Button onClick={() => salvarEventos.mutate(ev)} disabled={salvarEventos.isPending}><Save className="w-4 h-4 mr-2" />Salvar bônus</Button></div>
        </CardContent>
      </Card>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
const COMISSAO_STATUS_LABEL: Record<ParceiroComissao["status"], string> = { previsto: "Previsto", fechado: "Fechado", pago: "Pago", retido: "Retido" };
const COMISSAO_TIPO_LABEL: Record<ParceiroComissao["tipo"], string> = { recorrente: "Recorrente", bonus_renovacao: "Bônus renovação", evento: "Evento", ajuste: "Ajuste" };
function competenciaAtual() { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`; }
function competenciasRecentes(n = 12) {
  const out: string[] = []; const d = new Date(); d.setDate(1);
  for (let i = 0; i < n; i++) { out.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`); d.setMonth(d.getMonth() - 1); }
  return out;
}

function ComissoesPainel() {
  const [competencia, setCompetencia] = useState<string>(competenciaAtual());
  const { data: itens = [], isLoading } = useParceiroComissoes(competencia);
  const { fecharCompetencia, comissaoStatus, comissaoAjuste, parceiros } = useParceiros();
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [ajuste, setAjuste] = useState({ parceiroId: "", valor: "", obs: "" });
  const total = (st?: ParceiroComissao["status"]) => itens.filter((i) => !st || i.status === st).reduce((a, i) => a + Number(i.valor_cents || 0), 0);
  const toggle = (id: string) => setSel((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const porParceiro = useMemo(() => {
    const m = new Map<string, { nome: string; pix: string | null; total: number; pago: number }>();
    for (const i of itens) {
      const e = m.get(i.parceiro_id) ?? { nome: i.parceiro_nome, pix: i.pix_chave, total: 0, pago: 0 };
      if (i.status !== "retido") e.total += Number(i.valor_cents || 0);
      if (i.status === "pago") e.pago += Number(i.valor_cents || 0);
      m.set(i.parceiro_id, e);
    }
    return Array.from(m.entries());
  }, [itens]);

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
            <div>
              <CardTitle>Comissões</CardTitle>
              <CardDescription>Fecha dia 25 (automático) e paga até dia 10. Aqui você faz uma prévia, fecha manualmente, marca pagamentos e lança ajustes.</CardDescription>
            </div>
            <div className="flex flex-wrap gap-2 items-center">
              <Select value={competencia} onValueChange={setCompetencia}>
                <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
                <SelectContent>{competenciasRecentes().map((c) => <SelectItem key={c} value={c}>{c.split("-").reverse().join("/")}</SelectItem>)}</SelectContent>
              </Select>
              <Button variant="outline" disabled={fecharCompetencia.isPending} onClick={() => fecharCompetencia.mutate({ competencia: `${competencia}-01`, fechar: false })}><Play className="w-4 h-4 mr-1" />Prévia</Button>
              <Button disabled={fecharCompetencia.isPending} onClick={async () => { if (await confirm({ title: `Fechar ${competencia.split("-").reverse().join("/")}?`, description: "Os valores previstos passam a fechados e deixam de ser recalculados. Pagamentos e ajustes continuam possíveis." })) fecharCompetencia.mutate({ competencia: `${competencia}-01`, fechar: true }); }} data-testid="comissoes-fechar"><Lock className="w-4 h-4 mr-1" />Fechar competência</Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            {(["previsto", "fechado", "pago", "retido"] as const).map((st) => (
              <div key={st} className="rounded-lg border p-3"><div className="text-xs text-muted-foreground">{COMISSAO_STATUS_LABEL[st]}</div><div className="text-lg font-bold tabular-nums">R$ {centsToReais(total(st))}</div></div>
            ))}
          </div>

          {porParceiro.length > 0 && (
            <div>
              <h3 className="text-sm font-semibold mb-2">Resumo por parceiro (para o PIX)</h3>
              <Table>
                <TableHeader><TableRow><TableHead>Parceiro</TableHead><TableHead>Chave PIX</TableHead><TableHead className="text-right">A pagar (exclui retido)</TableHead><TableHead className="text-right">Já pago</TableHead></TableRow></TableHeader>
                <TableBody>{porParceiro.map(([id, p]) => <TableRow key={id}><TableCell className="font-medium">{p.nome}</TableCell><TableCell className="font-mono text-xs">{p.pix ?? <span className="text-amber-600">sem PIX cadastrado</span>}</TableCell><TableCell className="text-right font-mono">R$ {centsToReais(p.total)}</TableCell><TableCell className="text-right font-mono">R$ {centsToReais(p.pago)}</TableCell></TableRow>)}</TableBody>
              </Table>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm text-muted-foreground">{sel.size} selecionada(s):</span>
            <Button size="sm" variant="outline" disabled={!sel.size || comissaoStatus.isPending} onClick={() => { comissaoStatus.mutate({ ids: Array.from(sel), status: "pago" }); setSel(new Set()); }}>Marcar pago</Button>
            <Button size="sm" variant="outline" disabled={!sel.size || comissaoStatus.isPending} onClick={() => { comissaoStatus.mutate({ ids: Array.from(sel), status: "retido", observacao: "Retido pelo SuperAdmin" }); setSel(new Set()); }}>Reter</Button>
            <Button size="sm" variant="ghost" disabled={!sel.size || comissaoStatus.isPending} onClick={() => { comissaoStatus.mutate({ ids: Array.from(sel), status: "fechado" }); setSel(new Set()); }}>Voltar a fechado</Button>
          </div>

          {isLoading ? <Skeleton className="h-24 w-full" /> : itens.length === 0 ? (
            <p className="text-sm text-muted-foreground py-6 text-center">Nenhuma comissão nesta competência. Rode a prévia para calcular.</p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead></TableHead><TableHead>Parceiro</TableHead><TableHead>Cliente</TableHead><TableHead>Tipo</TableHead><TableHead className="text-right">Base</TableHead><TableHead className="text-right">%</TableHead><TableHead className="text-right">Valor</TableHead><TableHead>Status</TableHead><TableHead>Obs.</TableHead></TableRow></TableHeader>
                <TableBody>
                  {itens.map((c) => (
                    <TableRow key={c.id} data-testid="comissao-linha">
                      <TableCell><input type="checkbox" checked={sel.has(c.id)} onChange={() => toggle(c.id)} aria-label="Selecionar" /></TableCell>
                      <TableCell className="font-medium">{c.parceiro_nome}</TableCell>
                      <TableCell>{c.tenant_nome ?? "—"}</TableCell>
                      <TableCell className="text-xs">{COMISSAO_TIPO_LABEL[c.tipo]}{c.evento && c.tipo !== "ajuste" ? ` · ${c.evento}` : ""}</TableCell>
                      <TableCell className="text-right font-mono">{c.base_cents ? `R$ ${centsToReais(c.base_cents)}` : "—"}</TableCell>
                      <TableCell className="text-right font-mono">{c.percentual ?? "—"}</TableCell>
                      <TableCell className="text-right font-mono">R$ {centsToReais(c.valor_cents)}</TableCell>
                      <TableCell><Badge variant={c.status === "pago" ? "default" : c.status === "retido" ? "destructive" : c.status === "fechado" ? "secondary" : "outline"}>{COMISSAO_STATUS_LABEL[c.status]}</Badge></TableCell>
                      <TableCell className="text-xs text-muted-foreground max-w-[220px] truncate" title={c.observacao ?? ""}>{c.observacao ?? ""}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-base">Lançar ajuste</CardTitle><CardDescription>Crédito (positivo) ou débito (negativo) fora do cálculo automático, já como fechado.</CardDescription></CardHeader>
        <CardContent className="grid md:grid-cols-4 gap-3 items-end">
          <div><Label>Parceiro</Label>
            <Select value={ajuste.parceiroId} onValueChange={(v) => setAjuste((a) => ({ ...a, parceiroId: v }))}>
              <SelectTrigger><SelectValue placeholder="Escolha" /></SelectTrigger>
              <SelectContent>{parceiros.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div><Label>Valor (R$, negativo = débito)</Label><Input value={ajuste.valor} onChange={(e) => setAjuste((a) => ({ ...a, valor: e.target.value }))} placeholder="150,00" /></div>
          <div className="md:col-span-2"><Label>Motivo</Label><TextareaUi rows={1} value={ajuste.obs} onChange={(e) => setAjuste((a) => ({ ...a, obs: e.target.value }))} /></div>
          <div className="md:col-span-4 flex justify-end">
            <Button variant="outline" disabled={!ajuste.parceiroId || !ajuste.obs.trim() || comissaoAjuste.isPending}
              onClick={() => { const neg = ajuste.valor.trim().startsWith("-"); const cents = reaisToCents(ajuste.valor.replace("-", "")) * (neg ? -1 : 1); comissaoAjuste.mutate({ parceiroId: ajuste.parceiroId, competencia: `${competencia}-01`, valorCents: cents, observacao: ajuste.obs }); setAjuste({ parceiroId: "", valor: "", obs: "" }); }}>
              Lançar em {competencia.split("-").reverse().join("/")}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

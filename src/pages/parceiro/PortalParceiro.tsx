import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Copy, Download, Link2, TrendingUp, Wallet, Users, Percent, Store, Clock, Hourglass, FileSignature, MessageCircle, Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "sonner";
import { ParceirosLayout, CONTATO_WHATSAPP } from "@/components/parceiro/ParceirosLayout";
import { useParceiroPortal, formatarReais, linkPublico, linkContratar, ESTAGIO_LABEL, type CarteiraItem, type Estagio } from "@/hooks/useParceiroPortal";
import { PARCEIRO_TIPO_LABEL, PARCEIRO_TRILHA_LABEL, type ParceiroTrilha } from "@/hooks/useParceiros";

const ESTAGIO_CLASSE: Record<Estagio, string> = {
  lead: "bg-slate-500/20 text-slate-300", proposta: "bg-sky-500/20 text-sky-300", contrato: "bg-indigo-500/20 text-indigo-300",
  implantacao: "bg-amber-500/20 text-amber-300", go_live: "bg-orange-500/20 text-orange-300",
  ativo: "bg-emerald-500/20 text-emerald-300", churn: "bg-red-500/20 text-red-300",
};

function dataBr(d?: string | null) { return d ? new Date(d).toLocaleDateString("pt-BR") : "—"; }

function Card({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <div className={`rounded-2xl border border-white/10 bg-white/[0.04] p-5 ${className}`}>{children}</div>;
}

export default function PortalParceiro() {
  const { dados, isLoading, isError } = useParceiroPortal();
  const [copiado, setCopiado] = useState<string | null>(null);

  const copiar = async (chave: string, url: string) => {
    try { await navigator.clipboard?.writeText(url); } catch { /* sem clipboard: mostra o link para copiar à mão */ }
    setCopiado(chave); toast.success("Link copiado"); setTimeout(() => setCopiado(null), 1800);
  };

  const exportarCsv = () => {
    if (!dados) return;
    const linhas = [["Empresa", "Plano", "MRR", "Estágio", "Próximo passo", "Comissão/mês", "Papel", "Desde"]];
    for (const c of dados.carteira) {
      linhas.push([c.nome, c.plano ?? "", (c.mrr_cents / 100).toFixed(2), ESTAGIO_LABEL[c.estagio], c.proximo_passo ?? "", (c.comissao_mes_cents / 100).toFixed(2), c.papel, dataBr(c.desde)]);
    }
    const csv = linhas.map((l) => l.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(";")).join("\n");
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a"); a.href = url; a.download = `carteira-${dados.parceiro.codigo}.csv`; a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const funil = useMemo(() => {
    if (!dados) return [];
    const k = dados.kpis;
    const base = Math.max(k.leads_90d, 1);
    return [
      { rotulo: "Leads", valor: k.leads_90d, cor: "bg-sky-900" },
      { rotulo: "Propostas", valor: k.propostas_90d, cor: "bg-sky-500" },
      { rotulo: "Contratos", valor: k.contratos_90d, cor: "bg-[#FF8A00]" },
      { rotulo: "Ativos", valor: k.clientes_ativos, cor: "bg-emerald-500" },
    ].map((f) => ({ ...f, pct: Math.min(100, Math.round((f.valor / base) * 100)) }));
  }, [dados]);

  return (
    <ParceirosLayout>
      {isLoading && <div className="space-y-4"><Skeleton className="h-28 w-full bg-white/10" /><Skeleton className="h-24 w-full bg-white/10" /></div>}
      {isError && <Card><p className="text-red-300">Não foi possível carregar o seu painel. Tente novamente em instantes.</p></Card>}
      {dados && dados.parceiro.status !== "ativo" && (
        <div className="max-w-2xl mx-auto py-8 space-y-5" data-testid="portal-parceiro-espera">
          <Card className="text-center space-y-4">
            {dados.parceiro.status === "pendente" ? <Hourglass className="w-10 h-10 mx-auto text-[#60ABEF]" /> : <Lock className="w-10 h-10 mx-auto text-amber-400" />}
            <h1 className="text-2xl font-bold text-white">
              {dados.parceiro.status === "pendente" ? "Cadastro em análise" : dados.parceiro.status === "suspenso" ? "Cadastro suspenso" : "Cadastro encerrado"}
            </h1>
            <p className="text-sm text-slate-300">Olá, {dados.parceiro.nome}. {dados.parceiro.status === "pendente"
              ? `Recebemos o seu cadastro como ${PARCEIRO_TIPO_LABEL[dados.parceiro.tipo_parceiro] ?? dados.parceiro.tipo_parceiro} (trilha ${PARCEIRO_TRILHA_LABEL[dados.parceiro.trilha as ParceiroTrilha] ?? dados.parceiro.trilha}) em ${dataBr(dados.situacao?.criado_em)}. A equipe YourEyes avalia perfil, documentos e região de atuação e responde por e-mail, normalmente em até 2 dias úteis.`
              : `Seu cadastro está ${dados.parceiro.status}. ${dados.situacao?.motivo ? `Motivo informado: ${dados.situacao.motivo}.` : ""} Fale com a equipe para reavaliar.`}
            </p>
            {dados.parceiro.status === "pendente" && (
              <ol className="text-left text-sm text-slate-300 space-y-2 max-w-md mx-auto">
                <li className="flex gap-2"><span className="text-emerald-400">✓</span> Cadastro enviado</li>
                <li className="flex gap-2"><span className="text-[#60ABEF]">●</span> Aprovação da equipe YourEyes <span className="text-slate-500">(em andamento)</span></li>
                <li className="flex gap-2"><span className="text-slate-500">○</span> Assinatura eletrônica do Contrato de Parceria</li>
                <li className="flex gap-2"><span className="text-slate-500">○</span> Link de indicação e painel liberados</li>
              </ol>
            )}
            <div className="flex flex-wrap justify-center gap-2 pt-2">
              <Button asChild variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10"><Link to="/parceiro/perfil">Completar meu cadastro</Link></Button>
              <Button asChild variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10"><Link to="/parceiros/contrato">Ler o contrato</Link></Button>
              <Button asChild className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><a href={CONTATO_WHATSAPP} target="_blank" rel="noreferrer"><MessageCircle className="w-4 h-4 mr-1" />Falar com a equipe</a></Button>
            </div>
          </Card>
          <p className="text-xs text-slate-500 text-center">Enquanto a aprovação não sai, o link de indicação não é gerado e nenhuma empresa é atribuída ao seu cadastro.</p>
        </div>
      )}
      {dados && dados.parceiro.status === "ativo" && (
        <div className="space-y-6" data-testid="portal-parceiro">
          {dados.contrato?.pendente && (
            <div className="rounded-xl border border-[#60ABEF]/40 bg-[#60ABEF]/10 p-4 text-sm text-slate-100 flex flex-wrap items-center justify-between gap-3" data-testid="portal-contrato-pendente">
              <span>Há uma versão do <b>Contrato de Parceria</b> aguardando a sua assinatura eletrônica{dados.contrato.titulo_vigente ? ` (${dados.contrato.titulo_vigente})` : ""}.</span>
              <Button asChild size="sm" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/parceiros/contrato">Ler e assinar</Link></Button>
            </div>
          )}

          {/* Cabeçalho */}
          <Card className="flex flex-wrap items-center justify-between gap-6">
            <div>
              <h1 className="text-2xl font-bold text-white" data-testid="portal-parceiro-nome">Olá, {dados.parceiro.nome} 👋</h1>
              <div className="flex flex-wrap gap-2 mt-2">
                <Badge className="bg-[#FF8A00]/20 text-[#FF8A00] hover:bg-[#FF8A00]/20">Trilha {PARCEIRO_TRILHA_LABEL[dados.parceiro.trilha as ParceiroTrilha] ?? dados.parceiro.trilha}</Badge>
                {dados.nivel.nome && <Badge className="bg-[#60ABEF]/20 text-[#60ABEF] hover:bg-[#60ABEF]/20">Nível {dados.nivel.nome}</Badge>}
                <Badge variant="outline" className="border-white/20 text-slate-300">{PARCEIRO_TIPO_LABEL[dados.parceiro.tipo_parceiro]}</Badge>
                <span className="text-xs text-slate-400 self-center">{[dados.parceiro.cidade, dados.parceiro.uf].filter(Boolean).join("/")} · parceiro desde {dataBr(dados.parceiro.parceiro_desde)}</span>
              </div>
            </div>
            {dados.proximo_nivel && (
              <div className="min-w-[260px] flex-1 max-w-sm">
                <div className="flex justify-between text-xs text-slate-400 mb-1.5">
                  <span>Evolução até <b className="text-white">{dados.proximo_nivel.nome}</b></span>
                  <span className="font-mono"><b className="text-white">{formatarReais(dados.kpis.mrr_cents)}</b> / {formatarReais(dados.proximo_nivel.mrr_minimo_cents)}</span>
                </div>
                <div className="h-2.5 rounded-full bg-white/10 overflow-hidden">
                  <div className="h-full rounded-full bg-gradient-to-r from-[#60ABEF] to-[#FF8A00]" style={{ width: `${Math.min(100, Math.round((dados.kpis.mrr_cents / Math.max(dados.proximo_nivel.mrr_minimo_cents, 1)) * 100))}%` }} />
                </div>
                <p className="text-[11px] text-slate-400 mt-1.5">
                  Faltam <b className="text-white">{formatarReais(Math.max(0, dados.proximo_nivel.mrr_minimo_cents - dados.kpis.mrr_cents))}</b> de MRR sob atendimento para o nível {dados.proximo_nivel.nome} ({dados.proximo_nivel.percentual}% da mensalidade).
                </p>
              </div>
            )}
          </Card>

          {/* KPIs */}
          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
            <Kpi icone={<TrendingUp className="w-4 h-4 text-[#FF8A00]" />} rotulo="MRR sob atendimento" valor={formatarReais(dados.kpis.mrr_cents)} detalhe="planos públicos ativos e em go-live" />
            <Kpi icone={<Percent className="w-4 h-4 text-[#60ABEF]" />} rotulo="Comissão do mês" valor={formatarReais(dados.kpis.comissao_mes_cents)} detalhe={`${dados.nivel.percentual}% · fecha dia ${dados.kpis.fecha_dia}`} />
            <Kpi icone={<Wallet className="w-4 h-4 text-emerald-400" />} rotulo="Ganho acumulado" valor={formatarReais(dados.kpis.ganho_acumulado_cents)} detalhe="comissões pagas" />
            <Kpi icone={<Users className="w-4 h-4 text-emerald-400" />} rotulo="Clientes ativos" valor={String(dados.kpis.clientes_ativos)} detalhe={`${dados.kpis.em_implantacao} em implantação`} />
            <Kpi icone={<Clock className="w-4 h-4 text-amber-400" />} rotulo="Conversão (90 dias)" valor={dados.kpis.leads_90d ? `${Math.round((dados.kpis.clientes_ativos / dados.kpis.leads_90d) * 100)}%` : "—"} detalhe="lead → cliente ativo" />
          </div>

          {/* Link + funil */}
          <div className="grid lg:grid-cols-2 gap-4">
            <Card>
              <h2 className="font-semibold text-white flex items-center gap-2"><Link2 className="w-4 h-4" />Seus links de indicação</h2>
              {dados.contrato?.pendente ? (
                <div className="rounded-xl border border-amber-500/40 bg-amber-500/10 p-4 text-sm text-amber-100 space-y-3" data-testid="portal-link-travado">
                  <div className="flex items-start gap-2"><Lock className="w-4 h-4 mt-0.5 shrink-0" /><span>Seus links são liberados assim que você assinar eletronicamente o Contrato de Parceria.</span></div>
                  <Button asChild size="sm" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/parceiros/contrato"><FileSignature className="w-4 h-4 mr-1" />Assinar o contrato agora</Link></Button>
                </div>
              ) : (
                <>
                  <p className="text-xs text-slate-400 mb-3">Dois jeitos de indicar. Os dois registram a origem da conta automaticamente por 90 dias.</p>
                  {dados.links.map((l) => (
                    <div key={l.id} className="space-y-2 mb-3">
                      {l.campanha !== "principal" && <div className="text-[11px] uppercase tracking-wider text-slate-500">Campanha {l.campanha}</div>}
                      <div className="flex items-center gap-2">
                        <div className="flex-1 min-w-0 rounded-lg border border-white/15 bg-black/20 px-3 py-2" data-testid={l.campanha === "principal" ? "portal-link-principal" : undefined}>
                          <div className="text-[11px] text-slate-400">Apresentação <span className="text-slate-500">· para quem ainda não conhece a YourEyes (redes, WhatsApp)</span></div>
                          <div className="font-mono text-xs truncate">{linkPublico(l.codigo)}</div>
                        </div>
                        <Button size="sm" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" onClick={() => copiar(l.codigo, linkPublico(l.codigo))} data-testid={l.campanha === "principal" ? "portal-copiar-link" : undefined}>
                          <Copy className="w-4 h-4 mr-1" />{copiado === l.codigo ? "Copiado ✓" : "Copiar"}
                        </Button>
                      </div>
                      <div className="flex items-center gap-2">
                        <div className="flex-1 min-w-0 rounded-lg border border-white/15 bg-black/20 px-3 py-2">
                          <div className="text-[11px] text-slate-400">Contratar <span className="text-slate-500">· para quem já decidiu: abre direto nos planos</span></div>
                          <div className="font-mono text-xs truncate">{linkContratar(l.codigo)}</div>
                        </div>
                        <Button size="sm" variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={() => copiar(l.codigo + "#", linkContratar(l.codigo))}>
                          <Copy className="w-4 h-4 mr-1" />{copiado === l.codigo + "#" ? "Copiado ✓" : "Copiar"}
                        </Button>
                      </div>
                      <div className="text-[11px] text-slate-500">{l.cliques} cliques · {l.leads} leads pelo código {l.codigo}</div>
                    </div>
                  ))}
                  <p className="text-[11px] text-slate-500 mt-2">Links por campanha são criados pela equipe YourEyes a seu pedido.</p>
                </>
              )}
            </Card>
            <Card>
              <h2 className="font-semibold text-white">Conversões do seu funil</h2>
              <p className="text-xs text-slate-400 mb-3">Últimos 90 dias — do lead ao cliente ativo.</p>
              <div className="space-y-2">
                {funil.map((f) => (
                  <div key={f.rotulo} className="grid grid-cols-[110px_1fr_48px] items-center gap-2 text-sm">
                    <span className="text-slate-400">{f.rotulo}</span>
                    <div className="h-6 rounded bg-white/5 overflow-hidden"><div className={`h-full rounded ${f.cor}`} style={{ width: `${Math.max(f.pct, f.valor ? 4 : 0)}%` }} /></div>
                    <span className="font-mono text-right font-semibold">{f.valor}</span>
                  </div>
                ))}
              </div>
            </Card>
          </div>

          {/* Evolução 12 meses (snapshots do fechamento) */}
          <Card>
            <div className="flex items-end justify-between gap-3 flex-wrap">
              <div><h2 className="font-semibold text-white">Sua evolução com a YourEyes</h2><p className="text-xs text-slate-400">MRR sob atendimento registrado em cada fechamento mensal · últimos 12 meses.</p></div>
              {dados.proximo_nivel && <span className="text-[11px] text-[#60ABEF]">linha tracejada: meta {dados.proximo_nivel.nome} ({formatarReais(dados.proximo_nivel.mrr_minimo_cents)})</span>}
            </div>
            <GraficoEvolucao pontos={dados.historico ?? []} meta={dados.proximo_nivel?.mrr_minimo_cents ?? null} atual={dados.kpis.mrr_cents} />
          </Card>

          {/* Carteira */}
          <div>
            <div className="flex items-end justify-between mb-2">
              <div><h2 className="font-semibold text-white text-lg">Minha carteira de clientes</h2><p className="text-xs text-slate-400">Cada conta que você originou ou implanta, e onde ela está agora.</p></div>
              <Button variant="outline" size="sm" className="border-white/20 bg-transparent text-slate-200 hover:bg-white/10" onClick={exportarCsv} data-testid="portal-exportar"><Download className="w-4 h-4 mr-1" />Exportar</Button>
            </div>
            <div className="rounded-2xl border border-white/10 overflow-x-auto" data-testid="portal-carteira">
              <table className="w-full text-sm min-w-[720px]">
                <thead className="bg-white/5 text-[10.5px] uppercase tracking-wider text-slate-400">
                  <tr><th className="text-left px-4 py-3">Empresa</th><th className="text-left px-4 py-3">Plano</th><th className="text-right px-4 py-3">MRR</th><th className="text-left px-4 py-3">Estágio</th><th className="text-left px-4 py-3">Próximo passo / ciclo</th><th className="text-right px-4 py-3">Sua comissão/mês</th></tr>
                </thead>
                <tbody>
                  {dados.carteira.length === 0 && <tr><td colSpan={6} className="px-4 py-8 text-center text-slate-400">Nenhuma conta ainda. Compartilhe seu link para começar.</td></tr>}
                  {dados.carteira.map((c: CarteiraItem) => (
                    <tr key={`${c.tipo}-${c.id}`} className="border-t border-white/10 hover:bg-white/[0.03]">
                      <td className="px-4 py-3 font-medium text-white">{c.nome}{c.papel !== "origem" && <span className="ml-2 text-[10px] uppercase text-amber-300">{c.papel === "implantacao" ? "implanta" : "indica + implanta"}</span>}{c.aviso && <div className="text-[11px] text-amber-300">{c.aviso}</div>}</td>
                      <td className="px-4 py-3">{c.plano ?? "—"}</td>
                      <td className="px-4 py-3 text-right font-mono">{c.mrr_cents ? formatarReais(c.mrr_cents) : "—"}</td>
                      <td className="px-4 py-3"><span data-testid="estagio" className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${ESTAGIO_CLASSE[c.estagio]}`}>{ESTAGIO_LABEL[c.estagio]}</span></td>
                      <td className="px-4 py-3 text-xs text-slate-400">{c.proximo_passo || "—"}</td>
                      <td className="px-4 py-3 text-right font-mono">{c.comissao_mes_cents ? formatarReais(c.comissao_mes_cents) : "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Extrato + renovações */}
          <div className="grid lg:grid-cols-[1.3fr_1fr] gap-4">
            <div>
              <h2 className="font-semibold text-white">Extrato de ganhos</h2>
              <p className="text-xs text-slate-400 mb-2">Comissão recorrente · fecha dia {dados.kpis.fecha_dia}, paga até dia {dados.kpis.paga_dia}.</p>
              <div className="rounded-2xl border border-white/10 overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-white/5 text-[10.5px] uppercase tracking-wider text-slate-400"><tr><th className="text-left px-4 py-3">Competência</th><th className="text-right px-4 py-3">Base</th><th className="text-right px-4 py-3">%</th><th className="text-right px-4 py-3">Valor</th><th className="text-left px-4 py-3">Status</th></tr></thead>
                  <tbody>
                    {dados.extrato.length === 0 && <tr><td colSpan={5} className="px-4 py-6 text-center text-slate-400 text-xs">O primeiro fechamento acontece no dia {dados.kpis.fecha_dia}. Previsto para este mês: <b className="text-white">{formatarReais(dados.kpis.comissao_mes_cents)}</b>.</td></tr>}
                    {dados.extrato.map((e) => (
                      <tr key={e.competencia} className="border-t border-white/10">
                        <td className="px-4 py-3">{e.competencia.split("-").reverse().join("/")}</td>
                        <td className="px-4 py-3 text-right font-mono">{formatarReais(e.base_cents)}</td>
                        <td className="px-4 py-3 text-right font-mono">{e.percentual ?? "—"}{e.percentual != null ? "%" : ""}</td>
                        <td className="px-4 py-3 text-right font-mono">{formatarReais(e.valor_cents)}</td>
                        <td className="px-4 py-3"><Badge variant="outline" className="border-white/20 text-slate-200 capitalize">{e.status}</Badge></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
            <div>
              <h2 className="font-semibold text-white">Próximas renovações</h2>
              <p className="text-xs text-slate-400 mb-2">Cada renovação de ciclo rende bônus de {dados.nivel.bonus_renovacao ?? 2}× a comissão.</p>
              <Card className="p-2">
                {dados.renovacoes.length === 0 && <p className="text-xs text-slate-400 p-3">Nenhum ciclo com data de renovação registrada ainda.</p>}
                {dados.renovacoes.map((r) => (
                  <div key={`${r.nome}-${r.ciclo_fim}`} className="flex justify-between px-3 py-2 text-sm border-b border-white/10 last:border-0"><span className="font-medium text-white">{r.nome}</span><span className="text-xs text-slate-400 font-mono">{dataBr(r.ciclo_fim)} · +{formatarReais(r.bonus_cents)}</span></div>
                ))}
              </Card>
              <Card className="mt-4">
                <h3 className="font-semibold text-white flex items-center gap-2"><Store className="w-4 h-4" />Marketplace</h3>
                <p className="text-xs text-slate-400 mt-1">{dados.parceiro.marketplace_profissional_id ? "Seu perfil de profissional já está ligado a este cadastro." : "Também quer ofertar seus serviços para os clientes YourEyes? Cadastre-se como profissional na vitrine."}</p>
                <Button asChild size="sm" variant="outline" className="mt-3 border-white/20 bg-transparent text-slate-200 hover:bg-white/10"><Link to="/marketplace">{dados.parceiro.marketplace_profissional_id ? "Abrir Marketplace" : "Quero ofertar serviços"}</Link></Button>
              </Card>
            </div>
          </div>
        </div>
      )}
    </ParceirosLayout>
  );
}

function Kpi({ icone, rotulo, valor, detalhe }: { icone: React.ReactNode; rotulo: string; valor: string; detalhe: string }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4">
      <div className="text-[11.5px] text-slate-400 flex items-center gap-1.5">{icone}{rotulo}</div>
      <div className="text-2xl font-extrabold text-white mt-1.5 tabular-nums">{valor}</div>
      <div className="text-[11px] text-slate-500 mt-0.5">{detalhe}</div>
    </div>
  );
}

// Gráfico de uma série (MRR mensal). Uma série: sem legenda, o título nomeia.
// Linha 2px, marcadores >= 8px com anel da superfície, grade recessiva, eixo
// único, tooltip por ponto (title nativo + realce). Sem biblioteca externa.
function GraficoEvolucao({ pontos, meta, atual }: { pontos: { competencia: string; mrr_cents: number }[]; meta: number | null; atual: number }) {
  const [ativo, setAtivo] = useState<number | null>(null);
  const serie = pontos.length ? pontos : [{ competencia: new Date().toISOString().slice(0, 7), mrr_cents: atual }];
  const W = 900, H = 240, L = 70, R = 24, T = 20, B = 40;
  const maxV = Math.max(1, ...serie.map((p) => p.mrr_cents), meta ?? 0) * 1.1;
  const x = (i: number) => (serie.length === 1 ? (L + W - R) / 2 : L + (i * (W - L - R)) / (serie.length - 1));
  const y = (v: number) => T + (H - T - B) * (1 - v / maxV);
  const path = serie.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(p.mrr_cents).toFixed(1)}`).join(" ");
  const area = `${path} L${x(serie.length - 1).toFixed(1)},${(H - B).toFixed(1)} L${x(0).toFixed(1)},${(H - B).toFixed(1)} Z`;
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => f * maxV);
  const mes = (c: string) => ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"][Number(c.split("-")[1]) - 1] + "/" + c.slice(2, 4);
  return (
    <div className="overflow-x-auto mt-3">
      {pontos.length === 0 && <p className="text-xs text-slate-500 mb-1">Ainda sem fechamentos registrados: o gráfico começa no dia 25. Ponto atual = MRR de hoje.</p>}
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full min-w-[520px] h-auto" role="img" aria-label={`Evolução do MRR sob atendimento em ${serie.length} mês(es)`}>
        <defs><linearGradient id="grad-mrr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FF8A00" stopOpacity="0.28" /><stop offset="1" stopColor="#FF8A00" stopOpacity="0.02" /></linearGradient></defs>
        {ticks.map((t) => (
          <g key={t}><line x1={L} x2={W - R} y1={y(t)} y2={y(t)} stroke="rgba(255,255,255,0.08)" /><text x={L - 8} y={y(t) + 4} textAnchor="end" fontSize="11" fill="#8A909C" fontFamily="ui-monospace, monospace">{t >= 1000 ? `${Math.round(t / 100000)}k` : Math.round(t / 100)}</text></g>
        ))}
        {meta != null && meta <= maxV && <g><line x1={L} x2={W - R} y1={y(meta)} y2={y(meta)} stroke="#60ABEF" strokeDasharray="4 4" strokeWidth="1.5" /><text x={W - R} y={y(meta) - 6} textAnchor="end" fontSize="10" fill="#60ABEF" fontFamily="ui-monospace, monospace">meta</text></g>}
        <path d={area} fill="url(#grad-mrr)" />
        <path d={path} fill="none" stroke="#FF8A00" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        {serie.map((p, i) => (
          <g key={p.competencia} onMouseEnter={() => setAtivo(i)} onMouseLeave={() => setAtivo(null)} style={{ cursor: "default" }}>
            <rect x={x(i) - 16} y={T} width={32} height={H - T - B} fill="transparent" />
            <circle cx={x(i)} cy={y(p.mrr_cents)} r={ativo === i ? 6 : 4.5} fill="#FF8A00" stroke="#0B1D34" strokeWidth="2" />
            <title>{`${mes(p.competencia)}: ${formatarReais(p.mrr_cents)}`}</title>
            {(ativo === i || i === serie.length - 1) && <text x={x(i)} y={y(p.mrr_cents) - 12} textAnchor="middle" fontSize="12" fontWeight="600" fill="#ECEEF2" fontFamily="ui-monospace, monospace">{formatarReais(p.mrr_cents)}</text>}
            {(serie.length <= 6 || i % 2 === 0 || i === serie.length - 1) && <text x={x(i)} y={H - B + 18} textAnchor="middle" fontSize="10" fill="#8A909C" fontFamily="ui-monospace, monospace">{mes(p.competencia)}</text>}
          </g>
        ))}
      </svg>
    </div>
  );
}

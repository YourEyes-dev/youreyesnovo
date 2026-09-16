import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Building2, ShieldCheck, Sparkles, TrendingUp, MessageSquare, Scale, Bell, MapPin } from "lucide-react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { MarketYELayout } from "@/components/marketye/MarketYELayout";

interface VitrinePublica {
  empresas_faixa: string;
  especialistas_ativos: number;
  anuncios_publicados: number;
  categorias: { id: string; nome: string; slug: string; icone: string | null; obrigacao_legal: string[]; filhas: { id: string; nome: string; slug: string; obrigacao_legal: string[]; exige_registro: boolean }[] }[];
  vagas_demanda: { categoria: string; categoria_slug: string; uf: string | null; empresas: number }[];
  termos_versoes: Record<string, string>;
}

export function useMarketYEPublico() {
  return useQuery({
    queryKey: ["marketye-publico"],
    queryFn: async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any).rpc("marketye_vitrine_publica");
      if (error) throw error;
      return data as VitrinePublica;
    },
    staleTime: 5 * 60 * 1000,
  });
}

const PASSOS = [
  { t: "1. Cadastre-se em minutos", d: "Nome, CPF ou CNPJ, o que você faz e onde atende. Não precisa ser cliente do YourEyes." },
  { t: "2. Conferimos seus dados", d: "A equipe confere identidade e, quando a área exige, o registro profissional. Você ganha o selo de dados verificados." },
  { t: "3. Descreva seu serviço", d: "Uma frase sobre o que você faz vira um anúncio pronto, com sugestão de preço. Você revisa e publica." },
  { t: "4. As empresas entram em contato", d: "As empresas encontram você pelo que precisam resolver. A conversa acontece aqui; preço e combinado são seus." },
];

const GARANTIAS = [
  { icon: Scale, t: "Preço, horário e regras são seus", d: "O YourEyes não fixa preço nem horário. Você pode atender fora daqui e em outras plataformas, e recusar um contato não pesa contra você." },
  { icon: ShieldCheck, t: "Reputação justa, sem punição", d: "As empresas veem como anda seu atendimento e o nível que você construiu. Isso só muda sua posição na vitrine, nunca seu direito de trabalhar." },
  { icon: TrendingUp, t: "Boas-vindas a quem está começando", d: "Nos primeiros 30 dias seus serviços ganham um empurrão na vitrine para você conseguir as primeiras avaliações." },
  { icon: MessageSquare, t: "Discordou? Peça revisão", d: "Qualquer decisão sobre o seu perfil pode ser revista: uma pessoa da equipe lê, decide e responde a você." },
];

export default function MarketYEPublico() {
  const { data } = useMarketYEPublico();
  return (
    <MarketYELayout>
      <section className="grid lg:grid-cols-[1.2fr_1fr] gap-10 items-center py-6" data-testid="marketye-publico">
        <div className="space-y-6">
          <p className="text-[11px] uppercase tracking-[0.2em] text-[#60ABEF]">MarketYE · marketplace de serviços</p>
          <h1 className="text-4xl sm:text-5xl font-bold text-white leading-tight">
            Acesse <span className="text-[#FF8A00]">{data?.empresas_faixa ?? "centenas de"} empresas</span> que precisam do seu serviço.
          </h1>
          <p className="text-slate-300 text-lg">
            Treinamentos, palestras, consultorias, contabilidade, saúde e segurança do trabalho, fisioterapia, manutenção, tecnologia... Se você presta algum serviço para empresas, as empresas clientes do YourEyes estão aqui procurando. Pode ser você.
          </p>
          <div className="flex flex-wrap gap-3">
            <Button asChild size="lg" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/marketye/cadastro" data-testid="marketye-cta-cadastro">Quero me cadastrar <ArrowRight className="w-4 h-4 ml-1" /></Link></Button>
            <Button asChild size="lg" variant="outline" className="border-white/20 bg-transparent text-white hover:bg-white/10"><Link to="/marketye/entrar">Já tenho cadastro</Link></Button>
          </div>
          <div className="grid grid-cols-3 gap-3 text-center">
            <div className="rounded-xl border border-white/10 bg-white/[0.04] p-3"><div className="text-2xl font-bold text-white">{data?.empresas_faixa ?? "—"}</div><div className="text-[11px] text-slate-400">empresas clientes</div></div>
            <div className="rounded-xl border border-white/10 bg-white/[0.04] p-3"><div className="text-2xl font-bold text-white">{data?.categorias?.length ?? "—"}</div><div className="text-[11px] text-slate-400">áreas (e qualquer outra)</div></div>
            <div className="rounded-xl border border-white/10 bg-white/[0.04] p-3"><div className="text-2xl font-bold text-white">{data?.especialistas_ativos ?? "—"}</div><div className="text-[11px] text-slate-400">especialistas ativos</div></div>
          </div>
        </div>
        <div className="rounded-3xl border border-white/10 bg-white/[0.04] p-6 space-y-4">
          <h2 className="font-semibold text-white flex items-center gap-2"><Bell className="w-4 h-4 text-[#FF8A00]" />Vagas de demanda abertas</h2>
          <p className="text-xs text-slate-400">Áreas em que empresas procuraram nos últimos 30 dias e encontraram poucos especialistas. Só mostramos quando há 5 ou mais empresas, para ninguém ser identificado.</p>
          {data && data.vagas_demanda.length > 0 ? (
            <ul className="space-y-2" data-testid="marketye-vagas">
              {data.vagas_demanda.slice(0, 8).map((v, i) => (
                <li key={i} className="flex items-center justify-between rounded-xl bg-black/20 px-3 py-2 text-sm">
                  <span className="text-slate-100">{v.categoria}{v.uf ? <span className="text-slate-400"> · {v.uf}</span> : null}</span>
                  <span className="text-[#60ABEF] font-semibold">{v.empresas} empresas</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-slate-300">Ainda estamos juntando os primeiros dados. As áreas abaixo já são procuradas pelas empresas.</p>
          )}
          <div className="flex flex-wrap gap-1.5">
            {(data?.categorias ?? []).slice(0, 10).map((c) => <span key={c.id} className="text-[11px] rounded-full border border-white/15 px-2 py-0.5 text-slate-300">{c.nome}</span>)}
          </div>
        </div>
      </section>

      <section className="py-8">
        <h2 className="text-2xl font-bold text-white">Como funciona</h2>
        <div className="mt-4 grid md:grid-cols-4 gap-3">
          {PASSOS.map((p) => <div key={p.t} className="rounded-2xl border border-white/10 bg-white/[0.03] p-4"><div className="font-semibold text-white text-sm">{p.t}</div><p className="text-xs text-slate-400 mt-1">{p.d}</p></div>)}
        </div>
      </section>

      <section className="py-8">
        <h2 className="text-2xl font-bold text-white">O que fica combinado desde o início</h2>
        <div className="mt-4 grid md:grid-cols-2 gap-3">
          {GARANTIAS.map((g) => (
            <div key={g.t} className="rounded-2xl border border-white/10 bg-white/[0.03] p-4 flex gap-3">
              <g.icon className="w-5 h-5 text-[#60ABEF] shrink-0 mt-0.5" />
              <div><div className="font-semibold text-white text-sm">{g.t}</div><p className="text-xs text-slate-400 mt-1">{g.d}</p></div>
            </div>
          ))}
        </div>
        <p className="text-xs text-slate-500 mt-3">Nesta fase o MarketYE conecta (você combina e recebe direto da empresa). Pagamento pela plataforma vem numa etapa futura, com regras próprias.</p>
      </section>

      <section className="py-8">
        <h2 className="text-2xl font-bold text-white">Algumas áreas que as empresas procuram (vale qualquer outra)</h2>
        <div className="mt-4 grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {(data?.categorias ?? []).map((c) => (
            <div key={c.id} className="rounded-2xl border border-white/10 bg-white/[0.03] p-4">
              <div className="font-semibold text-white text-sm">{c.nome}</div>
              <div className="mt-2 flex flex-wrap gap-1">
                {c.filhas.slice(0, 5).map((f) => <span key={f.id} className="text-[11px] rounded-full bg-black/20 px-2 py-0.5 text-slate-300">{f.nome}{f.obrigacao_legal?.length ? ` · ${f.obrigacao_legal[0]}` : ""}</span>)}
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="py-8">
        <div className="rounded-3xl border border-white/10 bg-gradient-to-br from-[#12315a] to-[#0B1D34] p-8 flex flex-wrap items-center justify-between gap-4">
          <div className="max-w-xl">
            <h3 className="text-xl font-bold text-white flex items-center gap-2"><Sparkles className="w-5 h-5 text-[#FF8A00]" />Primeira aparição garantida</h3>
            <p className="text-sm text-slate-300 mt-1">Publicou, apareceu: nos primeiros 30 dias seus serviços ganham um empurrão na vitrine para você conseguir as primeiras conversas e avaliações.</p>
            <p className="text-xs text-slate-500 mt-2 flex items-center gap-1"><MapPin className="w-3 h-3" />Atende presencial, remoto ou os dois: você escolhe e muda quando quiser.</p>
          </div>
          <Button asChild size="lg" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/marketye/cadastro">Cadastrar agora <ArrowRight className="w-4 h-4 ml-1" /></Link></Button>
        </div>
        <p className="text-xs text-slate-500 mt-4 flex items-center gap-1"><Building2 className="w-3 h-3" />É empresa cliente e quer contratar? A vitrine fica dentro do sistema, no botão MarketYE do cabeçalho. Parceiro do canal de vendas? Veja o <Link to="/parceiros" className="underline">Programa de Parceiros</Link>.</p>
      </section>
    </MarketYELayout>
  );
}

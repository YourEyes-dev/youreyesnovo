import { useState, useMemo } from "react";
import { Link } from "react-router-dom";
import { useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { DiagnosticoPsicossocial } from "@/components/site/DiagnosticoPsicossocial";
import logoLocal from "@/assets/logo-youreyes.svg";
import { capturarRefDaUrl, lerRef } from "@/lib/parceiroRef";
import mascot from "@/assets/mascot-ye.png.asset.json";
import {
  ShieldCheck,
  Brain,
  Users,
  Activity,
  BarChart3,
  FileCheck2,
  Building2,
  Scale,
  Lock,
  CheckCircle2,
  ArrowRight,
  Menu,
  X,
  Mail,
  Phone,
  MapPin,
  Sparkles,
  Clock,
  AlertTriangle,
  Compass,
  LogIn,
} from "lucide-react";

// ---------------- Data ----------------
type Ciclo = "mensal" | "trimestral" | "semestral" | "anual";

const CICLOS: { key: Ciclo; label: string; badge?: string; discount: number }[] = [
  { key: "mensal", label: "Mensal", discount: 0 },
  { key: "trimestral", label: "Trimestral", badge: "−10%", discount: 0.1 },
  { key: "semestral", label: "Semestral", badge: "−50% lançamento", discount: 0.5 },
  { key: "anual", label: "Anual", badge: "−40%", discount: 0.4 },
];

type Plano = {
  id: string;
  tier: string;
  nome: string;
  base: number;
  publico: string;
  limite: string;
  modulos: string[];
  destaque?: boolean;
  consulta?: boolean;
};

const PLANOS: Plano[] = [
  {
    id: "starter",
    tier: "Nível 01",
    nome: "Starter",
    base: 197,
    publico: "Para quem está começando a organizar a operação.",
    limite: "Até 20 colaboradores",
    modulos: [
      "Estrutura Organizacional completa",
      "NR-1 básico e visão psicossocial",
      "Ponto simplificado",
      "Férias + Atestados",
      "Onboarding básico",
    ],
  },
  {
    id: "essential",
    tier: "Nível 02",
    nome: "Essential",
    base: 397,
    publico: "Para quem já tem processo e precisa colocar no ar.",
    limite: "Até 80 colaboradores",
    modulos: [
      "Tudo do Starter",
      "GRO + Inventário PGR automatizado",
      "Campanhas Psicossociais + Resultados",
      "EPIs + Ergonomia",
      "Análise de Jornada",
    ],
  },
  {
    id: "professional",
    tier: "Nível 03",
    nome: "Performance",
    base: 797,
    destaque: true,
    publico: "Para quem já tem processo e precisa medir.",
    limite: "Até 200 colaboradores",
    modulos: [
      "Tudo do Essential",
      "Benefícios + Documentos + Hub Contábil",
      "Metas + Plano de Ação (5W2H)",
      "Trilhas + Aprendizado & Competências",
      "Feedback, Ouvidoria e Cultura",
      "Contratos de Experiência",
    ],
  },
  {
    id: "business",
    tier: "Nível 04",
    nome: "Governança",
    base: 1797,
    publico: "Para quem opera em múltiplas unidades e precisa integrar.",
    limite: "Até 500 colaboradores",
    modulos: [
      "Tudo do Performance",
      "SSO + auditoria de acessos",
      "KPIs Operacionais avançados",
      "API TOTVS, SAP, Sênior, Gupy",
      "SLA 99,5% garantido",
      "CSM dedicado (1 sessão/mês)",
    ],
  },
  {
    id: "enterprise",
    tier: "Nível 05",
    nome: "Enterprise",
    base: 3500,
    consulta: true,
    publico: "Para grandes operações com exigência máxima de segurança.",
    limite: "300+ colaboradores · Banco isolado",
    modulos: [
      "Tudo do Governança",
      "Banco de dados dedicado",
      "IA customizada por setor",
      "API dedicada + webhooks",
      "Assessoria jurídico-trabalhista",
      "DPO + LGPD avançado",
      "Workshop mensal NR-1",
    ],
  },
] as const;

// 5 frentes (amplitude como consequência, não como abertura)
const FRENTES = [
  {
    icon: Users,
    titulo: "Pessoas e Cultura",
    desc: "Recrutamento, integração, desenvolvimento, clima e avaliação. Da contratação certa ao desligamento sem passivo, com registro de tudo que foi combinado, feito e medido.",
  },
  {
    icon: Activity,
    titulo: "Jornada e Folha",
    desc: "Ponto, escalas, férias, benefícios e departamento pessoal integrados. O tempo das pessoas deixa de ser conferência manual e vira dado confiável.",
  },
  {
    icon: ShieldCheck,
    titulo: "SST e Compliance",
    desc: "Riscos ocupacionais e psicossociais, exames, ASO, treinamentos, normas regulamentadoras, ISO e auditorias. Conformidade que se sustenta sozinha, com prazo e responsável em cada item.",
  },
  {
    icon: FileCheck2,
    titulo: "Documentos e Governança",
    desc: "Cada documento com versão, data, assinatura e responsável. Se alguém perguntar “quem aprovou isso e quando?”, a resposta leva três segundos.",
  },
  {
    icon: BarChart3,
    titulo: "Estratégia e Inteligência",
    desc: "Metas, planos de ação, indicadores e IA contextual. A direção enxerga a empresa inteira em um painel e sabe o que fazer com o que vê.",
  },
];

// 5 níveis de maturidade
const NIVEIS = [
  { n: 1, nome: "Reativa", desc: "Apaga incêndio. O documento existe para mostrar ao fiscal." },
  { n: 2, nome: "Organizada", desc: "Tem processo no papel, mas depende de pessoas para acontecer." },
  { n: 3, nome: "Controlada", desc: "Mede o que faz, tem evidência — mas em sistemas separados.", destaque: true },
  { n: 4, nome: "Integrada", desc: "Gestão, gente e conformidade conversam. A decisão nasce do dado." },
  { n: 5, nome: "Madura", desc: "O sistema opera sem heróis. Auditoria é rotina, não evento." },
];

const CONFIANCA = [
  { titulo: "LGPD", desc: "Dados de saúde em bucket privado com grupos clínicos" },
  { titulo: "Isolamento por empresa", desc: "Cada empresa acessa somente os próprios dados" },
  { titulo: "Assinatura digital", desc: "Injeção HTML com carimbo de auditoria" },
  { titulo: "Trilha auditável", desc: "Todo alerta convertível em Ação 5W2H" },
];

// FAQ de objeções (última peça de vendas antes do fechamento)
const FAQ = [
  { q: "Já tenho sistema de RH e de ponto.", a: "Você não troca tudo. Começa pelo que mais dói e integra o resto no seu ritmo." },
  { q: "Minha equipe não vai usar.", a: "Adoção é medida dentro da plataforma, a IA preenche o que dá para preencher, e a implantação leva 1 dia — não 6 meses." },
  { q: "É caro para o meu tamanho.", a: "A cobrança é por colaborador e por módulo. Você paga pelo que usa, no tamanho que tem hoje." },
  { q: "70 módulos parecem complexos demais.", a: "Você não implanta 70. Implanta o que o seu nível de maturidade pede — e ativa o resto quando subir de nível." },
  { q: "Sou uma empresa pequena, preciso disso?", a: "Empresa pequena é a que mais sofre com dependência de pessoa. Sistema é o que permite crescer sem contratar caos junto." },
  { q: "A oferta de 50% é permanente?", a: "É exclusiva de lançamento, válida por 6 meses. Quem assina o semestral neste período mantém o desconto durante todo o ciclo contratado." },
];

// ---------------- Component ----------------
export default function Site() {
  const [ciclo, setCiclo] = useState<Ciclo>("semestral");
  // Indicação de parceiro: guarda o código e mostra quem indicou
  const [indicador, setIndicador] = useState<{ nome: string; cidade: string | null; uf: string | null } | null>(null);
  const [faixaFechada, setFaixaFechada] = useState(false);
  useEffect(() => {
    const ref = capturarRefDaUrl();
    if (!ref) return;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).rpc("parceiro_ref_publico", { p_codigo: ref }).then(({ data }: { data: { nome: string; cidade: string | null; uf: string | null } | null }) => { if (data?.nome) setIndicador(data); });
    // Link "contratar" (#planos): rola até os planos depois que a página monta
    if (window.location.hash === "#planos") setTimeout(() => document.getElementById("planos")?.scrollIntoView({ behavior: "smooth" }), 400);
  }, []);
  const [menuOpen, setMenuOpen] = useState(false);
  const [loadingPlano, setLoadingPlano] = useState<string | null>(null);

  const cicloAtual = useMemo(() => CICLOS.find((c) => c.key === ciclo)!, [ciclo]);

  useEffect(() => {
    const prevTitle = document.title;
    document.title = "YourEyes — Sistema Operacional da Maturidade Organizacional";
    const meta = document.querySelector('meta[name="description"]');
    const prevDesc = meta?.getAttribute("content") || "";
    meta?.setAttribute(
      "content",
      "Sua empresa cresce ou só aumenta? A YourEyes organiza pessoas, SST, DP, documentos, metas e estratégia em uma única plataforma auditável com IA — e mede, em tempo real, o quanto sua empresa amadureceu.",
    );

    const params = new URLSearchParams(window.location.search);
    const pag = params.get("pagamento");
    if (pag === "sucesso") {
      toast({ title: "Pagamento aprovado!", description: "Em breve nosso time entrará em contato para ativar seu plano." });
    } else if (pag === "pendente") {
      toast({ title: "Pagamento pendente", description: "Aguardando confirmação do Mercado Pago." });
    } else if (pag === "falha") {
      toast({ title: "Pagamento não concluído", description: "Tente novamente ou escolha outro método.", variant: "destructive" });
    }

    return () => {
      document.title = prevTitle;
      meta?.setAttribute("content", prevDesc);
    };
  }, []);

  const precoMensal = (base: number) => Math.round(base * (1 - cicloAtual.discount) * 100) / 100;
  const formatarPreco = (base: number) =>
    precoMensal(base).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const formatarTotalCiclo = (base: number) => {
    const meses = ciclo === "mensal" ? 1 : ciclo === "trimestral" ? 3 : ciclo === "semestral" ? 6 : 12;
    const total = Math.round(precoMensal(base) * meses * 100) / 100;
    return total.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  };

  const handleAssinar = async (p: Plano) => {
    if (p.id === "enterprise") {
      const msg = encodeURIComponent(
        "Olá! Estou no site da YourEyes e gostaria de saber mais informações sobre o plano Enterprise. Pode me ajudar?"
      );
      window.open(`https://wa.me/554699337504?text=${msg}`, "_blank");
      return;
    }
    if (p.consulta) {
      window.location.hash = "#contato";
      return;
    }
    try {
      setLoadingPlano(p.id);
      const preco_mensal = Math.round(p.base * (1 - cicloAtual.discount) * 100) / 100;
      const { data, error } = await supabase.functions.invoke("mercadopago-checkout", {
        body: {
          plano_id: p.id,
          plano_nome: p.nome,
          preco_mensal,
          ciclo,
          origin: window.location.origin,
          ref_codigo: lerRef(),
        },
      });
      if (error) throw error;
      if (!data?.checkout_url) throw new Error("URL de checkout não retornada");
      window.location.href = data.checkout_url as string;
    } catch (err) {
      console.error(err);
      toast({
        title: "Erro ao iniciar pagamento",
        description: err instanceof Error ? err.message : "Tente novamente em instantes.",
        variant: "destructive",
      });
      setLoadingPlano(null);
    }
  };

  return (
    <div className="min-h-screen bg-[#0B1D34] text-slate-100">

      {/* NAV */}
      {indicador && !faixaFechada && (
        <div className="bg-[#FF8A00] text-[#0B1D34] text-sm" data-testid="faixa-indicacao">
          <div className="max-w-7xl mx-auto px-6 py-2 flex flex-wrap items-center justify-between gap-2">
            <span>🤝 Você foi indicado(a) por <b>{indicador.nome}</b>{indicador.cidade ? ` (${indicador.cidade}${indicador.uf ? `/${indicador.uf}` : ""})` : ""}, parceiro(a) YourEyes. Sua indicação já está registrada.</span>
            <span className="flex items-center gap-3">
              <a href="#planos" className="font-semibold underline underline-offset-2">Ver planos</a>
              <button type="button" aria-label="Fechar" className="opacity-70 hover:opacity-100" onClick={() => setFaixaFechada(true)}>✕</button>
            </span>
          </div>
        </div>
      )}
      <header className="sticky top-0 z-40 bg-[#0B1D34]/85 backdrop-blur border-b border-white/10">
        <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
          <a href="#topo" className="flex items-center gap-3">
            <img src={logoLocal} alt="YourEyes" className="h-10 w-auto" />
            <div className="leading-tight">
              <div className="font-bold text-white tracking-tight">YourEyes</div>
              <div className="text-[10px] uppercase tracking-widest text-slate-400">Maturidade Organizacional</div>
            </div>
          </a>
          <nav className="hidden lg:flex items-center gap-6 xl:gap-8 text-sm font-medium text-slate-200">
            <a href="#problema" className="hover:text-[#60ABEF]">Problema</a>
            <a href="#diagnostico" className="hover:text-[#60ABEF]">Diagnóstico</a>
            <a href="#niveis" className="hover:text-[#60ABEF]">Níveis</a>
            <a href="#plataforma" className="hover:text-[#60ABEF]">Plataforma</a>
            <a href="#planos" className="hover:text-[#60ABEF]">Planos</a>
            <a href="#seguranca" className="hover:text-[#60ABEF]">Segurança</a>
            <a href="#contato" className="hover:text-[#60ABEF]">Contato</a>
            <Link to="/parceiros" className="hover:text-[#60ABEF]">Parceiros</Link>
            <Link to="/marketye" className="hover:text-[#60ABEF]">MarketYE</Link>
          </nav>
          {/* Desde que o site virou a porta do domínio principal, quem chega
              aqui para TRABALHAR (cliente indo bater ponto, RH indo lançar
              atestado) precisa achar a entrada em um segundo. Por isso o
              acesso é um botão, não mais um texto discreto — e o rótulo diz
              também "cadastrar", porque a tela de login é de onde se abre
              conta nova ("Cadastre sua empresa"). */}
          <div className="hidden lg:flex items-center gap-3">
            <Link
              to="/login"
              className="inline-flex items-center gap-2 border border-[#60ABEF]/70 text-[#60ABEF] hover:bg-[#60ABEF] hover:text-[#0B1D34] text-sm font-semibold px-4 py-2 rounded-md transition"
            >
              <LogIn className="w-4 h-4" /> Entrar / Cadastrar
            </Link>
          </div>
          {/* No celular o acesso fica FORA do menu sanduíche: escondido atrás
              de dois toques, ele não serve a quem só quer entrar. */}
          <div className="flex items-center gap-2 lg:hidden">
            <Link
              to="/login"
              className="inline-flex items-center gap-1.5 border border-[#60ABEF]/70 text-[#60ABEF] hover:bg-[#60ABEF] hover:text-[#0B1D34] text-xs font-semibold px-3 py-1.5 rounded-md transition"
            >
              <LogIn className="w-4 h-4" /> Entrar
            </Link>
            <button
              className="text-white"
              onClick={() => setMenuOpen((v) => !v)}
              aria-label="Menu"
            >
              {menuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
        {menuOpen && (
          <div className="lg:hidden border-t border-white/10 bg-[#0B1D34] px-6 py-4 space-y-3 text-sm text-slate-200">
            {["problema", "diagnostico", "niveis", "plataforma", "planos", "seguranca", "contato"].map((s) => (
              <a key={s} href={`#${s}`} className="block capitalize" onClick={() => setMenuOpen(false)}>
                {s === "niveis" ? "Níveis" : s === "seguranca" ? "Segurança" : s === "diagnostico" ? "Diagnóstico" : s}
              </a>
            ))}
            <Link to="/parceiros" className="block" onClick={() => setMenuOpen(false)}>Parceiros</Link>
            <Link to="/marketye" className="block" onClick={() => setMenuOpen(false)}>MarketYE (especialistas)</Link>
            <Link to="/login" className="block text-[#60ABEF] font-semibold" onClick={() => setMenuOpen(false)}>
              Entrar ou cadastrar sua empresa →
            </Link>
          </div>
        )}
      </header>

      {/* HERO */}
      <section id="topo" className="relative overflow-hidden bg-gradient-to-b from-[#0B1D34] to-[#0F2647] text-white">
        <div className="max-w-7xl mx-auto px-6 py-24 grid lg:grid-cols-12 gap-12 items-center">
          <div className="lg:col-span-7">
            <div className="inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-[#FFA033] mb-6">
              <span className="w-8 h-px bg-[#FFA033]" /> Sistema Operacional da Maturidade Organizacional
            </div>
            <h1 className="text-4xl md:text-5xl lg:text-6xl font-bold leading-[1.05] tracking-tight">
              Sua empresa cresce <span className="text-[#60ABEF]">ou só aumenta?</span>
            </h1>
            <p className="mt-6 text-lg text-slate-300 max-w-2xl leading-relaxed">
              Crescer é faturar mais com processo, evidência e gente desenvolvida. Aumentar é faturar mais com caos,
              planilha e dependência de heróis. A YourEyes organiza pessoas, SST, DP, documentos, metas e estratégia em
              uma única plataforma auditável com IA — e mede, em tempo real, o quanto sua empresa amadureceu.
            </p>
            <div className="mt-8 flex flex-wrap gap-4">
              <a
                href="#diagnostico"
                className="inline-flex items-center gap-2 bg-[#FF8A00] hover:bg-[#e67a00] text-white font-semibold px-6 py-3 rounded-md transition"
              >
                Fazer o diagnóstico gratuito <ArrowRight className="w-4 h-4" />
              </a>
              <a
                href="#plataforma"
                className="inline-flex items-center gap-2 border border-white/30 hover:border-white text-white font-semibold px-6 py-3 rounded-md transition"
              >
                Ver a plataforma por dentro
              </a>
            </div>
            <div className="mt-4 text-xs text-slate-400">Diagnóstico em 3 minutos · grátis · sem compromisso</div>
          </div>
          <div className="lg:col-span-5 relative flex flex-col items-center">
            <div className="relative flex justify-center">
              <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                <div className="w-[380px] h-[380px] rounded-full bg-[#60ABEF]/20 blur-3xl" />
              </div>
              <img
                src={mascot.url}
                alt="EYE — assistente de IA da YourEyes"
                className="relative z-10 h-[360px] md:h-[420px] w-auto rounded-2xl drop-shadow-[0_25px_60px_rgba(96,171,239,0.35)] -scale-x-100"
                style={{ animation: "floatMascot 6s ease-in-out infinite" }}
              />
            </div>
            <div className="relative -mt-10 w-full rounded-lg border border-white/10 bg-white/5 backdrop-blur p-6 shadow-2xl z-20">
              <div className="flex items-center gap-2 mb-4">
                <span className="w-2.5 h-2.5 rounded-full bg-[#FF8A00]" />
                <span className="w-2.5 h-2.5 rounded-full bg-[#FFA033]" />
                <span className="w-2.5 h-2.5 rounded-full bg-[#21A365]" />
                <span className="ml-2 text-xs text-slate-400">Painel de Maturidade</span>
              </div>
              <div className="space-y-3">
                {[
                  { l: "Pessoas e Cultura", v: 85, c: "#60ABEF" },
                  { l: "Jornada e Folha", v: 78, c: "#0A6BBF" },
                  { l: "SST e Compliance", v: 92, c: "#21A365" },
                  { l: "Documentos e Governança", v: 68, c: "#FF8A00" },
                ].map((k) => (
                  <div key={k.l}>
                    <div className="flex justify-between text-xs text-slate-300 mb-1.5">
                      <span>{k.l}</span>
                      <span className="font-mono text-white">{k.v}%</span>
                    </div>
                    <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
                      <div className="h-full rounded-full" style={{ width: `${k.v}%`, background: k.c }} />
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-4 pt-4 border-t border-white/10 text-[11px] text-slate-400 leading-relaxed">
                Este é o painel real da plataforma. Descubra o da sua empresa em 3 minutos.
              </div>
            </div>
            <style>{`@keyframes floatMascot { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-14px)} }`}</style>
          </div>
        </div>
      </section>

      {/* PROBLEMA */}
      <section id="problema" className="py-24 bg-white/[0.03] border-y border-white/10">
        <div className="max-w-7xl mx-auto px-6">
          <div className="max-w-3xl mb-14">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">O problema</div>
            <h2 className="text-3xl md:text-4xl font-bold text-white leading-tight">
              Sua gestão não está desorganizada. Está espalhada.
            </h2>
            <p className="mt-4 text-slate-300 text-lg leading-relaxed">
              Um sistema para ponto. Outro para SST. Uma pasta compartilhada para documentos. Uma planilha para metas.
              Um grupo de WhatsApp para as ações. E, quando alguém pergunta “isso foi feito?”, começa a caça à evidência.
            </p>
          </div>
          <div className="grid md:grid-cols-3 gap-6">
            {[
              {
                icon: Clock,
                titulo: "Custo de tempo",
                desc: "Retrabalho, conferência manual, relatório montado à mão toda vez que a diretoria pede.",
              },
              {
                icon: AlertTriangle,
                titulo: "Custo de risco",
                desc: "Documento sem trilha, prazo perdido, ação sem responsável, passivo que aparece anos depois.",
              },
              {
                icon: Compass,
                titulo: "Custo de decisão",
                desc: "Você decide por percepção, porque o dado está em seis lugares diferentes.",
              },
            ].map((b) => (
              <div key={b.titulo} className="border border-white/10 rounded-lg p-6 bg-white/[0.04] backdrop-blur">
                <div className="w-11 h-11 rounded-md bg-[#FF8A00]/15 text-[#FFA033] flex items-center justify-center mb-4">
                  <b.icon className="w-5 h-5" />
                </div>
                <h3 className="font-semibold text-white mb-2">{b.titulo}</h3>
                <p className="text-sm text-slate-300 leading-relaxed">{b.desc}</p>
              </div>
            ))}
          </div>
          <div className="mt-10 text-center">
            <div className="inline-block text-lg font-semibold text-white border-l-4 border-[#FF8A00] pl-4 py-1">
              Não é falta de esforço. É falta de sistema.
            </div>
          </div>
        </div>
      </section>

      {/* DIAGNÓSTICO PSICOSSOCIAL — destino dos CTAs e isca do tráfego pago */}
      <section id="diagnostico" className="py-24 bg-white/[0.02] border-y border-white/10">
        <div className="max-w-7xl mx-auto px-6 grid lg:grid-cols-12 gap-12 items-start">
          <div className="lg:col-span-5 lg:sticky lg:top-24">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">
              Diagnóstico gratuito
            </div>
            <h2 className="text-3xl md:text-4xl font-bold text-white leading-tight">
              Sua empresa está preparada para a cobrança de riscos psicossociais da NR-1?
            </h2>
            <p className="mt-4 text-slate-300 leading-relaxed">
              Oito perguntas, menos de três minutos. No fim você recebe o índice de exposição da sua
              empresa, onde estão as lacunas e por onde começar — na tela, na hora.
            </p>

            <ul className="mt-8 space-y-3 text-sm text-slate-300">
              {[
                "Feito sobre a NR-1: identificar, registrar, tratar e comprovar",
                "Resultado por dimensão, não uma nota solta",
                "Avalia a empresa, não as pessoas — nenhum dado de saúde é coletado",
                "Grátis e sem compromisso",
              ].map((item) => (
                <li key={item} className="flex items-start gap-3">
                  <CheckCircle2 className="w-5 h-5 text-[#34D399] shrink-0 mt-0.5" />
                  <span>{item}</span>
                </li>
              ))}
            </ul>

            <div className="mt-8 border-l-4 border-[#FF8A00] pl-4 py-1 text-sm text-slate-300 leading-relaxed">
              Desde a atualização da NR-1, risco psicossocial não é mais tema de RH: é item de
              inventário de riscos, cobrado em fiscalização como qualquer outro.
            </div>
          </div>

          <div className="lg:col-span-7">
            <DiagnosticoPsicossocial />
          </div>
        </div>
      </section>

      {/* NÍVEIS DE MATURIDADE */}
      <section id="niveis" className="py-24">
        <div className="max-w-7xl mx-auto px-6">
          <div className="max-w-3xl mb-14">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">A virada</div>
            <h2 className="text-3xl md:text-4xl font-bold text-white leading-tight">
              Existem cinco níveis de maturidade organizacional. Em qual está a sua?
            </h2>
          </div>
          <div className="grid md:grid-cols-5 gap-4">
            {NIVEIS.map((nv) => (
              <div
                key={nv.n}
                className={`relative rounded-lg p-6 border transition ${
                  nv.destaque
                    ? "border-[#60ABEF] bg-gradient-to-b from-[#0A6BBF]/25 to-[#0B1D34] shadow-2xl shadow-[#60ABEF]/20 ring-1 ring-[#60ABEF]/40"
                    : "border-white/10 bg-white/[0.04]"
                }`}
              >
                {nv.destaque && (
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-[#0A6BBF] text-white text-[10px] font-bold uppercase tracking-widest px-3 py-1 rounded whitespace-nowrap">
                    Maioria das empresas
                  </div>
                )}
                <div className="text-5xl font-black text-white/20 leading-none">0{nv.n}</div>
                <div className="mt-3 text-lg font-bold text-white">{nv.nome}</div>
                <p className="mt-2 text-sm text-slate-300 leading-relaxed">{nv.desc}</p>
              </div>
            ))}
          </div>
          <div className="mt-10 text-center">
            <a
              href="#diagnostico"
              className="inline-flex items-center gap-2 bg-[#FF8A00] hover:bg-[#e67a00] text-white font-semibold px-6 py-3 rounded-md transition"
            >
              Descobrir meu nível agora <ArrowRight className="w-4 h-4" />
            </a>
          </div>
        </div>
      </section>

      {/* PLATAFORMA — 5 FRENTES (amplitude como prova) */}
      <section id="plataforma" className="py-24 bg-white/[0.03] border-y border-white/10">
        <div className="max-w-7xl mx-auto px-6">
          <div className="max-w-3xl mb-14">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">A plataforma</div>
            <h2 className="text-3xl md:text-4xl font-bold text-white leading-tight">
              Um sistema. Cinco frentes. Toda a operação humana da sua empresa.
            </h2>
          </div>
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            {FRENTES.map((f) => (
              <div
                key={f.titulo}
                className="border border-white/10 rounded-lg p-6 hover:border-[#60ABEF] hover:bg-white/[0.06] transition group bg-white/[0.03] backdrop-blur"
              >
                <div className="w-11 h-11 rounded-md bg-[#0A6BBF]/15 text-[#60ABEF] flex items-center justify-center mb-4 group-hover:bg-[#0A6BBF] group-hover:text-white transition">
                  <f.icon className="w-5 h-5" />
                </div>
                <h3 className="font-semibold text-white mb-2">{f.titulo}</h3>
                <p className="text-sm text-slate-300 leading-relaxed">{f.desc}</p>
              </div>
            ))}
          </div>
          <p className="mt-10 max-w-3xl text-slate-300 leading-relaxed">
            São mais de 70 módulos integrados. Você não precisa usar todos — precisa que eles conversem entre si.
            É exatamente isso que a YourEyes faz.
          </p>
        </div>
      </section>

      {/* PROVA */}
      <section className="py-16 bg-transparent">
        <div className="max-w-7xl mx-auto px-6 grid md:grid-cols-4 gap-8 text-center md:text-left">
          {[
            { n: "1.100+", l: "empresas com gestão rodando na plataforma" },
            { n: "38", l: "implantações concluídas em um único ciclo" },
            { n: "1 dia", l: "para estar operando — não meses" },
            { n: "99,5%", l: "SLA garantido em contrato" },
          ].map((s) => (
            <div key={s.l}>
              <div className="text-4xl font-bold text-white">{s.n}</div>
              <div className="text-sm text-slate-300 mt-2 leading-snug">{s.l}</div>
            </div>
          ))}
        </div>
      </section>

      {/* PLANOS */}
      <section id="planos" className="py-24">
        <div className="max-w-7xl mx-auto px-6">
          <div className="max-w-3xl mb-10">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">Planos & Preços</div>
            <h2 className="text-3xl md:text-4xl font-bold text-white leading-tight">
              Cinco níveis. Um para cada estágio de maturidade.
            </h2>
            <p className="mt-4 text-slate-300 text-lg">
              Cobrança por colaborador e por módulo. Você paga pelo que usa, no tamanho que tem hoje.
              Oferta de lançamento: <strong>50% de desconto</strong> no semestral.
            </p>
          </div>

          <div className="inline-flex bg-white/10 rounded-lg p-1 mb-10 border border-white/10">
            {CICLOS.map((c) => (
              <button
                key={c.key}
                onClick={() => setCiclo(c.key)}
                className={`px-4 py-2 text-sm font-medium rounded-md transition ${
                  ciclo === c.key ? "bg-white shadow text-[#0B1D34]" : "text-slate-300 hover:text-white"
                }`}
              >
                {c.label}
                {c.badge && (
                  <span className={`ml-2 text-[10px] font-bold ${c.key === "semestral" ? "text-[#FF8A00]" : "text-[#21A365]"}`}>
                    {c.badge}
                  </span>
                )}
              </button>
            ))}
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-5 gap-4">
            {PLANOS.map((p) => (
              <div
                key={p.id}
                className={`rounded-lg border ${
                  p.destaque ? "border-[#60ABEF] shadow-2xl shadow-[#60ABEF]/20 ring-1 ring-[#60ABEF]/30 relative" : "border-white/10"
                } bg-white flex flex-col text-[#0B1D34]`}
              >
                {p.destaque && (
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-[#0A6BBF] text-white text-[10px] font-bold uppercase tracking-widest px-3 py-1 rounded">
                    Recomendado
                  </div>
                )}
                <div className="p-6 border-b border-slate-200">
                  <div className="text-[10px] font-semibold uppercase tracking-widest text-slate-500">{p.tier}</div>
                  <div className="text-xl font-bold text-[#0B1D34] mt-1">{p.nome}</div>
                  <div className="text-xs text-slate-600 mt-1">{p.publico}</div>
                  <div className="text-xs text-slate-500 mt-1">{p.limite}</div>
                </div>
                <div className="p-6 border-b border-slate-200">
                  {p.consulta ? (
                    <div>
                      <div className="text-sm text-slate-500 mb-1">Sob consulta</div>
                      <div className="text-lg font-semibold text-[#0B1D34]">Contrato personalizado</div>
                      <div className="text-xs text-slate-500 mt-1">Fale com um especialista</div>
                    </div>
                  ) : (
                    <div>
                      <div className="flex items-baseline gap-1">
                        <span className="text-sm text-slate-500">R$</span>
                        <span className="text-3xl font-bold text-[#0B1D34]">{formatarPreco(p.base)}</span>
                        <span className="text-sm text-slate-500">/mês</span>
                      </div>
                      {cicloAtual.discount > 0 && (
                        <div className="text-xs text-slate-400 line-through mt-1">R$ {p.base.toLocaleString("pt-BR")}/mês regular</div>
                      )}
                      {ciclo !== "mensal" && (
                        <div className="text-xs text-slate-600 mt-1">
                          Total do ciclo: <strong>R$ {formatarTotalCiclo(p.base)}</strong>
                        </div>
                      )}
                      {ciclo === "semestral" && (
                        <div className="text-xs font-semibold text-[#FF8A00] mt-2">🔥 Preço de lançamento</div>
                      )}
                    </div>
                  )}
                </div>
                <div className="p-6 flex-1">
                  <ul className="space-y-3 text-[15px] leading-relaxed">
                    {p.modulos.map((m) => (
                      <li key={m} className="flex items-start gap-2.5 text-[#0B1D34]">
                        <CheckCircle2 className="w-5 h-5 text-[#21A365] flex-shrink-0 mt-0.5" />
                        <span className="font-medium">{m}</span>
                      </li>
                    ))}
                  </ul>
                </div>
                <div className="p-6 pt-0">
                  <button
                    type="button"
                    disabled={loadingPlano === p.id}
                    onClick={() => handleAssinar(p)}
                    className={`w-full inline-flex items-center justify-center gap-2 font-semibold text-sm py-2.5 rounded-md transition disabled:opacity-60 disabled:cursor-not-allowed ${
                      p.destaque
                        ? "bg-[#0A6BBF] hover:bg-[#0959a3] text-white"
                        : p.id === "enterprise"
                        ? "bg-[#0B1D34] hover:bg-[#132a4b] text-white"
                        : "border border-slate-300 hover:border-[#0A6BBF] hover:text-[#0A6BBF] text-slate-700"
                    }`}
                  >
                    {loadingPlano === p.id
                      ? "Redirecionando..."
                      : p.consulta
                      ? "Falar com especialista"
                      : `Assinar ${p.nome}`}
                  </button>
                </div>
              </div>
            ))}
          </div>

          <p className="text-xs text-slate-500 mt-8 max-w-3xl">
            * Descontos de ciclo e indicação são acumuláveis. Combinando o semestral de lançamento (−50%) com programa de indicação
            (−10%), o desconto pode chegar a −60% durante o período contratado.
          </p>
        </div>
      </section>

      {/* SEGURANÇA */}
      <section id="seguranca" className="py-24 bg-[#0B1D34] text-white">
        <div className="max-w-7xl mx-auto px-6 grid lg:grid-cols-12 gap-12">
          <div className="lg:col-span-5">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">Segurança & LGPD</div>
            <h2 className="text-3xl md:text-4xl font-bold leading-tight">
              Dados sensíveis exigem arquitetura à altura.
            </h2>
            <p className="mt-4 text-slate-300 leading-relaxed">
              Dados isolados por empresa, dados de saúde em bucket privado com classificação por grupos clínicos e
              trilha auditável de cada acesso ou alteração.
            </p>
            <div className="mt-8 flex items-center gap-4">
              <Lock className="w-5 h-5 text-[#21A365]" />
              <span className="text-sm text-slate-300">Isolamento por empresa em 100% dos dados.</span>
            </div>
            <div className="mt-3 flex items-center gap-4">
              <Scale className="w-5 h-5 text-[#21A365]" />
              <span className="text-sm text-slate-300">Assinatura digital com carimbo de auditoria e geolocalização.</span>
            </div>
          </div>
          <div className="lg:col-span-7 grid sm:grid-cols-2 gap-4">
            {CONFIANCA.map((c) => (
              <div key={c.titulo} className="border border-white/10 rounded-lg p-6 bg-white/5">
                <div className="text-lg font-semibold text-white mb-2">{c.titulo}</div>
                <div className="text-sm text-slate-300 leading-relaxed">{c.desc}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* SOBRE */}
      <section id="sobre" className="py-24">
        <div className="max-w-7xl mx-auto px-6 grid lg:grid-cols-12 gap-12 items-start">
          <div className="lg:col-span-5">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">Sobre a YourEyes</div>
            <h2 className="text-3xl md:text-4xl font-bold text-white leading-tight">
              A norma orienta. O sistema operacionaliza.
            </h2>
          </div>
          <div className="lg:col-span-7 space-y-6 text-slate-300 leading-relaxed text-lg">
            <p>
              A YourEyes nasceu para responder uma pergunta simples e desconfortável: sua empresa cresce ou só aumenta?
              Empresa que cresce tem processo, evidência e gente desenvolvida. Empresa que só aumenta acumula caos,
              planilha e dependência de heróis.
            </p>
            <p>
              Nosso propósito é entregar <strong>segurança jurídica ao empregador</strong> por meio de um sistema que gera
              contra-prova documental automática. Cada alerta pode ser convertido em Plano de Ação 5W2H. Cada análise
              alimenta o Escore de Maturidade da organização.
            </p>
            <div className="grid sm:grid-cols-3 gap-6 pt-6 border-t border-white/10">
              <div>
                <Building2 className="w-6 h-6 text-[#60ABEF] mb-2" />
                <div className="font-semibold text-white">Dados isolados por empresa</div>
                <div className="text-sm text-slate-400 mt-1">Cada cliente enxerga apenas suas unidades e colaboradores</div>
              </div>
              <div>
                <Brain className="w-6 h-6 text-[#60ABEF] mb-2" />
                <div className="font-semibold text-white">IA First</div>
                <div className="text-sm text-slate-400 mt-1">GPT-4o em extrações e auditorias</div>
              </div>
              <div>
                <Sparkles className="w-6 h-6 text-[#60ABEF] mb-2" />
                <div className="font-semibold text-white">Auditável</div>
                <div className="text-sm text-slate-400 mt-1">Trilha documental em cada ação</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ DE OBJEÇÕES */}
      <section className="py-24 bg-transparent border-y border-white/10">
        <div className="max-w-4xl mx-auto px-6">
          <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3 text-center">Objeções frequentes</div>
          <h2 className="text-3xl font-bold text-white text-center mb-12">O que costumam nos dizer antes de assinar</h2>
          <div className="space-y-3">
            {FAQ.map((f, i) => (
              <details key={i} className="group bg-white/[0.04] backdrop-blur border border-white/10 rounded-lg">
                <summary className="cursor-pointer list-none px-6 py-4 flex items-center justify-between font-medium text-white">
                  <span>“{f.q}”</span>
                  <span className="text-[#60ABEF] group-open:rotate-180 transition text-lg">▾</span>
                </summary>
                <div className="px-6 pb-5 text-sm text-slate-300 leading-relaxed border-t border-white/10 pt-4">{f.a}</div>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* FECHAMENTO / CONTATO */}
      <section id="contato" className="py-24 bg-white/[0.02] border-t border-white/10">
        <div className="max-w-7xl mx-auto px-6 grid lg:grid-cols-12 gap-12">
          <div className="lg:col-span-5">
            <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">Fechamento</div>
            <h2 className="text-3xl md:text-4xl font-bold text-white leading-tight">
              Toda empresa tem um nível de maturidade. A diferença está em saber qual é o seu — e o que fazer com ele.
            </h2>
            <p className="mt-4 text-slate-300 leading-relaxed">
              Preencha o formulário para agendar seu diagnóstico. Em 30 minutos, mapeamos onde sua operação está exposta
              e mostramos, em tempo real, o seu Painel de Maturidade.
            </p>
            <div className="mt-8 space-y-4">
              <div className="flex items-center gap-3 text-slate-200">
                <Mail className="w-5 h-5 text-[#60ABEF]" />
                <a href="mailto:contato@youreyes.com.br" className="hover:text-[#60ABEF]">contato@youreyes.com.br</a>
              </div>
              <div className="flex items-center gap-3 text-slate-200">
                <Phone className="w-5 h-5 text-[#60ABEF]" />
                <span>Atendimento comercial via WhatsApp</span>
              </div>
              <div className="flex items-center gap-3 text-slate-200">
                <MapPin className="w-5 h-5 text-[#60ABEF]" />
                <span>Brasil · SLA 99,5% garantido</span>
              </div>
            </div>
          </div>
          <div className="lg:col-span-7">
            <form
              className="border border-white/10 rounded-lg p-8 bg-white/[0.04] backdrop-blur shadow-2xl space-y-4"
              onSubmit={(e) => {
                e.preventDefault();
                const data = new FormData(e.currentTarget);
                window.location.href = `mailto:contato@youreyes.com.br?subject=Diagnóstico de Maturidade YourEyes&body=${encodeURIComponent(
                  Array.from(data.entries())
                    .map(([k, v]) => `${k}: ${v}`)
                    .join("\n"),
                )}`;
              }}
            >
              <div className="grid md:grid-cols-2 gap-4">
                <div>
                  <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider">Nome</label>
                  <input name="nome" required className="w-full mt-1 border border-white/15 bg-white/5 text-white placeholder:text-slate-400 rounded-md px-3 py-2 text-sm focus:border-[#60ABEF] focus:ring-1 focus:ring-[#60ABEF] outline-none" />
                </div>
                <div>
                  <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider">Empresa</label>
                  <input name="empresa" required className="w-full mt-1 border border-white/15 bg-white/5 text-white placeholder:text-slate-400 rounded-md px-3 py-2 text-sm focus:border-[#60ABEF] focus:ring-1 focus:ring-[#60ABEF] outline-none" />
                </div>
                <div>
                  <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider">E-mail corporativo</label>
                  <input type="email" name="email" required className="w-full mt-1 border border-white/15 bg-white/5 text-white placeholder:text-slate-400 rounded-md px-3 py-2 text-sm focus:border-[#60ABEF] focus:ring-1 focus:ring-[#60ABEF] outline-none" />
                </div>
                <div>
                  <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider">Nº de colaboradores</label>
                  <select name="colaboradores" className="w-full mt-1 border border-white/15 bg-white/5 text-white placeholder:text-slate-400 rounded-md px-3 py-2 text-sm focus:border-[#60ABEF] focus:ring-1 focus:ring-[#60ABEF] outline-none">
                    <option>Até 20</option>
                    <option>21 a 80</option>
                    <option>81 a 200</option>
                    <option>201 a 500</option>
                    <option>500+</option>
                  </select>
                </div>
              </div>
              <div>
                <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider">Onde mais dói hoje?</label>
                <textarea name="mensagem" rows={4} className="w-full mt-1 border border-white/15 bg-white/5 text-white placeholder:text-slate-400 rounded-md px-3 py-2 text-sm focus:border-[#60ABEF] focus:ring-1 focus:ring-[#60ABEF] outline-none" placeholder="Pessoas, jornada, SST, documentos, metas..." />
              </div>
              <button
                type="submit"
                className="w-full bg-[#FF8A00] hover:bg-[#e67a00] text-white font-semibold py-3 rounded-md transition inline-flex items-center justify-center gap-2"
              >
                Medir a maturidade da minha empresa <ArrowRight className="w-4 h-4" />
              </button>
              <p className="text-xs text-slate-500 text-center">
                Ao enviar, você concorda com nossa{" "}
                <Link to="/politica-de-privacidade" className="underline">Política de Privacidade</Link>.
              </p>
            </form>
          </div>
        </div>
      </section>

      {/* FOOTER */}
      <footer className="bg-[#0B1D34] text-slate-300 py-16">
        <div className="max-w-7xl mx-auto px-6 grid md:grid-cols-4 gap-10">
          <div>
            <div className="flex items-center gap-3 mb-4">
              <img src={logoLocal} alt="YourEyes" className="h-8 w-auto" />
              <div className="font-bold text-white">YourEyes</div>
            </div>
            <p className="text-sm leading-relaxed text-slate-400">
              Sistema Operacional da Maturidade Organizacional.
            </p>
          </div>
          <div>
            <div className="text-xs uppercase tracking-widest text-white font-semibold mb-4">Plataforma</div>
            <ul className="space-y-2 text-sm">
              <li><a href="#problema" className="hover:text-white">Problema</a></li>
              <li><a href="#niveis" className="hover:text-white">Níveis</a></li>
              <li><a href="#plataforma" className="hover:text-white">Plataforma</a></li>
              <li><a href="#planos" className="hover:text-white">Planos</a></li>
              <li><a href="#seguranca" className="hover:text-white">Segurança</a></li>
              <li><Link to="/parceiros" className="hover:text-white">Programa de Parceiros</Link></li>
              <li><Link to="/marketye" className="hover:text-white">MarketYE · marketplace de serviços</Link></li>
            </ul>
          </div>
          <div>
            <div className="text-xs uppercase tracking-widest text-white font-semibold mb-4">Empresa</div>
            <ul className="space-y-2 text-sm">
              <li><a href="#sobre" className="hover:text-white">Sobre</a></li>
              <li><a href="#contato" className="hover:text-white">Contato</a></li>
              <li><Link to="/login" className="hover:text-white">Entrar ou cadastrar</Link></li>
            </ul>
          </div>
          <div>
            <div className="text-xs uppercase tracking-widest text-white font-semibold mb-4">Legal</div>
            <ul className="space-y-2 text-sm">
              <li><Link to="/termos-de-uso" className="hover:text-white">Termos de Uso</Link></li>
              <li><Link to="/politica-de-privacidade" className="hover:text-white">Política de Privacidade</Link></li>
              <li><span className="text-slate-500">LGPD compliant</span></li>
            </ul>
          </div>
        </div>
        <div className="max-w-7xl mx-auto px-6 mt-12 pt-8 border-t border-white/10 flex flex-col md:flex-row justify-between gap-4 text-xs text-slate-500">
          <span>© {new Date().getFullYear()} YourEyes. Todos os direitos reservados.</span>
          <span>Sua empresa cresce — ou só aumenta?</span>
        </div>
      </footer>
    </div>
  );
}

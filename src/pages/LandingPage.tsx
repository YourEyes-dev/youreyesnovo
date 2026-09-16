import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { capturarRefDaUrl, lerRef } from "@/lib/parceiroRef";
import { motion, AnimatePresence } from "framer-motion";
import { 
  Shield, AlertTriangle, CheckCircle, ArrowRight, Clock, 
  Users, Brain, FileWarning, TrendingDown, Zap, Lock,
  ChevronDown, Star, Award, BarChart3, Heart, Bot,
  FileText, ClipboardCheck, Stethoscope, Gavel, Eye,
  MessageSquare, Briefcase, GraduationCap, Target, 
  CalendarCheck, Fingerprint, Building2, Sparkles,
  ShieldCheck, LayoutDashboard, Cpu, Globe, Megaphone,
  TrendingUp, UserCheck, Lightbulb, Scale
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import mockupDashboard from "@/assets/landing/mockup-dashboard.png";
import mockupPsicossocial from "@/assets/landing/mockup-psicossocial.png";
import mockupGovernanca from "@/assets/landing/mockup-governanca.png";
import mockupConfiguracoes from "@/assets/landing/mockup-configuracoes.png";
import logoYoureyes from "@/assets/logo-youreyes.png";
import { DiagnosticoQuiz } from "@/components/landing/DiagnosticoQuiz";

const WHATSAPP_NUMBER = "5546993375044";
const WHATSAPP_MESSAGE = encodeURIComponent(
  "Olá! Vim pelo site da YourEyes e gostaria de agendar uma demonstração da plataforma."
);
const WHATSAPP_URL = `https://wa.me/${WHATSAPP_NUMBER}?text=${WHATSAPP_MESSAGE}`;
const openWhatsApp = () => window.open(WHATSAPP_URL, "_blank", "noopener,noreferrer");

const scrollToDiag = () => {
  document.getElementById("diagnostico")?.scrollIntoView({ behavior: "smooth", block: "start" });
};

// CTA persuasivo reutilizável que rola até o diagnóstico
function DiagCTA({ children = "Fazer diagnóstico grátis em 60s", subtitle, variant = "primary", size = "lg" }: {
  children?: React.ReactNode;
  subtitle?: string;
  variant?: "primary" | "outline";
  size?: "lg" | "md";
}) {
  return (
    <div className="flex flex-col items-center gap-2">
      <Button
        size="lg"
        onClick={scrollToDiag}
        className={`group text-white font-black tracking-wide rounded-xl shadow-2xl whitespace-normal h-auto transition-transform hover:scale-[1.03] active:scale-95 ${size === "lg" ? "text-base sm:text-lg px-6 sm:px-10 py-6 sm:py-7" : "text-sm sm:text-base px-5 py-5"}`}
        style={
          variant === "primary"
            ? { background: 'linear-gradient(135deg, hsl(25 65% 42%), hsl(25 75% 32%))', boxShadow: '0 10px 40px hsl(25 65% 42% / 0.4)' }
            : { background: 'transparent', border: '2px solid hsl(25 60% 50%)', color: 'hsl(25 60% 60%)' }
        }
      >
        <Brain className="w-5 h-5 mr-2 shrink-0" />
        {children}
        <ArrowRight className="w-5 h-5 ml-2 shrink-0 group-hover:translate-x-1 transition-transform" />
      </Button>
      {subtitle && <p className="text-xs text-gray-500">{subtitle}</p>}
    </div>
  );
}

const fadeUp = {
  initial: { opacity: 0, y: 30 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true },
  transition: { duration: 0.6 },
};

const pulseGlow = {
  initial: { boxShadow: '0 0 0 0px hsl(33 100% 50% / 0.4)' },
  animate: { 
    boxShadow: ['0 0 0 0px hsl(33 100% 50% / 0.4)', '0 0 0 15px hsl(33 100% 50% / 0)', '0 0 0 0px hsl(33 100% 50% / 0)'],
    transition: { duration: 2, repeat: Infinity }
  }
};

export default function LandingPage() {
  useEffect(() => { capturarRefDaUrl(); }, []);
  const navigate = useNavigate();
  const [vagasRestantes, setVagasRestantes] = useState(4);
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [whatsapp, setWhatsapp] = useState("");
  const [loading, setLoading] = useState(false);
  const [showFormulario, setShowFormulario] = useState(false);
  const [leadEnviado, setLeadEnviado] = useState(false);

  useEffect(() => {
    fetchVagas();
  }, []);

  const fetchVagas = async () => {
    const { data } = await supabase
      .from("landing_vagas")
      .select("*")
      .eq("ativo", true)
      .limit(1)
      .maybeSingle();
    if (data) {
      // Garante mínimo de 6 vagas ocupadas para efeito de prova social
      const ocupadasReais = data.vagas_preenchidas ?? 0;
      const ocupadas = Math.max(6, ocupadasReais);
      setVagasRestantes(Math.max(0, data.total_vagas - ocupadas));
    }
  };

  const formatWhatsapp = (v: string) => {
    const digits = v.replace(/\D/g, "").substring(0, 11);
    if (digits.length <= 2) return digits;
    if (digits.length <= 7) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`;
    if (digits.length <= 10) return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
  };

  const handleSubmitLead = async () => {
    if (!nome.trim() || !email.trim() || !whatsapp.trim()) {
      toast.error("Preencha nome, e-mail e WhatsApp");
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      toast.error("E-mail inválido");
      return;
    }
    const digits = whatsapp.replace(/\D/g, "");
    if (digits.length < 10 || digits.length > 11) {
      toast.error("WhatsApp inválido. Use DDD + número");
      return;
    }
    setLoading(true);
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from("landing_leads").insert({
        nome: nome.trim().substring(0, 100),
        email: email.trim().substring(0, 255),
        telefone: digits,
        ref_codigo: lerRef(),
      });
      setLeadEnviado(true);
      toast.success("Cadastro realizado! Garanta sua vaga agora.");
    } catch {
      toast.error("Erro ao enviar. Tente novamente.");
    } finally {
      setLoading(false);
    }
  };

  const scrollToSection = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth" });
  };

  return (
    <div className="min-h-screen bg-[#050d1a] text-white overflow-x-hidden">
      {/* Floating urgency bar */}
      <div className="fixed top-0 left-0 right-0 z-50 py-2 text-[11px] sm:text-sm font-bold shadow-lg overflow-hidden" style={{ background: 'linear-gradient(90deg, hsl(207 90% 25%), hsl(207 90% 38%), hsl(207 90% 25%))' }}>
        {/* Desktop: estático e centralizado */}
        <div className="hidden sm:flex items-center justify-center gap-3 px-3 leading-tight">
          <span className="flex items-center gap-1">
            <Clock className="w-3.5 h-3.5 shrink-0" />
            ⚠️ NR-01 ATUALIZADA — Fatores de fatores de riscos psicossociais agora são OBRIGATÓRIOS. Multas de até R$ 50.000 por infração.
          </span>
          {vagasRestantes > 0 && (
            <span className="px-2 py-0.5 rounded-full text-xs font-black shrink-0" style={{ background: 'hsl(33 100% 50%)', color: '#fff' }}>
              🔥 {vagasRestantes} vagas
            </span>
          )}
        </div>
        {/* Mobile: marquee com texto completo */}
        <div className="sm:hidden relative w-full overflow-hidden">
          <div className="flex whitespace-nowrap animate-marquee">
            {[0, 1].map((i) => (
              <span key={i} className="flex items-center gap-2 px-4 shrink-0">
                <Clock className="w-3 h-3 shrink-0" />
                <span>⚠️ NR-01 ATUALIZADA — Fatores de fatores de riscos psicossociais agora são OBRIGATÓRIOS. Multas de até R$ 50.000 por infração.</span>
                {vagasRestantes > 0 && (
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-black shrink-0" style={{ background: 'hsl(33 100% 50%)', color: '#fff' }}>
                    🔥 {vagasRestantes} vagas
                  </span>
                )}
              </span>
            ))}
          </div>
        </div>
      </div>

      {/* ═══════════ HERO ═══════════ */}
      <section className="relative pt-32 pb-16 px-4 min-h-screen flex items-center justify-center overflow-hidden">
        <div className="absolute inset-0" style={{ background: 'radial-gradient(circle at 50% 50%, hsl(215 60% 12%) 0%, hsl(215 65% 7%) 100%)' }} />
        
        {/* Animated Background Elements */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <div className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] rounded-full blur-[120px] opacity-20 animate-pulse" style={{ background: 'hsl(207 90% 45%)' }} />
          <div className="absolute bottom-[-10%] right-[-10%] w-[40%] h-[40%] rounded-full blur-[120px] opacity-20 animate-pulse" style={{ background: 'hsl(33 100% 50%)', animationDelay: '1s' }} />
          
          {/* Grid Pattern */}
          <div className="absolute inset-0 opacity-[0.03]" style={{ backgroundImage: 'radial-gradient(circle, white 1px, transparent 1px)', backgroundSize: '40px 40px' }} />
        </div>
        
        <div className="relative max-w-6xl mx-auto text-center">
          <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8 }}>
            <motion.div
              animate={{ 
                scale: [1, 1.03, 1],
                transition: { duration: 3, repeat: Infinity }
              }}
            >
              <Badge className="mb-6 text-sm px-4 py-1.5 cursor-default select-none" style={{ background: 'hsl(33 100% 50% / 0.15)', color: 'hsl(33 100% 65%)', borderColor: 'hsl(33 100% 50% / 0.3)' }}>
                <AlertTriangle className="w-4 h-4 mr-2" />
                ALERTA: Sua empresa pode estar em risco AGORA
              </Badge>
            </motion.div>

            <h1 className="text-4xl sm:text-5xl md:text-7xl lg:text-8xl font-black leading-[1.1] mb-8 break-words tracking-tighter">
              Sua empresa está pronta para a{" "}
              <span className="relative inline-block">
                <span className="relative z-10" style={{ color: 'hsl(25 70% 55%)' }}>
                  maior fiscalização trabalhista
                </span>
                <motion.span 
                  className="absolute bottom-1 sm:bottom-2 left-0 w-full h-[30%] -z-0 opacity-25 rounded-sm"
                  style={{ background: 'hsl(25 66% 45%)' }}
                  initial={{ scaleX: 0 }}
                  whileInView={{ scaleX: 1 }}
                  transition={{ delay: 0.8, duration: 1 }}
                />
              </span>{" "}
              dos últimos 20 anos?
            </h1>

            {/* MOCKUP - logo após o título principal */}
            <motion.div
              initial={{ opacity: 0, y: 40 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.3, duration: 0.8 }}
              className="my-16 max-w-5xl mx-auto relative"
            >
              {/* Decorative elements around video */}
              <div className="absolute -top-6 -left-6 w-24 h-24 border-t-2 border-l-2 border-hsl(207 90% 45% / 0.3) rounded-tl-2xl hidden md:block" />
              <div className="absolute -bottom-6 -right-6 w-24 h-24 border-b-2 border-r-2 border-hsl(33 100% 50% / 0.3) rounded-br-2xl hidden md:block" />

              <div
                className="relative rounded-2xl overflow-hidden shadow-[0_32px_128px_-16px_rgba(0,0,0,0.5)] border border-white/5 bg-white/5 backdrop-blur-sm p-1"
                style={{ boxShadow: '0 30px 80px -20px hsl(25 66% 40% / 0.35)' }}
              >
                <div className="absolute inset-0 bg-gradient-to-tr from-blue-500/10 via-transparent to-orange-500/10 pointer-events-none" />
                <img
                  src={mockupDashboard}
                  alt="YourEyes Dashboard"
                  className="w-full h-auto block rounded-xl relative z-10 shadow-2xl"
                />
              </div>
              <p className="text-center text-[10px] uppercase tracking-widest text-gray-500 mt-6 font-bold opacity-60">
                Plataforma completa para gestão de riscos psicossociais
              </p>
            </motion.div>

            <p className="text-lg md:text-xl text-gray-300 max-w-3xl mx-auto mb-4">
              A NR-01 mudou. Agora <strong className="text-white">riscos psicossociais são obrigatórios</strong> no GRO/PGR —
              e o MTE já está autuando. Multas de até <strong style={{ color: 'hsl(33 100% 60%)' }}>R$ 50 mil por infração</strong>,
              interdição e processos por burnout.
            </p>

            <p className="text-base text-gray-500 max-w-2xl mx-auto mb-10">
              <strong className="text-white">97% das empresas brasileiras NÃO estão preparadas.</strong>
              Descubra em 60 segundos onde a sua está exposta — receba um diagnóstico personalizado e fale com um especialista.
            </p>

            <div className="flex flex-col items-center gap-3 mb-8">
              <DiagCTA subtitle="Sem cadastro de cartão • Resultado em tempo real" />
            </div>

            <div className="flex flex-wrap justify-center gap-6 text-sm text-gray-500">
              <span className="flex items-center gap-1"><CheckCircle className="w-4 h-4" style={{ color: 'hsl(25 50% 50%)' }} /> 60 segundos</span>
              <span className="flex items-center gap-1"><CheckCircle className="w-4 h-4" style={{ color: 'hsl(25 50% 50%)' }} /> 100% confidencial</span>
              <span className="flex items-center gap-1"><CheckCircle className="w-4 h-4" style={{ color: 'hsl(25 50% 50%)' }} /> Diagnóstico personalizado</span>
            </div>
          </motion.div>

          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1.5, duration: 1 }} className="mt-10">
            <ChevronDown className="w-8 h-8 mx-auto text-gray-600 animate-bounce" />
          </motion.div>
        </div>
      </section>

      {/* ═══════════ PAIN SECTION ═══════════ */}
      <section className="py-20 px-4" style={{ background: 'linear-gradient(180deg, hsl(215 65% 7%) 0%, hsl(215 60% 10%) 100%)' }}>
        <div className="max-w-6xl mx-auto">
          <motion.div {...fadeUp}>
            <h2 className="text-3xl md:text-5xl font-black text-center mb-4">
              O que acontece com quem <span style={{ color: 'hsl(33 100% 50%)' }}>ignora</span> a NR-01?
            </h2>
            <p className="text-gray-400 text-center max-w-2xl mx-auto mb-16">
              A fiscalização não avisa. Ela chega. E quando chega, o prejuízo é irreversível.
            </p>
          </motion.div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            {[
              { icon: FileWarning, title: "Multas de até R$ 50.000", desc: "Por infração. Reincidência dobra o valor. Uma única visita do MTE pode custar mais que 5 anos de prevenção.", color: "hsl(33 100% 50%)", bg: "hsl(33 100% 50% / 0.1)" },
              { icon: Lock, title: "Interdição Total", desc: "Sua empresa pode ser PARADA. Sem produção, sem faturamento, sem folha. Até a adequação completa.", color: "hsl(207 90% 55%)", bg: "hsl(207 90% 45% / 0.1)" },
              { icon: TrendingDown, title: "Processos Trabalhistas", desc: "Burnout, assédio e danos morais. Um único processo pode ultrapassar R$ 200.000 em indenizações.", color: "hsl(38 90% 55%)", bg: "hsl(38 90% 50% / 0.1)" },
              { icon: Users, title: "Perda de Talentos", desc: "Colaboradores adoecidos pedem demissão. O custo de turnover chega a 213% do salário anual.", color: "hsl(25 66% 50%)", bg: "hsl(25 66% 50% / 0.1)" },
            ].map((item, i) => (
              <motion.div key={i} {...fadeUp} transition={{ delay: i * 0.1 }}>
                <div 
                  className="rounded-2xl p-8 h-full transition-all duration-300 hover:scale-[1.02] group relative overflow-hidden" 
                  style={{ 
                    background: 'linear-gradient(135deg, rgba(255,255,255,0.03) 0%, rgba(255,255,255,0.01) 100%)', 
                    border: '1px solid rgba(255,255,255,0.05)',
                    backdropFilter: 'blur(10px)'
                  }}
                >
                  <div className="absolute inset-0 bg-gradient-to-br opacity-0 group-hover:opacity-10 transition-opacity duration-500" style={{ backgroundImage: `linear-gradient(135deg, ${item.color}, transparent)` }} />
                  
                  <div className="w-14 h-14 rounded-2xl flex items-center justify-center mb-6 shadow-lg transition-transform group-hover:rotate-6" style={{ background: item.bg, border: `1px solid ${item.color}20` }}>
                    <item.icon className="w-7 h-7" style={{ color: item.color }} />
                  </div>
                  <h3 className="text-xl font-bold mb-3 tracking-tight group-hover:text-white transition-colors">{item.title}</h3>
                  <p className="text-gray-400 text-sm leading-relaxed group-hover:text-gray-300 transition-colors">{item.desc}</p>
                </div>
              </motion.div>
            ))}
          </div>

          <motion.div {...fadeUp} className="mt-14 text-center">
            <p className="text-gray-300 text-lg mb-5">
              Não espere a fiscalização chegar para descobrir onde sua empresa está vulnerável.
            </p>
            <DiagCTA subtitle="Resultado na hora • Especialista entra em contato">
              Descobrir meus riscos agora
            </DiagCTA>
          </motion.div>
        </div>
      </section>

      {/* ═══════════ IA SECTION ═══════════ */}
      <section className="py-20 px-4 relative overflow-hidden" style={{ background: 'hsl(215 60% 10%)' }}>
        <div className="absolute top-0 right-0 w-[500px] h-[500px] rounded-full blur-[200px]" style={{ background: 'hsl(207 90% 45% / 0.05)' }} />
        <div className="max-w-6xl mx-auto relative">
          {/* ═══════════ BIG NUMBERS SECTION ═══════════ */}
          <div className="mb-32">
            <motion.div {...fadeUp} className="text-center mb-16">
              <h2 className="text-3xl md:text-5xl font-black mb-4">
                Números que tiram o <span style={{ color: 'hsl(33 100% 50%)' }}>sono</span> do empregador
              </h2>
              <p className="text-gray-400 max-w-2xl mx-auto text-lg">
                Ignorar a conformidade legal não é uma economia. É um risco financeiro de proporções catastróficas.
              </p>
            </motion.div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-8 text-center">
              {[
                { number: "R$ 100 Bi", label: "Custos anuais das empresas com processos trabalhistas no Brasil", icon: TrendingDown, color: "hsl(33 100% 50%)" },
                { number: "213%", label: "Do salário anual é o custo médio para substituir um talento perdido por burnout", icon: Users, color: "hsl(207 90% 55%)" },
                { number: "R$ 50 Mil", label: "Multa máxima POR INFRAÇÃO em caso de descumprimento das NRs", icon: Scale, color: "hsl(25 66% 50%)" },
              ].map((stat, i) => (
                <motion.div 
                  key={stat.label}
                  {...fadeUp}
                  transition={{ delay: i * 0.1 }}
                  className="p-10 rounded-[2rem] relative overflow-hidden group transition-all duration-500 hover:-translate-y-2"
                  style={{ 
                    background: 'rgba(255,255,255,0.02)', 
                    border: '1px solid rgba(255,255,255,0.05)',
                    boxShadow: '0 20px 40px rgba(0,0,0,0.2)'
                  }}
                >
                  <div className="absolute -right-4 -bottom-4 opacity-[0.05] group-hover:opacity-[0.1] transition-opacity duration-500">
                    <stat.icon size={160} style={{ color: stat.color }} />
                  </div>
                  
                  <div className="relative z-10">
                    <motion.div 
                      className="text-6xl md:text-7xl font-black mb-6 tracking-tighter"
                      style={{ color: stat.color, textShadow: `0 0 30px ${stat.color}40` }}
                      initial={{ scale: 0.8 }}
                      whileInView={{ scale: 1 }}
                      transition={{ type: "spring", stiffness: 100 }}
                    >
                      {stat.number}
                    </motion.div>
                    <p className="text-gray-300 font-semibold text-lg leading-snug group-hover:text-white transition-colors">{stat.label}</p>
                  </div>
                </motion.div>
              ))}
            </div>
          </div>

          <motion.div {...fadeUp} className="text-center mb-16">
            <Badge className="mb-4" style={{ background: 'hsl(207 90% 45% / 0.15)', color: 'hsl(25 66% 55%)', borderColor: 'hsl(207 90% 45% / 0.3)' }}>
              <Sparkles className="w-4 h-4 mr-1" /> INTELIGÊNCIA ARTIFICIAL
            </Badge>
            <h2 className="text-3xl md:text-5xl font-black mb-4">
              IA que <span style={{ backgroundImage: 'linear-gradient(90deg, hsl(207 90% 55%), hsl(25 66% 55%))', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>trabalha por você</span> 24 horas por dia
            </h2>
            <p className="text-gray-400 max-w-3xl mx-auto text-lg">
              Enquanto seus concorrentes usam planilhas, o YourEyes usa <strong className="text-white">GPT-4o e visão computacional</strong> para automatizar 
              o que antes levava semanas. Isso não é marketing — é tecnologia real rodando agora.
            </p>
          </motion.div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            {[
              { icon: Brain, title: "Psicossocial NR-01", desc: "O motor psicossocial cruza dados de Ponto, Atestados, Ouvidoria, Avaliações, Turnover e Ocorrências em tempo real para detectar burnout e assédio antes da fiscalização." },
              { icon: Fingerprint, title: "EPI com Facial", desc: "Cada entrega é validada por liveness + biometria facial — prova jurídica indiscutível para o eSocial S-2240 e auditorias trabalhistas." },
              { icon: Eye, title: "Leitura IA (OCR)", desc: "Foto de NF-e, atestado médico, ASO ou DANFE: a IA extrai CID, dias de afastamento, valores e classifica automaticamente." },
              { icon: MessageSquare, title: "Ouvidoria com IA", desc: "Classifica denúncias por sentimento, urgência e categoria (assédio, ética, segurança). Identifica reincidência e sugere encaminhamento." },
              { icon: Target, title: "PDI Inteligente", desc: "Planos de Desenvolvimento Individual gerados automaticamente após avaliações, com metas SMART personalizadas por cargo." },
              { icon: ClipboardCheck, title: "Detecção Automática", desc: "Monitora turnover, horas extras, atestados mentais e ocorrências disciplinares — gatilhos automáticos para campanhas extraordinárias." },
            ].map((item, i) => (
              <motion.div key={i} {...fadeUp} transition={{ delay: i * 0.08 }}>
                <div className="rounded-2xl p-8 h-full transition-all duration-300 hover:bg-white/[0.05] group border border-white/5 bg-white/[0.02] backdrop-blur-md">
                  <div className="w-12 h-12 rounded-xl flex items-center justify-center mb-6 bg-gradient-to-br from-blue-500/20 to-emerald-500/20 group-hover:scale-110 transition-transform">
                    <item.icon className="w-6 h-6" style={{ color: 'hsl(25 66% 55%)' }} />
                  </div>
                  <h3 className="text-lg font-bold mb-3 tracking-tight group-hover:text-emerald-400 transition-colors">{item.title}</h3>
                  <p className="text-gray-400 text-sm leading-relaxed">{item.desc}</p>
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══════════ PSYCHOSOCIAL DEEP DIVE ═══════════ */}
      <section className="relative py-24 px-4 overflow-hidden" style={{ background: 'linear-gradient(180deg, hsl(215 60% 10%) 0%, hsl(215 70% 6%) 100%)' }}>
        {/* Ambient glow orbs */}
        <div className="absolute inset-0 pointer-events-none overflow-hidden">
          <motion.div
            className="absolute -top-40 -left-40 w-[500px] h-[500px] rounded-full opacity-30 blur-3xl"
            style={{ background: 'radial-gradient(circle, hsl(33 100% 50% / 0.6), transparent 70%)' }}
            animate={{ x: [0, 60, 0], y: [0, 40, 0] }}
            transition={{ duration: 14, repeat: Infinity, ease: 'easeInOut' }}
          />
          <motion.div
            className="absolute -bottom-40 -right-40 w-[600px] h-[600px] rounded-full opacity-25 blur-3xl"
            style={{ background: 'radial-gradient(circle, hsl(207 90% 55% / 0.6), transparent 70%)' }}
            animate={{ x: [0, -80, 0], y: [0, -60, 0] }}
            transition={{ duration: 18, repeat: Infinity, ease: 'easeInOut' }}
          />
          {/* subtle grid */}
          <div className="absolute inset-0 opacity-[0.04]" style={{ backgroundImage: 'linear-gradient(hsl(33 100% 50%) 1px, transparent 1px), linear-gradient(90deg, hsl(33 100% 50%) 1px, transparent 1px)', backgroundSize: '60px 60px' }} />
        </div>

        <div className="relative max-w-6xl mx-auto">
          <motion.div {...fadeUp} className="text-center mb-16">
            <motion.div
              initial={{ scale: 0.8, opacity: 0 }}
              whileInView={{ scale: 1, opacity: 1 }}
              viewport={{ once: true }}
              className="inline-flex"
            >
              <Badge className="mb-5 px-4 py-1.5 text-xs tracking-widest" style={{ background: 'linear-gradient(90deg, hsl(33 100% 50% / 0.2), hsl(0 80% 55% / 0.2))', color: 'hsl(33 100% 65%)', border: '1px solid hsl(33 100% 50% / 0.4)', boxShadow: '0 0 30px hsl(33 100% 50% / 0.3)' }}>
                <AlertTriangle className="w-4 h-4 mr-1.5" /> NR-01 — OBRIGATÓRIO DESDE MAIO/2025
              </Badge>
            </motion.div>
            <h2 className="text-4xl md:text-6xl font-black mb-5 leading-tight tracking-tight">
              Gestão Psicossocial{' '}
              <span className="relative inline-block">
                <span style={{ backgroundImage: 'linear-gradient(135deg, hsl(33 100% 60%) 0%, hsl(15 90% 55%) 50%, hsl(0 85% 60%) 100%)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent', filter: 'drop-shadow(0 0 24px hsl(33 100% 50% / 0.5))' }}>
                  Completa
                </span>
              </span>
              <br className="hidden md:block" />
              {' '}e <span className="text-white">Automatizada</span>
            </h2>
            <p className="text-gray-300 max-w-3xl mx-auto text-lg md:text-xl leading-relaxed">
              O YourEyes é a <strong className="text-white" style={{ borderBottom: '2px solid hsl(33 100% 50%)' }}>única plataforma</strong> que cobre 100% dos fatores de riscos psicossociais exigidos pela NR-01,
              com questionários validados, indicadores automáticos e relatórios prontos para a fiscalização.
            </p>
          </motion.div>

          <div className="grid md:grid-cols-2 gap-6 lg:gap-8">
            {/* Card 1 — Questionário */}
            <motion.div
              {...fadeUp}
              whileHover={{ y: -6 }}
              className="group relative rounded-3xl p-8 backdrop-blur-xl overflow-hidden"
              style={{
                background: 'linear-gradient(135deg, hsl(215 60% 14% / 0.9), hsl(215 65% 10% / 0.9))',
                border: '1px solid hsl(207 90% 55% / 0.25)',
                boxShadow: '0 20px 60px -20px hsl(207 90% 30% / 0.4), inset 0 1px 0 hsl(207 90% 60% / 0.1)',
              }}
            >
              {/* corner glow */}
              <div className="absolute -top-20 -right-20 w-60 h-60 rounded-full opacity-40 blur-3xl group-hover:opacity-70 transition-opacity" style={{ background: 'radial-gradient(circle, hsl(207 90% 55%), transparent 70%)' }} />

              <div className="relative">
                <div className="flex items-center gap-3 mb-6">
                  <div className="p-3 rounded-2xl" style={{ background: 'linear-gradient(135deg, hsl(207 90% 55%), hsl(220 90% 50%))', boxShadow: '0 10px 30px hsl(207 90% 50% / 0.4)' }}>
                    <FileText className="w-6 h-6 text-white" />
                  </div>
                  <div>
                    <h3 className="text-xl font-black tracking-tight">Questionário NR-01 Completo</h3>
                    <p className="text-xs text-gray-500 font-medium">14 blocos · validação científica</p>
                  </div>
                </div>

                <div className="space-y-2.5 text-sm text-gray-300">
                  {[
                    "14 blocos temáticos cobrindo TODOS os fatores de risco",
                    "R01: Assédio e Violência no Trabalho",
                    "R02: Gestão de Mudanças Organizacionais",
                    "R08: Eventos Violentos e Traumáticos",
                    "R12: Comunicação Organizacional",
                    "Escala de 5 níveis (0 a 4) com matriz de risco NR-01",
                    "100% anônimo — privacidade garantida (mín. 5 respondentes)",
                    "Ciclos regulares e extraordinários por gatilhos",
                  ].map((item, i) => (
                    <motion.div
                      key={i}
                      initial={{ opacity: 0, x: -10 }}
                      whileInView={{ opacity: 1, x: 0 }}
                      viewport={{ once: true }}
                      transition={{ delay: i * 0.04 }}
                      className="flex items-start gap-2.5 p-2 rounded-lg hover:bg-white/[0.03] transition-colors"
                    >
                      <div className="mt-0.5 shrink-0 p-0.5 rounded-full" style={{ background: 'hsl(207 90% 55% / 0.2)' }}>
                        <CheckCircle className="w-3.5 h-3.5" style={{ color: 'hsl(207 90% 65%)' }} />
                      </div>
                      <span>{item}</span>
                    </motion.div>
                  ))}
                </div>
              </div>
            </motion.div>

            {/* Card 2 — Indicadores */}
            <motion.div
              {...fadeUp}
              transition={{ delay: 0.15 }}
              whileHover={{ y: -6 }}
              className="group relative rounded-3xl p-8 backdrop-blur-xl overflow-hidden"
              style={{
                background: 'linear-gradient(135deg, hsl(215 60% 14% / 0.9), hsl(215 65% 10% / 0.9))',
                border: '1px solid hsl(33 100% 50% / 0.25)',
                boxShadow: '0 20px 60px -20px hsl(33 100% 30% / 0.4), inset 0 1px 0 hsl(33 100% 60% / 0.1)',
              }}
            >
              <div className="absolute -top-20 -right-20 w-60 h-60 rounded-full opacity-40 blur-3xl group-hover:opacity-70 transition-opacity" style={{ background: 'radial-gradient(circle, hsl(33 100% 50%), transparent 70%)' }} />

              <div className="relative">
                <div className="flex items-center gap-3 mb-6">
                  <div className="p-3 rounded-2xl" style={{ background: 'linear-gradient(135deg, hsl(33 100% 55%), hsl(15 90% 50%))', boxShadow: '0 10px 30px hsl(33 100% 50% / 0.4)' }}>
                    <BarChart3 className="w-6 h-6 text-white" />
                  </div>
                  <div>
                    <h3 className="text-xl font-black tracking-tight">Indicadores Automáticos</h3>
                    <p className="text-xs text-gray-500 font-medium">cálculo em tempo real · auditável</p>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  {[
                    { code: "IRP-S", name: "Índice de Risco Psicossocial", icon: Brain },
                    { code: "IBO-S", name: "Índice de Burnout Organizacional", icon: TrendingDown },
                    { code: "IBD-S", name: "Índice de Bem-Estar e Desgaste", icon: Heart },
                    { code: "IREC-S", name: "Índice de Reconhecimento", icon: Award },
                    { code: "ICOP-S", name: "Índice de Cooperação Social", icon: Users },
                    { code: "INOT-S", name: "Índice de Notificações de Risco", icon: AlertTriangle },
                  ].map((ind, i) => (
                    <motion.div
                      key={i}
                      initial={{ opacity: 0, scale: 0.9 }}
                      whileInView={{ opacity: 1, scale: 1 }}
                      viewport={{ once: true }}
                      transition={{ delay: i * 0.06 }}
                      whileHover={{ scale: 1.05, y: -2 }}
                      className="relative rounded-xl p-3 cursor-default overflow-hidden"
                      style={{
                        background: 'linear-gradient(135deg, hsl(215 70% 8%), hsl(215 75% 5%))',
                        border: '1px solid hsl(33 100% 50% / 0.2)',
                      }}
                    >
                      <div className="flex items-start justify-between mb-1.5">
                        <p className="text-xs font-mono font-black tracking-tight" style={{ color: 'hsl(33 100% 65%)', textShadow: '0 0 12px hsl(33 100% 50% / 0.6)' }}>{ind.code}</p>
                        <ind.icon className="w-3.5 h-3.5 opacity-50" style={{ color: 'hsl(33 100% 65%)' }} />
                      </div>
                      <p className="text-[11px] text-gray-400 leading-tight">{ind.name}</p>
                      {/* Animated bar */}
                      <motion.div
                        className="absolute bottom-0 left-0 h-0.5"
                        style={{ background: 'linear-gradient(90deg, hsl(33 100% 50%), hsl(15 90% 55%))' }}
                        initial={{ width: '0%' }}
                        whileInView={{ width: `${60 + (i * 5)}%` }}
                        viewport={{ once: true }}
                        transition={{ delay: 0.3 + i * 0.06, duration: 1 }}
                      />
                    </motion.div>
                  ))}
                </div>

                <div className="mt-5 flex items-center gap-2 p-3 rounded-xl" style={{ background: 'hsl(33 100% 50% / 0.08)', border: '1px dashed hsl(33 100% 50% / 0.3)' }}>
                  <Sparkles className="w-4 h-4 shrink-0" style={{ color: 'hsl(33 100% 65%)' }} />
                  <p className="text-xs text-gray-300">
                    Calculados em tempo real e <strong className="text-white">exportáveis para relatórios</strong> de auditoria.
                  </p>
                </div>
              </div>
            </motion.div>
          </div>
        </div>
      </section>

      {/* ═══════════ ALL MODULES ═══════════ */}
      <section className="py-20 px-4" style={{ background: 'hsl(215 65% 8%)' }}>
        <div className="max-w-6xl mx-auto">
          <motion.div {...fadeUp} className="text-center mb-16">
            <Badge className="mb-4" style={{ background: 'hsl(25 50% 42% / 0.15)', color: 'hsl(25 50% 55%)', borderColor: 'hsl(25 50% 42% / 0.3)' }}>
              <Shield className="w-4 h-4 mr-1" /> PLATAFORMA COMPLETA
            </Badge>
            <h2 className="text-3xl md:text-5xl font-black mb-4">
              <span style={{ backgroundImage: 'linear-gradient(90deg, hsl(207 90% 55%), hsl(25 66% 50%))', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>+30 módulos</span> integrados em uma única plataforma
            </h2>
            <p className="text-gray-400 max-w-3xl mx-auto text-lg">
              Tudo que sua empresa precisa para SST, RH e compliance — sem precisar de 10 softwares diferentes.
            </p>
          </motion.div>

          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {[
              { icon: Brain, name: "Psicossocial NR-01", tag: "IA" },
              { icon: Stethoscope, name: "Saúde Ocupacional" },
              { icon: Shield, name: "Gestão de EPIs" },
              { icon: FileText, name: "Atestados e ASOs" },
              { icon: ClipboardCheck, name: "PGR / GRO" },
              { icon: UserCheck, name: "Admissão Digital" },
              { icon: GraduationCap, name: "Onboarding Automático" },
              { icon: Target, name: "PDIs com IA", tag: "IA" },
              { icon: Star, name: "Avaliações 360°" },
              { icon: BarChart3, name: "9-Box / Talent Review" },
              { icon: CalendarCheck, name: "Controle de Ponto" },
              { icon: Fingerprint, name: "Ponto com Geolocalização" },
              { icon: Heart, name: "Bem-Estar e Clima" },
              { icon: Megaphone, name: "Ouvidoria com IA", tag: "IA" },
              { icon: Gavel, name: "Ocorrências e Advertências" },
              { icon: Scale, name: "Desligamento Estruturado" },
              { icon: Building2, name: "Gestão de Terceiros" },
              { icon: Globe, name: "Marketplace SST" },
              { icon: FileWarning, name: "Guias e Certidões" },
              { icon: TrendingUp, name: "Hub Contábil" },
              { icon: Briefcase, name: "Benefícios e Cargos" },
              { icon: GraduationCap, name: "Trilhas de Aprendizagem" },
              { icon: Award, name: "Certificados e Medalhas" },
              { icon: Lightbulb, name: "Cultura e Valores" },
              { icon: Eye, name: "OCR de Notas Fiscais", tag: "IA" },
              { icon: ShieldCheck, name: "Auditoria e Compliance" },
              { icon: LayoutDashboard, name: "Dashboards Inteligentes" },
              { icon: Users, name: "Multi-Tenant / Multi-Empresa" },
            ].map((mod, i) => (
              <motion.div key={i} {...fadeUp} transition={{ delay: i * 0.03 }}>
                <div className="rounded-xl p-4 h-full transition-colors group relative" style={{ background: 'hsl(215 55% 12%)', border: '1px solid hsl(215 40% 20%)' }}>
                  {mod.tag && (
                    <span className="absolute top-2 right-2 text-[9px] font-bold px-1.5 py-0.5 rounded" style={{ background: 'hsl(33 100% 50% / 0.2)', color: 'hsl(33 100% 60%)' }}>
                      {mod.tag}
                    </span>
                  )}
                  <mod.icon className="w-6 h-6 mb-2 transition-colors" style={{ color: 'hsl(207 90% 60%)' }} />
                  <p className="text-sm font-medium text-gray-300">{mod.name}</p>
                </div>
              </motion.div>
            ))}
          </div>

          <motion.div {...fadeUp} className="text-center mt-12 space-y-5">
            <p className="text-gray-300 text-lg">
              Quer saber <strong className="text-white">quais módulos</strong> sua empresa precisa primeiro?
            </p>
            <DiagCTA subtitle="Indicamos os módulos certos com base no seu perfil">
              Receber recomendação personalizada
            </DiagCTA>
            <p className="text-gray-500 text-xs">
              E muito mais sendo adicionado toda semana. Quem entrar agora, leva <strong className="text-white">TUDO desbloqueado</strong>.
            </p>
          </motion.div>
        </div>
      </section>

      {/* ═══════════ HOW IT WORKS ═══════════ */}
      <section className="py-20 px-4" style={{ background: 'linear-gradient(180deg, hsl(215 65% 8%) 0%, hsl(215 60% 10%) 100%)' }}>
        <div className="max-w-4xl mx-auto">
          <motion.div {...fadeUp} className="text-center mb-16">
            <h2 className="text-3xl md:text-5xl font-black mb-4">
              Comece em <span style={{ color: 'hsl(25 66% 55%)' }}>3 passos simples</span>
            </h2>
          </motion.div>
          <div className="space-y-8">
            {[
              { step: "01", title: "Diagnóstico Rápido", desc: "Responda 7 perguntas críticas e receba um relatório imediato do nível de exposição da sua empresa." },
              { step: "02", title: "Setup Inteligente", desc: "Nossa IA importa seus dados e configura departamentos e cargos automaticamente em minutos." },
              { step: "03", title: "Monitoramento Ativo", desc: "O sistema assume o controle, disparando alertas proativos e gerando conformidade automática." },
            ].map((s, i) => (
              <motion.div key={i} {...fadeUp} transition={{ delay: i * 0.15 }} className="flex gap-8 items-start group">
                <div className="shrink-0 w-20 h-20 rounded-3xl flex items-center justify-center relative" style={{ background: 'linear-gradient(135deg, rgba(255,255,255,0.05) 0%, rgba(255,255,255,0.01) 100%)', border: '1px solid rgba(255,255,255,0.1)' }}>
                  <div className="absolute inset-0 bg-blue-500/10 blur-xl opacity-0 group-hover:opacity-100 transition-opacity" />
                  <span className="text-3xl font-black relative z-10" style={{ backgroundImage: 'linear-gradient(135deg, hsl(207 90% 65%), hsl(25 66% 60%))', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>{s.step}</span>
                </div>
                <div className="pt-2">
                  <h3 className="text-2xl font-black mb-2 tracking-tight group-hover:text-white transition-colors">{s.title}</h3>
                  <p className="text-gray-400 text-lg leading-relaxed group-hover:text-gray-300 transition-colors">{s.desc}</p>
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══════════ SOCIAL PROOF ═══════════ */}
      <section className="py-20 px-4" style={{ background: 'hsl(215 60% 10%)' }}>
        <div className="max-w-5xl mx-auto text-center">
          <h2 className="text-3xl md:text-4xl font-black mb-16">
            Números que <span style={{ color: 'hsl(25 66% 55%)' }}>falam por si</span>
          </h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            {[
              { num: "97%", label: "das empresas não estão adequadas à NR-01" },
              { num: "R$ 50mil", label: "multa média por infração identificada" },
              { num: "213%", label: "custo de turnover por burnout não tratado" },
              { num: "74%", label: "redução de riscos com gestão psicossocial" },
            ].map((stat, i) => (
              <motion.div key={i} initial={{ opacity: 0, scale: 0.8 }} whileInView={{ opacity: 1, scale: 1 }} viewport={{ once: true }} transition={{ delay: i * 0.1 }}>
                <p className="text-3xl md:text-4xl font-black" style={{ backgroundImage: 'linear-gradient(90deg, hsl(207 90% 55%), hsl(33 100% 50%))', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>{stat.num}</p>
                <p className="text-sm text-gray-500 mt-2">{stat.label}</p>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══════════ DIFFERENTIATORS ═══════════ */}
      <section className="py-20 px-4" style={{ background: 'linear-gradient(180deg, hsl(215 60% 10%) 0%, hsl(215 65% 8%) 100%)' }}>
        <div className="max-w-5xl mx-auto">
          <motion.div {...fadeUp} className="text-center mb-16">
            <h2 className="text-3xl md:text-5xl font-black mb-4">
              Por que o YourEyes é <span style={{ color: 'hsl(33 100% 50%)' }}>diferente</span>?
            </h2>
          </motion.div>

          <div className="grid md:grid-cols-2 gap-6">
            {[
              { title: "Outros softwares", items: ["Planilhas disfarçadas de sistema", "Sem IA real — apenas formulários", "SST separado do RH", "Sem gestão psicossocial", "Sem compliance NR-01 atualizada", "Interface ultrapassada"], bad: true },
              { title: "YourEyes", items: ["Plataforma inteligente com IA real (GPT-4o)", "Detecção automática de riscos", "SST + RH + Psicossocial integrados", "100% compliance NR-01 atualizada", "Indicadores em tempo real", "Design moderno e intuitivo"], bad: false },
            ].map((col, i) => (
              <motion.div key={i} {...fadeUp} transition={{ delay: i * 0.15 }}>
                <div className="rounded-2xl p-8 h-full" style={{ background: col.bad ? 'hsl(0 20% 10%)' : 'hsl(215 55% 12%)', border: `1px solid ${col.bad ? 'hsl(0 40% 25% / 0.3)' : 'hsl(25 50% 42% / 0.2)'}` }}>
                  <h3 className="text-xl font-bold mb-6" style={{ color: col.bad ? 'hsl(0 60% 60%)' : 'hsl(25 50% 55%)' }}>{col.title}</h3>
                  <div className="space-y-3">
                    {col.items.map((item, j) => (
                      <div key={j} className="flex items-center gap-2 text-sm text-gray-400">
                        {col.bad ? (
                          <span className="w-4 h-4 rounded-full flex items-center justify-center shrink-0" style={{ background: 'hsl(0 40% 25% / 0.3)' }}>
                            <span style={{ color: 'hsl(0 60% 60%)' }} className="text-xs">✕</span>
                          </span>
                        ) : (
                          <CheckCircle className="w-4 h-4 shrink-0" style={{ color: 'hsl(25 50% 50%)' }} />
                        )}
                        {item}
                      </div>
                    ))}
                  </div>
                </div>
              </motion.div>
            ))}
          </div>

          <motion.div {...fadeUp} className="mt-14 text-center">
            <DiagCTA subtitle="Levamos sua empresa nesse mesmo cenário em até 7 dias">
              Quero esse nível de controle
            </DiagCTA>
          </motion.div>
        </div>
      </section>

      {/* ═══════════ MOCKUPS GALLERY ═══════════ */}
      <section className="py-20 px-4" style={{ background: 'hsl(215 65% 8%)' }}>
        <div className="max-w-6xl mx-auto">
          <motion.div {...fadeUp} className="text-center mb-14">
            <Badge className="mb-4" style={{ background: 'hsl(25 66% 45% / 0.15)', color: 'hsl(25 66% 60%)', borderColor: 'hsl(25 66% 45% / 0.3)' }}>
              <LayoutDashboard className="w-4 h-4 mr-1" /> A PLATAFORMA POR DENTRO
            </Badge>
            <h2 className="text-3xl md:text-5xl font-black mb-4">
              Veja o YourEyes <span style={{ color: 'hsl(25 66% 55%)' }}>em ação</span>
            </h2>
            <p className="text-gray-400 max-w-3xl mx-auto text-lg">
              Interface moderna, indicadores em tempo real e governança integrada — desenhado para quem decide.
            </p>
          </motion.div>

          <div className="grid md:grid-cols-2 gap-6">
            {[
              { src: mockupGovernanca, title: "Governança do Trabalho Humano", desc: "Visão integrada dos 4 pilares estratégicos com escore de maturidade em tempo real." },
              { src: mockupPsicossocial, title: "Gestão Psicossocial NR-01", desc: "IRP-S, Confiabilidade e campanhas anônimas com privacidade garantida (mín. 5 respondentes)." },
              { src: mockupConfiguracoes, title: "Configurações e Perfis de Acesso", desc: "Controle granular de papéis, vínculos e permissões por empresa e estabelecimento." },
              { src: mockupDashboard, title: "Dashboard Operacional", desc: "KPIs de Colaboradores, Admissões, EPIs, Documentos, Avaliações e Metas em um só lugar." },
            ].map((m, i) => (
              <motion.div key={i} {...fadeUp} transition={{ delay: i * 0.08 }}>
                <div className="rounded-2xl overflow-hidden group hover:scale-[1.01] transition-transform" style={{ background: 'hsl(215 55% 12%)', border: '1px solid hsl(215 40% 20%)' }}>
                  <img src={m.src} alt={m.title} loading="lazy" width={1536} height={1024} className="w-full h-auto" />
                  <div className="p-5">
                    <h3 className="font-bold text-lg mb-1">{m.title}</h3>
                    <p className="text-sm text-gray-400">{m.desc}</p>
                  </div>
                </div>
              </motion.div>
            ))}
          </div>

          <motion.div {...fadeUp} className="mt-12 text-center">
            <DiagCTA subtitle="Em 60 segundos você descobre por onde começar">
              Mapear minha empresa agora
            </DiagCTA>
          </motion.div>
        </div>
      </section>

      {/* ═══════════ DIAGNÓSTICO RÁPIDO + LEAD ═══════════ */}
      <section id="diagnostico" className="py-20 px-4 relative overflow-hidden" style={{ background: 'hsl(215 65% 8%)' }}>
        <div className="absolute inset-0 opacity-5">
          <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[800px] rounded-full blur-[250px]" style={{ background: 'hsl(25 60% 40%)' }} />
        </div>
        <div className="relative max-w-3xl mx-auto">
          <motion.div {...fadeUp} className="text-center mb-8">
            <Brain className="w-14 h-14 mx-auto mb-4" style={{ color: 'hsl(25 60% 50%)' }} />
            <h2 className="text-3xl md:text-5xl font-black mb-3">
              Descubra em 60s o seu <span style={{ color: 'hsl(25 60% 50%)' }}>nível de risco SST</span>
            </h2>
            <p className="text-gray-400 text-lg max-w-2xl mx-auto">
              Responda 5 perguntas e receba um diagnóstico personalizado.
              Em seguida, um <strong className="text-white">especialista da YourEyes</strong> entra em contato para agendar uma apresentação.
            </p>
          </motion.div>
          <motion.div {...fadeUp}>
            <DiagnosticoQuiz origem="lp" />
          </motion.div>
          <p className="text-xs text-gray-600 mt-4 text-center">Sem compromisso • Retorno em até 1 dia útil</p>
        </div>
      </section>

      {/* ═══════════ CTA / VAGAS ═══════════ */}
      <section id="vagas" className="py-20 px-4 relative" style={{ background: 'linear-gradient(180deg, hsl(215 65% 8%) 0%, hsl(215 70% 5%) 100%)' }}>
        <div className="absolute inset-0 opacity-5">
          <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[600px] h-[600px] rounded-full blur-[200px]" style={{ background: 'hsl(207 90% 45%)' }} />
        </div>
        <div className="relative max-w-2xl mx-auto">
          <motion.div {...fadeUp}>
            <div className="text-center mb-10">
              <Badge className="mb-4 animate-pulse text-sm border" style={{ background: 'hsl(265 50% 18%)', color: 'hsl(265 90% 85%)', borderColor: 'hsl(265 70% 50% / 0.5)' }}>
                <Zap className="w-4 h-4 mr-1" />
                CONSULTORIA EXCLUSIVA — VAGAS LIMITADAS
              </Badge>
              <h2 className="text-3xl md:text-5xl font-black mb-4 text-white">
                Restam{" "}
                <span style={{ color: 'hsl(265 90% 72%)' }}>{vagasRestantes}</span>{" "}
                {vagasRestantes === 1 ? "vaga" : "vagas"} para{" "}
                <span style={{ color: 'hsl(265 90% 72%)' }}>consultoria com especialista</span>
              </h2>
              <p className="text-gray-400 max-w-xl mx-auto">
                Estamos liberando <strong className="text-white">10 vagas exclusivas</strong> de consultoria 1:1 com um especialista YourEyes para
                estruturar o diagnóstico SST da sua empresa e desenhar o plano de ação. Após as 10 vagas, o atendimento volta ao formato padrão.
              </p>
            </div>

            {/* Vagas visual */}
            <div className="rounded-[2rem] p-8 mb-10 overflow-hidden relative" style={{ background: 'hsl(260 35% 10%)', border: '1px solid hsl(265 50% 30% / 0.5)' }}>
              <div className="flex items-center justify-between mb-4 relative z-10">
                <span className="text-sm font-bold uppercase tracking-widest text-gray-400">Status das Vagas</span>
                <span
                  className="text-xl font-black px-3 py-1 rounded-lg text-white"
                  style={{ background: 'hsl(265 80% 55%)' }}
                >
                  {10 - vagasRestantes}/10
                </span>
              </div>
              <div className="w-full rounded-full h-5 overflow-hidden p-1 relative z-10" style={{ background: 'hsl(265 30% 18%)' }}>
                <motion.div
                  className="h-full rounded-full"
                  style={{ background: 'hsl(265 80% 60%)' }}
                  initial={{ width: 0 }}
                  whileInView={{ width: `${((10 - vagasRestantes) / 10) * 100}%` }}
                  viewport={{ once: true }}
                  transition={{ duration: 1.5, ease: "circOut" }}
                />
              </div>
              <p className="text-xs text-gray-500 mt-4 text-center font-medium italic relative z-10">
                Atenção: Após o preenchimento total, novas solicitações entram em lista de espera.
              </p>
            </div>

            {/* What's included */}
            <div className="rounded-2xl p-6 mb-8" style={{ background: 'hsl(215 55% 12%)', border: '1px solid hsl(215 40% 20%)' }}>
              <h3 className="font-bold text-lg mb-4 flex items-center gap-2">
                <Award className="w-5 h-5" style={{ color: 'hsl(33 100% 50%)' }} />
                O que está incluso na consultoria com especialista:
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {[
                  "Diagnóstico SST aprofundado da sua operação",
                  "Sessão 1:1 com especialista YourEyes",
                  "Mapa de não conformidades e prioridades",
                  "Plano de ação 5W2H sob medida",
                  "Recomendação de módulos por dor real",
                  "Roteiro de implantação dos primeiros 90 dias",
                  "Benchmark com empresas do mesmo setor",
                  "Materiais de apoio (PGR, NR-1, eSocial)",
                ].map((item, i) => (
                  <div key={i} className="flex items-center gap-2 text-sm text-gray-300">
                    <CheckCircle className="w-4 h-4 shrink-0" style={{ color: 'hsl(25 50% 50%)' }} />
                    {item}
                  </div>
                ))}
              </div>
            </div>

            {/* After plans warning */}
            <div className="rounded-2xl p-5 mb-8" style={{ background: 'hsl(38 20% 10%)', border: '1px solid hsl(38 50% 40% / 0.2)' }}>
              <p className="font-bold text-sm mb-2" style={{ color: 'hsl(38 90% 55%)' }}>⚠️ O que acontece depois das 10 vagas?</p>
              <div className="text-xs text-gray-500 space-y-1">
                <p>• Novas solicitações entram em <strong className="text-gray-400">lista de espera</strong> até abrirmos a próxima janela.</p>
                <p>• O atendimento volta ao formato padrão, sem a sessão 1:1 dedicada com especialista.</p>
                <p>• A apresentação da plataforma continua disponível, porém sem o diagnóstico aprofundado incluso.</p>
              </div>
            </div>

            <motion.div
              variants={pulseGlow}
              initial="initial"
              animate="animate"
              className="rounded-xl"
            >
              <Button
                size="lg"
                onClick={scrollToDiag}
                disabled={vagasRestantes <= 0}
                className="w-full text-white text-sm sm:text-lg px-4 py-6 sm:py-7 rounded-xl shadow-2xl whitespace-normal h-auto transform transition-all active:scale-95"
                style={{ background: 'linear-gradient(135deg, hsl(207 90% 45%), hsl(33 100% 50%))', boxShadow: '0 8px 32px hsl(33 100% 50% / 0.35)' }}
              >
                {vagasRestantes > 0 ? (
                  <>
                    <Brain className="w-5 h-5 mr-2 shrink-0 animate-pulse" />
                    <span className="break-words font-black tracking-wide">FAZER DIAGNÓSTICO GRÁTIS EM 60 SEGUNDOS</span>
                    <ArrowRight className="w-5 h-5 ml-2 shrink-0" />
                  </>
                ) : (
                  <span className="break-words font-bold">Vagas esgotadas — Lista de espera em breve</span>
                )}
              </Button>
              <p className="text-xs text-gray-500 text-center mt-3">
                Sem cadastro de cartão • Um especialista entra em contato para agendar a apresentação
              </p>
            </motion.div>
          </motion.div>
        </div>
      </section>

      {/* ═══════════ FINAL URGENCY ═══════════ */}
      <section className="py-16 px-4" style={{ background: 'hsl(215 70% 5%)', borderTop: '1px solid hsl(215 40% 16%)' }}>
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="text-2xl md:text-3xl font-black mb-4">
            A pergunta não é <em>"Quanto custa adequar?"</em>
          </h2>
          <p className="text-xl text-gray-300 mb-6">
            A pergunta é: <strong style={{ color: 'hsl(33 100% 55%)' }}>"Quanto vai custar NÃO adequar?"</strong>
          </p>
          <p className="text-gray-500 text-sm mb-8 max-w-2xl mx-auto">
            Uma única multa do MTE paga 5 anos de YourEyes. Um único processo por burnout paga 10 anos.
            Comece pelo diagnóstico — leva 60 segundos e mostra exatamente onde sua empresa está exposta.
          </p>
          <DiagCTA subtitle="100% gratuito • Especialista entra em contato para apresentar a solução">
            Iniciar meu diagnóstico agora
          </DiagCTA>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 px-4 text-center text-sm" style={{ borderTop: '1px solid hsl(215 40% 16%)', color: 'hsl(215 15% 55%)' }}>
        <p>© {new Date().getFullYear()} YourEyes — Plataforma de Gestão Inteligente de SST e RH</p>
        <p className="mt-1 text-xs" style={{ color: 'hsl(215 15% 40%)' }}>Este site não é afiliado ao Ministério do Trabalho e Emprego (MTE).</p>
      </footer>

      {/* Floating Diagnóstico CTA */}
      <div className="fixed bottom-6 right-6 z-50">
        <button
          onClick={scrollToDiag}
          aria-label="Fazer diagnóstico grátis"
          className="flex items-center gap-2 rounded-full pl-4 pr-5 py-3 shadow-2xl transition-transform hover:scale-105 text-white font-bold text-sm"
          style={{ background: 'linear-gradient(135deg, hsl(25 65% 42%), hsl(25 75% 32%))', boxShadow: '0 8px 32px hsl(25 65% 42% / 0.5)' }}
        >
          <Brain className="w-4 h-4" />
          Diagnóstico grátis
        </button>
      </div>
    </div>
  );
}

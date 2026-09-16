import { useState } from "react";
import { Link } from "react-router-dom";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { CONTATO_WHATSAPP, CONTATO_EMAIL } from "@/components/parceiro/ParceirosLayout";
import { ArrowRight, Link2, Wallet, MapPin, Store, Handshake, TrendingUp, MessageCircle, Mail, ChevronRight } from "lucide-react";
import { ParceirosLayout } from "@/components/parceiro/ParceirosLayout";

// Seção pública "Parceiros" do site: o que é o programa e o convite para entrar.
// Números aqui são a regra do programa (níveis padrão), não dados de clientes.
const PASSOS = [
  { icone: <Handshake className="w-5 h-5" />, t: "Cadastre-se", d: "Indicador entra na hora. Representante e Operador passam por uma aprovação rápida e recebem certificação." },
  { icone: <Link2 className="w-5 h-5" />, t: "Compartilhe seu link", d: "Cada conta que chegar pelo seu link fica registrada como sua, do primeiro clique ao cliente ativo." },
  { icone: <Wallet className="w-5 h-5" />, t: "Receba todo mês", d: "Comissão recorrente sobre a mensalidade dos seus clientes enquanto eles estiverem ativos. Fecha dia 25, paga até dia 10." },
];
type TipoInfo = { t: string; trilha: string; d: string; quem: string; exemplo: string; faz: string[]; naoFaz: string; ganha: string[]; setup: string; aprovacao: string; requisitos: string; perfis: string[] };
const TIPOS: TipoInfo[] = [
  { t: "Indicador", trilha: "indicador", d: "Você conhece empresas e faz a ponte. A YourEyes vende, implanta e cuida do cliente.",
    quem: "Contadores, consultores, associações e entidades de classe, profissionais de RH e SST, clientes satisfeitos — qualquer pessoa com acesso a empresas.",
    exemplo: "A contadora Ana atende 40 empresas. Ela manda o link dela para 10 clientes que reclamam do controle de ponto. Três contratam. Enquanto essas três empresas ficarem na plataforma, Ana recebe todo mês uma parte da mensalidade de cada uma, sem fazer mais nada.",
    faz: ["Apresenta o contato qualificado e empresta a sua credibilidade.", "Compartilha o link de indicação (WhatsApp, e-mail, redes, eventos)."],
    naoFaz: "Não negocia preço, não fecha contrato e não implanta. A YourEyes conduz do primeiro contato ao sistema no ar.",
    ganha: ["6% da mensalidade de cada cliente ativo (nível Foco), subindo para 8% (Visão) e 10% (Diamante) conforme a sua carteira cresce.", "Parte da implantação paga pelo cliente: 20% a 30%, em três parcelas conforme o cliente avança.", "Bônus a cada renovação de ciclo de 24 meses: duas comissões extras daquele cliente."],
    setup: "Recebe 20% (Foco), 25% (Visão) ou 30% (Diamante) do valor da implantação, liberado em três etapas: 1ª mensalidade paga, sistema no ar e 3º mês ativo.",
    aprovacao: "Imediata: o cadastro já nasce ativo e o link funciona na hora.",
    requisitos: "Conta ativa, dados de contato e chave PIX para receber. Não precisa saber de tecnologia.",
    perfis: ["Contabilidade", "Associação / sindicato", "Consultor", "Cliente satisfeito"] },
  { t: "Representante", trilha: "representante", d: "Você apresenta, negocia e fecha o contrato. A YourEyes implanta e dá o suporte.",
    quem: "Representantes comerciais, corretores, vendedores de sistemas, engenheiros e técnicos de segurança com rede regional.",
    exemplo: "O técnico de segurança Carlos visita 15 empresas por mês. Ele apresenta a YourEyes, demonstra o sistema e fecha o contrato dentro da tabela de preços. A YourEyes implanta. Carlos recebe 12% a 18% da mensalidade de cada empresa, todo mês, mais 60% a 80% da implantação.",
    faz: ["Prospecta, apresenta e demonstra a plataforma com o material oficial.", "Negocia dentro da política de preço e acompanha até a assinatura.", "Pode receber leads que chegam à YourEyes na sua região."],
    naoFaz: "Não implanta nem presta suporte técnico: isso é da YourEyes.",
    ganha: ["12% da mensalidade (Foco), 15% (Visão) ou 18% (Diamante) de cada cliente ativo, todo mês.", "60% a 80% da implantação paga pelo cliente, em três parcelas.", "Bônus de renovação a cada ciclo de 24 meses e bônus de retenção (+15% do setup) quando o cliente chega ativo ao 90º dia."],
    setup: "Recebe 60% (Foco), 70% (Visão) ou 80% (Diamante) do valor da implantação, em três etapas: 30% na 1ª mensalidade paga, 40% no sistema no ar e 30% no 3º mês ativo.",
    aprovacao: "Manual: a equipe YourEyes analisa o cadastro, pode pedir referências e libera a certificação de vendas.",
    requisitos: "CNPJ ou CPF, experiência comercial, certificação nível 1 (feita com a gente) e aceite do Contrato de Parceria.",
    perfis: ["Representante comercial", "Engenheiro / técnico de segurança", "Corretor", "Consultor de RH"] },
  { t: "Operador", trilha: "operador", d: "Você vende, implanta, treina e atende o cliente. É a trilha que mais paga.",
    quem: "Clínicas de medicina e segurança do trabalho, consultorias de RH e SST, escritórios de contabilidade estruturados, empresas de BPO e revendas regionais de tecnologia.",
    exemplo: "A Clínica Vida tem 300 empresas na carteira de exames e PGR. Em dois anos, 45 delas passam a usar a YourEyes pela clínica. A clínica fatura a implantação direto do cliente, cuida do dia a dia e recebe 20% a 30% de cada mensalidade: com ticket médio de R$ 650, são cerca de R$ 8.775 por mês, todo mês, além dos serviços que já vendia.",
    faz: ["Vende e implanta: cadastros, colaboradores, escalas, documentos e treinamento.", "Presta o suporte de primeiro nível e acompanha o sucesso da conta.", "Passa a ser o ponto de atendimento reconhecido pelo cliente."],
    naoFaz: "Não fatura a mensalidade nem é dono da base: o contrato do sistema é entre a YourEyes e o cliente. A YourEyes dá o suporte avançado e evolui o produto.",
    ganha: ["20% da mensalidade (Foco), 25% (Visão) ou 30% (Diamante) de cada cliente ativo, todo mês — o triplo do Indicador, porque você faz o trabalho que a YourEyes faria.", "100% da implantação, cobrada e faturada por você direto ao cliente.", "Bônus de renovação, bônus de retenção 90 dias, Fast Start (R$ 2.000 ao ativar 3 empresas em 90 dias), volume e velocidade."],
    setup: "A implantação é serviço seu: você cobra e fatura direto do cliente. Só um cuidado combinado em contrato: no máximo metade antes do sistema entrar no ar homologado.",
    aprovacao: "Manual, com certificação nível 2 antes de implantar. Nos 3 primeiros meses de cada cliente novo, 20% da comissão fica guardada e é liberada quando o cliente paga a 3ª mensalidade.",
    requisitos: "CNPJ ativo, equipe para implantar e atender, certificação nível 2 e aceite do Contrato de Parceria.",
    perfis: ["Clínica de SST", "Contabilidade estruturada", "Consultoria de RH/SST", "Revenda de TI / BPO"] },
];
const REGRAS_SIMPLES = [
  { t: "O cliente é da YourEyes", d: "O contrato do sistema e a cobrança são da YourEyes. O que é seu, e está protegido em contrato, é o registro de quem trouxe a conta: ninguém vende nela sem te pagar." },
  { t: "Sua comissão não tem prazo para acabar", d: "Ciclos de 24 meses por cliente que renovam sozinhos enquanto você estiver ativo e o cliente ficar. A cada renovação, duas comissões extras." },
  { t: "Nível é conquista", d: "Foco (até R$ 4 mil de carteira), Visão (R$ 4 mil a 12 mil) e Diamante (acima de R$ 12 mil). Subiu, o percentual muda na hora; conquistado, não cai por 12 meses." },
  { t: "Fecha dia 25, paga até dia 10", d: "Extrato detalhado na Área do Parceiro, pagamento por PIX contra nota fiscal ou recibo." },
];

export default function ParceirosPublico() {
  const [tipoAberto, setTipoAberto] = useState<TipoInfo | null>(null);
  return (
    <ParceirosLayout>
      <section className="py-10 lg:py-16 grid lg:grid-cols-[1.2fr_1fr] gap-10 items-center">
        <div>
          <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-3">Programa de Parceiros</div>
          <h1 className="text-4xl lg:text-5xl font-extrabold text-white leading-tight">Cresça na sua região <span className="text-[#60ABEF]">indicando a YourEyes</span>.</h1>
          <p className="mt-5 text-lg text-slate-300 leading-relaxed">Clínicas, contabilidades, consultores e profissionais de SST ganham comissão recorrente por cada empresa que trazem para a plataforma, e podem ofertar seus próprios serviços na vitrine para todos os clientes.</p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link to="/parceiros/cadastro" className="inline-flex items-center gap-2 bg-[#FF8A00] hover:bg-[#e67a00] text-white font-semibold px-6 py-3 rounded-md transition">Quero ser parceiro <ArrowRight className="w-4 h-4" /></Link>
            <Link to="/parceiros/entrar" className="inline-flex items-center gap-2 border border-white/20 hover:bg-white/10 text-white font-semibold px-6 py-3 rounded-md transition">Já sou parceiro</Link>
            <a href={CONTATO_WHATSAPP} target="_blank" rel="noreferrer" className="inline-flex items-center gap-2 text-[#60ABEF] hover:text-white font-semibold px-4 py-3 transition"><MessageCircle className="w-4 h-4" />Fale conosco</a>
          </div>
        </div>
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-6">
          <div className="text-xs uppercase tracking-widest text-slate-400 mb-4">Como funciona a remuneração</div>
          <div className="space-y-4">
            <div className="flex items-start gap-3"><TrendingUp className="w-5 h-5 text-[#FF8A00] mt-0.5" /><div><div className="font-semibold text-white">Recorrente</div><div className="text-sm text-slate-300">Percentual da mensalidade de cada cliente ativo, todo mês: de 6% (Indicador) a 30% (Operador), subindo com a sua carteira. Em ciclos de 24 meses que renovam sozinhos.</div></div></div>
            <div className="flex items-start gap-3"><Wallet className="w-5 h-5 text-[#60ABEF] mt-0.5" /><div><div className="font-semibold text-white">Setup e renovação</div><div className="text-sm text-slate-300">A implantação é paga pelo cliente e a maior parte fica com quem a faz: de 20% a 100%, em etapas. Toda renovação de ciclo rende bônus.</div></div></div>
            <div className="flex items-start gap-3"><MapPin className="w-5 h-5 text-emerald-400 mt-0.5" /><div><div className="font-semibold text-white">Leads da sua região</div><div className="text-sm text-slate-300">Empresas que chegam à YourEyes perto de você podem ser encaminhadas ao parceiro local.</div></div></div>
          </div>
        </div>
      </section>

      <section className="py-10 border-t border-white/10">
        <h2 className="text-2xl font-bold text-white mb-6">Três passos</h2>
        <div className="grid md:grid-cols-3 gap-4">
          {PASSOS.map((p, i) => (
            <div key={p.t} className="rounded-2xl border border-white/10 bg-white/[0.04] p-5">
              <div className="flex items-center gap-2 text-[#60ABEF]">{p.icone}<span className="text-xs font-mono">0{i + 1}</span></div>
              <div className="mt-3 font-bold text-white">{p.t}</div>
              <p className="mt-1 text-sm text-slate-300">{p.d}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="py-10 border-t border-white/10">
        <h2 className="text-2xl font-bold text-white mb-2">Escolha como quer participar</h2>
        <p className="text-slate-300 mb-6">Três trilhas. Quanto mais você faz pelo cliente, maior a sua parte. Você pode começar em uma e migrar depois. Clique em cada uma para ver, com exemplos, o que faz, o que não faz e quanto ganha.</p>
        <div className="grid md:grid-cols-3 gap-3">
          {TIPOS.map((t) => (
            <button key={t.t} type="button" onClick={() => setTipoAberto(t)} data-testid="tipo-parceiro-card"
              className="text-left rounded-xl border border-white/10 p-4 hover:border-[#60ABEF]/60 hover:bg-white/[0.04] transition group">
              <div className="font-semibold text-white flex items-center justify-between text-lg">{t.t}<ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-[#60ABEF]" /></div>
              <p className="text-sm text-slate-300 mt-1">{t.d}</p>
              <div className="mt-3 flex flex-wrap gap-1">{t.perfis.map((p) => <span key={p} className="text-[10px] rounded-full border border-white/15 px-2 py-0.5 text-slate-400">{p}</span>)}</div>
              <p className="text-[11px] text-[#60ABEF] mt-3">Ver como funciona, com exemplo</p>
            </button>
          ))}
        </div>
        <div className="mt-8 grid md:grid-cols-2 lg:grid-cols-4 gap-3">
          {REGRAS_SIMPLES.map((r) => <div key={r.t} className="rounded-xl border border-white/10 bg-white/[0.03] p-4"><div className="font-semibold text-white text-sm">{r.t}</div><p className="text-xs text-slate-400 mt-1">{r.d}</p></div>)}
        </div>
        <p className="text-xs text-slate-500 mt-3">Uma identidade, dois papéis: todo parceiro pode também ofertar serviços no <Link to="/marketye" className="text-[#60ABEF] hover:underline">MarketYE</Link> (marketplace de serviços), e todo especialista do MarketYE pode virar parceiro.</p>
        <div className="mt-8 rounded-2xl border border-white/10 bg-white/[0.04] p-5 flex flex-wrap items-center gap-4 justify-between">
          <div className="flex items-center gap-3"><Store className="w-6 h-6 text-[#FF8A00]" /><div><div className="font-semibold text-white">Já é especialista do MarketYE?</div><div className="text-sm text-slate-300">Entre com a mesma conta e conclua o cadastro de parceiro em um minuto.</div></div></div>
          <Link to="/parceiros/cadastro" className="inline-flex items-center gap-2 bg-[#FF8A00] hover:bg-[#e67a00] text-white font-semibold px-5 py-2.5 rounded-md transition">Virar parceiro <ArrowRight className="w-4 h-4" /></Link>
        </div>
      </section>

      <section className="py-10 border-t border-white/10">
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-6 grid md:grid-cols-[1fr_auto] gap-6 items-center">
          <div>
            <h2 className="text-xl font-bold text-white">Ficou com dúvida? Fale conosco</h2>
            <p className="text-sm text-slate-300 mt-1">Conversamos sobre o modelo, a sua região e a melhor modalidade para o seu perfil antes de você se cadastrar. As regras completas estão no <Link to="/parceiros/contrato" className="text-[#60ABEF] hover:underline">Contrato de Parceria</Link>.</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <a href={CONTATO_WHATSAPP} target="_blank" rel="noreferrer" className="inline-flex items-center gap-2 bg-[#25D366] hover:bg-[#1fb658] text-[#0B1D34] font-semibold px-4 py-2.5 rounded-md transition"><MessageCircle className="w-4 h-4" />WhatsApp</a>
            <a href={CONTATO_EMAIL} className="inline-flex items-center gap-2 border border-white/20 hover:bg-white/10 text-white font-semibold px-4 py-2.5 rounded-md transition"><Mail className="w-4 h-4" />E-mail</a>
          </div>
        </div>
      </section>

      <Dialog open={!!tipoAberto} onOpenChange={(o) => !o && setTipoAberto(null)}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          {tipoAberto && (
            <>
              <DialogHeader>
                <DialogTitle>{tipoAberto.t}</DialogTitle>
                <DialogDescription>{tipoAberto.d}</DialogDescription>
              </DialogHeader>
              <div className="space-y-4 text-sm">
                <div className="rounded-lg bg-[#FF8A00]/10 border border-[#FF8A00]/30 p-3"><div className="font-semibold mb-1 text-[#e67a00]">Na prática</div><p className="text-foreground/90">{tipoAberto.exemplo}</p></div>
                <div><div className="font-semibold mb-1">Para quem é</div><p className="text-muted-foreground">{tipoAberto.quem}</p></div>
                <div><div className="font-semibold mb-1">O que você faz</div><ul className="list-disc pl-5 space-y-1 text-muted-foreground">{tipoAberto.faz.map((x) => <li key={x}>{x}</li>)}</ul></div>
                <div><div className="font-semibold mb-1">O que você não precisa fazer</div><p className="text-muted-foreground">{tipoAberto.naoFaz}</p></div>
                <div><div className="font-semibold mb-1">Quanto ganha</div><ul className="list-disc pl-5 space-y-1 text-muted-foreground">{tipoAberto.ganha.map((x) => <li key={x}>{x}</li>)}</ul></div>
                <div><div className="font-semibold mb-1">E a implantação (setup)?</div><p className="text-muted-foreground">{tipoAberto.setup}</p></div>
                <div className="grid sm:grid-cols-2 gap-3">
                  <div className="rounded-lg border p-3"><div className="text-xs uppercase tracking-wide text-muted-foreground">Aprovação</div><p className="mt-1">{tipoAberto.aprovacao}</p></div>
                  <div className="rounded-lg border p-3"><div className="text-xs uppercase tracking-wide text-muted-foreground">Requisitos</div><p className="mt-1">{tipoAberto.requisitos}</p></div>
                </div>
                <p className="text-xs text-muted-foreground">Níveis e valores vigentes constam na Área do Parceiro e no <Link to="/parceiros/contrato" className="text-primary underline underline-offset-2">Contrato de Parceria</Link>.</p>
                <div className="flex justify-end gap-2 pt-2">
                  <a href={CONTATO_WHATSAPP} target="_blank" rel="noreferrer" className="inline-flex items-center gap-2 border px-4 py-2 rounded-md text-sm font-medium hover:bg-muted"><MessageCircle className="w-4 h-4" />Fale conosco</a>
                  <Link to={`/parceiros/cadastro?trilha=${tipoAberto.trilha}`} className="inline-flex items-center gap-2 bg-[#FF8A00] hover:bg-[#e67a00] text-white px-4 py-2 rounded-md text-sm font-semibold">Quero ser {tipoAberto.t.toLowerCase()} <ArrowRight className="w-4 h-4" /></Link>
                </div>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </ParceirosLayout>
  );
}

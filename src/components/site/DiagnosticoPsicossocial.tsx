import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  ArrowRight,
  ArrowLeft,
  ShieldCheck,
  AlertTriangle,
  CheckCircle2,
  Sparkles,
  MessageCircle,
  Loader2,
} from "lucide-react";

/**
 * Diagnóstico rápido de riscos psicossociais — isca de tráfego pago.
 *
 * Duas decisões que definem este componente:
 *
 * 1. É um diagnóstico ORGANIZACIONAL, não clínico. Ele pergunta o que a
 *    EMPRESA faz (inventário, canal de escuta, plano de ação), nunca como a
 *    PESSOA se sente. Um quiz de tráfego pago que pergunta sintoma coleta
 *    dado de saúde — sensível pela LGPD (art. 11) — de quem só queria saber
 *    se está em conformidade. Aqui nada do que é respondido é dado de saúde.
 *
 * 2. O lead vale mais que o clique. As respostas vão para `landing_leads`,
 *    que já tem trava de spam por IP, validação de tamanho e gatilho que
 *    joga o lead no CRM. Nada de banco novo: a estrutura já existia para a
 *    landing page e serve igual aqui.
 *
 * O resultado termina no WhatsApp do comercial com a mensagem já escrita —
 * é onde a conversa acontece de fato em tráfego pago.
 */

/**
 * Número do comercial em formato internacional, sem sinais.
 *
 * O card pedia 554699337504 (12 dígitos). Celular brasileiro tem 13 com o
 * país: 55 + DDD 46 + 9 dígitos. Faltava o último dígito, e o número
 * completo já estava no código da outra landing (5546993375044) — o pedido
 * é exatamente o prefixo dele. Usamos o completo; qualquer troca é aqui,
 * numa linha só.
 */
const WHATSAPP_COMERCIAL = "5546993375044";

const PORTES = [
  { v: "ate_19", l: "Até 19" },
  { v: "20_99", l: "20 a 99" },
  { v: "100_499", l: "100 a 499" },
  { v: "500_mais", l: "500 ou mais" },
];

const SETORES = [
  "Indústria / Fábrica",
  "Construção Civil",
  "Saúde / Hospitalar",
  "Logística / Transporte",
  "Comércio / Varejo",
  "Serviços / Escritório",
  "Agronegócio",
  "Outro",
];

/** Peso de RISCO: 0 = em ordem, 3 = descoberto. */
type RespKey = "sim" | "parcial" | "nao" | "nao_sei";
const RESPOSTAS: { v: RespKey; l: string; risco: number }[] = [
  { v: "sim", l: "Sim, e temos documento que comprova", risco: 0 },
  { v: "parcial", l: "Em parte / estamos construindo", risco: 2 },
  { v: "nao", l: "Não", risco: 3 },
  // Não saber é risco de verdade: numa fiscalização, "não sei" e "não" dão no
  // mesmo lugar. Pesa quase como o "não" de propósito.
  { v: "nao_sei", l: "Não sei dizer", risco: 2 },
];

type Dim = "identificacao" | "escuta" | "organizacao" | "acao";

const DIM_LABEL: Record<Dim, string> = {
  identificacao: "Identificação dos riscos",
  escuta: "Canal de escuta e apuração",
  organizacao: "Organização do trabalho",
  acao: "Plano de ação e preparo da liderança",
};

interface Pergunta {
  id: string;
  dim: Dim;
  pergunta: string;
  ajuda: string;
  /** O que a resposta ruim significa na prática — vira o texto do resultado. */
  exposicao: string;
}

const PERGUNTAS: Pergunta[] = [
  {
    id: "q_inventario",
    dim: "identificacao",
    pergunta: "Os riscos psicossociais estão no inventário de riscos da empresa (PGR)?",
    ajuda: "Sobrecarga, assédio, pressão por metas e jornada extenuante descritos no mesmo documento em que ficam ruído e produto químico.",
    exposicao: "Riscos psicossociais fora do inventário do PGR — é a não conformidade mais direta com a NR-1, e a primeira que o auditor procura.",
  },
  {
    id: "q_avaliacao",
    dim: "identificacao",
    pergunta: "Nos últimos 12 meses, a empresa aplicou alguma avaliação estruturada sobre carga de trabalho, assédio ou estresse?",
    ajuda: "Questionário anônimo respondido pelos colaboradores, com resultado por setor. Conversa de corredor não conta.",
    exposicao: "Sem avaliação aplicada, a empresa não tem como provar que olhou para o tema — só a percepção da liderança, que costuma ser a mais otimista da casa.",
  },
  {
    id: "q_canal",
    dim: "escuta",
    pergunta: "Existe um canal em que o colaborador possa relatar assédio ou sobrecarga sem se identificar?",
    ajuda: "Ouvidoria, canal de denúncia ou caixa anônima — o ponto é o colaborador não precisar expor o nome para o chefe.",
    exposicao: "Sem canal anônimo, o problema só aparece quando já virou processo ou pedido de demissão. A empresa perde a chance de resolver antes.",
  },
  {
    id: "q_tratativa",
    dim: "escuta",
    pergunta: "Quando chega uma queixa, existe um fluxo definido de apuração — com responsável, prazo e registro?",
    ajuda: "Quem recebe, quem apura, em quanto tempo responde e onde isso fica registrado.",
    exposicao: "Queixa sem fluxo de apuração registrado: em juízo, a empresa não consegue provar que agiu, mesmo tendo agido.",
  },
  {
    id: "q_jornada",
    dim: "organizacao",
    pergunta: "A empresa acompanha horas extras, jornadas longas e pausas por setor?",
    ajuda: "Não é o total da folha: é saber quais equipes estão sistematicamente esticando a jornada.",
    exposicao: "Jornada sem acompanhamento por setor é o fator de risco psicossocial mais fácil de medir — e o mais citado em perícia de adoecimento.",
  },
  {
    id: "q_metas",
    dim: "organizacao",
    pergunta: "Quando uma equipe sinaliza sobrecarga, existe caminho formal para revisar metas e prazos?",
    ajuda: "Alguém pode dizer 'não cabe' e ser ouvido, com registro da decisão.",
    exposicao: "Meta que não pode ser questionada é pressão sem válvula — a origem mais comum de afastamento por transtorno mental.",
  },
  {
    id: "q_plano",
    dim: "acao",
    pergunta: "O que é encontrado vira plano de ação com responsável, prazo e evidência?",
    ajuda: "Não basta medir. A NR-1 cobra a medida de controle, e o registro de que ela foi tomada.",
    exposicao: "Risco identificado e não tratado é pior do que risco não identificado: prova que a empresa sabia e não agiu.",
  },
  {
    id: "q_lideranca",
    dim: "acao",
    pergunta: "As lideranças foram treinadas em assédio, saúde mental e gestão de conflitos nos últimos 24 meses?",
    ajuda: "Líder despreparado é, ele mesmo, um fator de risco psicossocial reconhecido.",
    exposicao: "Liderança sem treinamento registrado enfraquece a defesa da empresa em qualquer alegação de assédio moral.",
  },
];

const PERFIS = {
  critico: {
    l: "Crítico",
    cor: "#F87171",
    resumo:
      "A gestão de riscos psicossociais praticamente não existe de forma documentada. Numa fiscalização ou numa ação trabalhista hoje, a empresa não teria o que apresentar.",
  },
  alto: {
    l: "Alto",
    cor: "#FF8A00",
    resumo:
      "Há iniciativas soltas, mas sem a espinha que a NR-1 cobra: identificar, registrar, tratar e comprovar. As lacunas estão em pontos que costumam ser os primeiros verificados.",
  },
  moderado: {
    l: "Moderado",
    cor: "#60ABEF",
    resumo:
      "A base existe. O que falta é fechar o ciclo — transformar o que já se sabe em registro e em plano de ação com prova.",
  },
  estruturado: {
    l: "Estruturado",
    cor: "#34D399",
    resumo:
      "A empresa está à frente da maioria. O ganho aqui é eficiência e evidência: menos planilha, mais trilha automática para auditoria.",
  },
} as const;

type PerfilKey = keyof typeof PERFIS;

const PRIMEIROS_PASSOS: Record<Dim, string[]> = {
  identificacao: [
    "Incluir os fatores psicossociais no inventário de riscos do PGR",
    "Aplicar um questionário anônimo por setor (COPSOQ ou equivalente)",
  ],
  escuta: [
    "Abrir canal de escuta com opção de anonimato",
    "Definir prazo e responsável para apuração de cada relato",
  ],
  organizacao: [
    "Acompanhar horas extras e pausas por equipe, não só o total",
    "Criar caminho formal para revisão de meta quando houver sobrecarga",
  ],
  acao: [
    "Transformar cada achado em plano de ação 5W2H com evidência",
    "Treinar lideranças em assédio, saúde mental e conflitos",
  ],
};

function calcular(respostas: Record<string, RespKey>) {
  const porDim: Record<Dim, { soma: number; max: number }> = {
    identificacao: { soma: 0, max: 0 },
    escuta: { soma: 0, max: 0 },
    organizacao: { soma: 0, max: 0 },
    acao: { soma: 0, max: 0 },
  };

  let soma = 0;
  PERGUNTAS.forEach((p) => {
    const peso = RESPOSTAS.find((o) => o.v === respostas[p.id])?.risco ?? 2;
    soma += peso;
    porDim[p.dim].soma += peso;
    porDim[p.dim].max += 3;
  });

  const score = Math.round((soma / (PERGUNTAS.length * 3)) * 100);

  let perfil: PerfilKey = "estruturado";
  if (score >= 70) perfil = "critico";
  else if (score >= 50) perfil = "alto";
  else if (score >= 30) perfil = "moderado";

  const expostas = PERGUNTAS.filter(
    (p) => (RESPOSTAS.find((o) => o.v === respostas[p.id])?.risco ?? 0) >= 2,
  );

  const dims = (Object.entries(porDim) as [Dim, { soma: number; max: number }][])
    .map(([dim, v]) => ({ dim, pct: v.max ? Math.round((v.soma / v.max) * 100) : 0 }))
    .sort((a, b) => b.pct - a.pct);

  return { score, perfil, expostas, dims, porDim };
}

export function DiagnosticoPsicossocial() {
  const totalPassos = 2 + PERGUNTAS.length + 1; // porte, setor, perguntas, contato
  const passoContato = totalPassos - 1;

  const [passo, setPasso] = useState(0);
  const [enviando, setEnviando] = useState(false);
  const [resultado, setResultado] = useState<ReturnType<typeof calcular> | null>(null);

  const [porte, setPorte] = useState("");
  const [setor, setSetor] = useState("");
  const [respostas, setRespostas] = useState<Record<string, RespKey>>({});

  const [nome, setNome] = useState("");
  const [empresa, setEmpresa] = useState("");
  const [cargo, setCargo] = useState("");
  const [email, setEmail] = useState("");
  const [telefone, setTelefone] = useState("");

  const avancar = () => setPasso((p) => Math.min(passoContato, p + 1));
  const voltar = () => setPasso((p) => Math.max(0, p - 1));

  const enviar = async () => {
    if (!nome.trim() || !empresa.trim() || !email.trim() || !telefone.trim()) {
      toast.error("Preencha nome, empresa, e-mail e WhatsApp.");
      return;
    }
    // Mesma regra do banco (constraint landing_leads_email_fmt). Precisa ser a
    // mesma mesmo: o campo é type="email", mas ele só é validado pelo navegador
    // dentro de um <form> que envia — aqui é botão, então o navegador não
    // valida nada, e um "fulano@empresa" sem ponto batia direto na trava do
    // banco. O visitante via "não conseguimos registrar" sem saber o motivo, e
    // o lead ia embora.
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) {
      toast.error("E-mail inválido.", { description: "Confira o endereço — falta algo como @empresa.com.br." });
      return;
    }
    const tel = telefone.replace(/\D/g, "");
    if (tel.length < 10 || tel.length > 13) {
      toast.error("WhatsApp inválido.", { description: "Informe DDD + número, por exemplo (46) 99999-9999." });
      return;
    }
    // Os limites de tamanho também são do banco. Cortar aqui é mais gentil do
    // que deixar a gravação falhar por causa de um campo colado sem querer.
    if (nome.trim().length > 200 || empresa.trim().length > 300 || cargo.trim().length > 200) {
      toast.error("Algum campo está longo demais.", { description: "Reduza nome, empresa ou cargo." });
      return;
    }

    const diag = calcular(respostas);
    setEnviando(true);
    try {
      const { error } = await supabase.from("landing_leads").insert({
        nome: nome.trim(),
        email: email.trim().toLowerCase(),
        telefone: tel,
        empresa: empresa.trim(),
        cargo: cargo.trim() || null,
        setor: setor || null,
        num_funcionarios: porte || null,
        landing_page_origem: "site-diagnostico-psicossocial",
        perfil_diagnostico: diag.perfil,
        pontuacao_diagnostico: diag.score,
        diagnostico_resultado: {
          instrumento: "diagnostico_psicossocial_nr1_v1",
          respostas,
          score: diag.score,
          perfil: diag.perfil,
          dimensoes: diag.porDim,
          contexto: { porte, setor },
          concluido_em: new Date().toISOString(),
        },
      });
      if (error) throw error;

      setResultado(diag);
      trackConversion("Lead", {
        email: email.trim().toLowerCase(),
        phone: tel,
        url: typeof window !== "undefined" ? window.location.href : undefined,
      });
    } catch (e) {
      // O lead é o produto desta tela: se o registro falhar, o visitante não
      // pode ficar sem saída. Mostramos o resultado assim mesmo e deixamos o
      // WhatsApp na frente dele — a conversa é o que interessa.
      console.error("Falha ao registrar lead do diagnóstico:", e);
      setResultado(diag);

      // "Não deu certo" sem motivo é o pior aviso possível: quem lê não sabe
      // se tenta de novo, se corrige algo ou se desiste. Traduzimos o que o
      // banco devolve nos dois casos que realmente acontecem.
      const err = e as { code?: string; message?: string };
      const limiteAtingido =
        err?.code === "23514" && /rate limit/i.test(err?.message ?? "");
      toast.error(
        limiteAtingido
          ? "Muitos envios deste mesmo acesso."
          : "Não conseguimos registrar seus dados.",
        {
          description: limiteAtingido
            ? "Aguarde alguns minutos e tente de novo. Seu resultado continua aqui."
            : "Seu resultado está aqui do mesmo jeito — fale com um especialista pelo WhatsApp.",
        },
      );
    } finally {
      setEnviando(false);
    }
  };

  // ============================ RESULTADO ============================
  if (resultado) {
    const cfg = PERFIS[resultado.perfil];
    const foco = resultado.dims[0];
    const passos = Array.from(
      new Set(resultado.dims.slice(0, 2).flatMap((d) => PRIMEIROS_PASSOS[d.dim])),
    ).slice(0, 4);

    const mensagem = encodeURIComponent(
      `Olá! Fiz o diagnóstico de riscos psicossociais no site da YourEyes.\n\n` +
        `Empresa: ${empresa}\n` +
        `Índice de exposição: ${resultado.score}/100 (perfil ${cfg.l})\n` +
        `Ponto mais frágil: ${DIM_LABEL[foco.dim]}\n\n` +
        `Gostaria de falar com um especialista.`,
    );
    const whatsappUrl = `https://wa.me/${WHATSAPP_COMERCIAL}?text=${mensagem}`;

    return (
      <div className="border border-white/10 rounded-lg bg-white/[0.04] backdrop-blur p-6 md:p-8">
        <div className="text-center mb-8">
          <CheckCircle2 className="w-10 h-10 mx-auto mb-3" style={{ color: cfg.cor }} />
          <h3 className="text-2xl font-bold text-white">Seu resultado</h3>
          <p className="text-sm text-slate-400 mt-1">
            {empresa} · {PORTES.find((p) => p.v === porte)?.l ?? "—"} colaboradores · {setor || "—"}
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-6 mb-8">
          <div className="rounded-lg p-6 text-center bg-white/[0.04] border border-white/10">
            <div className="text-xs uppercase tracking-widest text-slate-400 mb-2">
              Índice de exposição
            </div>
            <div className="text-6xl font-bold" style={{ color: cfg.cor }}>
              {resultado.score}
              <span className="text-xl text-slate-500">/100</span>
            </div>
            <div
              className="inline-block mt-3 px-3 py-1 rounded-full text-xs font-semibold"
              style={{ background: `${cfg.cor}22`, color: cfg.cor, border: `1px solid ${cfg.cor}55` }}
            >
              Perfil: {cfg.l}
            </div>
            <p className="text-[11px] text-slate-500 mt-3">Quanto maior, mais descoberta está a empresa.</p>
          </div>

          <div className="space-y-4">
            {resultado.dims.map((d) => {
              const cor = d.pct >= 60 ? "#F87171" : d.pct >= 30 ? "#FF8A00" : "#34D399";
              return (
                <div key={d.dim}>
                  <div className="flex justify-between text-xs mb-1">
                    <span className="text-slate-300">{DIM_LABEL[d.dim]}</span>
                    <span className="font-semibold" style={{ color: cor }}>{d.pct}/100</span>
                  </div>
                  <div className="h-2 rounded-full bg-white/10 overflow-hidden">
                    <div className="h-full rounded-full transition-all duration-700" style={{ width: `${d.pct}%`, background: cor }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        <p className="text-slate-300 leading-relaxed text-center mb-8">{cfg.resumo}</p>

        <div className="grid md:grid-cols-2 gap-4 mb-8">
          <div className="rounded-lg p-5 border border-[#F87171]/40 bg-[#F87171]/[0.07]">
            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-[#F87171] mb-3">
              <AlertTriangle className="w-4 h-4" /> Onde você está exposto
            </div>
            {resultado.expostas.length === 0 ? (
              <p className="text-sm text-slate-300">
                Nenhuma lacuna crítica nas respostas. Vale confirmar se cada item tem evidência guardada.
              </p>
            ) : (
              <ul className="space-y-2.5 text-sm text-slate-200">
                {resultado.expostas.slice(0, 4).map((p) => (
                  <li key={p.id} className="flex gap-2">
                    <span className="text-[#F87171]">•</span>
                    <span>{p.exposicao}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="rounded-lg p-5 border border-[#34D399]/40 bg-[#34D399]/[0.07]">
            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-[#34D399] mb-3">
              <Sparkles className="w-4 h-4" /> Por onde começar
            </div>
            <ul className="space-y-2.5 text-sm text-slate-200">
              {passos.map((a) => (
                <li key={a} className="flex gap-2">
                  <span className="text-[#34D399]">✓</span>
                  <span>{a}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="rounded-lg p-6 text-center border border-white/10 bg-white/[0.04]">
          <p className="text-white font-semibold mb-1">Quer entender o que fazer com esse resultado?</p>
          <p className="text-sm text-slate-400 mb-5">
            Um especialista analisa o seu caso e mostra o caminho para fechar as lacunas — sem compromisso.
          </p>
          <a
            href={whatsappUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 bg-[#25D366] hover:bg-[#1FB855] text-[#0B1D34] font-bold px-6 py-3 rounded-md transition"
          >
            <MessageCircle className="w-5 h-5" /> Falar com um especialista
          </a>
          <p className="text-[11px] text-slate-500 mt-4">
            Abre uma conversa no WhatsApp com o seu resultado já preenchido.
          </p>
        </div>

        <p className="text-[11px] text-slate-500 text-center mt-6 leading-relaxed">
          Este é um diagnóstico organizacional de conformidade com a NR-1. Não avalia pessoas nem
          substitui avaliação clínica, e nenhuma informação de saúde é coletada aqui.
        </p>
      </div>
    );
  }

  // ============================ PASSOS ============================
  const pct = ((passo + 1) / totalPassos) * 100;
  const inputCls =
    "w-full mt-1 border border-white/15 bg-white/5 text-white placeholder:text-slate-500 rounded-md px-3 py-2 text-sm focus:border-[#60ABEF] focus:ring-1 focus:ring-[#60ABEF] outline-none";
  const labelCls = "text-xs font-semibold text-slate-300 uppercase tracking-wider";

  const opcoes = (
    itens: { value: string; label: string }[],
    valor: string,
    onPick: (v: string) => void,
    cols: 1 | 2,
  ) => (
    <div className={`grid gap-2 ${cols === 2 ? "grid-cols-1 sm:grid-cols-2" : "grid-cols-1"}`}>
      {itens.map((o) => {
        const sel = valor === o.value;
        return (
          <button
            key={o.value}
            type="button"
            onClick={() => onPick(o.value)}
            className={`text-left px-4 py-3 rounded-md border text-sm font-medium transition ${
              sel
                ? "border-[#60ABEF] bg-[#60ABEF]/15 text-[#8CC5F5]"
                : "border-white/15 bg-white/[0.04] text-slate-200 hover:border-white/30 hover:bg-white/[0.07]"
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );

  const conteudo = () => {
    if (passo === 0) {
      return (
        <>
          <h3 className="text-xl md:text-2xl font-bold text-white mb-1">
            Quantas pessoas trabalham na empresa?
          </h3>
          <p className="text-sm text-slate-400 mb-6">
            Inclui CLT, terceirizados e estagiários. Serve de contexto — não pontua.
          </p>
          {opcoes(
            PORTES.map((p) => ({ value: p.v, label: p.l })),
            porte,
            (v) => {
              setPorte(v);
              avancar();
            },
            2,
          )}
        </>
      );
    }

    if (passo === 1) {
      return (
        <>
          <h3 className="text-xl md:text-2xl font-bold text-white mb-1">Qual o setor da empresa?</h3>
          <p className="text-sm text-slate-400 mb-6">
            Cada segmento tem fatores psicossociais típicos — usamos isso para ler o seu resultado.
          </p>
          {opcoes(
            SETORES.map((s) => ({ value: s, label: s })),
            setor,
            (v) => {
              setSetor(v);
              avancar();
            },
            2,
          )}
        </>
      );
    }

    if (passo < passoContato) {
      const p = PERGUNTAS[passo - 2];
      return (
        <>
          <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-2">
            {DIM_LABEL[p.dim]}
          </div>
          <h3 className="text-xl md:text-2xl font-bold text-white mb-1">{p.pergunta}</h3>
          <p className="text-sm text-slate-400 mb-6">{p.ajuda}</p>
          {opcoes(
            RESPOSTAS.map((o) => ({ value: o.v, label: o.l })),
            respostas[p.id] ?? "",
            (v) => {
              setRespostas((r) => ({ ...r, [p.id]: v as RespKey }));
              avancar();
            },
            1,
          )}
        </>
      );
    }

    return (
      <>
        <h3 className="text-xl md:text-2xl font-bold text-white mb-1">
          Pronto. Para onde enviamos o resultado?
        </h3>
        <p className="text-sm text-slate-400 mb-6">
          O resultado aparece aqui na tela, na hora. Os dados servem para o especialista falar com você.
        </p>
        <div className="grid md:grid-cols-2 gap-4">
          <div>
            <label className={labelCls}>Nome*</label>
            <input className={inputCls} value={nome} onChange={(e) => setNome(e.target.value)} maxLength={200} placeholder="Seu nome" />
          </div>
          <div>
            <label className={labelCls}>Empresa*</label>
            <input className={inputCls} value={empresa} onChange={(e) => setEmpresa(e.target.value)} maxLength={300} placeholder="Nome da empresa" />
          </div>
          <div>
            <label className={labelCls}>Cargo</label>
            <input className={inputCls} value={cargo} onChange={(e) => setCargo(e.target.value)} maxLength={200} placeholder="Ex.: Gestor de RH" />
          </div>
          <div>
            <label className={labelCls}>E-mail corporativo*</label>
            <input className={inputCls} type="email" value={email} onChange={(e) => setEmail(e.target.value)} maxLength={320} placeholder="voce@empresa.com.br" />
          </div>
          <div className="md:col-span-2">
            <label className={labelCls}>WhatsApp*</label>
            <input className={inputCls} value={telefone} onChange={(e) => setTelefone(e.target.value)} inputMode="tel" maxLength={30} placeholder="(46) 99999-9999" />
          </div>
        </div>
        <button
          type="button"
          onClick={enviar}
          disabled={enviando}
          className="w-full mt-6 bg-[#FF8A00] hover:bg-[#e67a00] disabled:opacity-60 text-white font-semibold py-3 rounded-md transition inline-flex items-center justify-center gap-2"
        >
          {enviando ? (
            <>
              <Loader2 className="w-4 h-4 animate-spin" /> Calculando...
            </>
          ) : (
            <>
              Ver meu resultado <ArrowRight className="w-4 h-4" />
            </>
          )}
        </button>
      </>
    );
  };

  return (
    <div className="border border-white/10 rounded-lg bg-white/[0.04] backdrop-blur p-6 md:p-8">
      <div className="mb-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-slate-400">
            <ShieldCheck className="w-4 h-4 text-[#60ABEF]" />
            Riscos psicossociais · NR-1
          </div>
          <span className="text-xs text-slate-500">
            {passo + 1} / {totalPassos}
          </span>
        </div>
        <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
          <div
            className="h-full rounded-full bg-gradient-to-r from-[#60ABEF] to-[#FF8A00] transition-all duration-300"
            style={{ width: `${pct}%` }}
          />
        </div>
      </div>

      {conteudo()}

      {passo > 0 && (
        <button
          type="button"
          onClick={voltar}
          className="mt-5 text-xs text-slate-500 hover:text-slate-300 inline-flex items-center gap-1"
        >
          <ArrowLeft className="w-3 h-3" /> Voltar
        </button>
      )}
    </div>
  );
}

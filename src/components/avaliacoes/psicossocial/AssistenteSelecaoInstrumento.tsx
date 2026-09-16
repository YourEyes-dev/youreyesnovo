import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Sparkles, Brain, ArrowRight, ArrowLeft, CheckCircle2,
  Building2, AlertTriangle, Shield,
  FileText, Clock, Search, Award, Zap, Activity,
} from "lucide-react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";

// ─── Types ────────────────────────────────────────────────────────────────────

type Step = 'choice' | 'auto-loading' | 'checklist' | 'result' | 'entrevista-recomendada';

interface SystemData {
  totalColaboradores: number;
  totalSetores: number;
  temTurnoNoturno: boolean;
  temTurnoRevezamento: boolean;
  mediaHorasExtras: number; // minutos por semana
  totalAfastamentosSaudeMental: number;
  totalAfastamentos: number;
  totalCampanhasAnteriores: number;
  temEscalaIrregular: boolean;
  grauRisco: number; // 1-4
  // Condições especiais do cadastro da empresa
  possuiTerceiroTurno: boolean;
  trabalhoAltura: boolean;
  espacoConfinado: boolean;
  insalubridade: boolean;
  periculosidade: boolean;
  aposentadoriaEspecial: boolean;
  cnae: string | null;
}

interface ChecklistRespostas {
  experienciaPrevia: '' | 'nunca' | 'uma_vez' | 'periodicamente';
  objetivo: '' | 'diagnostico' | 'gestao_lideranca' | 'investigar_afastamentos' | 'auditoria' | 'pgr';
  sinaisRisco: '' | 'nenhum' | 'alguns' | 'varios';
  complexidade: string[]; // múltipla escolha
  tipoPredominante: '' | 'administrativo' | 'industrial' | 'saude' | 'educacao' | 'logistica' | 'comercial' | 'servicos';
}

interface InstrumentoScore {
  id: 'sipro' | 'copsoq' | 'hse' | 'proart';
  nome: string;
  descricao: string;
  score: number;
  motivos: string[];
  cor: string;
  bgCor: string;
  icone: string;
}

// ─── Scoring Engine ───────────────────────────────────────────────────────────

function calcularScores(sys: SystemData, c: ChecklistRespostas): InstrumentoScore[] {
  // Cada instrumento começa em 0. O total de pontos disponíveis por critério é
  // distribuído de forma proporcional entre os candidatos, garantindo disputa real.
  let sipro = 0, copsoq = 0, hse = 0, proart = 0;
  const motivosSipro: string[] = [];
  const motivosCopsoq: string[] = [];
  const motivosHse: string[] = [];
  const motivosProart: string[] = [];

  // ── 1. TAMANHO DA EMPRESA (máx 20 pts, distribuídos) ──
  if (sys.totalColaboradores < 50) {
    sipro += 20;
    motivosSipro.push(`pequena empresa (${sys.totalColaboradores} colaboradores) — SIPRO abrange todas as dimensões`);
  } else if (sys.totalColaboradores <= 200) {
    sipro += 14; copsoq += 10; hse += 6;
    motivosCopsoq.push(`empresa de porte médio (${sys.totalColaboradores} colaboradores)`);
  } else if (sys.totalColaboradores <= 500) {
    copsoq += 16; sipro += 10; hse += 8;
    motivosCopsoq.push("empresa de médio-grande porte — COPSOQ amplamente validado");
  } else {
    copsoq += 20; hse += 14; sipro += 6;
    motivosCopsoq.push("grande empresa (500+) — COPSOQ modificado referência global");
    motivosHse.push("escala grande favorece HSE como padrão de gestão");
  }

  // ── 2. EXPERIÊNCIA PRÉVIA (máx 20 pts) ──
  if (c.experienciaPrevia === 'nunca') {
    sipro += 20; copsoq += 8;
    motivosSipro.push("primeira avaliação — SIPRO oferece onboarding integrado");
  } else if (c.experienciaPrevia === 'uma_vez') {
    sipro += 12; copsoq += 12; hse += 8;
    motivosCopsoq.push("experiência prévia permite comparação com benchmarks");
  } else {
    copsoq += 20; proart += 14; hse += 10;
    motivosCopsoq.push("avaliações periódicas — COPSOQ permite séries históricas comparadas");
    motivosProart.push("histórico de avaliações favorece aprofundamento com PROART");
  }

  // ── 3. OBJETIVO PRINCIPAL (máx 25 pts) ──
  if (c.objetivo === 'diagnostico') {
    sipro += 25; copsoq += 18;
    motivosSipro.push("diagnóstico inicial — SIPRO cobre 12 dimensões NR-01/ISO 45003");
    motivosCopsoq.push("COPSOQ modificado também é referência para diagnósticos abrangentes");
  } else if (c.objetivo === 'pgr') {
    sipro += 25; copsoq += 15;
    motivosSipro.push("integração nativa ao PGR dentro do YourEyes");
    motivosCopsoq.push("COPSOQ aceito em auditoria de PGR");
  } else if (c.objetivo === 'gestao_lideranca') {
    hse += 25; copsoq += 18; sipro += 8;
    motivosHse.push("HSE Management Standards criado especificamente para gestão de líderes");
    motivosCopsoq.push("COPSOQ inclui fatores de liderança e suporte social");
  } else if (c.objetivo === 'investigar_afastamentos') {
    proart += 25; sipro += 12; copsoq += 8;
    motivosProart.push("PROART investiga sofrimento e danos — indicado para afastamentos");
    motivosSipro.push("SIPRO detecta dimensões com risco de sobrecarga");
  } else if (c.objetivo === 'auditoria') {
    copsoq += 25; hse += 18; sipro += 10;
    motivosCopsoq.push("COPSOQ modificado referência internacional para auditorias externas");
    motivosHse.push("HSE padrão britânico reconhecido por órgãos regulatórios");
  }

  // ── 4. SINAIS DE RISCO PSICOSSOCIAL (máx 20 pts) ──
  if (c.sinaisRisco === 'varios') {
    proart += 20; copsoq += 14; sipro += 10;
    motivosProart.push("múltiplos sinais de risco — PROART aprofunda causas e sofrimento");
    motivosCopsoq.push("COPSOQ quantifica os fatores de risco com precisão");
  } else if (c.sinaisRisco === 'alguns') {
    sipro += 16; copsoq += 16; proart += 10;
    motivosSipro.push("sinais moderados — SIPRO mapeia dimensões de atenção");
  } else {
    sipro += 12; hse += 12; copsoq += 8;
    motivosHse.push("sem sinais críticos — HSE ideal para monitoramento preventivo");
    motivosSipro.push("ambiente estável — diagnóstico de base recomendado");
  }

  // ── 5. COMPLEXIDADE ORGANIZACIONAL (máx 15 pts) ──
  const nComplexidade = c.complexidade.length;
  if (nComplexidade >= 4) {
    copsoq += 15; sipro += 10; hse += 8;
    motivosCopsoq.push("alta complexidade organizacional — COPSOQ abrange todos os fatores");
  } else if (nComplexidade >= 2) {
    sipro += 12; copsoq += 10; hse += 6;
  } else if (nComplexidade === 1) {
    hse += 12; sipro += 8;
    motivosHse.push("baixa complexidade favorece abordagem objetiva do HSE");
  } else {
    hse += 10; sipro += 8; copsoq += 6;
  }

  if (c.complexidade.includes('turno_noturno') || c.complexidade.includes('turnos')) {
    sipro += 10;
    motivosSipro.push("turnos noturnos — Bloco CET Ritmo Biológico exclusivo do SIPRO");
  }
  if (c.complexidade.includes('alta_pressao')) {
    proart += 10; copsoq += 8;
    motivosProart.push("alta pressão — PROART avalia prazer/sofrimento no trabalho");
  }
  if (c.complexidade.includes('teletrabalho') || c.complexidade.includes('hibrido')) {
    copsoq += 8; hse += 6;
    motivosCopsoq.push("teletrabalho/híbrido — COPSOQ inclui fatores de isolamento");
  }

  // ── 6. SETOR / TIPO DE TRABALHO (máx 15 pts) ──
  if (c.tipoPredominante === 'saude') {
    proart += 15; copsoq += 10; sipro += 6;
    motivosProart.push("setor saúde — alta demanda emocional e risco de burnout");
    motivosCopsoq.push("COPSOQ validado extensivamente em trabalhadores da saúde");
  } else if (c.tipoPredominante === 'educacao') {
    proart += 12; copsoq += 12; sipro += 6;
    motivosProart.push("educação — PROART detecta sofrimento por falta de sentido");
    motivosCopsoq.push("COPSOQ cobre exigências emocionais do ensino");
  } else if (c.tipoPredominante === 'industrial' || c.tipoPredominante === 'logistica') {
    sipro += 15; proart += 6;
    motivosSipro.push(`setor ${c.tipoPredominante} — SIPRO avalia ergonomia e ritmo biológico`);
  } else if (c.tipoPredominante === 'administrativo' || c.tipoPredominante === 'servicos') {
    hse += 12; copsoq += 10; sipro += 6;
    motivosHse.push("setor administrativo/serviços — HSE foca em demandas e controle");
  } else if (c.tipoPredominante === 'comercial') {
    copsoq += 12; hse += 10; sipro += 6;
    motivosCopsoq.push("setor comercial — COPSOQ avalia pressão de metas e suporte");
  } else {
    sipro += 8; copsoq += 8; hse += 6;
  }

  // ── 7. DADOS OBJETIVOS DO SISTEMA (máx 20 pts, bônus baseados em evidências) ──
  if (sys.totalAfastamentosSaudeMental > 10) {
    proart += 20; sipro += 8; copsoq += 6;
    motivosProart.push(`${sys.totalAfastamentosSaudeMental} afastamentos saúde mental — PROART investiga causas`);
  } else if (sys.totalAfastamentosSaudeMental > 3) {
    proart += 14; sipro += 10; copsoq += 8;
    motivosProart.push("afastamentos por saúde mental — aprofundamento recomendado");
  } else if (sys.totalAfastamentosSaudeMental > 0) {
    sipro += 10; copsoq += 8;
    motivosSipro.push("afastamentos por saúde mental detectados — mapeamento preventivo");
  }

  if (sys.temTurnoNoturno || sys.temTurnoRevezamento || sys.possuiTerceiroTurno) {
    sipro += 12; proart += 5;
    motivosSipro.push("turnos/revezamento — Bloco CET Ritmo Biológico incluso no SIPRO");
  }

  if (sys.mediaHorasExtras > 180) {
    proart += 12; sipro += 8; copsoq += 6;
    motivosProart.push("horas extras elevadas — PROART avalia sobrecarga e danos");
  } else if (sys.mediaHorasExtras > 80) {
    sipro += 8; copsoq += 6;
    motivosSipro.push("horas extras moderadas — dimensão Ritmo & Carga inclusa");
  }

  if (sys.grauRisco >= 3) {
    proart += 10; sipro += 8; copsoq += 5;
    motivosProart.push(`grau de risco ${sys.grauRisco} (NR-04) — investigação aprofundada recomendada`);
    motivosSipro.push(`grau de risco ${sys.grauRisco} — SIPRO cobre dimensões de segurança`);
  } else if (sys.grauRisco === 2) {
    sipro += 6; hse += 8;
    motivosHse.push("grau de risco 2 — HSE adequado para gestão preventiva");
  }

  if (sys.insalubridade || sys.periculosidade) {
    sipro += 8; proart += 6;
    const conds = [sys.insalubridade && 'insalubridade', sys.periculosidade && 'periculosidade'].filter(Boolean).join(', ');
    motivosSipro.push(`${conds} detectada — Blocos CET disponíveis no SIPRO`);
  }

  if (sys.trabalhoAltura || sys.espacoConfinado) {
    sipro += 6;
    motivosSipro.push("condições de trabalho especiais — SIPRO possui blocos CET dedicados");
  }

  if (sys.totalCampanhasAnteriores === 0) {
    sipro += 10; copsoq += 8;
    motivosSipro.push("primeira campanha — SIPRO integrado ao fluxo do YourEyes");
  } else if (sys.totalCampanhasAnteriores >= 2) {
    copsoq += 10; proart += 8;
    motivosCopsoq.push("histórico de campanhas — COPSOQ permite comparação longitudinal");
  }

  // ── Normalização: converter para escala 0-100 relativa ao maior score ──
  const rawMax = Math.max(sipro, copsoq, hse, proart);
  const normalize = (v: number) => rawMax === 0 ? 0 : Math.round((v / rawMax) * 100);

  const result: InstrumentoScore[] = [
    {
      id: 'sipro' as const,
      nome: 'SIPRO',
      descricao: 'Instrumento autoral YourEyes — alinhado à NR-01, NR-17, ISO 45001 e ISO 45003. Diagnóstico multidimensional com 52 itens e cálculo integrado ao sistema.',
      score: normalize(sipro),
      motivos: motivosSipro.filter(Boolean).slice(0, 4),
      cor: 'text-purple-700',
      bgCor: 'bg-purple-50 border-purple-200',
      icone: '⭐',
    },
    {
      id: 'copsoq' as const,
      nome: 'COPSOQ modificado',
      descricao: 'Instrumento psicossocial mais utilizado internacionalmente, com base científica robusta e ampla cobertura de fatores organizacionais.',
      score: normalize(copsoq),
      motivos: motivosCopsoq.filter(Boolean).slice(0, 4),
      cor: 'text-blue-700',
      bgCor: 'bg-blue-50 border-blue-200',
      icone: '🌍',
    },
    {
      id: 'hse' as const,
      nome: 'HSE Management Standards',
      descricao: 'Focado em fatores organizacionais de estresse relacionados à gestão, liderança e mudanças organizacionais.',
      score: normalize(hse),
      motivos: motivosHse.filter(Boolean).slice(0, 4),
      cor: 'text-emerald-700',
      bgCor: 'bg-emerald-50 border-emerald-200',
      icone: '🏛️',
    },
    {
      id: 'proart' as const,
      nome: 'PROART',
      descricao: 'Instrumento aprofundado para investigação detalhada de sofrimento e danos relacionados ao trabalho. Indicado quando há sinais críticos.',
      score: normalize(proart),
      motivos: motivosProart.filter(Boolean).slice(0, 4),
      cor: 'text-amber-700',
      bgCor: 'bg-amber-50 border-amber-200',
      icone: '🔬',
    },
  ];
  return result.sort((a, b) => b.score - a.score);
}

// ─── Props ────────────────────────────────────────────────────────────────────

interface AssistenteSelecaoInstrumentoProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelectInstrumento: (instrumento: string, manual: boolean) => void;
}

// ─── Component ────────────────────────────────────────────────────────────────

export function AssistenteSelecaoInstrumento({
  open, onOpenChange, onSelectInstrumento,
}: AssistenteSelecaoInstrumentoProps) {
  const { user } = useAuthContext();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [step, setStep] = useState<Step>('choice');
  const [sysData, setSysData] = useState<SystemData | null>(null);
  const [respostas, setRespostas] = useState<ChecklistRespostas>({
    experienciaPrevia: '',
    objetivo: '',
    sinaisRisco: '',
    complexidade: [],
    tipoPredominante: '',
  });
  const [scores, setScores] = useState<InstrumentoScore[]>([]);
  const [currentQuestion, setCurrentQuestion] = useState(0);

  // Reset on open
  useEffect(() => {
    if (open) {
      setStep('choice');
      setCurrentQuestion(0);
      setRespostas({ experienciaPrevia: '', objetivo: '', sinaisRisco: '', complexidade: [], tipoPredominante: '' });
      setScores([]);
    }
  }, [open]);

  // Load system data
  const loadSystemData = async () => {
    setStep('auto-loading');
    try {
      const tenantId = user
        ? (await supabase.from('profiles').select('tenant_id').eq('user_id', user.id).single()).data?.tenant_id
        : null;

      // Queries paralelas — filtrando por empresa ativa quando disponível
      const empresaFilter = empresaAtivaId ? { empresa_id: empresaAtivaId } : {};

      const [campanhasRes, afastamentosRes, escalasRes, empresaRes, colaboradoresRes, setoresRes] =
        await Promise.allSettled([
          // Campanhas psicossociais anteriores
          tenantId
            ? (supabase as any).from('questionario_psicossocial_campanhas').select('id', { count: 'exact' }).eq('tenant_id', tenantId)
            : Promise.resolve({ data: [], count: 0 }),

          // Afastamentos filtrados pela empresa ativa
          tenantId
            ? supabase.from('afastamentos')
                .select('motivo_principal, nexo_trabalho')
                .eq('tenant_id', tenantId)
                .match(empresaFilter)
            : Promise.resolve({ data: [] }),

          // Escalas de ponto
          tenantId
            ? supabase.from('ponto_escalas').select('turno, jornada_diaria_minutos').eq('tenant_id', tenantId)
            : Promise.resolve({ data: [] }),

          // Dados completos da empresa ativa
          tenantId && empresaAtivaId
            ? supabase.from('empresa_cadastro')
                .select('grau_risco, total_colaboradores, cnae_principal, possui_terceiro_turno, possui_escalas_especiais, trabalho_altura, espaco_confinado, insalubridade, periculosidade, aposentadoria_especial')
                .eq('id', empresaAtivaId).single()
            : tenantId
              ? supabase.from('empresa_cadastro')
                  .select('grau_risco, total_colaboradores, cnae_principal, possui_terceiro_turno, possui_escalas_especiais, trabalho_altura, espaco_confinado, insalubridade, periculosidade, aposentadoria_especial')
                  .eq('tenant_id', tenantId).limit(1).single()
              : Promise.resolve({ data: null }),

          // Contagem real de colaboradores ativos
          tenantId
            ? supabase.from('admissoes')
                .select('id', { count: 'exact', head: true })
                .eq('tenant_id', tenantId)
                .not('status', 'eq', 'desligado')
                .match(empresaFilter)
            : Promise.resolve({ count: 0, data: [] }),

          // Contagem de setores/departamentos
          tenantId
            ? supabase.from('departamentos')
                .select('id', { count: 'exact', head: true })
                .eq('tenant_id', tenantId)
                .eq('ativo', true)
                .match(empresaAtivaId ? { empresa_id: empresaAtivaId } : {})
            : Promise.resolve({ count: 0, data: [] }),
        ]);

      const campanhas = campanhasRes.status === 'fulfilled' ? ((campanhasRes.value as any).data || []) : [];
      const afastamentos = afastamentosRes.status === 'fulfilled' ? (afastamentosRes.value.data || []) : [];
      const escalas = escalasRes.status === 'fulfilled' ? (escalasRes.value.data || []) : [];
      const empresa = empresaRes.status === 'fulfilled' ? (empresaRes.value as any).data : null;
      const totalColabCount = colaboradoresRes.status === 'fulfilled' ? ((colaboradoresRes.value as any).count ?? 0) : 0;
      const totalSetoresCount = setoresRes.status === 'fulfilled' ? ((setoresRes.value as any).count ?? 0) : 0;

      const afastSaudeMental = afastamentos.filter((a: any) =>
        a.motivo_principal === 'f' || a.nexo_trabalho === 'sim'
      ).length;

      const temNoturno = escalas.some((e: any) => e.turno === 'noturno' || e.turno === 'terceiro');
      const temRevezamento = escalas.some((e: any) => e.turno === 'revezamento' || e.turno === 'irregular');

      // Colaboradores: preferir contagem real, fallback ao campo do cadastro
      const totalColaboradores = totalColabCount > 0
        ? totalColabCount
        : (empresa?.total_colaboradores ?? 0);

      setSysData({
        totalColaboradores,
        totalSetores: totalSetoresCount,
        temTurnoNoturno: temNoturno || !!empresa?.possui_terceiro_turno,
        temTurnoRevezamento: temRevezamento || !!empresa?.possui_escalas_especiais,
        mediaHorasExtras: 0,
        totalAfastamentosSaudeMental: afastSaudeMental,
        totalAfastamentos: afastamentos.length,
        totalCampanhasAnteriores: campanhas.length,
        temEscalaIrregular: temRevezamento,
        grauRisco: empresa?.grau_risco ?? 2,
        possuiTerceiroTurno: !!empresa?.possui_terceiro_turno,
        trabalhoAltura: !!empresa?.trabalho_altura,
        espacoConfinado: !!empresa?.espaco_confinado,
        insalubridade: !!empresa?.insalubridade,
        periculosidade: !!empresa?.periculosidade,
        aposentadoriaEspecial: !!empresa?.aposentadoria_especial,
        cnae: empresa?.cnae_principal ?? null,
      });

      // Faixa <5 colaboradores → entrevista guiada por IA (anonimato + representatividade)
      if (totalColaboradores > 0 && totalColaboradores < 5) {
        setStep('entrevista-recomendada');
      } else {
        setStep('checklist');
      }
    } catch {
      setSysData({
        totalColaboradores: 0, totalSetores: 0, temTurnoNoturno: false,
        temTurnoRevezamento: false, mediaHorasExtras: 0, totalAfastamentosSaudeMental: 0,
        totalAfastamentos: 0, totalCampanhasAnteriores: 0, temEscalaIrregular: false, grauRisco: 2,
        possuiTerceiroTurno: false, trabalhoAltura: false, espacoConfinado: false,
        insalubridade: false, periculosidade: false, aposentadoriaEspecial: false, cnae: null,
      });
      setStep('checklist');
    }
  };

  const isChecklistComplete =
    respostas.experienciaPrevia !== '' &&
    respostas.objetivo !== '' &&
    respostas.sinaisRisco !== '' &&
    respostas.tipoPredominante !== '';

  const handleCalcular = () => {
    if (!sysData) return;
    const calculado = calcularScores(sysData, respostas);
    setScores(calculado);
    setStep('result');
  };

  const handleConfirm = (instrumento: string, manual = false) => {
    onSelectInstrumento(instrumento, manual);
  };

  const questions = [
    {
      id: 'experienciaPrevia',
      label: 'Experiência prévia',
      pergunta: 'Sua empresa já realizou avaliação psicossocial antes?',
      icon: <Clock className="h-5 w-5 text-purple-600" />,
      opcoes: [
        { value: 'nunca', label: 'Nunca realizou', desc: 'Primeira avaliação' },
        { value: 'uma_vez', label: 'Já realizou uma vez', desc: 'Experiência inicial' },
        { value: 'periodicamente', label: 'Realiza periodicamente', desc: 'Processo maduro' },
      ],
    },
    {
      id: 'objetivo',
      label: 'Objetivo',
      pergunta: 'Qual o principal objetivo desta avaliação?',
      icon: <Search className="h-5 w-5 text-blue-600" />,
      opcoes: [
        { value: 'diagnostico', label: 'Diagnóstico inicial', desc: 'Mapear o cenário atual' },
        { value: 'gestao_lideranca', label: 'Gestão e liderança', desc: 'Melhorar gestão de pessoas' },
        { value: 'investigar_afastamentos', label: 'Investigar afastamentos', desc: 'Entender aumento de afastamentos' },
        { value: 'auditoria', label: 'Auditoria / fiscalização', desc: 'Atender exigência legal' },
        { value: 'pgr', label: 'PGR / NR-01', desc: 'Avaliação periódica do PGR' },
      ],
    },
    {
      id: 'sinaisRisco',
      label: 'Sinais de risco',
      pergunta: 'Nos últimos 12 meses, quantos sinais de risco você identificou?',
      icon: <AlertTriangle className="h-5 w-5 text-amber-600" />,
      opcoes: [
        { value: 'nenhum', label: 'Nenhum sinal', desc: 'Ambiente aparentemente estável' },
        { value: 'alguns', label: 'Alguns sinais', desc: 'Indícios pontuais' },
        { value: 'varios', label: 'Vários sinais', desc: 'Afastamentos, conflitos, denúncias, turnover' },
      ],
    },
    {
      id: 'tipoPredominante',
      label: 'Tipo de trabalho',
      pergunta: 'Qual o tipo predominante de trabalho na empresa?',
      icon: <Building2 className="h-5 w-5 text-emerald-600" />,
      opcoes: [
        { value: 'administrativo', label: 'Administrativo', desc: 'Escritório, backoffice' },
        { value: 'industrial', label: 'Industrial', desc: 'Produção, manufatura' },
        { value: 'saude', label: 'Saúde', desc: 'Hospitalar, clínicas' },
        { value: 'logistica', label: 'Logística', desc: 'Transporte, armazém' },
        { value: 'comercial', label: 'Comercial', desc: 'Varejo, vendas' },
        { value: 'servicos', label: 'Serviços', desc: 'TI, consultoria, outros' },
      ],
    },
  ];

  const currentQ = questions[currentQuestion];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        {/* ── CHOICE ── */}
        <AnimatePresence mode="wait">
          {step === 'choice' && (
            <motion.div key="choice" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -12 }}>
              <DialogHeader className="mb-6">
                <div className="flex items-center gap-3 mb-2">
                  <div className="p-2.5 rounded-xl bg-purple-100">
                    <Sparkles className="h-6 w-6 text-purple-600" />
                  </div>
                  <div>
                    <DialogTitle className="text-xl">Nova Campanha Psicossocial</DialogTitle>
                    <DialogDescription>Como deseja escolher o instrumento de avaliação?</DialogDescription>
                  </div>
                </div>
              </DialogHeader>

              <div className="grid gap-4 sm:grid-cols-2">
                {/* Assistente Inteligente */}
                <button
                  id="btn-assistente-inteligente-psicossocial"
                  onClick={loadSystemData}
                  className="group text-left p-5 rounded-xl border-2 border-purple-200 bg-gradient-to-br from-purple-50 to-background hover:border-purple-400 hover:shadow-md transition-all"
                >
                  <div className="flex items-center gap-3 mb-3">
                    <div className="p-2 rounded-lg bg-purple-100 group-hover:bg-purple-200 transition-colors">
                      <Sparkles className="h-5 w-5 text-purple-600" />
                    </div>
                    <div>
                      <p className="font-semibold text-sm">Assistente Inteligente</p>
                      <Badge className="bg-purple-600 text-xs mt-0.5">Recomendado</Badge>
                    </div>
                  </div>
                  <p className="text-sm text-muted-foreground leading-relaxed">
                    O sistema analisa dados da sua empresa e faz perguntas guiadas para recomendar o instrumento mais adequado.
                  </p>
                  <div className="mt-3 flex items-center gap-1.5 text-xs text-purple-600 font-medium">
                    <Zap className="h-3.5 w-3.5" />
                    Leva menos de 2 minutos
                  </div>
                </button>

                {/* Escolha manual */}
                <button
                  id="btn-escolher-instrumento-manualmente"
                  onClick={() => handleConfirm('sipro', true)}
                  className="group text-left p-5 rounded-xl border-2 border-border hover:border-foreground/30 hover:shadow-sm transition-all"
                >
                  <div className="flex items-center gap-3 mb-3">
                    <div className="p-2 rounded-lg bg-muted group-hover:bg-muted/80 transition-colors">
                      <Brain className="h-5 w-5 text-foreground/60" />
                    </div>
                    <p className="font-semibold text-sm">Escolher manualmente</p>
                  </div>
                  <p className="text-sm text-muted-foreground leading-relaxed">
                    Você já sabe qual instrumento usar e prefere configurar a campanha diretamente.
                  </p>
                  <div className="mt-3 flex items-center gap-1.5 text-xs text-muted-foreground font-medium">
                    <FileText className="h-3.5 w-3.5" />
                    Acesso direto ao formulário
                  </div>
                </button>
              </div>

              {/* Normas */}
              <div className="mt-5 flex flex-wrap gap-2">
                {['NR-01', 'NR-17', 'ISO 45001', 'ISO 45003'].map(n => (
                  <Badge key={n} variant="outline" className="text-xs text-muted-foreground">{n}</Badge>
                ))}
              </div>
            </motion.div>
          )}

          {/* ── LOADING ── */}
          {step === 'auto-loading' && (
            <motion.div key="loading" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
              className="flex flex-col items-center justify-center py-16 gap-4">
              <div className="relative">
                <div className="h-16 w-16 rounded-full border-4 border-purple-200 border-t-purple-600 animate-spin" />
                <Brain className="absolute inset-0 m-auto h-6 w-6 text-purple-600" />
              </div>
              <div className="text-center">
                <p className="font-semibold">Analisando dados da empresa</p>
                <p className="text-sm text-muted-foreground mt-1">
                  Lendo colaboradores, escalas, afastamentos e histórico...
                </p>
              </div>
            </motion.div>
          )}

          {/* ── CHECKLIST ── */}
          {step === 'checklist' && sysData && (
            <motion.div key="checklist" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }}>
              <DialogHeader className="mb-4">
                <div className="flex items-center gap-2">
                  <Sparkles className="h-5 w-5 text-purple-600" />
                  <DialogTitle>Assistente de Seleção</DialogTitle>
                </div>
                <DialogDescription>
                  Pergunta {currentQuestion + 1} de {questions.length}
                </DialogDescription>
              </DialogHeader>

              {/* Progress bar */}
              <div className="w-full bg-muted rounded-full h-1.5 mb-5">
                <motion.div
                  className="bg-purple-600 h-1.5 rounded-full"
                  initial={{ width: 0 }}
                  animate={{ width: `${((currentQuestion + 1) / questions.length) * 100}%` }}
                  transition={{ duration: 0.3 }}
                />
              </div>

              {/* Dados automáticos detectados */}
              {currentQuestion === 0 && (
                <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
                  className="mb-5 p-3 rounded-lg bg-blue-50 border border-blue-200">
                  <p className="text-xs font-semibold text-blue-700 mb-2 flex items-center gap-1.5">
                    <Activity className="h-3.5 w-3.5" />
                    Dados detectados automaticamente do cadastro da empresa
                  </p>
                  <div className="grid grid-cols-2 gap-1.5 text-xs text-blue-800">
                    <span>👥 {sysData.totalColaboradores} colaboradores ativos</span>
                    <span>📋 {sysData.totalCampanhasAnteriores} campanhas anteriores</span>
                    <span>🏷️ Grau de risco {sysData.grauRisco} (NR-04)</span>
                    {sysData.cnae && <span>🏭 CNAE {sysData.cnae}</span>}
                    {(sysData.temTurnoNoturno || sysData.possuiTerceiroTurno) && <span>🌙 3º turno / noturno</span>}
                    {sysData.temTurnoRevezamento && <span>🔄 Revezamento detectado</span>}
                    {sysData.trabalhoAltura && <span>⬆️ Trabalho em altura</span>}
                    {sysData.espacoConfinado && <span>🔒 Espaço confinado</span>}
                    {sysData.insalubridade && <span>⚠️ Insalubridade</span>}
                    {sysData.periculosidade && <span>🔴 Periculosidade</span>}
                    {sysData.aposentadoriaEspecial && <span>📅 Aposent. especial</span>}
                    {sysData.totalAfastamentosSaudeMental > 0 && (
                      <span>🏥 {sysData.totalAfastamentosSaudeMental} afastamentos saúde mental</span>
                    )}
                  </div>
                </motion.div>
              )}

              {/* Pergunta atual */}
              <AnimatePresence mode="wait">
                <motion.div key={currentQuestion}
                  initial={{ opacity: 0, x: 15 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -15 }}>
                  <div className="flex items-center gap-2 mb-4">
                    {currentQ.icon}
                    <h3 className="font-semibold text-base">{currentQ.pergunta}</h3>
                  </div>

                  {currentQ.id === 'complexidade' ? (
                    /* Multi-select */
                    <div className="grid gap-2 sm:grid-cols-2">
                      {[
                        { value: 'multi_departamentos', label: 'Mais de 3 departamentos' },
                        { value: 'multi_unidades', label: 'Múltiplas unidades' },
                        { value: 'turnos', label: 'Turnos de trabalho' },
                        { value: 'turno_noturno', label: 'Trabalho noturno' },
                        { value: 'alta_pressao', label: 'Alta pressão / metas' },
                      ].map(op => {
                        const sel = respostas.complexidade.includes(op.value);
                        return (
                          <button key={op.value}
                            onClick={() => setRespostas(r => ({
                              ...r,
                              complexidade: sel
                                ? r.complexidade.filter(v => v !== op.value)
                                : [...r.complexidade, op.value],
                            }))}
                            className={cn(
                              "p-3 rounded-lg border text-left text-sm transition-all",
                              sel ? "border-purple-400 bg-purple-50 font-medium text-purple-800" : "border-border hover:border-purple-200"
                            )}>
                            <span>{sel ? '✓ ' : ''}{op.label}</span>
                          </button>
                        );
                      })}
                    </div>
                  ) : (
                    /* Single-select */
                    <div className="grid gap-2 sm:grid-cols-2">
                      {currentQ.opcoes?.map(op => {
                        const sel = (respostas as any)[currentQ.id] === op.value;
                        return (
                          <button key={op.value}
                            onClick={() => setRespostas(r => ({ ...r, [currentQ.id]: op.value }))}
                            className={cn(
                              "p-3 rounded-lg border text-left transition-all",
                              sel ? "border-purple-400 bg-purple-50" : "border-border hover:border-purple-200"
                            )}>
                            <p className={cn("font-medium text-sm", sel && "text-purple-800")}>{op.label}</p>
                            <p className="text-xs text-muted-foreground mt-0.5">{op.desc}</p>
                          </button>
                        );
                      })}
                    </div>
                  )}
                </motion.div>
              </AnimatePresence>

              {/* Navigation */}
              <div className="flex items-center justify-between mt-6">
                <Button variant="ghost" size="sm"
                  onClick={() => currentQuestion > 0 ? setCurrentQuestion(q => q - 1) : setStep('choice')}
                  className="gap-1.5">
                  <ArrowLeft className="h-4 w-4" /> Voltar
                </Button>
                {currentQuestion < questions.length - 1 ? (
                  <Button size="sm" onClick={() => setCurrentQuestion(q => q + 1)} className="gap-1.5">
                    Próximo <ArrowRight className="h-4 w-4" />
                  </Button>
                ) : (
                  <Button size="sm" onClick={handleCalcular}
                    disabled={!isChecklistComplete}
                    className="gap-1.5 bg-purple-600 hover:bg-purple-700">
                    <Sparkles className="h-4 w-4" /> Ver Recomendação
                  </Button>
                )}
              </div>
            </motion.div>
          )}

          {/* ── RESULT ── */}
          {/* ── ENTREVISTA RECOMENDADA (<5 colaboradores) ── */}
          {step === 'entrevista-recomendada' && sysData && (
            <motion.div key="entrevista-rec" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -12 }}>
              <DialogHeader className="mb-5">
                <div className="flex items-center gap-2">
                  <Award className="h-5 w-5 text-purple-600" />
                  <DialogTitle>Entrevista Guiada por IA</DialogTitle>
                </div>
                <DialogDescription>
                  Recomendação baseada no porte da empresa
                </DialogDescription>
              </DialogHeader>

              <div className="rounded-xl border-2 border-purple-200 bg-purple-50 p-5 mb-4">
                <div className="flex items-start gap-3 mb-3">
                  <span className="text-2xl">🎙️</span>
                  <div>
                    <h3 className="font-bold text-lg text-purple-700">Entrevista Guiada por IA (SIPRO conversacional)</h3>
                    <p className="text-xs text-muted-foreground mt-1">
                      Coleta qualitativa individual, anonimizada por IA, com geração de evidências para o PGR.
                    </p>
                  </div>
                </div>
                <div className="mb-3">
                  <p className="text-xs font-semibold text-muted-foreground mb-1.5">Motivos:</p>
                  <ul className="space-y-1 text-xs">
                    <li className="flex items-center gap-2">
                      <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500 shrink-0" />
                      Empresa com {sysData.totalColaboradores} colaboradores — abaixo do mínimo de 5 respondentes para anonimato em questionário (ISO 45003).
                    </li>
                    <li className="flex items-center gap-2">
                      <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500 shrink-0" />
                      Entrevista guiada preserva o anonimato via trechos anonimizados pela IA.
                    </li>
                    <li className="flex items-center gap-2">
                      <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500 shrink-0" />
                      Gera evidências qualitativas válidas para o PGR e atende NR-01.
                    </li>
                  </ul>
                </div>
                <div className="flex flex-wrap gap-1.5 pt-3 border-t border-black/10">
                  {['NR-01', 'ISO 45003', 'LGPD'].map(n => (
                    <Badge key={n} variant="outline" className="text-xs">{n}</Badge>
                  ))}
                </div>
              </div>

              <div className="flex flex-col sm:flex-row gap-2">
                <Button className="flex-1 bg-purple-600 hover:bg-purple-700 gap-2"
                  onClick={() => handleConfirm('sipro', false)}>
                  <CheckCircle2 className="h-4 w-4" />
                  Iniciar Entrevista Guiada
                </Button>
                <Button variant="outline" size="sm"
                  onClick={() => setStep('checklist')}
                  className="gap-1.5 text-xs">
                  <Brain className="h-3.5 w-3.5" /> Ver análise completa mesmo assim
                </Button>
              </div>

              <p className="text-center text-xs text-muted-foreground mt-3">
                A modalidade será travada como "Entrevista guiada" no formulário da campanha.
              </p>
            </motion.div>
          )}

          {step === 'result' && scores.length > 0 && (
            <motion.div key="result" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -12 }}>
              <DialogHeader className="mb-5">
                <div className="flex items-center gap-2">
                  <Award className="h-5 w-5 text-purple-600" />
                  <DialogTitle>Recomendação do Assistente</DialogTitle>
                </div>
                <DialogDescription>
                  Baseada na análise organizacional realizada pelo Assistente YourEyes
                </DialogDescription>
              </DialogHeader>

              {/* Banner faixa 5-10 → ambas modalidades viáveis */}
              {sysData && sysData.totalColaboradores >= 5 && sysData.totalColaboradores <= 10 && (
                <div className="mb-4 p-3 rounded-lg bg-amber-50 border border-amber-200 text-xs text-amber-800">
                  <p className="font-semibold mb-1 flex items-center gap-1.5">
                    <AlertTriangle className="h-3.5 w-3.5" />
                    Empresa com {sysData.totalColaboradores} colaboradores — faixa de transição (5 a 10).
                  </p>
                  <p>
                    Tanto o <strong>questionário</strong> quanto a <strong>entrevista guiada por IA</strong> são viáveis.
                    A entrevista preserva melhor o anonimato em grupos pequenos; o questionário traz indicadores quantitativos comparáveis.
                    A modalidade poderá ser escolhida no formulário da campanha.
                  </p>
                </div>
              )}


              {/* Principal */}
              <div className={cn("rounded-xl border-2 p-5 mb-4", scores[0].bgCor)}>
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <span className="text-2xl">{scores[0].icone}</span>
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className={cn("font-bold text-lg", scores[0].cor)}>{scores[0].nome}</h3>
                        <Badge className="bg-purple-600 text-xs">Mais indicado</Badge>
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5">{scores[0].descricao}</p>
                    </div>
                  </div>
                  <div className={cn("text-2xl font-bold", scores[0].cor)}>{scores[0].score}%</div>
                </div>

                <div className="mb-3">
                  <p className="text-xs font-semibold text-muted-foreground mb-1.5">Motivos da recomendação:</p>
                  <ul className="space-y-1">
                    {scores[0].motivos.map((m, i) => (
                      <li key={i} className="flex items-center gap-2 text-xs">
                        <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500 shrink-0" />
                        {m}
                      </li>
                    ))}
                  </ul>
                </div>

                {/* Normas */}
                <div className="flex flex-wrap gap-1.5 mt-3 pt-3 border-t border-black/10">
                  {['NR-01', 'NR-17', 'ISO 45003'].map(n => (
                    <Badge key={n} variant="outline" className="text-xs">{n}</Badge>
                  ))}
                  <Badge variant="outline" className="text-xs text-emerald-600 border-emerald-300">
                    <Shield className="h-3 w-3 mr-1" />Recomendação baseada em evidências
                  </Badge>
                </div>
              </div>

              {/* Alternativas */}
              {scores.slice(1).map(s => (
                <div key={s.id} className={cn("rounded-lg border p-3.5 mb-2 opacity-80 hover:opacity-100 transition-opacity", s.bgCor)}>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span>{s.icone}</span>
                      <div>
                        <p className={cn("font-semibold text-sm", s.cor)}>{s.nome}</p>
                        {s.motivos[0] && <p className="text-xs text-muted-foreground">{s.motivos[0]}</p>}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className={cn("text-sm font-bold", s.cor)}>{s.score}%</span>
                      <Button variant="outline" size="sm" className="text-xs h-7"
                        onClick={() => handleConfirm(s.id)}>
                        Usar este
                      </Button>
                    </div>
                  </div>
                </div>
              ))}

              {/* Actions */}
              <div className="flex flex-col sm:flex-row gap-2 mt-4">
                <Button className="flex-1 bg-purple-600 hover:bg-purple-700 gap-2"
                  onClick={() => handleConfirm(scores[0].id)}>
                  <CheckCircle2 className="h-4 w-4" />
                  Usar {scores[0].nome}
                </Button>
                <Button variant="outline" size="sm"
                  onClick={() => handleConfirm('sipro', true)}
                  className="gap-1.5 text-xs">
                  <Brain className="h-3.5 w-3.5" /> Escolher outro
                </Button>
              </div>

              <p className="text-center text-xs text-muted-foreground mt-3">
                A decisão e o motivo da recomendação serão registrados para fins de auditoria.
              </p>
            </motion.div>
          )}
        </AnimatePresence>
      </DialogContent>
    </Dialog>
  );
}

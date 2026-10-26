import { useState, useMemo, useEffect } from "react";
import { motion } from "framer-motion";
import { type CampanhaPsicossocial, type RadarDimensao, getMinimoRespostas, isEntrevistaInstrumento } from "@/types/psicossocial";
import {
  Flame, Battery, Sparkles, CheckCircle2, AlertTriangle,
  Brain, Users, Clock, Heart, Target, RotateCcw, HelpCircle,
  Meh, TrendingDown, MessageSquareWarning, Zap, ExternalLink,
  ChevronDown, ChevronUp, Plus, Info, Minus, RefreshCw, Filter
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { Separator } from "@/components/ui/separator";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { toast } from "sonner";
import { useNavigate } from "react-router-dom";
import { FatorActionForm } from "@/components/ergonomia/radar/FatorActionForm";
import type { AcaoPrioridade } from "@/types/ergonomia";

// ────────── tipos ──────────
type NivelRisco = 'baixo' | 'moderado' | 'alto' | 'critico';

interface SugestaoAcao {
  titulo: string;
  porque: string;
}

interface FatorConfig {
  key: string;
  label: string;
  valor: number;
  descricao: string;
  detailedAnalysis: string;
  dataSource: readonly string[];
  icon: React.ElementType;
  sugestoes: readonly SugestaoAcao[];
}

// ────────── configuração de nível ──────────
const NIVEL_CONFIG: Record<NivelRisco, {
  color: string; bgColor: string; borderColor: string;
  label: string; icon: string; badgeClass: string
}> = {
  baixo:    { color: 'text-success',    bgColor: 'bg-success/10',    borderColor: 'border-success/40',    label: 'Baixo Risco', icon: '✓',  badgeClass: 'bg-success/10 text-success border-success/30' },
  moderado: { color: 'text-warning',    bgColor: 'bg-warning/10',    borderColor: 'border-warning/40',    label: 'Atenção',     icon: '⚠',  badgeClass: 'bg-warning/10 text-warning border-warning/30' },
  alto:     { color: 'text-orange-500', bgColor: 'bg-orange-500/10', borderColor: 'border-orange-500/40', label: 'Alto Risco',  icon: '🔥', badgeClass: 'bg-orange-500/10 text-orange-500 border-orange-500/30' },
  critico:  { color: 'text-destructive',bgColor: 'bg-destructive/10',borderColor: 'border-destructive/40',label: 'Crítico',     icon: '🚨', badgeClass: 'bg-destructive/10 text-destructive border-destructive/30' },
};

function calcularNivel(score: number): NivelRisco {
  if (score < 25) return 'baixo';
  if (score < 50) return 'moderado';
  if (score < 75) return 'alto';
  return 'critico';
}

// ────────── mapeamento dimensões SIPRO → fatores ──────────
// Radar `subject` usa as 2 primeiras palavras do nome da dimensão.
// Para SIPRO: scores altos = mais risco. Para protetores invertidos, invertemos (100 - score).

// Cada chave aceita múltiplos aliases de subject (sem acentos, lowercase) para
// suportar diferentes versões de instrumentos (SIPRO antigo, COPSOQ, HSE etc.).
// `inverted: true` significa dimensão protetora (score alto = bom) e precisa
// ser invertida (100 - score) para virar score de risco.
interface DimensionMatcher {
  aliases: string[];
  inverted: boolean;
}

// IMPORTANTE: No SIPRO, TODAS as dimensões do radar seguem convenção protetiva
// (score alto = saudável / baixo risco). Para gerar score de RISCO de burnout/boreout
// invertemos sempre (100 - score). Ex.: IPS=100 → risco=0; IPS=20 → risco=80.
const BURNOUT_DIMENSION_MAP: Record<string, DimensionMatcher> = {
  sobrecargaCognitiva: { aliases: ['demandas cognitivas', 'demanda cognitiva', 'carga cognitiva'], inverted: true },
  ritmoTrabalho:       { aliases: ['demandas quantitativas', 'demanda quantitativa', 'ritmo de trabalho', 'ritmo'], inverted: true },
  faltaPausas:         { aliases: ['recuperacao e equilibrio', 'recuperacao', 'equilibrio trabalho-vida', 'equilibrio trabalho vida', 'pausas'], inverted: true },
  humorNegativo:       { aliases: ['demandas emocionais', 'demanda emocional', 'burnout / esgotamento', 'burnout', 'esgotamento'], inverted: true },
  denuncias:           { aliases: ['conflito de papeis', 'relacionamentos e suporte', 'suporte dos colegas', 'suporte da lideranca'], inverted: true },
  exigenciasEmocionais:{ aliases: ['demandas emocionais', 'demanda emocional', 'exigencias emocionais'], inverted: true },
};

const BOREOUT_DIMENSION_MAP: Record<string, DimensionMatcher> = {
  baixoDesafio:   { aliases: ['autonomia e controle', 'influencia e controle', 'previsibilidade'], inverted: true },
  repetitividade: { aliases: ['clareza de papeis', 'conflito de papeis'], inverted: true },
  faltaSentido:   { aliases: ['sentido do trabalho', 'sentido'], inverted: true },
  apatia:         { aliases: ['reconhecimento e justica', 'reconhecimento e recompensas', 'reconhecimento'], inverted: true },
  desconexao:     { aliases: ['relacionamentos e suporte', 'suporte dos colegas', 'suporte da lideranca'], inverted: true },
};

function normalize(s: string): string {
  return (s || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[\u2010-\u2015\u2212]/g, '-') // en-dash, em-dash, minus → hífen comum
    .replace(/\s+/g, ' ')
    .toLowerCase()
    .trim();
}

function resolveRadarScore(
  radarData: RadarDimensao[] | undefined,
  matcher: DimensionMatcher | undefined,
  fallback: number
): number {
  if (!matcher || !radarData || radarData.length === 0) return fallback;
  const normalizedSubjects = radarData.map(d => ({ raw: d, norm: normalize(d.subject) }));

  for (const alias of matcher.aliases) {
    const aliasNorm = normalize(alias);
    // Tenta match exato, depois "começa com", depois "contém"
    const found =
      normalizedSubjects.find(s => s.norm === aliasNorm) ||
      normalizedSubjects.find(s => s.norm.startsWith(aliasNorm)) ||
      normalizedSubjects.find(s => s.norm.includes(aliasNorm));
    if (found) {
      const raw = found.raw.value;
      return matcher.inverted ? Math.max(0, 100 - raw) : raw;
    }
  }
  return fallback;
}

// ────────── templates de fatores (sem valor fixo) ──────────
interface FatorTemplate {
  key: string;
  label: string;
  fallback: number;
  descricao: string;
  detailedAnalysis: string;
  dataSource: readonly string[];
  icon: React.ElementType;
  sugestoes: readonly SugestaoAcao[];
}

const BURNOUT_TEMPLATES: FatorTemplate[] = [
  {
    key: 'sobrecargaCognitiva', label: 'Sobrecarga Cognitiva', fallback: 62, icon: Brain,
    descricao: 'Excesso de tarefas e demandas mentais intensas',
    detailedAnalysis: 'Vem da dimensão de demandas cognitivas do questionário SIPRO: quanto mais os trabalhadores relatam exigência de atenção, memória e concentração, maior o risco calculado. Reflete a percepção respondida na campanha, não uma medição automática da carga mental.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Demandas Cognitivas'],
    sugestoes: [
      { titulo: 'Implementar rodízio de tarefas complexas', porque: 'Reduzir a sobrecarga mental causada pela exposição prolongada a tarefas de alta complexidade cognitiva' },
      { titulo: 'Criar pausas programadas para recuperação mental', porque: 'Permitir recuperação cognitiva adequada e prevenir fadiga mental acumulada' },
      { titulo: 'Simplificar processos e procedimentos', porque: 'Diminuir a carga cognitiva exigida para execução das atividades rotineiras' },
      { titulo: 'Implementar ferramentas de apoio cognitivo', porque: 'Oferecer suporte tecnológico que reduza a demanda de memória e processamento mental' },
    ],
  },
  {
    key: 'ritmoTrabalho', label: 'Ritmo de Trabalho', fallback: 71, icon: Clock,
    descricao: 'Pressão por velocidade e volume de produção',
    detailedAnalysis: 'Vem da dimensão de demandas quantitativas do questionário SIPRO: parte da percepção dos trabalhadores sobre volume, prazos e pressão por velocidade. É a resposta ao questionário, não uma leitura automática do ponto ou da jornada.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Demandas Quantitativas'],
    sugestoes: [
      { titulo: 'Revisar metas e prazos irrealistas', porque: 'Adequar as expectativas de entrega à capacidade real da equipe, evitando sobrecarga' },
      { titulo: 'Balancear carga de trabalho entre equipes', porque: 'Distribuir demandas de forma equitativa para evitar sobrecarga em indivíduos específicos' },
      { titulo: 'Implementar gestão de prioridades', porque: 'Permitir foco nas atividades mais importantes e reduzir sensação de urgência constante' },
      { titulo: 'Avaliar necessidade de contratações', porque: 'Dimensionar adequadamente a equipe para atender às demandas sem sobrecarga' },
    ],
  },
  {
    key: 'faltaPausas', label: 'Falta de Pausas', fallback: 55, icon: AlertTriangle,
    descricao: 'Ausência de intervalos adequados para recuperação',
    detailedAnalysis: 'Vem da dimensão de recuperação e equilíbrio do questionário SIPRO: baseia-se em como os trabalhadores percebem suas pausas e o equilíbrio entre trabalho e descanso. Não verifica automaticamente políticas de pausa nem registros de ponto.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Recuperação e Equilíbrio'],
    sugestoes: [
      { titulo: 'Implementar pausas ativas obrigatórias', porque: 'Garantir momentos de recuperação física e mental durante a jornada de trabalho' },
      { titulo: 'Criar espaços de descanso adequados', porque: 'Oferecer ambientes propícios para recuperação e descompressão dos colaboradores' },
      { titulo: 'Estabelecer política formal de pausas', porque: 'Institucionalizar a cultura de pausas e garantir que todos tenham direito ao descanso' },
      { titulo: 'Monitorar intervalos por sistema', porque: 'Acompanhar o cumprimento das pausas e identificar colaboradores em risco de fadiga' },
    ],
  },
  {
    key: 'humorNegativo', label: 'Humor Negativo', fallback: 44, icon: TrendingDown,
    descricao: 'Irritabilidade, negatividade e desgaste emocional',
    detailedAnalysis: 'Vem da dimensão de demandas emocionais do questionário SIPRO, respondida pelos trabalhadores na campanha. Reflete a percepção relatada sobre desgaste e tensão emocional; não acompanha registros de humor diário.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Demandas Emocionais'],
    sugestoes: [
      { titulo: 'Realizar escuta ativa com gestores', porque: 'Identificar causas específicas do humor negativo através de conversas individuais' },
      { titulo: 'Oferecer apoio psicológico', porque: 'Disponibilizar suporte profissional para colaboradores em sofrimento emocional' },
      { titulo: 'Investigar causas de insatisfação', porque: 'Compreender os fatores organizacionais que contribuem para o humor negativo' },
      { titulo: 'Promover ações de bem-estar', porque: 'Criar iniciativas que melhorem o clima organizacional e a satisfação no trabalho' },
    ],
  },
  {
    key: 'denuncias', label: 'Denúncias/Ocorrências', fallback: 30, icon: MessageSquareWarning,
    descricao: 'Relatos de conflitos, pressão indevida ou ambiente hostil',
    detailedAnalysis: 'Vem das dimensões de conflito de papéis e de relacionamentos e suporte do questionário SIPRO: mede a percepção de conflito e de apoio relatada pelos trabalhadores. Não lê as manifestações da Ouvidoria nem as ocorrências registradas.',
    dataSource: ['Questionário SIPRO', 'Dimensões: Conflito de Papéis e Suporte'],
    sugestoes: [
      { titulo: 'Investigar denúncias pendentes', porque: 'Resolver situações reportadas que podem estar causando sofrimento aos colaboradores' },
      { titulo: 'Implementar ações corretivas', porque: 'Tratar as causas raiz das denúncias e prevenir novas ocorrências similares' },
      { titulo: 'Reforçar canais de comunicação', porque: 'Garantir que colaboradores tenham meios seguros para reportar problemas' },
      { titulo: 'Capacitar lideranças', porque: 'Preparar gestores para lidar adequadamente com conflitos e situações sensíveis' },
    ],
  },
  {
    key: 'exigenciasEmocionais', label: 'Exigências Emocionais', fallback: 68, icon: Heart,
    descricao: 'Necessidade de suprimir emoções no exercício das funções',
    detailedAnalysis: 'Vem da dimensão de demandas emocionais do questionário SIPRO: parte de quanto os trabalhadores relatam precisar conter ou administrar emoções no trabalho. Baseia-se na percepção respondida, não no cruzamento automático de outros módulos.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Demandas Emocionais'],
    sugestoes: [
      { titulo: 'Oferecer treinamento de inteligência emocional', porque: 'Desenvolver habilidades para lidar com demandas emocionais do trabalho' },
      { titulo: 'Criar grupos de apoio entre pares', porque: 'Estabelecer rede de suporte entre colegas para compartilhar experiências e estratégias' },
      { titulo: 'Revisar atribuições de funções de alto contato', porque: 'Adequar a exposição emocional às características e limites de cada colaborador' },
      { titulo: 'Implementar supervisão técnica', porque: 'Oferecer acompanhamento profissional para funções com alta demanda emocional' },
    ],
  },
];

const BOREOUT_TEMPLATES: FatorTemplate[] = [
  {
    key: 'baixoDesafio', label: 'Baixo Desafio', fallback: 75, icon: Target,
    descricao: 'Tarefas excessivamente simples e sem estímulo intelectual',
    detailedAnalysis: 'Vem da dimensão de autonomia e controle do questionário SIPRO: quanto menos autonomia e influência os trabalhadores percebem, maior o risco de subcarga estimado. Reflete a percepção respondida, não um mapeamento automático de competências.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Autonomia e Controle'],
    sugestoes: [
      { titulo: 'Mapear competências e realocá-las', porque: 'Aproveitar melhor o potencial dos colaboradores e reduzir a subutilização de habilidades' },
      { titulo: 'Criar projetos especiais desafiadores', porque: 'Estimular o engajamento através de desafios que correspondam às capacidades do colaborador' },
      { titulo: 'Implementar job enrichment', porque: 'Enriquecer as funções com responsabilidades que aumentem o senso de realização' },
      { titulo: 'Oferecer oportunidades de desenvolvimento', porque: 'Proporcionar crescimento profissional e novos desafios de aprendizagem' },
    ],
  },
  {
    key: 'repetitividade', label: 'Repetitividade', fallback: 80, icon: RotateCcw,
    descricao: 'Ciclos repetitivos e monotonia nas atividades diárias',
    detailedAnalysis: 'Vem da dimensão de clareza de papéis do questionário SIPRO, que capta a percepção sobre a natureza e a variação das tarefas. É a resposta ao questionário, não uma análise automática das atividades realizadas.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Clareza de Papéis'],
    sugestoes: [
      { titulo: 'Implementar rodízio de atividades', porque: 'Quebrar a monotonia através da alternância entre diferentes tipos de tarefas' },
      { titulo: 'Automatizar tarefas repetitivas', porque: 'Liberar colaboradores para atividades mais estimulantes e de maior valor agregado' },
      { titulo: 'Criar variação nas rotinas', porque: 'Introduzir elementos de novidade que mantenham o interesse e a atenção' },
      { titulo: 'Enriquecer postos de trabalho', porque: 'Adicionar responsabilidades e atividades diversificadas às funções existentes' },
    ],
  },
  {
    key: 'faltaSentido', label: 'Falta de Sentido', fallback: 60, icon: Minus,
    descricao: 'Percepção de que o trabalho não tem propósito ou impacto',
    detailedAnalysis: 'Vem da dimensão de sentido do trabalho do questionário SIPRO: parte de quanto os trabalhadores enxergam propósito e importância no que fazem. Baseia-se na percepção respondida na campanha.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Sentido do Trabalho'],
    sugestoes: [
      { titulo: 'Comunicar propósito e impacto do trabalho', porque: 'Conectar as atividades diárias aos resultados e benefícios gerados pela empresa' },
      { titulo: 'Conectar tarefas aos objetivos maiores', porque: 'Demonstrar como cada função contribui para o sucesso organizacional' },
      { titulo: 'Promover reconhecimento', porque: 'Valorizar contribuições individuais e reforçar a importância de cada colaborador' },
      { titulo: 'Envolver em decisões', porque: 'Aumentar o senso de pertencimento e responsabilidade sobre os resultados' },
    ],
  },
  {
    key: 'apatia', label: 'Apatia Emocional', fallback: 55, icon: Meh,
    descricao: 'Perda de entusiasmo, envolvimento e motivação com o trabalho',
    detailedAnalysis: 'Vem da dimensão de reconhecimento e recompensas do questionário SIPRO: percepção de valorização e reconhecimento relatada pelos trabalhadores. Reflete a resposta ao questionário, não o acompanhamento de registros de humor.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Reconhecimento e Recompensas'],
    sugestoes: [
      { titulo: 'Realizar conversas individuais', porque: 'Identificar causas pessoais ou profissionais da apatia através de escuta ativa' },
      { titulo: 'Investigar causas da apatia', porque: 'Compreender fatores organizacionais que levam ao desinteresse e desengajamento' },
      { titulo: 'Criar momentos de celebração', porque: 'Estimular emoções positivas e reconexão com aspectos prazerosos do trabalho' },
      { titulo: 'Promover conexões interpessoais', porque: 'Fortalecer vínculos sociais que aumentam o engajamento e a satisfação' },
    ],
  },
  {
    key: 'desconexao', label: 'Desconexão com Equipe', fallback: 48, icon: Users,
    descricao: 'Isolamento e falta de pertencimento ao grupo',
    detailedAnalysis: 'Vem da dimensão de relacionamentos e suporte do questionário SIPRO: percepção de apoio de colegas e liderança e de pertencimento ao grupo. Baseia-se na resposta ao questionário, não em dados de participação em atividades.',
    dataSource: ['Questionário SIPRO', 'Dimensão: Relacionamentos e Suporte'],
    sugestoes: [
      { titulo: 'Promover team building', porque: 'Fortalecer vínculos entre membros da equipe através de atividades conjuntas' },
      { titulo: 'Criar rituais de integração', porque: 'Estabelecer momentos regulares de conexão e fortalecimento do grupo' },
      { titulo: 'Facilitar colaboração entre áreas', porque: 'Ampliar a rede de relacionamentos e reduzir o isolamento departamental' },
      { titulo: 'Estabelecer mentoria entre pares', porque: 'Criar conexões significativas através do compartilhamento de conhecimento' },
    ],
  },
];

function buildFatores(
  templates: FatorTemplate[],
  dimensionMap: Record<string, DimensionMatcher>,
  radarData: RadarDimensao[] | undefined,
): FatorConfig[] {
  return templates.map(t => ({
    ...t,
    valor: resolveRadarScore(radarData, dimensionMap[t.key], t.fallback),
  }));
}

// ────────── cartão de fator individual ──────────
interface FatorCardProps {
  fator: FatorConfig;
  radarType: 'burnout' | 'boreout';
  existingActions: { titulo: string; status: string }[];
  onCreateAction: (acao: {
    titulo: string; descricao: string;
    tipo: 'corretiva' | 'preventiva' | 'melhoria';
    prioridade: AcaoPrioridade;
    fator_radar: string; radar_type: string;
    responsavel_nome: string; prazo: string; onde: string;
    porque: string; como: string; custo_estimado: string;
  }) => Promise<void>;
  isCreatingAction?: boolean;
}

function FatorCard({ fator, radarType, existingActions, onCreateAction, isCreatingAction }: FatorCardProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [showActionForm, setShowActionForm] = useState(false);
  const { valor } = fator;
  const Icon = fator.icon;

  const colorClass = valor >= 70
    ? { text: 'text-destructive', progress: '[&>div]:bg-destructive' }
    : valor >= 45
    ? { text: 'text-warning', progress: '[&>div]:bg-warning' }
    : { text: 'text-success', progress: '[&>div]:bg-success' };

  const handleSubmit = async (acao: Parameters<typeof onCreateAction>[0]) => {
    await onCreateAction(acao);
    setShowActionForm(false);
  };

  return (
    <div className="border rounded-lg bg-card overflow-hidden">
      <Collapsible open={isExpanded} onOpenChange={setIsExpanded}>
        {/* Header */}
        <div className="p-3">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2 flex-1">
              <Icon className="h-4 w-4 text-muted-foreground shrink-0" />
              <span className="font-medium text-sm">{fator.label}</span>
            </div>
            <div className="flex items-center gap-2">
              <span className={cn("font-bold text-sm", colorClass.text)}>{valor}%</span>
              <CollapsibleTrigger asChild>
                <Button variant="ghost" size="sm" className="h-7 w-7 p-0">
                  {isExpanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                </Button>
              </CollapsibleTrigger>
            </div>
          </div>
          <p className="text-xs text-muted-foreground mb-2">{fator.descricao}</p>
          <Progress value={valor} className={cn("h-1.5", colorClass.progress)} />
        </div>

        {/* Expanded */}
        <CollapsibleContent>
          <div className="px-3 pb-3 space-y-3 border-t pt-3 bg-muted/20">
            {/* O que analisamos */}
            <div className="space-y-1.5">
              <div className="flex items-center gap-1.5 text-xs font-medium">
                <Info className="h-3.5 w-3.5 text-primary" />
                O que analisamos
              </div>
              <p className="text-xs text-muted-foreground">{fator.detailedAnalysis}</p>
              <div className="flex flex-wrap gap-1.5 mt-1">
                {fator.dataSource.map((src, i) => (
                  <Badge key={i} variant="secondary" className="text-xs py-0">{src}</Badge>
                ))}
              </div>
            </div>

            {/* Ações existentes */}
            {existingActions.length > 0 && (
              <div className="space-y-1.5">
                <div className="flex items-center gap-1.5 text-xs font-medium">
                  <CheckCircle2 className="h-3.5 w-3.5 text-success" />
                  Ações vinculadas ({existingActions.length})
                </div>
                {existingActions.map((a, i) => (
                  <div key={i} className="flex items-center gap-2 text-xs p-2 bg-card rounded border">
                    <span className="flex-1">{a.titulo}</span>
                    <Badge variant="outline" className="text-xs py-0">{a.status}</Badge>
                  </div>
                ))}
              </div>
            )}

            {/* Form ou botão */}
            {showActionForm ? (
              <FatorActionForm
                fatorKey={fator.key}
                fatorLabel={fator.label}
                radarType={radarType}
                sugestoes={fator.sugestoes}
                onSubmit={handleSubmit}
                onCancel={() => setShowActionForm(false)}
                isLoading={isCreatingAction}
              />
            ) : (
              <Button
                variant="outline"
                size="sm"
                className="w-full text-xs h-8 gap-1.5"
                onClick={() => setShowActionForm(true)}
              >
                <Plus className="h-3.5 w-3.5" />
                Cadastrar Ação para este Fator
              </Button>
            )}
          </div>
        </CollapsibleContent>
      </Collapsible>
    </div>
  );
}

// ────────── painel de radar ──────────
interface RadarPanelProps {
  tipo: 'burnout' | 'boreout';
  score: number;
  nivel: NivelRisco;
  fatores: FatorConfig[];
  existingActionsByFator: Record<string, { titulo: string; status: string }[]>;
  onCreateAction: (
    fatorKey: string,
    radarType: 'burnout' | 'boreout',
    acao: {
      titulo: string; descricao: string;
      tipo: 'corretiva' | 'preventiva' | 'melhoria';
      prioridade: AcaoPrioridade;
      fator_radar: string; radar_type: string;
      responsavel_nome: string; prazo: string; onde: string;
      porque: string; como: string; custo_estimado: string;
    }
  ) => Promise<void>;
  onGerarAcaoGlobal: (tipo: 'burnout' | 'boreout', fatores: FatorConfig[], score: number, nivel: NivelRisco) => void;
  gerandoGlobal: boolean;
  creatingActionFor: string | null;
}

function RadarPanel({
  tipo, score, nivel, fatores,
  existingActionsByFator, onCreateAction, onGerarAcaoGlobal, gerandoGlobal, creatingActionFor,
}: RadarPanelProps) {
  const config = NIVEL_CONFIG[nivel];
  const isBurnout = tipo === 'burnout';
  const TipoIcon = isBurnout ? Flame : Battery;
  const titulo = isBurnout ? 'Radar de Burnout' : 'Radar de Boreout';
  const subtitulo = isBurnout ? 'Índice de Risco de Esgotamento Profissional' : 'Índice de Subcarga / Desengajamento';

  const dica: Record<NivelRisco, string> = isBurnout ? {
    critico:  'Ação imediata necessária. Revise carga, pausas e suporte emocional.',
    alto:     'Fatores de risco elevados. Intervenção recomendada a curto prazo.',
    moderado: 'Monitorar indicadores e promover pausas regulares e autonomia.',
    baixo:    'Ambiente saudável. Manter boas práticas preventivas.',
  } : {
    critico:  'Colaboradores em esgotamento por subcarga. Redesenhe funções urgentemente.',
    alto:     'Sinais claros de desengajamento. Considere rodízio e novos desafios.',
    moderado: 'Atenção à monotonia. Promova projetos e participação em decisões.',
    baixo:    'Equipe engajada. Continue promovendo desenvolvimento.',
  };

  const fatoresCriticos = fatores.filter(f => f.valor >= 70);
  const fatoresAtencao = fatores.filter(f => f.valor >= 45 && f.valor < 70);

  return (
    <Card className={cn("border-2 flex flex-col", config.borderColor)}>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="flex items-center gap-2 text-base">
            <TipoIcon className={cn("h-5 w-5", config.color)} />
            {titulo}
          </CardTitle>
          <Badge className={cn("text-xs border", config.badgeClass)}>
            {config.icon} {config.label}
          </Badge>
        </div>
        <CardDescription>{subtitulo}</CardDescription>
      </CardHeader>

      <CardContent className="space-y-4 flex-1">
        {/* Score */}
        <div className="flex items-center gap-4">
          <motion.div
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            transition={{ type: "spring", stiffness: 200, delay: 0.1 }}
            className={cn(
              "flex items-center justify-center w-20 h-20 rounded-full border-4 shrink-0",
              config.borderColor, config.bgColor
            )}
          >
            <span className={cn("text-2xl font-bold", config.color)}>{score}%</span>
          </motion.div>

          <div className="flex-1 space-y-1.5">
            {fatoresCriticos.length > 0 && (
              <div className="flex items-center gap-1.5 text-xs text-destructive">
                <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
                <span><strong>{fatoresCriticos.length}</strong> fator(es) crítico(s)</span>
              </div>
            )}
            {fatoresAtencao.length > 0 && (
              <div className="flex items-center gap-1.5 text-xs text-warning">
                <Zap className="h-3.5 w-3.5 shrink-0" />
                <span><strong>{fatoresAtencao.length}</strong> fator(es) em atenção</span>
              </div>
            )}
            {nivel === 'baixo' && (
              <div className="flex items-center gap-1.5 text-xs text-success">
                <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
                <span>Todos os indicadores saudáveis</span>
              </div>
            )}
          </div>
        </div>

        <Separator />

        {/* Dica */}
        <div className={cn("p-3 rounded-lg text-sm flex items-start gap-2", config.bgColor)}>
          <TipoIcon className={cn("h-4 w-4 shrink-0 mt-0.5", config.color)} />
          <p className={cn("font-medium leading-relaxed text-xs", config.color)}>{dica[nivel]}</p>
        </div>

        <Separator />

        {/* Fatores com ação por fator */}
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
              Fatores Avaliados ({fatores.length} critérios)
            </p>
            <p className="text-xs text-muted-foreground">Expanda para criar ações por fator</p>
          </div>
          {fatores.map(fator => (
            <FatorCard
              key={fator.key}
              fator={fator}
              radarType={tipo}
              existingActions={existingActionsByFator[fator.key] || []}
              onCreateAction={(acao) => onCreateAction(fator.key, tipo, acao)}
              isCreatingAction={creatingActionFor === fator.key}
            />
          ))}
        </div>

        <Separator />

        {/* Botão ação global IA */}
        <Button
          className="w-full gap-2"
          variant={nivel === 'baixo' ? 'outline' : 'default'}
          disabled={gerandoGlobal}
          onClick={() => onGerarAcaoGlobal(tipo, fatores, score, nivel)}
        >
          {gerandoGlobal ? (
            <>
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
              Gerando plano com IA…
            </>
          ) : (
            <>
              <Sparkles className="h-4 w-4" />
              Gerar Ação Global com IA
            </>
          )}
        </Button>
      </CardContent>
    </Card>
  );
}

// ────────── componente principal ──────────


interface RadaresPsicossocialSectionProps {
  campanhas?: CampanhaPsicossocial[];
}

export function RadaresPsicossocialSection({ campanhas = [] }: RadaresPsicossocialSectionProps) {
  const { tenantId, user, profile } = useAuthContext();
  const navigate = useNavigate();
  const [gerandoBurnout, setGerandoBurnout] = useState(false);
  const [gerandoBoreout, setGerandoBoreout] = useState(false);
  const [acoesCriadas, setAcoesCriadas] = useState<string[]>([]);
  const [creatingActionFor, setCreatingActionFor] = useState<string | null>(null);
  
  // Se houver apenas uma campanha filtrada, usamos ela como filtro automático
  const [filtroCampanha, setFiltroCampanha] = useState<string>("");

  const [existingActionsByFator, setExistingActionsByFator] = useState<
    Record<string, { titulo: string; status: string }[]>
  >({});

  // Filtrar campanhas válidas (com dados de radar e respostas suficientes)
  const campanhasValidas = useMemo(() => {
    return campanhas.filter(
      c => c.radar_data && Array.isArray(c.radar_data) && c.radar_data.length > 0
        && (c.total_respostas || 0) >= getMinimoRespostas(c)
    ).sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  }, [campanhas]);

  const campanhaMaisRecenteId = useMemo(
    () => campanhasValidas[0]?.id ?? "",
    [campanhasValidas]
  );

  // Sincronizar filtro quando as campanhas filtradas mudarem no pai
  useEffect(() => {
    if (!filtroCampanha || !campanhasValidas.some(c => c.id === filtroCampanha)) {
      setFiltroCampanha(campanhaMaisRecenteId);
    }
  }, [campanhasValidas, campanhaMaisRecenteId, filtroCampanha]);

  // Agregar radar_data das campanhas com dados suficientes
  const radarAgregado = useMemo<RadarDimensao[] | undefined>(() => {
    if (campanhasValidas.length === 0) return undefined;
    const selecionada = campanhasValidas.find(c => c.id === filtroCampanha) ?? campanhasValidas[0];
    return selecionada?.radar_data as RadarDimensao[] | undefined;
  }, [campanhasValidas, filtroCampanha]);

  const temDadosReais = !!radarAgregado;

  const FATORES_BURNOUT = useMemo(
    () => buildFatores(BURNOUT_TEMPLATES, BURNOUT_DIMENSION_MAP, radarAgregado),
    [radarAgregado]
  );
  const FATORES_BOREOUT = useMemo(
    () => buildFatores(BOREOUT_TEMPLATES, BOREOUT_DIMENSION_MAP, radarAgregado),
    [radarAgregado]
  );

  const SCORE_BURNOUT = Math.round(FATORES_BURNOUT.reduce((s, f) => s + f.valor, 0) / FATORES_BURNOUT.length);
  const SCORE_BOREOUT = Math.round(FATORES_BOREOUT.reduce((s, f) => s + f.valor, 0) / FATORES_BOREOUT.length);

  const nivelBurnout = calcularNivel(SCORE_BURNOUT);
  const nivelBoreout = calcularNivel(SCORE_BOREOUT);

  // Criar ação por fator individual
  const handleCreateAction = async (
    fatorKey: string,
    radarType: 'burnout' | 'boreout',
    acao: {
      titulo: string; descricao: string;
      tipo: 'corretiva' | 'preventiva' | 'melhoria';
      prioridade: AcaoPrioridade;
      fator_radar: string; radar_type: string;
      responsavel_nome: string; prazo: string; onde: string;
      porque: string; como: string; custo_estimado: string;
    }
  ) => {
    if (!tenantId) return;
    setCreatingActionFor(fatorKey);
    try {
      const { data, error } = await supabase.from('plano_acoes').insert({
        tenant_id: tenantId,
        titulo: acao.titulo,
        descricao: acao.descricao || undefined,
        porque: acao.porque || undefined,
        onde: acao.onde || undefined,
        como: acao.como || undefined,
        responsavel_nome: acao.responsavel_nome || undefined,
        prazo: acao.prazo || undefined,
        custo_estimado: acao.custo_estimado ? parseFloat(acao.custo_estimado) : undefined,
        tipo: acao.tipo,
        prioridade: (acao.prioridade === 'baixa' ? 'baixo' : acao.prioridade === 'media' ? 'medio' : acao.prioridade === 'urgente' ? 'urgente' : 'imediato') as any,
        origem_modulo: 'psicossocial' as const,
        origem_descricao: `Radar ${radarType === 'burnout' ? 'Burnout' : 'Boreout'} — Fator: ${fatorKey} — Psicossocial NR-01`,
        criado_por: user?.id,
        criado_por_nome: profile?.nome_completo || 'Sistema',
        exige_evidencia: false,
        codigo: '',
        progresso: 0,
        status: 'pendente' as const,
        tempo_gasto_minutos: 0,
      }).select('id').single();

      if (error) throw error;

      if (data?.id) {
        setAcoesCriadas(prev => [...prev, data.id]);
        setExistingActionsByFator(prev => ({
          ...prev,
          [fatorKey]: [...(prev[fatorKey] || []), { titulo: acao.titulo, status: 'Pendente' }],
        }));
      }

      toast.success(`Ação criada no Plano de Ação! 🎯`, {
        action: { label: 'Ver ações', onClick: () => navigate('/plano-acao') },
      });
    } catch (err: any) {
      console.error(err);
      toast.error(`Erro ao criar ação: ${err.message || 'Erro desconhecido'}`);
    } finally {
      setCreatingActionFor(null);
    }
  };

  // Gerar ação global via IA
  const handleGerarAcaoGlobal = async (
    tipo: 'burnout' | 'boreout',
    fatores: FatorConfig[],
    score: number,
    nivel: NivelRisco
  ) => {
    if (!tenantId) return;
    const setGerando = tipo === 'burnout' ? setGerandoBurnout : setGerandoBoreout;
    setGerando(true);
    try {
      const fatoresCriticos = fatores.filter(f => f.valor >= 70).map(f => f.label);
      const fatoresAtencao = fatores.filter(f => f.valor >= 45 && f.valor < 70).map(f => f.label);

      const { data, error } = await supabase.functions.invoke('ai-psicossocial-analise', {
        body: {
          contexto: {
            campanha: `Diagnóstico Psicossocial — ${tipo === 'burnout' ? 'Burnout' : 'Boreout'}`,
            instrumento: tipo,
            ips: 100 - score,
            classificacao: nivel === 'baixo' ? 'saudavel' : nivel === 'moderado' ? 'atencao' : nivel === 'alto' ? 'risco' : 'critico',
            dimensoes_criticas: fatoresCriticos,
            dimensoes_atencao: fatoresAtencao,
            tipo_radar: tipo,
            score_risco: score,
          },
          modo: 'plano_acao',
        },
      });

      if (error) throw error;
      const sugestao = data?.sugestao_acao;
      const prioridade = score >= 75 ? 'imediato' : score >= 50 ? 'urgente' : score >= 25 ? 'medio' : 'baixo';

      const { data: acaoCreated, error: errAcao } = await supabase.from('plano_acoes').insert({
        tenant_id: tenantId,
        titulo: sugestao?.titulo || `Ação ${tipo === 'burnout' ? 'Burnout' : 'Boreout'} Global — Score ${score}%`,
        descricao: sugestao?.descricao || `Ação gerada por IA a partir do diagnóstico de ${tipo}.`,
        porque: sugestao?.porque || `Score de ${tipo} em ${score}% — Fatores críticos: ${fatoresCriticos.join(', ') || 'nenhum'}.`,
        onde: sugestao?.onde || 'Organização / Setores identificados',
        como: sugestao?.como || `Implementar ações específicas para reduzir os fatores de risco de ${tipo}.`,
        tipo: tipo === 'burnout' ? 'preventiva' : 'melhoria',
        prioridade: prioridade as any,
        origem_modulo: 'psicossocial' as const,
        origem_descricao: `Radar ${tipo === 'burnout' ? 'Burnout' : 'Boreout'} (IA) — Psicossocial NR-01`,
        criado_por: user?.id,
        criado_por_nome: profile?.nome_completo || 'Sistema',
        exige_evidencia: false,
        codigo: '',
        progresso: 0,
        status: 'pendente' as const,
        tempo_gasto_minutos: 0,
      }).select('id').single();

      if (errAcao) throw errAcao;
      if (acaoCreated?.id) setAcoesCriadas(prev => [...prev, acaoCreated.id]);

      toast.success(`Ação global de ${tipo === 'burnout' ? 'Burnout' : 'Boreout'} criada com IA! 🎯`, {
        action: { label: 'Ver ações', onClick: () => navigate('/plano-acao') },
      });
    } catch (err: any) {
      console.error(err);
      toast.error(`Erro ao gerar ação: ${err.message || 'Erro desconhecido'}`);
    } finally {
      setGerando(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Cabeçalho */}
      <Card className="border-primary/20 bg-gradient-to-br from-primary/5 to-background">
        <CardContent className="pt-4">
          <div className="flex items-start gap-3">
            <div className="p-2 rounded-full bg-primary/10 shrink-0">
              <Brain className="h-5 w-5 text-primary" />
            </div>
            <div className="flex-1">
              <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <p className="font-semibold text-sm">Diagnóstico de Burnout & Boreout</p>
                    {temDadosReais ? (
                      <Badge variant="outline" className="text-[10px] bg-success/10 text-success border-success/30">
                        Dados Reais
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="text-[10px] bg-warning/10 text-warning border-warning/30">
                        Estimativa
                      </Badge>
                    )}
                  </div>
                </div>

                {campanhasValidas.length > 0 && (
                  <div className="flex items-center gap-2 bg-background/50 p-1.5 rounded-lg border border-primary/10 shadow-sm">
                    <Filter className="h-3.5 w-3.5 text-primary/60" />
                    <Select value={filtroCampanha} onValueChange={setFiltroCampanha}>
                      <SelectTrigger className="w-[200px] h-8 text-xs border-none bg-transparent focus:ring-0">
                        <SelectValue placeholder="Filtrar por Campanha" />
                      </SelectTrigger>
                      <SelectContent>
                        {campanhasValidas.map(c => {
                          const isEntrevista =isEntrevistaInstrumento((c as any).tipo_instrumento);
                          const sufixo = c.id === campanhaMaisRecenteId ? " (mais recente)" : "";
                          return (
                            <SelectItem key={c.id} value={c.id}>
                              {isEntrevista ? "🎙️ " : ""}{c.nome}{sufixo}{isEntrevista ? " — Entrevista" : ""}
                            </SelectItem>
                          );
                        })}
                      </SelectContent>
                    </Select>
                  </div>
                )}
              </div>
              <p className="text-sm text-muted-foreground mt-0.5">
                {temDadosReais
                  ? 'Radares calculados a partir das respostas do questionário psicossocial da campanha mais recente. Cada fator reflete a percepção dos trabalhadores; quando uma dimensão não é medida na campanha, mostramos um valor de referência (estimativa), não uma medição.'
                  : 'Valores de referência (estimativa). Crie e aplique uma campanha psicossocial para calcular os radares a partir das respostas reais.'
                }
                {' '}Expanda cada fator para ver de onde vem o indicador e criar ações específicas,
                ou use a IA para gerar um plano preventivo completo.
              </p>
            </div>
            {acoesCriadas.length > 0 && (
              <Button
                variant="outline"
                size="sm"
                className="gap-1.5 text-xs shrink-0"
                onClick={() => navigate('/plano-acao')}
              >
                <ExternalLink className="h-3.5 w-3.5" />
                {acoesCriadas.length} ação(ões) criada(s)
              </Button>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Legenda */}
      <div className="flex flex-wrap gap-3">
        {([
          { nivel: 'baixo' as NivelRisco, range: '0–24%', label: 'Saudável' },
          { nivel: 'moderado' as NivelRisco, range: '25–49%', label: 'Atenção' },
          { nivel: 'alto' as NivelRisco, range: '50–74%', label: 'Alto Risco' },
          { nivel: 'critico' as NivelRisco, range: '75–100%', label: 'Crítico' },
        ]).map(({ nivel, range, label }) => {
          const c = NIVEL_CONFIG[nivel];
          return (
            <div key={nivel} className={cn("flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium border", c.badgeClass)}>
              <span>{c.icon}</span>
              <span>{range} — {label}</span>
            </div>
          );
        })}
      </div>

      {/* Radares — exibidos apenas com dados reais (≥ 5 respostas) */}
      {temDadosReais ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <RadarPanel
            tipo="burnout"
            score={SCORE_BURNOUT}
            nivel={nivelBurnout}
            fatores={FATORES_BURNOUT}
            existingActionsByFator={existingActionsByFator}
            onCreateAction={handleCreateAction}
            onGerarAcaoGlobal={handleGerarAcaoGlobal}
            gerandoGlobal={gerandoBurnout}
            creatingActionFor={creatingActionFor}
          />
          <RadarPanel
            tipo="boreout"
            score={SCORE_BOREOUT}
            nivel={nivelBoreout}
            fatores={FATORES_BOREOUT}
            existingActionsByFator={existingActionsByFator}
            onCreateAction={handleCreateAction}
            onGerarAcaoGlobal={handleGerarAcaoGlobal}
            gerandoGlobal={gerandoBoreout}
            creatingActionFor={creatingActionFor}
          />
        </div>
      ) : (
        <Card className="border-dashed">
          <CardContent className="py-12 flex flex-col items-center text-center gap-3">
            <div className="p-3 rounded-full bg-muted">
              <Brain className="h-6 w-6 text-muted-foreground" />
            </div>
            <div className="space-y-1 max-w-md">
              <p className="font-semibold text-sm">Sem dados para os radares de Burnout & Boreout</p>
              <p className="text-xs text-muted-foreground">
                {campanhas.length === 0
                  ? 'Nenhuma campanha psicossocial criada para esta empresa. Crie uma campanha SIPRO para liberar os radares.'
                  : `Nenhuma campanha desta empresa atingiu o mínimo de respostas necessárias para liberar os radares. Os radares só são calculados com dados reais — não exibimos estimativas para preservar a integridade do diagnóstico.`}
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Nota técnica */}
      <Card className="border-muted bg-muted/20">
        <CardContent className="pt-4">
          <p className="text-xs text-muted-foreground">
            <strong>Metodologia:</strong> Os scores de Burnout e Boreout são derivados das dimensões IBO-S e IBD-S do instrumento SIPRO
            (Índice YourEyes de Risco Psicossocial Organizacional). Os critérios avaliados incluem fatores ocupacionais,
            organizacionais e individuais conforme ISO 45003, NR-01 e NR-17. Disponível quando houver mínimo de 5 respostas na campanha.
            Cada fator traduz a percepção respondida no questionário em um score de risco; quando uma dimensão não é medida na campanha,
            exibimos um valor de referência (estimativa), não uma medição. O cruzamento com dados operacionais (atestados, ponto, bem-estar,
            feedback e ocorrências) é feito na Contraprova Organizacional, com um indicador de alinhamento global.
            Clique em cada fator para ver de onde vem o indicador e criar ações corretivas/preventivas vinculadas ao Plano de Ação.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

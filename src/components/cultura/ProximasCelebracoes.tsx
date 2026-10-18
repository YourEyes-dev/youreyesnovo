import { useRef, useState } from "react";
import { motion } from "framer-motion";
import { format, differenceInCalendarDays, startOfDay } from "date-fns";
import { ptBR } from "date-fns/locale";
import { Cake, Award, CalendarHeart, Sparkles, Loader2, Bell, Briefcase, Lock } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import type { CulturaAcao, CulturaPreferencia } from "@/types/cultura";
import { TIPO_ACAO_LABELS, STATUS_ACAO_COLORS, STATUS_ACAO_LABELS } from "@/types/cultura";
import { useCelebracoes } from "@/hooks/useCelebracoes";
import { toDateLocal } from "@/lib/dataLocal";
import { chaveDaAcao, indexarAcoes, payloadAcaoDaCelebracao, pessoaReservada, type Celebracao } from "@/lib/celebracoes";

interface CelebracaoItem {
  chave: string;
  nome: string;
  tipo: "aniversario" | "tempo_casa" | "dia_profissao" | "acao";
  data: Date;
  diasRestantes: number;
  cargo?: string;
  anos?: number;
  /** ação já registrada para esta celebração (RN-004: no máximo uma por pessoa+tipo+ano) */
  acao?: CulturaAcao;
  celebracao?: Celebracao;
  pessoaId?: string;
}

interface Props {
  acoes: CulturaAcao[];
  preferencias?: CulturaPreferencia[];
  onCreateAcao?: (data: Partial<CulturaAcao>) => Promise<void>;
  onUpdateStatus?: (id: string, status: string) => Promise<void>;
}

export const ProximasCelebracoes = ({ acoes, preferencias = [], onCreateAcao, onUpdateStatus }: Props) => {
  const [criandoAcao, setCriandoAcao] = useState<string | null>(null);
  // trava síncrona: o refetch das ações é assíncrono e um segundo clique rápido duplicaria a ação
  const emCriacao = useRef(new Set<string>());

  // A Configuração do módulo governa o que é detectado e a janela de dias
  const { celebracoes: detectadas, janelaDias } = useCelebracoes({ exigirEmpresa: true });

  const acoesPorChave = indexarAcoes(acoes);
  const chavesDetectadas = new Set(detectadas.map((c) => c.chave));
  const hoje = startOfDay(new Date());

  const itensDetectados: CelebracaoItem[] = detectadas.map((c) => ({
    chave: c.chave,
    nome: c.nome,
    tipo: c.tipo,
    data: c.data,
    diasRestantes: c.diasRestantes,
    cargo: c.cargo,
    anos: c.anos,
    acao: acoesPorChave.get(c.chave),
    celebracao: c,
    pessoaId: c.pessoaId,
  }));

  // Ações sem celebração detectada correspondente (manuais, datas configuradas, rituais)
  const itensAcoes: CelebracaoItem[] = acoes
    .filter((a) => {
      if (a.status === "concluida" || a.status === "cancelada") return false;
      const k = chaveDaAcao(a);
      if (k && chavesDetectadas.has(k)) return false; // já aparece junto da celebração
      const ref = toDateLocal(a.data_referencia);
      if (!ref) return false;
      const dias = differenceInCalendarDays(ref, hoje);
      return dias >= 0 && dias <= janelaDias;
    })
    .map((a) => {
      const ref = toDateLocal(a.data_referencia)!;
      return {
        chave: `acao-${a.id}`,
        nome: a.colaborador_nome || a.titulo,
        tipo: "acao" as const,
        data: ref,
        diasRestantes: differenceInCalendarDays(ref, hoje),
        acao: a,
      };
    });

  const celebracoes = [...itensDetectados, ...itensAcoes].sort((a, b) => a.diasRestantes - b.diasRestantes);

  const handleCriarAcao = async (item: CelebracaoItem) => {
    if (!onCreateAcao || !item.celebracao) return;
    if (item.acao || emCriacao.current.has(item.chave)) return;
    emCriacao.current.add(item.chave);
    setCriandoAcao(item.chave);
    try {
      await onCreateAcao(payloadAcaoDaCelebracao(item.celebracao));
    } catch {
      emCriacao.current.delete(item.chave);
    } finally {
      setCriandoAcao(null);
    }
  };

  const getInitials = (name: string) =>
    name.split(" ").map((n) => n[0]).join("").toUpperCase().slice(0, 2);

  const getIcon = (tipo: string) => {
    if (tipo === "aniversario") return <Cake className="h-3.5 w-3.5" />;
    if (tipo === "tempo_casa") return <Award className="h-3.5 w-3.5" />;
    if (tipo === "dia_profissao") return <Briefcase className="h-3.5 w-3.5" />;
    return <CalendarHeart className="h-3.5 w-3.5" />;
  };

  const getBadgeLabel = (item: CelebracaoItem) => {
    if (item.tipo === "aniversario") return "Aniversário";
    if (item.tipo === "tempo_casa") return `${item.anos} ano${(item.anos || 0) > 1 ? "s" : ""} de empresa`;
    if (item.tipo === "dia_profissao") return "Dia da Profissão";
    return item.acao ? TIPO_ACAO_LABELS[item.acao.tipo] || "Ação" : "Ação";
  };

  const getDiasLabel = (dias: number) => {
    if (dias === 0) return "Hoje!";
    if (dias === 1) return "Amanhã";
    return `em ${dias} dias`;
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base flex items-center gap-2">
            <Bell className="h-4 w-4 text-primary" strokeWidth={1.75} />
            Próximas Celebrações ({janelaDias} dias)
          </CardTitle>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {celebracoes.slice(0, 8).map((item, i) => (
            <motion.div
              key={item.chave}
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: i * 0.05 }}
              className={`flex items-center gap-3 p-2 rounded-lg transition-colors ${
                item.diasRestantes === 0
                  ? "bg-primary/5 border border-primary/20"
                  : item.diasRestantes <= 3
                  ? "bg-amber-500/5 border border-amber-500/10"
                  : "hover:bg-muted/50"
              }`}
            >
              <Avatar className="h-10 w-10">
                <AvatarFallback className={
                  item.tipo === "aniversario"
                    ? "bg-pink-500/10 text-pink-600"
                    : item.tipo === "tempo_casa"
                    ? "bg-blue-500/10 text-blue-600"
                    : item.tipo === "dia_profissao"
                    ? "bg-amber-500/10 text-amber-600"
                    : "bg-violet-500/10 text-violet-600"
                }>
                  {getInitials(item.nome)}
                </AvatarFallback>
              </Avatar>

              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="text-sm font-medium truncate">{item.nome}</p>
                  <Badge variant="outline" className="text-[10px] shrink-0 gap-1">
                    {getIcon(item.tipo)}
                    {getBadgeLabel(item)}
                  </Badge>
                  {item.tipo !== "dia_profissao" && pessoaReservada(preferencias, item.pessoaId, item.nome) && (
                    <Badge variant="outline" className="text-[10px] shrink-0 gap-1" title="Preferiu reconhecimento reservado: celebre com discrição">
                      <Lock className="h-2.5 w-2.5" /> Reservado
                    </Badge>
                  )}
                </div>
                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  {item.cargo && <span>{item.cargo}</span>}
                  {item.cargo && <span>·</span>}
                  <span>{format(item.data, "dd 'de' MMMM", { locale: ptBR })}</span>
                  <span className={`font-medium ${
                    item.diasRestantes === 0
                      ? "text-primary"
                      : item.diasRestantes <= 3
                      ? "text-amber-600"
                      : ""
                  }`}>
                    ({getDiasLabel(item.diasRestantes)})
                  </span>
                </div>
              </div>

              {item.celebracao && !item.acao && onCreateAcao && (
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 px-2 text-xs shrink-0"
                  disabled={criandoAcao === item.chave}
                  onClick={() => handleCriarAcao(item)}
                >
                  {criandoAcao === item.chave ? (
                    <Loader2 className="h-3 w-3 animate-spin" />
                  ) : (
                    <>
                      <Sparkles className="h-3 w-3 mr-1" />
                      Criar Ação
                    </>
                  )}
                </Button>
              )}

              {item.acao && item.acao.status !== "concluida" && onUpdateStatus && (
                <Button
                  variant="outline"
                  size="sm"
                  className="h-7 px-2 text-xs shrink-0"
                  onClick={() => onUpdateStatus(item.acao!.id, "concluida")}
                >
                  Concluir
                </Button>
              )}
              {item.acao && item.acao.status === "concluida" && (
                <Badge className={`text-[10px] shrink-0 ${STATUS_ACAO_COLORS["concluida"]}`}>
                  Concluída
                </Badge>
              )}
              {item.celebracao && item.acao && item.acao.status !== "concluida" && (
                <Badge className={`text-[10px] shrink-0 ${STATUS_ACAO_COLORS[item.acao.status] || ""}`}>
                  {STATUS_ACAO_LABELS[item.acao.status] || item.acao.status}
                </Badge>
              )}
            </motion.div>
          ))}

          {celebracoes.length === 0 && (
            <p className="text-sm text-muted-foreground text-center py-4">
              Nenhuma celebração nos próximos {janelaDias} dias
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  );
};

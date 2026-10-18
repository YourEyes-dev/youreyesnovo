import { useState, useMemo } from "react";
import { motion } from "framer-motion";
import { MessageSquare, RefreshCw, CalendarHeart, Sparkles, Cake, Award, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { PostForm } from "@/components/feed/PostForm";
import { PostCard } from "@/components/feed/PostCard";
import { useFeed } from "@/hooks/useFeed";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useCelebracoes } from "@/hooks/useCelebracoes";
import { chaveDaAcao, pessoaReservada } from "@/lib/celebracoes";
import { TIPO_ACAO_LABELS, STATUS_ACAO_COLORS, STATUS_ACAO_LABELS } from "@/types/cultura";
import { format, parseISO, differenceInCalendarDays, startOfDay } from "date-fns";
import { ptBR } from "date-fns/locale";

interface LembreteMural {
  id: string;
  titulo: string;
  tipo: string;
  tipoLabel: string;
  nome: string;
  dataStr: string;
  diasFaltam: number;
  source: "auto" | "acao";
  status?: string;
  chaveDispensa: string;
}

function FeedSkeleton() {
  return (
    <div className="space-y-4">
      {[1, 2, 3].map((i) => (
        <div key={i} className="bg-card rounded-lg p-4 space-y-3">
          <div className="flex items-center gap-3">
            <Skeleton className="h-10 w-10 rounded-full" />
            <div className="space-y-1">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-3 w-20" />
            </div>
          </div>
          <Skeleton className="h-16 w-full" />
          <div className="flex gap-2">
            <Skeleton className="h-8 w-16" />
            <Skeleton className="h-8 w-16" />
            <Skeleton className="h-8 w-16" />
          </div>
        </div>
      ))}
    </div>
  );
}

function EmptyState() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="text-center py-12"
    >
      <div className="inline-flex p-4 rounded-2xl bg-primary/10 mb-4">
        <MessageSquare className="w-10 h-10 text-primary" />
      </div>
      <h3 className="text-lg font-semibold mb-2">Nenhuma publicação ainda</h3>
      <p className="text-muted-foreground max-w-md mx-auto">
        Seja o primeiro a compartilhar algo com a equipe! Use o formulário acima
        para criar sua primeira publicação.
      </p>
    </motion.div>
  );
}

// Widget unificado — puxa automaticamente de admissões + ações manuais
function AvisosCulturaWidget({ onFelicitar }: { onFelicitar: (msg: string) => void }) {
  const { tenantId, user } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const userId = user?.id;
  const queryClient = useQueryClient();

  // Dispensados pelo usuário (chave com ano)
  const { data: dispensados = [] } = useQuery({
    queryKey: ["lembretes-dispensados", tenantId, userId],
    queryFn: async () => {
      if (!tenantId || !userId) return [];
      const { data, error } = await fromTable("lembretes_dispensados")
        .select("chave")
        .eq("tenant_id", tenantId)
        .eq("usuario_id", userId);
      if (error) throw error;
      return (data || []).map((d: any) => d.chave);
    },
    enabled: !!tenantId && !!userId,
  });

  const dispensar = async (chave: string) => {
    if (!tenantId || !userId) return;
    await fromTable("lembretes_dispensados").insert({
      tenant_id: tenantId,
      usuario_id: userId,
      chave,
    });
    queryClient.invalidateQueries({ queryKey: ["lembretes-dispensados"] });
  };
  const { data: acoesPendentes = [] } = useQuery({
    queryKey: ["cultura-acoes-mural", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      let query = fromTable("cultura_acoes")
        .select("*")
        .eq("tenant_id", tenantId)
        .in("status", ["pendente", "em_andamento"])
        .order("data_referencia", { ascending: true })
        .limit(20);
      if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);
      const { data, error } = await query;
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Mesma fonte da tela de Cultura: respeita a Configuração (tipos ligados e janela de dias)
  const { celebracoes } = useCelebracoes();

  // Quem pediu reconhecimento "reservado" não é exposto no Mural (RN-006)
  const { data: preferencias = [] } = useQuery({
    queryKey: ["cultura-preferencias", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await fromTable("cultura_preferencias")
        .select("colaborador_id, colaborador_nome, tipo_reconhecimento")
        .eq("tenant_id", tenantId);
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  const lembretes = useMemo(() => {
    const hoje = startOfDay(new Date());
    const items: LembreteMural[] = [];
    const dispensadoSet = new Set(dispensados);

    for (const c of celebracoes) {
      if (c.tipo === "dia_profissao") continue; // o Mural só traz celebrações de pessoas
      if (pessoaReservada(preferencias, c.pessoaId, c.nome)) continue;
      const ano = c.data.getFullYear();
      if (c.tipo === "aniversario") {
        const chave = `aniv-${c.pessoaId}-${ano}`;
        if (dispensadoSet.has(chave)) continue;
        items.push({
          id: `aniv-${c.pessoaId}`,
          titulo: `🎂 Aniversário de ${c.nome}`,
          tipo: "aniversario",
          tipoLabel: "Aniversário",
          nome: c.nome,
          dataStr: format(c.data, "dd/MM"),
          diasFaltam: c.diasRestantes,
          source: "auto",
          chaveDispensa: chave,
        });
      } else {
        const anos = c.anos ?? 0;
        const chave = `tempo-${c.pessoaId}-${ano}`;
        if (dispensadoSet.has(chave)) continue;
        items.push({
          id: `tempo-${c.pessoaId}`,
          titulo: `🏆 ${anos} ano${anos > 1 ? "s" : ""} de empresa — ${c.nome}`,
          tipo: "tempo_casa",
          tipoLabel: "Tempo de Casa",
          nome: c.nome,
          dataStr: format(c.data, "dd/MM"),
          diasFaltam: c.diasRestantes,
          source: "auto",
          chaveDispensa: chave,
        });
      }
    }

    // Ações manuais — deduplicar por nome+tipo
    const autoKeys = new Set(celebracoes.map(c => c.chave));
    for (const acao of acoesPendentes) {
      const key = chaveDaAcao(acao);
      if (key && autoKeys.has(key)) continue;
      if (acao.colaborador_nome && pessoaReservada(preferencias, undefined, acao.colaborador_nome)) continue;
      const chave = `acao-${acao.id}`;
      if (dispensadoSet.has(chave)) continue;
      items.push({
        id: `acao-${acao.id}`,
        titulo: acao.titulo,
        tipo: acao.tipo,
        tipoLabel: TIPO_ACAO_LABELS[acao.tipo] || acao.tipo,
        nome: acao.colaborador_nome || "Colaborador",
        dataStr: acao.data_referencia ? format(parseISO(acao.data_referencia), "dd/MM", { locale: ptBR }) : "",
        diasFaltam: acao.data_referencia ? differenceInCalendarDays(parseISO(acao.data_referencia), hoje) : 99,
        source: "acao",
        status: acao.status,
        chaveDispensa: chave,
      });
    }

    items.sort((a, b) => a.diasFaltam - b.diasFaltam);
    return items.slice(0, 8);
  }, [celebracoes, preferencias, acoesPendentes, dispensados]);

  if (lembretes.length === 0) return null;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <CalendarHeart className="h-4 w-4 text-primary" />
          Lembretes
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {lembretes.map((item) => (
          <div
            key={item.id}
            className="flex flex-col gap-1.5 p-2 rounded-lg bg-muted/50"
          >
            <div className="flex items-start gap-2">
              {item.tipo === "aniversario" ? (
                <Cake className="h-3.5 w-3.5 mt-0.5 text-primary shrink-0" />
              ) : item.tipo === "tempo_casa" ? (
                <Award className="h-3.5 w-3.5 mt-0.5 text-primary shrink-0" />
              ) : (
                <Sparkles className="h-3.5 w-3.5 mt-0.5 text-primary shrink-0" />
              )}
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium truncate">{item.titulo}</p>
                <div className="flex items-center gap-1.5 mt-0.5">
                  <Badge variant="outline" className="text-[9px] h-4">
                    {item.tipoLabel}
                  </Badge>
                  {item.diasFaltam === 0 ? (
                    <Badge className="text-[9px] h-4 bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400">
                      Hoje! 🎉
                    </Badge>
                  ) : (
                    <Badge variant="secondary" className="text-[9px] h-4">
                      em {item.diasFaltam} dia{item.diasFaltam > 1 ? "s" : ""}
                    </Badge>
                  )}
                </div>
                <p className="text-[10px] text-muted-foreground mt-0.5">
                  {item.nome} · {item.dataStr}
                </p>
              </div>
              <button
                className="shrink-0 p-0.5 rounded hover:bg-muted text-muted-foreground hover:text-foreground transition-colors"
                title="Dispensar lembrete"
                onClick={() => dispensar(item.chaveDispensa)}
              >
                <X className="h-3 w-3" />
              </button>
            </div>
            <Button
              variant="ghost"
              size="sm"
              className="h-6 text-[10px] text-primary self-end"
              onClick={() => {
                onFelicitar(`Parabéns, ${item.nome}! `);
                window.scrollTo({ top: 0, behavior: "smooth" });
              }}
            >
              <MessageSquare className="h-3 w-3 mr-1" />
              Deixar uma mensagem
            </Button>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

export default function Feed() {
  const { posts, isLoading, refetch } = useFeed();
  const [prefillContent, setPrefillContent] = useState("");

  const handleFelicitacao = (mensagem: string) => {
    setPrefillContent(mensagem);
  };

  return (
    <div className="space-y-6">
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center justify-between"
      >
        <div>
          <h1 className="text-2xl font-bold text-foreground">Mural Interno</h1>
          <p className="text-muted-foreground">
            Conecte-se e compartilhe com sua equipe
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={() => refetch()}>
          <RefreshCw className="h-4 w-4 mr-2" />
          Atualizar
        </Button>
      </motion.div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <PostForm
            prefillContent={prefillContent}
            onPrefillConsumed={() => setPrefillContent("")}
          />

          {isLoading ? (
            <FeedSkeleton />
          ) : posts.length === 0 ? (
            <EmptyState />
          ) : (
            <div>
              {posts.map((post) => (
                <PostCard key={post.id} post={post} />
              ))}
            </div>
          )}
        </div>

        <div className="space-y-4">
          <AvisosCulturaWidget onFelicitar={handleFelicitacao} />
        </div>
      </div>
    </div>
  );
}

import { useRef, useState } from "react";
import { startOfDay, differenceInCalendarDays } from "date-fns";
import { Cake, Award, Briefcase, CalendarHeart, PartyPopper, Lock, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useCelebracoes } from "@/hooks/useCelebracoes";
import { toDateLocal } from "@/lib/dataLocal";
import {
  indexarAcoes, payloadAcaoDaCelebracao, pessoaReservada, proximaExecucaoRitual, chaveDaAcao,
  type Celebracao,
} from "@/lib/celebracoes";
import type { CulturaAcao, CulturaPreferencia, CulturaRitual } from "@/types/cultura";

interface Props {
  acoes: CulturaAcao[];
  rituais: CulturaRitual[];
  preferencias: CulturaPreferencia[];
  onParabenizar: (payload: Partial<CulturaAcao>, existente?: CulturaAcao) => Promise<() => Promise<void>>;
  onRegistrarRitual: (r: CulturaRitual) => Promise<void>;
}

interface ItemHoje {
  chave: string;
  tipo: string;
  titulo: string;
  detalhe: string;
  atraso: number; // dias de atraso (0 = é hoje)
  pessoaId?: string;
  nomePessoa?: string;
  celebracao?: Celebracao;
  acao?: CulturaAcao;
  ritual?: CulturaRitual;
}

const ICONE: Record<string, JSX.Element> = {
  aniversario: <Cake className="h-4 w-4 text-pink-600" />,
  tempo_casa: <Award className="h-4 w-4 text-blue-600" />,
  dia_profissao: <Briefcase className="h-4 w-4 text-amber-600" />,
  ritual: <PartyPopper className="h-4 w-4 text-violet-600" />,
  acao: <CalendarHeart className="h-4 w-4 text-violet-600" />,
};

const DESFAZER_MS = 10_000;

export const HojeCelebracoes = ({ acoes, rituais, preferencias, onParabenizar, onRegistrarRitual }: Props) => {
  const { celebracoes, pessoas } = useCelebracoes({ exigirEmpresa: true });
  const [ocupado, setOcupado] = useState<string | null>(null);
  const emCurso = useRef(new Set<string>());
  const hoje = startOfDay(new Date());
  const tratadas = indexarAcoes(acoes);
  const idPorNome = new Map(pessoas.map((p) => [p.nome_completo.trim().toLowerCase(), p.id]));

  const itens: ItemHoje[] = [];

  // Celebrações detectadas para hoje ainda não concluídas
  for (const c of celebracoes.filter((x) => x.diasRestantes === 0)) {
    const acao = tratadas.get(c.chave);
    if (acao?.status === "concluida") continue;
    itens.push({
      chave: c.chave, tipo: c.tipo, titulo: c.nome, pessoaId: c.pessoaId,
      nomePessoa: c.tipo === "dia_profissao" ? undefined : c.nome,
      detalhe: c.tipo === "aniversario" ? "Aniversário" : c.tipo === "tempo_casa" ? `${c.anos} ano${(c.anos ?? 0) > 1 ? "s" : ""} de empresa` : "Dia da Profissão",
      atraso: 0, celebracao: c, acao,
    });
  }

  // Ações atrasadas que ninguém tratou (as de hoje já aparecem acima, junto da celebração)
  const chavesNaLista = new Set(itens.map((i) => i.chave));
  for (const a of acoes) {
    if (a.status !== "pendente" && a.status !== "em_andamento") continue;
    const k = chaveDaAcao(a);
    if (k && chavesNaLista.has(k)) continue;
    const ref = toDateLocal(a.data_referencia);
    if (!ref) continue;
    const dias = differenceInCalendarDays(hoje, ref);
    if (dias < 0) continue;
    itens.push({
      chave: `acao-${a.id}`, tipo: "acao", titulo: a.colaborador_nome || a.titulo, detalhe: a.titulo,
      atraso: dias, acao: a, nomePessoa: a.colaborador_nome || undefined,
      pessoaId: a.colaborador_nome ? idPorNome.get(a.colaborador_nome.trim().toLowerCase()) : undefined,
    });
  }

  // Rituais que vencem hoje ou estão vencidos
  for (const r of rituais.filter((x) => x.ativo)) {
    const prox = proximaExecucaoRitual(r);
    if (!prox) continue;
    const dias = differenceInCalendarDays(hoje, prox);
    if (dias >= 0) itens.push({ chave: `ritual-${r.id}`, tipo: "ritual", titulo: r.nome, detalhe: "Ritual", atraso: dias, ritual: r });
  }

  itens.sort((a, b) => b.atraso - a.atraso);

  const celebrar = async (item: ItemHoje): Promise<(() => Promise<void>) | null> => {
    if (emCurso.current.has(item.chave)) return null;
    emCurso.current.add(item.chave);
    try {
      if (item.ritual) {
        await onRegistrarRitual(item.ritual);
        return null;
      }
      return await onParabenizar(item.celebracao ? payloadAcaoDaCelebracao(item.celebracao) : {}, item.acao);
    } finally {
      emCurso.current.delete(item.chave);
    }
  };

  const handleUm = async (item: ItemHoje) => {
    setOcupado(item.chave);
    try {
      const desfazer = await celebrar(item);
      if (desfazer) {
        toast.success(`${item.titulo} celebrado(a)`, {
          duration: DESFAZER_MS,
          action: { label: "Desfazer", onClick: () => void desfazer() },
        });
      }
    } catch {
      /* o hook já avisou o erro */
    } finally {
      setOcupado(null);
    }
  };

  const handleTodos = async () => {
    setOcupado("todos");
    const desfazeres: Array<() => Promise<void>> = [];
    try {
      for (const item of itens.filter((i) => !i.ritual)) {
        const d = await celebrar(item);
        if (d) desfazeres.push(d);
      }
      toast.success(`${desfazeres.length} celebrações concluídas`, {
        duration: DESFAZER_MS,
        action: { label: "Desfazer", onClick: () => void Promise.all(desfazeres.map((d) => d())) },
      });
    } catch {
      /* o hook já avisou o erro */
    } finally {
      setOcupado(null);
    }
  };

  const celebraveis = itens.filter((i) => !i.ritual).length;

  return (
    <Card data-testid="painel-hoje">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <CardTitle className="text-base flex items-center gap-2">
            <PartyPopper className="h-4 w-4 text-primary" strokeWidth={1.75} />
            Hoje
            {itens.length > 0 && <Badge variant="secondary" className="text-[10px]">{itens.length}</Badge>}
          </CardTitle>
          {celebraveis > 1 && (
            <Button size="sm" variant="outline" className="h-7 text-xs" disabled={ocupado !== null} onClick={handleTodos}>
              {ocupado === "todos" ? <Loader2 className="h-3 w-3 animate-spin" /> : "Celebrar todos"}
            </Button>
          )}
        </div>
      </CardHeader>
      <CardContent>
        {itens.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-3">Nada para celebrar hoje. Tudo em dia.</p>
        ) : (
          <div className="space-y-2">
            {itens.map((item) => {
              const reservado = !!item.nomePessoa && pessoaReservada(preferencias, item.pessoaId, item.nomePessoa);
              return (
                <div key={item.chave} className="flex items-center gap-3 p-2 rounded-lg border bg-muted/30">
                  <div className="shrink-0">{ICONE[item.tipo] ?? ICONE.acao}</div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{item.titulo}</p>
                    <div className="flex items-center gap-1.5 flex-wrap text-xs text-muted-foreground">
                      <span>{item.detalhe}</span>
                      {item.atraso > 0 && (
                        <Badge className="text-[10px] h-4 bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400">
                          {item.atraso} dia{item.atraso > 1 ? "s" : ""} de atraso
                        </Badge>
                      )}
                      {reservado && (
                        <Badge variant="outline" className="text-[10px] h-4 gap-1" title="Preferiu reconhecimento reservado: celebre com discrição">
                          <Lock className="h-2.5 w-2.5" /> Reservado
                        </Badge>
                      )}
                    </div>
                  </div>
                  <Button
                    size="sm"
                    className="h-8 shrink-0"
                    disabled={ocupado !== null}
                    onClick={() => handleUm(item)}
                  >
                    {ocupado === item.chave ? (
                      <Loader2 className="h-3 w-3 animate-spin" />
                    ) : item.ritual ? (
                      "Registrar realização"
                    ) : (
                      "Parabenizar"
                    )}
                  </Button>
                </div>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
};

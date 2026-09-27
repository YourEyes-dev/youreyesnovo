import { useState } from "react";
import { MessageSquareWarning, CheckCircle2, Loader2, RefreshCw } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import {
  useContestacoes, useResolverContestacao, type Contestacao,
} from "@/hooks/useMapaComportamentalContestacoes";

const STATUS_BADGE: Record<Contestacao["status"], { label: string; variant: "secondary" | "outline" | "default" }> = {
  aberta: { label: "Aberta", variant: "default" },
  em_analise: { label: "Em análise", variant: "outline" },
  resolvida: { label: "Resolvida", variant: "secondary" },
};

export function ContestacoesGov() {
  const { data: lista = [], isLoading } = useContestacoes(true);
  const resolver = useResolverContestacao();
  const [respostas, setRespostas] = useState<Record<string, string>>({});

  if (isLoading) return <Skeleton className="h-32" />;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base">
          <MessageSquareWarning className="w-4 h-4 text-amber-600" /> Contestações de resultado
          {lista.some((c) => c.status !== "resolvida") && (
            <Badge variant="default" className="ml-auto">
              {lista.filter((c) => c.status !== "resolvida").length} em aberto
            </Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {lista.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhuma contestação registrada. Isso é bom sinal — ou o texto do relatório está agradável demais.</p>
        ) : (
          lista.map((c) => (
            <div key={c.id} className="rounded-lg border p-3 space-y-2">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-medium">{c.colaborador_nome ?? "Colaborador"}</span>
                <div className="flex items-center gap-2">
                  {c.solicitou_reaplicacao && (
                    <Badge variant="outline" className="gap-1"><RefreshCw className="w-3 h-3" /> Pediu refazer</Badge>
                  )}
                  <Badge variant={STATUS_BADGE[c.status].variant}>{STATUS_BADGE[c.status].label}</Badge>
                </div>
              </div>
              <p className="text-sm text-muted-foreground">{c.texto}</p>
              <p className="text-xs text-muted-foreground">
                Aberta em {new Date(c.created_at).toLocaleString("pt-BR")}
              </p>

              {c.status === "resolvida" ? (
                c.resposta && (
                  <p className="text-xs bg-muted/50 rounded p-2">
                    <strong>Resposta:</strong> {c.resposta}
                    {c.resolvido_por_nome ? ` — ${c.resolvido_por_nome}` : ""}
                  </p>
                )
              ) : (
                <div className="space-y-2">
                  <Textarea
                    rows={2}
                    placeholder="Resposta ao colaborador (opcional)"
                    value={respostas[c.id] ?? ""}
                    onChange={(e) => setRespostas((r) => ({ ...r, [c.id]: e.target.value }))}
                  />
                  <div className="flex flex-wrap gap-2">
                    {c.status === "aberta" && (
                      <Button size="sm" variant="outline"
                        onClick={() => resolver.mutate({ id: c.id, status: "em_analise", resposta: respostas[c.id] })}
                        disabled={resolver.isPending}>
                        Marcar em análise
                      </Button>
                    )}
                    <Button size="sm" className="gap-1"
                      onClick={() => resolver.mutate({ id: c.id, status: "resolvida", resposta: respostas[c.id] })}
                      disabled={resolver.isPending}>
                      {resolver.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle2 className="w-4 h-4" />}
                      Marcar como resolvida
                    </Button>
                  </div>
                </div>
              )}
            </div>
          ))
        )}
        <p className="text-xs text-muted-foreground pt-1">
          Contestar é um direito do colaborador (revisão humana, LGPD art. 20). Se a pessoa pediu para
          refazer, oriente-a a abrir “Meu Mapa” e responder novamente — a nova aplicação preserva o histórico.
        </p>
      </CardContent>
    </Card>
  );
}

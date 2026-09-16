/**
 * Eventos do eSocial de uma concessão de férias (RF-008): S-2230, S-1200,
 * S-1210. Gera sob demanda, valida antes e mostra o status. O envio real é
 * passo seguinte (fora deste escopo).
 */
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Landmark, AlertTriangle, CheckCircle2 } from "lucide-react";
import { useFeriasEsocial, type EsocialEvento } from "@/hooks/useFeriasEsocial";

const eventoLabel: Record<string, string> = {
  "S-2230": "S-2230 — gozo (motivo 15)",
  "S-1200": "S-1200 — remuneração",
  "S-1210": "S-1210 — pagamento",
};

const statusStyle: Record<string, string> = {
  pendente: "bg-sky-500/10 text-sky-600 border-sky-500/20",
  processado: "bg-success/10 text-success border-success/20",
  enviado: "bg-success/10 text-success border-success/20",
  rejeitado: "bg-destructive/10 text-destructive border-destructive/20",
  invalido: "bg-amber-500/10 text-amber-600 border-amber-500/20",
};

export function FeriasEsocialEventos({ calculoId }: { calculoId: string }) {
  const { eventos, isLoading, gerar } = useFeriasEsocial(calculoId);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <p className="font-medium text-sm flex items-center gap-1.5">
          <Landmark className="w-4 h-4" /> eSocial
        </p>
        <Button size="sm" variant="outline" onClick={() => gerar.mutate()} disabled={gerar.isPending}>
          {gerar.isPending ? "Gerando..." : eventos.length ? "Regerar" : "Gerar eventos"}
        </Button>
      </div>

      {!isLoading && eventos.length === 0 && (
        <p className="text-xs text-muted-foreground">
          Gere o S-2230 (gozo), o S-1200 (remuneração) e o S-1210 (pagamento) desta concessão.
          A validação roda antes; o envio ao governo é um passo posterior.
        </p>
      )}

      {eventos.map((ev: EsocialEvento) => (
        <div key={ev.id} className="flex flex-wrap items-center gap-2 rounded border p-2 text-xs">
          <span className="flex-1 font-medium">{eventoLabel[ev.tipo_evento] || ev.tipo_evento}</span>
          <Badge variant="outline" className={statusStyle[ev.status] || ""}>
            {ev.status === "invalido" && <AlertTriangle className="w-3 h-3 mr-1" />}
            {(ev.status === "processado" || ev.status === "enviado") && <CheckCircle2 className="w-3 h-3 mr-1" />}
            {ev.status}
          </Badge>
          {ev.mensagem_retorno && (
            <p className="w-full text-muted-foreground">{ev.mensagem_retorno}</p>
          )}
        </div>
      ))}
    </div>
  );
}

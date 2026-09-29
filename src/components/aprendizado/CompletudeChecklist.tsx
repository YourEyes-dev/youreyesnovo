import { CheckCircle2, Circle } from "lucide-react";
import { Progress } from "@/components/ui/progress";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Button } from "@/components/ui/button";
import type { CompletudeResultado, CompletudeItem } from "@/lib/completudeFuncao";

function corBarra(pct: number) {
  if (pct >= 100) return "text-emerald-600 dark:text-emerald-400";
  if (pct >= 50) return "text-amber-600 dark:text-amber-400";
  return "text-muted-foreground";
}

function ItemLinha({ item, onNavegar }: { item: CompletudeItem; onNavegar?: (aba: string) => void }) {
  const clicavel = !!(onNavegar && item.aba && !item.concluido);
  const conteudo = (
    <div className="flex items-center gap-2 text-sm py-1">
      {item.concluido ? (
        <CheckCircle2 className="w-4 h-4 text-emerald-600 dark:text-emerald-400 shrink-0" />
      ) : (
        <Circle className="w-4 h-4 text-muted-foreground/50 shrink-0" />
      )}
      <span className={item.concluido ? "text-foreground" : "text-muted-foreground"}>{item.label}</span>
      {item.detalhe && (
        <span className="text-xs text-muted-foreground/70 ml-auto">{item.detalhe}</span>
      )}
    </div>
  );
  if (clicavel) {
    return (
      <button
        type="button"
        onClick={() => onNavegar?.(item.aba!)}
        className="w-full text-left rounded hover:bg-muted/60 px-1 -mx-1 transition-colors"
      >
        {conteudo}
      </button>
    );
  }
  return <div className="px-1 -mx-1">{conteudo}</div>;
}

/** Checklist completo (usado no topo do FuncaoDetail). */
export function CompletudeResumo({
  resultado,
  onNavegar,
}: {
  resultado: CompletudeResultado;
  onNavegar?: (aba: string) => void;
}) {
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <p className="text-sm font-semibold text-foreground">Completude da função</p>
          <span className={`text-sm font-bold ${corBarra(resultado.percentual)}`}>
            {resultado.percentual}%
          </span>
        </div>
        <span className="text-xs text-muted-foreground">
          {resultado.concluidos} de {resultado.total} itens
        </span>
      </div>
      <Progress value={resultado.percentual} className="h-2" />
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6">
        {resultado.itens.map((item) => (
          <ItemLinha key={item.chave} item={item} onNavegar={onNavegar} />
        ))}
      </div>
    </div>
  );
}

/** Chip compacto de porcentagem + popover com o checklist (usado nos cards da lista). */
export function CompletudeBadgePopover({
  resultado,
  onNavegar,
}: {
  resultado: CompletudeResultado;
  onNavegar?: (aba: string) => void;
}) {
  return (
    <Popover>
      <PopoverTrigger asChild onClick={(e) => e.stopPropagation()}>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 gap-1.5 px-2"
          title="Completude da função"
        >
          <div className="w-16 hidden sm:block">
            <Progress value={resultado.percentual} className="h-1.5" />
          </div>
          <span className={`text-xs font-semibold ${corBarra(resultado.percentual)}`}>
            {resultado.percentual}%
          </span>
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-64" onClick={(e) => e.stopPropagation()}>
        <p className="text-xs font-semibold text-muted-foreground mb-2">
          Completude — {resultado.concluidos}/{resultado.total}
        </p>
        <div className="space-y-0.5">
          {resultado.itens.map((item) => (
            <ItemLinha key={item.chave} item={item} onNavegar={onNavegar} />
          ))}
        </div>
      </PopoverContent>
    </Popover>
  );
}

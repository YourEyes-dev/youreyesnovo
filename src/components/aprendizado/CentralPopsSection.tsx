import { useState } from "react";
import { FileText, Pencil, Trash2, Sparkles, Loader2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { usePopAtividade, type PopData } from "@/hooks/usePopAtividade";
import { useAprendizado } from "@/hooks/useAprendizado";
import { PopEditorModal } from "./PopEditorModal";
import { ExportarTodosPopsPdf } from "./ExportarTodosPopsPdf";

interface CentralPopsSectionProps {
  cargoId: string;
  funcaoNome: string;
}

// Dark-safe (O2-C): status com tokens que funcionam em claro e escuro.
const STATUS_META: Record<string, { label: string; classe: string }> = {
  rascunho: { label: "Rascunho", classe: "bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300" },
  em_revisao: { label: "Em revisão", classe: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300" },
  publicado: { label: "Publicado", classe: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300" },
  desatualizado: { label: "Desatualizado", classe: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" },
};

export function CentralPopsSection({ cargoId, funcaoNome }: CentralPopsSectionProps) {
  const {
    pops, isLoading, atualizarPop, atualizandoPop, excluirPop, buscarVersoes, reescreverTrechoIA,
  } = usePopAtividade(cargoId, funcaoNome);
  const { atividades } = useAprendizado(cargoId);

  const [popEditando, setPopEditando] = useState<PopData | null>(null);
  const [popExcluir, setPopExcluir] = useState<PopData | null>(null);
  const [excluindo, setExcluindo] = useState(false);

  const nomeAtividade = (atividadeId: string) =>
    atividades.find((a) => a.id === atividadeId)?.nome || null;

  const confirmarExclusao = async () => {
    if (!popExcluir) return;
    setExcluindo(true);
    try {
      await excluirPop(popExcluir.id);
      setPopExcluir(null);
    } finally {
      setExcluindo(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-10 text-muted-foreground">
        <Loader2 className="w-5 h-5 animate-spin mr-2" /> Carregando POPs...
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div>
          <p className="text-sm font-semibold text-foreground">
            Central de POPs {pops.length > 0 && <span className="text-muted-foreground font-normal">({pops.length})</span>}
          </p>
          <p className="text-xs text-muted-foreground">
            Todos os Procedimentos Operacionais Padrão desta função, com status e versão.
          </p>
        </div>
        {pops.length > 0 && <ExportarTodosPopsPdf pops={pops} funcaoNome={funcaoNome} />}
      </div>

      {pops.length === 0 ? (
        <div className="text-center py-12 text-muted-foreground border rounded-lg">
          <FileText className="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p className="text-sm">Nenhum POP nesta função ainda.</p>
          <p className="text-xs mt-1 flex items-center justify-center gap-1">
            <Sparkles className="w-3.5 h-3.5" />
            Gere POPs pela aba <strong>Atividades</strong> (individual ou em lote).
          </p>
        </div>
      ) : (
        <div className="border rounded-lg divide-y">
          {pops.map((pop) => {
            const meta = STATUS_META[pop.status] || { label: pop.status, classe: "bg-muted text-muted-foreground" };
            const atv = nomeAtividade(pop.atividade_id);
            return (
              <div key={pop.id} className="flex items-center gap-3 p-3 flex-wrap sm:flex-nowrap">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-xs font-mono text-muted-foreground">{pop.codigo}</span>
                    <p className="text-sm font-medium text-foreground truncate">{pop.titulo}</p>
                    {pop.gerado_por_ia && (
                      <Badge variant="outline" className="text-[10px] gap-1 shrink-0">
                        <Sparkles className="w-3 h-3" /> IA
                      </Badge>
                    )}
                  </div>
                  {atv && <p className="text-xs text-muted-foreground truncate mt-0.5">Atividade: {atv}</p>}
                </div>

                <Badge className={`text-xs shrink-0 ${meta.classe}`}>{meta.label}</Badge>
                <span className="text-xs text-muted-foreground shrink-0 w-10 text-right">v{pop.versao_atual}</span>

                <div className="flex gap-1 shrink-0">
                  <Button variant="ghost" size="icon" className="h-8 w-8" title="Editar / versões / exportar" onClick={() => setPopEditando(pop)}>
                    <Pencil className="w-4 h-4" />
                  </Button>
                  <Button variant="ghost" size="icon" className="h-8 w-8 text-destructive hover:text-destructive" title="Excluir POP" onClick={() => setPopExcluir(pop)}>
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {popEditando && (
        <PopEditorModal
          open={!!popEditando}
          onClose={() => setPopEditando(null)}
          pop={popEditando}
          onSave={(id, updates, motivo) => atualizarPop({ id, updates, motivo })}
          saving={atualizandoPop}
          buscarVersoes={buscarVersoes}
          reescreverTrechoIA={reescreverTrechoIA}
        />
      )}

      <AlertDialog open={!!popExcluir} onOpenChange={(v) => !v && !excluindo && setPopExcluir(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir este POP?</AlertDialogTitle>
            <AlertDialogDescription>
              O POP <strong>{popExcluir?.codigo}</strong> — {popExcluir?.titulo} será removido, junto do documento vinculado. Esta ação não pode ser desfeita.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={excluindo}>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => { e.preventDefault(); confirmarExclusao(); }}
              disabled={excluindo}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {excluindo ? <Loader2 className="w-4 h-4 animate-spin" /> : "Excluir"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

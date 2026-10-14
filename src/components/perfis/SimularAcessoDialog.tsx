import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { PerfilAcesso } from "@/hooks/usePerfisAcesso";
import { MODULOS_SISTEMA, ACOES_DISPONIVEIS, ESCOPOS_DISPONIVEIS, ESCOPO_APLICADO } from "@/hooks/usePerfisAcesso";
import { CheckCircle2, XCircle, Lock, Eye } from "lucide-react";
import { cn } from "@/lib/utils";

interface SimularAcessoDialogProps {
  open: boolean;
  onClose: () => void;
  perfil: PerfilAcesso;
}

export function SimularAcessoDialog({ open, onClose, perfil }: SimularAcessoDialogProps) {
  const permissoes = perfil.permissoes || [];
  const modulosAtivos = new Set(permissoes.filter((p) => p.ativo !== false).map((p) => p.modulo));
  const grupos = [...new Set(MODULOS_SISTEMA.map((m) => m.grupo))];

  const getPermissoesModulo = (moduloId: string) =>
    permissoes.filter((p) => p.modulo === moduloId && p.ativo !== false);

  const getEscopoLabel = (escopoId: string) =>
    ESCOPOS_DISPONIVEIS.find((e) => e.id === escopoId)?.label || escopoId;

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[88vh] flex flex-col overflow-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Eye className="w-4 h-4 text-primary" />
            Simulação de Acesso — {perfil.nome}
          </DialogTitle>
          <p className="text-[12px] text-muted-foreground">
            Visualize exatamente o que um usuário com este perfil pode fazer no sistema
          </p>
        </DialogHeader>

        <ScrollArea className="flex-1">
          <div className="space-y-4 pr-2">
            {grupos.map((grupo) => {
              const modulosGrupo = MODULOS_SISTEMA.filter((m) => m.grupo === grupo);
              const algumAtivo = modulosGrupo.some((m) => modulosAtivos.has(m.id));

              return (
                <div key={grupo}>
                  <p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground mb-2">{grupo}</p>
                  <div className="space-y-1">
                    {modulosGrupo.map((modulo) => {
                      const ativo = modulosAtivos.has(modulo.id);
                      const perms = getPermissoesModulo(modulo.id);
                      const escopo = perms[0]?.escopo;

                      return (
                        <div
                          key={modulo.id}
                          className={cn(
                            "flex items-start gap-3 p-2.5 rounded-lg border text-[13px]",
                            ativo
                              ? "bg-background border-border"
                              : "bg-muted/20 border-border/30 opacity-50"
                          )}
                        >
                          {ativo
                            ? <CheckCircle2 className="w-4 h-4 text-emerald-500 mt-0.5 shrink-0" />
                            : <XCircle className="w-4 h-4 text-muted-foreground/40 mt-0.5 shrink-0" />
                          }
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className={cn("font-medium", !ativo && "text-muted-foreground")}>{modulo.label}</span>
                              {ativo && escopo && (
                                <Badge
                                  variant="outline"
                                  className={cn(
                                    "text-[10px] h-4 px-1.5",
                                    !ESCOPO_APLICADO(escopo) && "border-amber-300 text-amber-600"
                                  )}
                                  title={
                                    ESCOPO_APLICADO(escopo)
                                      ? undefined
                                      : "Este recorte ainda não filtra os dados — hoje o módulo se comporta como Empresa inteira."
                                  }
                                >
                                  {getEscopoLabel(escopo)}
                                  {!ESCOPO_APLICADO(escopo) && " · como empresa inteira"}
                                </Badge>
                              )}
                            </div>
                            {ativo && perms.length > 0 && (
                              <div className="flex flex-wrap gap-1 mt-1.5">
                                {perms.map((p) => {
                                  const acaoConfig = ACOES_DISPONIVEIS.find((a) => a.id === p.acao);
                                  return (
                                    <span
                                      key={`${p.modulo}-${p.acao}`}
                                      className={cn(
                                        "inline-flex items-center gap-0.5 text-[10px] px-1.5 py-0.5 rounded border",
                                        acaoConfig?.sensivel
                                          ? "bg-red-50 border-red-200 text-red-700 dark:bg-red-950 dark:border-red-800 dark:text-red-400"
                                          : "bg-primary/5 border-primary/20 text-primary"
                                      )}
                                    >
                                      {acaoConfig?.sensivel && <Lock className="w-2.5 h-2.5" />}
                                      {acaoConfig?.label || p.acao}
                                    </span>
                                  );
                                })}
                              </div>
                            )}
                            {!ativo && (
                              <p className="text-[11px] text-muted-foreground/60 mt-0.5">Sem acesso a este módulo</p>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </ScrollArea>
      </DialogContent>
    </Dialog>
  );
}

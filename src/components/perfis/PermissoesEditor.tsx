import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import {
  MODULOS_SISTEMA,
  ACOES_DISPONIVEIS,
  ESCOPOS_DISPONIVEIS,
  ESCOPO_APLICADO,
  type PerfilPermissao,
} from "@/hooks/usePerfisAcesso";
import { AlertTriangle, ChevronDown, ChevronRight, Lock } from "lucide-react";
import { cn } from "@/lib/utils";

interface PermissoesEditorProps {
  permissoes: Partial<PerfilPermissao>[];
  onChange: (permissoes: Partial<PerfilPermissao>[]) => void;
}

type GrupoState = Record<string, boolean>;

export function PermissoesEditor({ permissoes, onChange }: PermissoesEditorProps) {
  const [gruposAbertos, setGruposAbertos] = useState<GrupoState>({});

  const grupos = [...new Set(MODULOS_SISTEMA.map((m) => m.grupo))];

  const toggleGrupo = (grupo: string) =>
    setGruposAbertos((prev) => ({ ...prev, [grupo]: !prev[grupo] }));

  const hasPermissao = (modulo: string, acao: string) =>
    permissoes.some((p) => p.modulo === modulo && p.acao === acao && p.ativo !== false);

  const getEscopo = (modulo: string): string => {
    const p = permissoes.find((p) => p.modulo === modulo);
    return p?.escopo || "empresa_inteira";
  };

  const togglePermissao = (modulo: string, acao: string) => {
    const existing = permissoes.find((p) => p.modulo === modulo && p.acao === acao);
    if (existing) {
      onChange(permissoes.filter((p) => !(p.modulo === modulo && p.acao === acao)));
    } else {
      const escopo = getEscopo(modulo);
      onChange([...permissoes, { modulo, acao, escopo, ativo: true }]);
    }
  };

  const toggleModulo = (modulo: string, checked: boolean) => {
    const escopo = getEscopo(modulo);
    const filtered = permissoes.filter((p) => p.modulo !== modulo);
    if (checked) {
      const novas = ACOES_DISPONIVEIS.slice(0, 3).map((a) => ({
        modulo, acao: a.id, escopo, ativo: true,
      }));
      onChange([...filtered, ...novas]);
    } else {
      onChange(filtered);
    }
  };

  const updateEscopo = (modulo: string, escopo: string) => {
    onChange(permissoes.map((p) => p.modulo === modulo ? { ...p, escopo } : p));
  };

  const isModuloAtivo = (modulo: string) =>
    permissoes.some((p) => p.modulo === modulo);

  const countPermissoesModulo = (modulo: string) =>
    permissoes.filter((p) => p.modulo === modulo).length;

  return (
    <div className="space-y-2">
      {grupos.map((grupo) => {
        const modulosGrupo = MODULOS_SISTEMA.filter((m) => m.grupo === grupo);
        const aberto = !!gruposAbertos[grupo];
        const ativos = modulosGrupo.filter((m) => isModuloAtivo(m.id)).length;

        return (
          <div key={grupo} className="border border-border rounded-lg overflow-hidden">
            <button
              type="button"
              onClick={() => toggleGrupo(grupo)}
              className="w-full flex items-center gap-2 px-3 py-2 bg-muted/40 hover:bg-muted/60 transition-colors text-left"
            >
              {aberto ? <ChevronDown className="w-4 h-4 text-muted-foreground" /> : <ChevronRight className="w-4 h-4 text-muted-foreground" />}
              <span className="text-[12px] font-semibold text-foreground flex-1">{grupo}</span>
              {ativos > 0 && (
                <Badge variant="secondary" className="text-[10px] h-4">
                  {ativos}/{modulosGrupo.length}
                </Badge>
              )}
            </button>
            {aberto && (
              <div className="divide-y divide-border/50">
                {modulosGrupo.map((modulo) => {
                  const ativo = isModuloAtivo(modulo.id);
                  const count = countPermissoesModulo(modulo.id);
                  const escopo = getEscopo(modulo.id);

                  return (
                    <div key={modulo.id} className={cn("px-3 py-3 space-y-2 transition-colors", ativo ? "bg-background" : "bg-muted/20")}>
                      <div className="flex items-center gap-3">
                        <Checkbox
                          id={`mod-${modulo.id}`}
                          checked={ativo}
                          onCheckedChange={(c) => toggleModulo(modulo.id, !!c)}
                        />
                        <Label htmlFor={`mod-${modulo.id}`} className="flex-1 text-[13px] font-medium cursor-pointer">
                          {modulo.label}
                        </Label>
                        {ativo && (
                          <div className="flex items-center gap-2">
                            <span className="text-[10px] text-muted-foreground">{count} ação{count !== 1 ? "ões" : ""}</span>
                            <Select value={escopo} onValueChange={(v) => updateEscopo(modulo.id, v)}>
                              <SelectTrigger className="h-6 text-[11px] w-44 border-dashed">
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                {ESCOPOS_DISPONIVEIS.map((e) => (
                                  <SelectItem
                                    key={e.id}
                                    value={e.id}
                                    // Escopo ainda sem filtro de dados: não deixa escolher
                                    // (mas continua selecionável se o perfil JÁ o tiver, para
                                    // não travar a edição de perfis antigos).
                                    disabled={!e.aplicado && e.id !== escopo}
                                    className="text-[12px]"
                                  >
                                    {e.label}
                                    {!e.aplicado && (
                                      <span className="ml-1 text-muted-foreground">(em breve)</span>
                                    )}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        )}
                      </div>
                      {ativo && !ESCOPO_APLICADO(escopo) && (
                        <div className="ml-6 flex items-start gap-1.5 text-[10px] text-amber-600">
                          <AlertTriangle className="w-3 h-3 flex-shrink-0 mt-0.5" />
                          <span>
                            O recorte "{ESCOPOS_DISPONIVEIS.find((e) => e.id === escopo)?.label || escopo}"
                            ainda não filtra os dados — hoje este módulo se comporta como
                            <strong> Empresa inteira</strong>. Troque para "Próprio usuário"
                            se a intenção é limitar o acesso.
                          </span>
                        </div>
                      )}
                      {ativo && (
                        <div className="ml-6 flex flex-wrap gap-1.5">
                          {ACOES_DISPONIVEIS.map((acao) => {
                            const checked = hasPermissao(modulo.id, acao.id);
                            return (
                              <Tooltip key={acao.id}>
                                <TooltipTrigger asChild>
                                  <button
                                    type="button"
                                    onClick={() => togglePermissao(modulo.id, acao.id)}
                                    className={cn(
                                      "flex items-center gap-1 px-2 py-0.5 rounded text-[11px] border transition-all",
                                      checked
                                        ? acao.sensivel
                                          ? "bg-red-50 border-red-200 text-red-700 dark:bg-red-950 dark:border-red-800 dark:text-red-400"
                                          : "bg-primary/10 border-primary/30 text-primary"
                                        : "bg-muted/30 border-border/50 text-muted-foreground hover:bg-muted"
                                    )}
                                  >
                                    {acao.sensivel && <Lock className="w-2.5 h-2.5" />}
                                    {acao.label}
                                  </button>
                                </TooltipTrigger>
                                <TooltipContent>
                                  {acao.sensivel ? "⚠️ Permissão sensível" : acao.label}
                                </TooltipContent>
                              </Tooltip>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
      {permissoes.some((p) => ACOES_DISPONIVEIS.find((a) => a.id === p.acao)?.sensivel) && (
        <div className="flex items-center gap-2 text-[11px] text-amber-600 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-lg p-2">
          <AlertTriangle className="w-3.5 h-3.5 flex-shrink-0" />
          Este perfil possui permissões sensíveis. Atribua com critério.
        </div>
      )}
      <div className="flex items-start gap-2 text-[11px] text-muted-foreground bg-muted/40 border border-border rounded-lg p-2">
        <AlertTriangle className="w-3.5 h-3.5 flex-shrink-0 mt-0.5" />
        <span>
          Por enquanto, só os recortes <strong>Próprio usuário</strong> e{" "}
          <strong>Empresa inteira</strong> filtram os dados. Os demais (subordinados
          diretos, setor, unidade, estabelecimento…) ainda estão em desenvolvimento
          e, se escolhidos, o módulo se comporta como <strong>Empresa inteira</strong>.
        </span>
      </div>
    </div>
  );
}

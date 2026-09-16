import { useState } from "react";
import { LogIn, LogOut, Pencil, Loader2, EyeOff, MapPin, Camera, Clock } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { confirm } from "@/components/ui/confirm-dialog";
import { cn } from "@/lib/utils";
import { supabase } from "@/integrations/supabase/client";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

interface Props {
  id: string;
  hora: string;
  isEntry: boolean;
  original: boolean;
  podeEditar: boolean;
  editando: boolean;
  onSalvar: (args: { marcacaoId: string; novaHora: string; motivo: string }) => Promise<unknown>;
  onExcluir?: (args: { marcacaoId: string; motivo: string }) => Promise<unknown>;
  excluindo?: boolean;
  endereco?: string;
  selfieUrl?: string;
  tipo?: string;
  distanciaMetros?: number | null;
  dentroCerca?: boolean | null;
  /** Tenant e CPF do dono da marcação — para registrar quem viu a selfie. */
  tenantId?: string | null;
  colaboradorCpf?: string | null;
}

export function MarcacaoBadge({ 
  id, hora, isEntry, original, podeEditar, editando, onSalvar, onExcluir, excluindo,
  endereco, selfieUrl, tipo, distanciaMetros, dentroCerca, tenantId, colaboradorCpf
}: Props) {
  const [open, setOpen] = useState(false);
  // LGPD arts. 11 e 46 (PONTO-397): a selfie é dado pessoal sensível. Fica
  // coberta por padrão e só é revelada por um gesto deliberado — e esse gesto
  // é registrado na trilha, com quem viu, o que viu e quando. Antes ela era
  // servida a quem apenas abrisse a lista, sem deixar rastro.
  const [selfieRevelada, setSelfieRevelada] = useState(false);

  const revelarSelfie = async () => {
    setSelfieRevelada(true);
    if (!tenantId) return;
    try {
      await (supabase.rpc as any)("ponto_log_acesso_sensivel", {
        p_tenant_id: tenantId,
        p_acao: "visualizou_selfie",
        p_recurso: "ponto_marcacoes",
        p_recurso_id: id,
        p_colaborador_cpf: colaboradorCpf || null,
        p_descricao: "Selfie da marcação exibida na tela de espelho de ponto.",
      });
    } catch {
      // O registro não pode impedir o RH de trabalhar; a falha fica no console.
    }
  };
  const [novaHora, setNovaHora] = useState(hora?.substring(0, 5) || "");
  const [motivo, setMotivo] = useState("");
  const motivoValido = motivo.trim().length >= 10;

  const badgeClasses = cn(
    "flex items-center justify-between p-2 rounded-lg border transition-all w-full",
    isEntry
      ? "bg-emerald-50 text-emerald-700 border-emerald-100 hover:border-emerald-300"
      : "bg-rose-50 text-rose-700 border-rose-100 hover:border-rose-300",
    podeEditar && "cursor-pointer"
  );

  const content = (
    <div className="flex items-center gap-3 w-full">
      <div className={cn(
        "p-1.5 rounded-full",
        isEntry ? "bg-emerald-100" : "bg-rose-100"
      )}>
        {isEntry ? <LogIn className="w-3.5 h-3.5" /> : <LogOut className="w-3.5 h-3.5" />}
      </div>
      
      <div className="flex-1">
        <div className="flex items-center gap-2">
          <span className="font-mono font-bold text-sm">{hora?.substring(0, 5)}</span>
          <span className="text-[10px] uppercase font-semibold opacity-70">
            {tipo === 'batida' ? (isEntry ? 'Entrada' : 'Saída') : (tipo || (isEntry ? 'Entrada' : 'Saída'))}
          </span>
          {!original && <span className="text-[9px] bg-amber-100 text-amber-700 px-1 rounded">Ajustado</span>}
          {podeEditar && dentroCerca === true && (
            <span
              className="text-[9px] bg-emerald-100 text-emerald-700 px-1 rounded font-semibold"
              title={distanciaMetros != null ? `Dentro da cerca (${Math.round(distanciaMetros)} m do local)` : "Dentro da cerca"}
            >
              ✓ Cerca{distanciaMetros != null ? ` ${Math.round(distanciaMetros)}m` : ""}
            </span>
          )}
          {podeEditar && dentroCerca === false && (
            <span
              className="text-[9px] bg-amber-100 text-amber-800 px-1 rounded font-semibold"
              title={distanciaMetros != null ? `Batida ${Math.round(distanciaMetros)} m FORA do raio configurado` : "Fora da cerca"}
            >
              ⚠ Fora{distanciaMetros != null ? ` ${Math.round(distanciaMetros)}m` : ""}
            </span>
          )}
        </div>
        
        {endereco && (
          <div className="flex items-center gap-1 mt-0.5 text-[10px] text-muted-foreground line-clamp-1">
            <MapPin className="w-2.5 h-2.5 shrink-0" />
            {endereco}
          </div>
        )}
      </div>

      {selfieUrl && !selfieRevelada && (
        <button
          type="button"
          title="Ver a selfie desta marcação. O acesso fica registrado (LGPD)."
          className="w-8 h-8 rounded border bg-muted shrink-0 flex items-center justify-center hover:bg-muted/70 transition"
          onClick={(e) => { e.stopPropagation(); void revelarSelfie(); }}
        >
          <Camera className="w-3.5 h-3.5 text-muted-foreground" />
        </button>
      )}

      {selfieUrl && selfieRevelada && (
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <div className="w-8 h-8 rounded border bg-muted overflow-hidden shrink-0">
                <img src={selfieUrl} alt="Selfie" className="w-full h-full object-cover" />
              </div>
            </TooltipTrigger>
            <TooltipContent className="p-0 border-none">
              <img src={selfieUrl} alt="Selfie ampliada" className="w-48 h-48 object-cover rounded-lg shadow-xl" />
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      )}

      {podeEditar && <Pencil className="w-3 h-3 opacity-40" />}
    </div>
  );

  if (!podeEditar) {
    return (
      <div className={badgeClasses} title={original ? "Registro Nativo" : "Registro Ajustado"}>
        {content}
      </div>
    );
  }

  return (
    <>
      <Popover open={open} onOpenChange={(o) => { setOpen(o); if (o) { setNovaHora(hora?.substring(0, 5) || ""); setMotivo(""); } }}>
        <PopoverTrigger asChild>
          <button type="button" className={badgeClasses} title="Clique para retificar ou desconsiderar a marcação">
            {content}
          </button>
        </PopoverTrigger>
        <PopoverContent className="w-72 max-w-[calc(100vw-2rem)] p-3" align="start" collisionPadding={16}>
          <div className="space-y-3">
            <div>
              <p className="text-sm font-semibold">Retificar marcação</p>
              <p className="text-[11px] text-muted-foreground">
                A marcação original é preservada. A retificação gera um ajuste auditável (Portaria MTP 671/2021).
              </p>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs">Nova hora</Label>
              <Input
                type="time"
                value={novaHora}
                onChange={(e) => setNovaHora(e.target.value)}
                step={60}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs">Justificativa (obrigatória)</Label>
              <Textarea
                value={motivo}
                onChange={(e) => setMotivo(e.target.value)}
                placeholder="Ex.: esquecimento de batida confirmado pelo gestor da área"
                rows={3}
                className="text-xs"
              />
              <p className={cn("text-[10px]", motivoValido ? "text-muted-foreground" : "text-destructive")}>
                {motivo.trim().length}/10 caracteres mínimos
              </p>
            </div>
            <div className="flex items-center gap-2">
              {onExcluir && (
                <Button
                  size="sm"
                  variant="ghost"
                  className="flex-1 px-2 text-amber-700 hover:text-amber-800 hover:bg-amber-500/10"
                  disabled={editando || excluindo || !motivoValido}
                  onClick={async () => {
                    setOpen(false);
                    const ok = await confirm({
                      title: "Desconsiderar marcação?",
                      description: `A marcação das ${hora?.substring(0, 5)} será desconsiderada: fica registrada no acervo (a prova não é apagada), mas sai do cálculo da jornada do dia. Use para batidas duplicadas ou incorretas.`,
                      confirmLabel: "Desconsiderar",
                    });
                    if (ok) await onExcluir({ marcacaoId: id, motivo: motivo.trim() });
                  }}
                  title="Desconsiderar esta marcação (mantida no acervo, fora do cálculo) — informe o motivo acima"
                >
                  <EyeOff className="w-3.5 h-3.5 mr-1" /> Desconsiderar
                </Button>
              )}
              <Button size="sm" variant="ghost" className="flex-1 px-2" onClick={() => setOpen(false)} disabled={editando}>
                Cancelar
              </Button>
              <Button
                size="sm"
                className="flex-1 px-2"
                disabled={editando || !novaHora || !motivoValido || novaHora === hora?.substring(0, 5)}
                onClick={async () => {
                  await onSalvar({ marcacaoId: id, novaHora, motivo: motivo.trim() });
                  setOpen(false);
                }}
              >
                {editando ? <Loader2 className="w-3 h-3 animate-spin" /> : "Retificar"}
              </Button>
            </div>
          </div>
        </PopoverContent>
      </Popover>
    </>
  );
}

import { useState } from "react";
import { Loader2, MessageSquareWarning } from "lucide-react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { useCriarContestacao } from "@/hooks/useMapaComportamentalContestacoes";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  mapaId: string | null;
  /** Chamado quando o titular pede nova aplicação e escolhe refazer agora. */
  onRefazer?: () => void;
}

export function ContestarModal({ open, onOpenChange, mapaId, onRefazer }: Props) {
  const criar = useCriarContestacao();
  const [texto, setTexto] = useState("");
  const [reaplicar, setReaplicar] = useState(false);

  const enviar = async () => {
    if (!texto.trim()) return;
    await criar.mutateAsync({ mapaId, texto: texto.trim(), solicitouReaplicacao: reaplicar });
    const querRefazer = reaplicar;
    setTexto("");
    setReaplicar(false);
    onOpenChange(false);
    if (querRefazer) onRefazer?.();
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <MessageSquareWarning className="w-5 h-5 text-amber-600" /> Não me reconheço neste resultado
          </DialogTitle>
          <DialogDescription>
            Conte, com as suas palavras, o que não parece combinar com você. O RH vai analisar. Isso é um
            direito seu — o resultado não decide nada sobre a sua carreira.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1">
            <Label>O que não bateu?</Label>
            <Textarea
              rows={5}
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              placeholder="Ex.: o arquétipo não parece o meu jeito de trabalhar porque…"
            />
          </div>
          <label className="flex items-start gap-2 text-sm">
            <Checkbox checked={reaplicar} onCheckedChange={(v) => setReaplicar(v === true)} className="mt-0.5" />
            <span>Quero refazer o mapa (nova aplicação). Você pode começar agora ou depois.</span>
          </label>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={enviar} disabled={!texto.trim() || criar.isPending} className="gap-1">
            {criar.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
            Enviar contestação
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

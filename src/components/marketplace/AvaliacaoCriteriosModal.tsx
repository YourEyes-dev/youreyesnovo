import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Star, Send } from "lucide-react";

export interface CriterioAvaliacao { key: string; label: string; desc: string }

export const CRITERIOS_ESPECIALISTA: CriterioAvaliacao[] = [
  { key: "pontualidade", label: "Pontualidade", desc: "Cumpriu prazos e horários?" },
  { key: "clareza", label: "Clareza", desc: "Orientações e entregas foram claras?" },
  { key: "aderencia_escopo", label: "Aderência ao escopo", desc: "Entregou o que foi combinado?" },
  { key: "profissionalismo", label: "Profissionalismo", desc: "Postura ética e profissional?" },
];
export const CRITERIOS_EMPRESA: CriterioAvaliacao[] = [
  { key: "clareza_demanda", label: "Clareza da demanda", desc: "A empresa explicou bem o que precisava?" },
  { key: "acesso_fornecido", label: "Acesso e informações", desc: "Forneceu acesso, dados e documentos a tempo?" },
  { key: "pagamento_combinado", label: "Combinado cumprido", desc: "Pagamento e condições foram respeitados?" },
  { key: "respeito", label: "Relacionamento", desc: "Tratamento respeitoso e comunicação fluida?" },
];

function Estrelas({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const [hover, setHover] = useState(0);
  return (
    <div className="flex gap-0.5">
      {[1, 2, 3, 4, 5].map((s) => (
        <button key={s} type="button" onClick={() => onChange(s)} onMouseEnter={() => setHover(s)} onMouseLeave={() => setHover(0)} className="p-0.5 transition-transform hover:scale-110" aria-label={`${s} estrelas`}>
          <Star className={`h-5 w-5 ${s <= (hover || value) ? "text-amber-400 fill-amber-400" : "text-muted-foreground/30"}`} />
        </button>
      ))}
    </div>
  );
}

interface Props {
  open: boolean;
  onClose: () => void;
  titulo: string;
  subtitulo?: string;
  criterios: CriterioAvaliacao[];
  onEnviar: (notas: Record<string, number>, comentario: string) => void;
  isLoading?: boolean;
}

export function AvaliacaoCriteriosModal({ open, onClose, titulo, subtitulo, criterios, onEnviar, isLoading }: Props) {
  const [notas, setNotas] = useState<Record<string, number>>({});
  const [comentario, setComentario] = useState("");
  const completo = criterios.every((c) => (notas[c.key] ?? 0) > 0);
  const media = completo ? +(criterios.reduce((s, c) => s + notas[c.key], 0) / criterios.length).toFixed(1) : 0;
  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader><DialogTitle className="flex items-center gap-2"><Star className="h-5 w-5 text-amber-400" />{titulo}</DialogTitle></DialogHeader>
        <div className="space-y-4">
          {subtitulo && <p className="text-xs text-muted-foreground">{subtitulo}</p>}
          <p className="text-[11px] text-muted-foreground">Avalie apenas aspectos profissionais e administrativos. Contatos diretos no comentário são ocultados.</p>
          <div className="space-y-3">
            {criterios.map((c) => (
              <div key={c.key} className="flex items-center justify-between gap-3">
                <div className="flex-1 min-w-0"><p className="text-sm font-medium">{c.label}</p><p className="text-[11px] text-muted-foreground">{c.desc}</p></div>
                <Estrelas value={notas[c.key] ?? 0} onChange={(v) => setNotas((n) => ({ ...n, [c.key]: v }))} />
              </div>
            ))}
          </div>
          {completo && <div className="text-center p-3 bg-amber-50 rounded-xl"><p className="text-xs text-amber-700 font-medium">Nota geral</p><p className="text-2xl font-bold text-amber-600">{media}</p></div>}
          <div className="space-y-1.5">
            <Label>Comentário (opcional)</Label>
            <Textarea value={comentario} onChange={(e) => setComentario(e.target.value)} rows={2} maxLength={500} placeholder="Feedback objetivo..." />
          </div>
          <Button onClick={() => onEnviar(notas, comentario)} disabled={!completo || isLoading} className="w-full bg-gradient-to-r from-amber-500 to-orange-500 text-white border-0">
            <Send className="h-4 w-4 mr-1.5" />{isLoading ? "Enviando..." : "Enviar avaliação"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

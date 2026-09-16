import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Star, Send } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import type { MarketplaceContratacao } from "@/hooks/useMarketplace";

interface AvaliacaoModalProps {
  contratacao: MarketplaceContratacao | null;
  open: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

const CRITERIOS = [
  { key: "pontualidade", label: "Pontualidade", desc: "O profissional cumpriu prazos e horários?" },
  { key: "clareza", label: "Clareza", desc: "As orientações e entregas foram claras?" },
  { key: "aderencia_escopo", label: "Aderência ao Escopo", desc: "O serviço entregue corresponde ao contratado?" },
  { key: "profissionalismo", label: "Profissionalismo", desc: "Postura ética e profissional adequada?" },
] as const;

function StarRating({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const [hover, setHover] = useState(0);
  return (
    <div className="flex gap-0.5">
      {[1, 2, 3, 4, 5].map((star) => (
        <button
          key={star}
          type="button"
          onClick={() => onChange(star)}
          onMouseEnter={() => setHover(star)}
          onMouseLeave={() => setHover(0)}
          className="p-0.5 transition-transform hover:scale-110"
        >
          <Star
            className={`h-5 w-5 transition-colors ${
              star <= (hover || value)
                ? "text-amber-400 fill-amber-400"
                : "text-muted-foreground/30"
            }`}
          />
        </button>
      ))}
    </div>
  );
}

export function AvaliacaoModal({ contratacao, open, onClose, onSuccess }: AvaliacaoModalProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [notas, setNotas] = useState<Record<string, number>>({
    pontualidade: 0,
    clareza: 0,
    aderencia_escopo: 0,
    profissionalismo: 0,
  });
  const [comentario, setComentario] = useState("");

  if (!contratacao) return null;

  const allRated = Object.values(notas).every((v) => v > 0);
  const notaGeral = allRated
    ? +(Object.values(notas).reduce((a, b) => a + b, 0) / 4).toFixed(1)
    : 0;

  const handleSubmit = async () => {
    if (!allRated) {
      toast.error("Avalie todos os critérios antes de enviar");
      return;
    }

    setIsLoading(true);
    try {
      // Só transação verificada avalia (RN-004): a função confere status/prazo e
      // recalcula a reputação em dois eixos; nada de UPDATE direto de nota.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error } = await (supabase as any).rpc("marketye_avaliar", {
        p_ref_tipo: "contratacao", p_ref_id: contratacao.id, p_notas: notas, p_comentario: comentario.trim() || null,
      });
      if (error) throw error;
      toast.success("Avaliação enviada com sucesso!");
      onSuccess();
      onClose();
    } catch (err: any) {
      toast.error(err.message || "Erro ao enviar avaliação");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Star className="h-5 w-5 text-amber-400" />
            Avaliar Serviço
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Service summary */}
          <div className="p-3 bg-muted/50 rounded-xl">
            <p className="font-medium text-sm">{contratacao.servico?.nome || "Serviço"}</p>
            <p className="text-xs text-muted-foreground">
              {contratacao.profissional?.nome_completo} • {contratacao.profissional?.conselho}
            </p>
          </div>

          {/* Disclaimer */}
          <p className="text-[11px] text-muted-foreground">
            Avalie apenas aspectos profissionais e administrativos. Não é permitido avaliar conteúdo clínico ou terapêutico.
          </p>

          {/* Rating criteria */}
          <div className="space-y-3">
            {CRITERIOS.map((c) => (
              <div key={c.key} className="flex items-center justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium">{c.label}</p>
                  <p className="text-[11px] text-muted-foreground">{c.desc}</p>
                </div>
                <StarRating
                  value={notas[c.key]}
                  onChange={(v) => setNotas((n) => ({ ...n, [c.key]: v }))}
                />
              </div>
            ))}
          </div>

          {/* Overall score */}
          {allRated && (
            <div className="text-center p-3 bg-amber-50 rounded-xl">
              <p className="text-xs text-amber-700 font-medium">Nota geral</p>
              <p className="text-2xl font-bold text-amber-600">{notaGeral}</p>
            </div>
          )}

          {/* Comment */}
          <div className="space-y-1.5">
            <Label>Comentário (opcional)</Label>
            <Textarea
              value={comentario}
              onChange={(e) => setComentario(e.target.value)}
              rows={2}
              placeholder="Feedback objetivo sobre o serviço prestado..."
              maxLength={500}
            />
            <p className="text-[10px] text-muted-foreground text-right">{comentario.length}/500</p>
          </div>

          <Button
            onClick={handleSubmit}
            disabled={!allRated || isLoading}
            className="w-full bg-gradient-to-r from-amber-500 to-orange-500 text-white border-0"
          >
            <Send className="h-4 w-4 mr-1.5" />
            {isLoading ? "Enviando..." : "Enviar Avaliação"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

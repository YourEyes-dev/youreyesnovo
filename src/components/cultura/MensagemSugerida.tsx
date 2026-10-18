import { useEffect, useState } from "react";
import { Copy, Lock, RefreshCw, Send } from "lucide-react";
import { toast } from "sonner";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { quantidadeDeVariantes, sugerirMensagem, type Celebracao } from "@/lib/celebracoes";
import type { TomMensagem } from "@/types/cultura";

interface Props {
  celebracao: Celebracao | null;
  tom: TomMensagem;
  /** pessoa pediu reconhecimento reservado: o texto serve para um recado pessoal, não para o Mural */
  reservado: boolean;
  onPublicar: (conteudo: string) => Promise<void>;
  onFechar: () => void;
}

/** A Íris sugere o texto; quem decide, edita e publica é uma pessoa. */
export const MensagemSugerida = ({ celebracao, tom, reservado, onPublicar, onFechar }: Props) => {
  const [variante, setVariante] = useState(0);
  const [texto, setTexto] = useState("");
  const [publicando, setPublicando] = useState(false);

  useEffect(() => {
    if (celebracao) {
      setVariante(0);
      setTexto(sugerirMensagem(celebracao, tom, 0));
    }
  }, [celebracao, tom]);

  const outra = () => {
    if (!celebracao) return;
    const prox = (variante + 1) % quantidadeDeVariantes(celebracao.tipo, tom);
    setVariante(prox);
    setTexto(sugerirMensagem(celebracao, tom, prox));
  };

  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(texto);
      toast.success("Mensagem copiada");
    } catch {
      toast.error("Não foi possível copiar");
    }
  };

  const publicar = async () => {
    setPublicando(true);
    try {
      await onPublicar(texto);
      onFechar();
    } catch {
      /* o hook já avisou o erro */
    } finally {
      setPublicando(false);
    }
  };

  return (
    <Dialog open={!!celebracao} onOpenChange={(o) => !o && onFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Mensagem para {celebracao?.nome}</DialogTitle>
          <DialogDescription>Sugestão da Íris. Edite como quiser antes de usar.</DialogDescription>
        </DialogHeader>
        <Textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={5} aria-label="Texto da mensagem" />
        {reservado && (
          <p className="flex items-start gap-1.5 text-xs text-muted-foreground">
            <Lock className="h-3.5 w-3.5 mt-0.5 shrink-0" />
            {celebracao?.nome} preferiu reconhecimento reservado: não publicamos no Mural. Copie o texto e envie em particular.
          </p>
        )}
        <div className="flex gap-2 flex-wrap">
          <Button variant="outline" size="sm" onClick={outra} className="gap-1">
            <RefreshCw className="h-3.5 w-3.5" /> Outra sugestão
          </Button>
          <Button variant="outline" size="sm" onClick={copiar} className="gap-1">
            <Copy className="h-3.5 w-3.5" /> Copiar
          </Button>
          <Button size="sm" onClick={publicar} disabled={reservado || publicando || !texto.trim()} className="gap-1 ml-auto">
            <Send className="h-3.5 w-3.5" /> Publicar no Mural
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};

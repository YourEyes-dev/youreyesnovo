import { useEffect, useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Loader2 } from "lucide-react";

/**
 * Pré-visualização do Espelho de Ponto: o PDF do gerador único aparece num
 * <iframe> com um endereço temporário do próprio navegador (blob), sem botão de
 * baixar e sem gravar arquivo no computador. Ao fechar, o endereço é liberado.
 */
export interface EspelhoVisualizarDialogProps {
  aberto: boolean;
  onFechar: () => void;
  /** Monta o PDF (ou devolve null quando não há o que mostrar). */
  gerar: () => Promise<Blob | null>;
  subtitulo?: string;
}

export function EspelhoVisualizarDialog({ aberto, onFechar, gerar, subtitulo }: EspelhoVisualizarDialogProps) {
  const [url, setUrl] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);
  const [vazio, setVazio] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (!aberto) return;
    let cancelado = false;
    let criada: string | null = null;
    setCarregando(true);
    setVazio(false);
    setErro(null);
    setUrl(null);
    gerar()
      .then((blob) => {
        if (cancelado) return;
        if (!blob) {
          setVazio(true);
          return;
        }
        criada = URL.createObjectURL(blob);
        setUrl(criada);
      })
      .catch((e: Error) => {
        if (!cancelado) setErro(e.message || "Não foi possível montar o espelho.");
      })
      .finally(() => {
        if (!cancelado) setCarregando(false);
      });
    return () => {
      cancelado = true;
      if (criada) URL.revokeObjectURL(criada);
    };
    // gerar muda a cada render do pai; a pré-visualização só remonta ao abrir.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aberto]);

  return (
    <Dialog open={aberto} onOpenChange={(v) => { if (!v) onFechar(); }}>
      <DialogContent className="max-w-5xl w-[95vw]" data-testid="espelho-visualizar">
        <DialogHeader>
          <DialogTitle>Pré-visualização do espelho</DialogTitle>
          <DialogDescription>
            {subtitulo || "Confira o documento. Esta tela não gera arquivo para baixar."}
          </DialogDescription>
        </DialogHeader>
        <div className="h-[75vh] rounded-md border bg-muted/30 flex items-center justify-center overflow-hidden">
          {carregando && (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" /> Montando o espelho...
            </div>
          )}
          {!carregando && vazio && (
            <p className="text-sm text-muted-foreground">Nenhum colaborador com apuração nesta competência.</p>
          )}
          {!carregando && erro && <p className="text-sm text-destructive">{erro}</p>}
          {!carregando && url && (
            <iframe
              title="Pré-visualização do espelho de ponto"
              src={`${url}#toolbar=0&navpanes=0`}
              className="h-full w-full"
            />
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

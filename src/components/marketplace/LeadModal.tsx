import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Shield, Send } from "lucide-react";
import { formatarPreco, type MarketYEAnuncio } from "@/hooks/useMarketYE";

interface LeadModalProps {
  anuncio: MarketYEAnuncio | null;
  open: boolean;
  onClose: () => void;
  onEnviar: (mensagem: string) => void;
  isLoading?: boolean;
  origem?: { modulo?: string | null; id?: string | null; obrigacao?: string | null };
}

export function LeadModal({ anuncio, open, onClose, onEnviar, isLoading, origem }: LeadModalProps) {
  const [mensagem, setMensagem] = useState("");
  if (!anuncio) return null;
  const sugestao = origem?.obrigacao
    ? `Olá! Precisamos atender a ${origem.obrigacao} e vimos seu anúncio "${anuncio.nome}". Pode nos passar um orçamento e prazos?`
    : `Olá! Vimos seu anúncio "${anuncio.nome}" no MarketYE. Pode nos contar como funciona o atendimento, prazos e valores?`;

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader><DialogTitle>Falar com {anuncio.profissional.nome_completo}</DialogTitle></DialogHeader>
        <div className="space-y-4">
          <div className="p-3 bg-muted/50 rounded-xl">
            <p className="font-medium text-sm">{anuncio.nome}</p>
            <p className="text-xs text-muted-foreground">{anuncio.categoria_nome} · {formatarPreco(anuncio)}</p>
          </div>
          <div className="space-y-2">
            <Label>Sua mensagem</Label>
            <Textarea value={mensagem} onChange={(e) => setMensagem(e.target.value)} rows={4} placeholder={sugestao} data-testid="marketye-lead-mensagem" />
            {!mensagem && <Button type="button" variant="link" size="sm" className="px-0 h-auto" onClick={() => setMensagem(sugestao)}>Usar a sugestão</Button>}
          </div>
          <div className="p-3 bg-amber-50 border border-amber-200 rounded-xl text-xs text-amber-800 flex gap-2">
            <Shield className="h-4 w-4 mt-0.5 shrink-0" />
            <p>A conversa acontece pelo MarketYE. Telefones e e-mails ficam ocultos até você liberar o contato — assim a conversa fica registrada e você avalia depois. O YourEyes conecta; o serviço é do especialista.</p>
          </div>
          <Button className="w-full bg-gradient-to-r from-indigo-500 to-violet-600 text-white border-0" disabled={isLoading || mensagem.trim().length < 5} onClick={() => onEnviar(mensagem.trim())} data-testid="marketye-lead-enviar">
            <Send className="h-4 w-4 mr-1.5" />{isLoading ? "Enviando..." : "Enviar mensagem"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

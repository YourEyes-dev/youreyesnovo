import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Briefcase } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import type { MarketplaceCategoria } from "@/hooks/useMarketplace";

interface ServicoFormModalProps {
  open: boolean;
  onClose: () => void;
  onSuccess: () => void;
  profissionalId: string;
  categorias: MarketplaceCategoria[];
}

export function ServicoFormModal({ open, onClose, onSuccess, categorias }: ServicoFormModalProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [form, setForm] = useState({
    nome: "",
    descricao: "",
    categoria_id: "",
    base_legal: "",
    modalidade: "presencial" as "presencial" | "online" | "hibrido",
    publico_alvo: "",
    evidencia_minima: "",
    vinculo_tipo_acao: "",
    preco_referencia: "",
    duracao_estimada_minutos: "",
  });

  const updateField = (field: string, value: string) => {
    setForm((f) => ({ ...f, [field]: value }));
  };

  const handleSubmit = async () => {
    if (!form.nome || !form.descricao) {
      toast.error("Nome e descrição são obrigatórios");
      return;
    }

    setIsLoading(true);
    try {
      // Anúncio salvo como rascunho pela função e publicado em seguida (RN-021).
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const sb = supabase as any;
      const { data: salvo, error } = await sb.rpc("marketye_anuncio_salvar", {
        _dados: {
          categoria_id: form.categoria_id || null, nome: form.nome, descricao: form.descricao, base_legal: form.base_legal || null,
          modalidade: form.modalidade, publico_alvo: form.publico_alvo || null, evidencia_minima: form.evidencia_minima || null,
          preco_referencia: form.preco_referencia ? parseFloat(form.preco_referencia) : null,
          tipo_preco: form.preco_referencia ? "visita" : "sob_orcamento",
          duracao_estimada_minutos: form.duracao_estimada_minutos ? parseInt(form.duracao_estimada_minutos) : null,
        },
      });
      if (error) throw error;
      const { error: pubErr } = await sb.rpc("marketye_anuncio_publicar", { p_id: salvo.id });
      if (pubErr) { toast.warning(String(pubErr.message).replace(/^.*?:\s*/, "")); }
      toast.success("Serviço cadastrado com sucesso!");
      onSuccess();
      onClose();
    } catch (err: any) {
      toast.error(err.message || "Erro ao cadastrar serviço");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Briefcase className="h-5 w-5" />
            Cadastrar Serviço
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800">
            📌 Serviços genéricos ou vagos não são aceitos. Informe base legal e evidência mínima esperada.
          </div>

          <div className="space-y-1.5">
            <Label>Nome do serviço *</Label>
            <Input value={form.nome} onChange={(e) => updateField("nome", e.target.value)} placeholder="Ex: Análise Ergonômica Preliminar (AEP)" />
          </div>

          <div className="space-y-1.5">
            <Label>Descrição objetiva *</Label>
            <Textarea value={form.descricao} onChange={(e) => updateField("descricao", e.target.value)} rows={3} placeholder="Descreva o que inclui o serviço..." />
          </div>

          <div className="space-y-1.5">
            <Label>Categoria</Label>
            <Select value={form.categoria_id} onValueChange={(v) => updateField("categoria_id", v)}>
              <SelectTrigger><SelectValue placeholder="Selecione a categoria" /></SelectTrigger>
              <SelectContent>
                {categorias.map((c) => <SelectItem key={c.id} value={c.id}>{c.nome}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label>Base legal / Normativa</Label>
            <Input value={form.base_legal} onChange={(e) => updateField("base_legal", e.target.value)} placeholder="Ex: NR-17, NR-01, Resolução CFP nº 011/2018" />
          </div>

          <div className="space-y-1.5">
            <Label>Modalidade *</Label>
            <Select value={form.modalidade} onValueChange={(v) => updateField("modalidade", v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="presencial">Presencial</SelectItem>
                <SelectItem value="online">Online</SelectItem>
                <SelectItem value="hibrido">Híbrido</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label>Público-alvo</Label>
            <Input value={form.publico_alvo} onChange={(e) => updateField("publico_alvo", e.target.value)} placeholder="Ex: Empresas com mais de 20 funcionários" />
          </div>

          <div className="space-y-1.5">
            <Label>Evidência mínima esperada</Label>
            <Input value={form.evidencia_minima} onChange={(e) => updateField("evidencia_minima", e.target.value)} placeholder="Ex: Relatório AEP assinado" />
          </div>

          <div className="space-y-1.5">
            <Label>Vínculo com tipo de ação do sistema</Label>
            <Input value={form.vinculo_tipo_acao} onChange={(e) => updateField("vinculo_tipo_acao", e.target.value)} placeholder="Ex: Ação corretiva de ergonomia" />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Preço de referência (R$)</Label>
              <Input type="number" step="0.01" value={form.preco_referencia} onChange={(e) => updateField("preco_referencia", e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Duração estimada (min)</Label>
              <Input type="number" value={form.duracao_estimada_minutos} onChange={(e) => updateField("duracao_estimada_minutos", e.target.value)} />
            </div>
          </div>

          <Button
            onClick={handleSubmit}
            disabled={isLoading}
            className="w-full bg-gradient-to-r from-indigo-500 to-violet-600 text-white border-0"
          >
            {isLoading ? "Salvando..." : "Cadastrar Serviço"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

import { useState } from "react";
import { motion } from "framer-motion";
import { Award, Target, TrendingUp, Sparkles, Loader2, Send, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { ColaboradorSelect } from "@/components/shared/ColaboradorSelect";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useColaboradores } from "@/hooks/useColaboradores";
import { useAfastamentosAtivos } from "@/hooks/useAfastamentosAtivos";
import { AfastadoBadge } from "@/components/shared/AfastadoBadge";
import { GuiaFeedbackPanel } from "@/components/mapa-comportamental/GuiaFeedbackPanel";
import type { FeedbackCategoria } from "@/types/feedback";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface FeedbackFormProps {
  onSubmit: (data: {
    colaborador_id: string;
    colaborador_nome: string;
    colaborador_cargo?: string;
    colaborador_departamento?: string;
    colaborador_filial?: string;
    categoria: FeedbackCategoria;
    descricao: string;
    descricao_ia?: string;
    ia_utilizada?: boolean;
    enviado_email?: boolean;
  }) => Promise<void>;
  isLoading: boolean;
}

const CATEGORIAS: { value: FeedbackCategoria; label: string; icon: React.ElementType; desc: string }[] = [
  { value: "reconhecimento", label: "Reconhecimento", icon: Award, desc: "Reforçar comportamento positivo" },
  { value: "alinhamento", label: "Alinhamento", icon: Target, desc: "Ajustar expectativa ou padrão" },
  { value: "desenvolvimento", label: "Desenvolvimento", icon: TrendingUp, desc: "Indicar ponto de melhoria" },
];

export function FeedbackForm({ onSubmit, isLoading }: FeedbackFormProps) {
  const { colaboradores, isLoading: loadingColabs } = useColaboradores();
  const { getAfastamento } = useAfastamentosAtivos();
  const [colaboradorId, setColaboradorId] = useState("");
  const [categoria, setCategoria] = useState<FeedbackCategoria | "">("");
  const [descricao, setDescricao] = useState("");
  const [descricaoIA, setDescricaoIA] = useState("");
  const [iaUtilizada, setIaUtilizada] = useState(false);
  const [gerandoIA, setGerandoIA] = useState(false);
  const [enviarEmail, setEnviarEmail] = useState(false);

  const selectedColab = colaboradores.find((c) => c.id === colaboradorId);

  const handleGerarIA = async () => {
    if (!descricao || !categoria) {
      toast.error("Preencha a descrição e selecione a categoria antes.");
      return;
    }
    setGerandoIA(true);
    try {
      const { data, error } = await supabase.functions.invoke("ai-feedback", {
        body: { descricao, categoria, colaborador_nome: selectedColab?.nome_completo },
      });
      if (error) throw error;
      setDescricaoIA(data.texto_estruturado || descricao);
      setIaUtilizada(true);
      toast.success("Texto estruturado pela IA!");
    } catch {
      toast.error("Erro ao gerar texto com IA. Use o texto original.");
    } finally {
      setGerandoIA(false);
    }
  };

  const handleSubmit = async () => {
    if (!colaboradorId || !categoria || !descricao) {
      toast.error("Preencha todos os campos obrigatórios.");
      return;
    }
    await onSubmit({
      colaborador_id: colaboradorId,
      colaborador_nome: selectedColab?.nome_completo || "",
      colaborador_cargo: selectedColab?.cargo,
      colaborador_departamento: selectedColab?.departamento || undefined,
      colaborador_filial: selectedColab?.filial || undefined,
      categoria: categoria as FeedbackCategoria,
      descricao: iaUtilizada && descricaoIA ? descricaoIA : descricao,
      descricao_ia: descricaoIA || undefined,
      ia_utilizada: iaUtilizada,
      enviado_email: enviarEmail,
    });
    // Reset
    setColaboradorId("");
    setCategoria("");
    setDescricao("");
    setDescricaoIA("");
    setIaUtilizada(false);
    setEnviarEmail(false);
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-lg">Novo Feedback</CardTitle>
      </CardHeader>
      <CardContent className="space-y-5">
        {/* Passo 1: Colaborador */}
        <div className="space-y-2">
          <Label>Colaborador *</Label>
          <ColaboradorSelect
            value={colaboradorId}
            onChange={setColaboradorId}
            colaboradores={colaboradores}
            isLoading={loadingColabs}
          />
          {selectedColab && <AfastadoBadge afastamento={getAfastamento({ cpf: selectedColab.cpf, nome: selectedColab.nome_completo })} />}
          {selectedColab && (
            <div className="text-xs text-muted-foreground bg-muted/50 rounded-lg p-3 grid grid-cols-2 gap-1">
              <span>Função: {selectedColab.cargo}</span>
              <span>Depto: {selectedColab.departamento || "—"}</span>
              <span>Unidade: {selectedColab.filial || "—"}</span>
            </div>
          )}
          {selectedColab && <GuiaFeedbackPanel cpf={selectedColab.cpf} />}
        </div>

        {/* Passo 2: Categoria */}
        <div className="space-y-2">
          <Label>Categoria *</Label>
          <div className="grid grid-cols-3 gap-2">
            {CATEGORIAS.map((cat) => (
              <button
                key={cat.value}
                onClick={() => setCategoria(cat.value)}
                className={`flex flex-col items-center gap-1 p-3 rounded-lg border-2 transition-all text-center ${
                  categoria === cat.value
                    ? "border-primary bg-primary/10"
                    : "border-border hover:border-primary/50"
                }`}
              >
                <cat.icon className="w-5 h-5" />
                <span className="text-sm font-medium">{cat.label}</span>
                <span className="text-xs text-muted-foreground">{cat.desc}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Passo 3: Descrição */}
        <div className="space-y-2">
          <Label>Descrição do fato ou situação *</Label>
          <Textarea
            value={descricao}
            onChange={(e) => setDescricao(e.target.value)}
            placeholder="Descreva brevemente o fato ou situação observada..."
            rows={4}
          />
        </div>

        {/* Passo 4: IA */}
        {descricao && categoria && (
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="space-y-2">
            <Button variant="outline" size="sm" onClick={handleGerarIA} disabled={gerandoIA}>
              {gerandoIA ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Sparkles className="w-4 h-4 mr-2" />}
              Ajudar a estruturar feedback
            </Button>
            {descricaoIA && (
              <div className="bg-muted/50 rounded-lg p-3 border">
                <p className="text-xs font-medium text-muted-foreground mb-1">Texto estruturado pela IA:</p>
                <Textarea
                  value={descricaoIA}
                  onChange={(e) => setDescricaoIA(e.target.value)}
                  rows={4}
                />
              </div>
            )}
          </motion.div>
        )}

        {/* Passo 5: Envio */}
        <div className="flex items-center justify-between border-t pt-4">
          <div className="flex items-center gap-2">
            <Switch checked={enviarEmail} onCheckedChange={setEnviarEmail} />
            <Label className="flex items-center gap-1 text-sm">
              <Mail className="w-4 h-4" /> Enviar por e-mail ao colaborador
            </Label>
          </div>
          <Button onClick={handleSubmit} disabled={isLoading || !colaboradorId || !categoria || !descricao}>
            {isLoading ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Send className="w-4 h-4 mr-2" />}
            Registrar Feedback
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

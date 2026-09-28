import { useState, useRef } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { Sparkles, Loader2, CheckCircle2, XCircle, AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import type { FuncaoAtividade, FuncaoResponsabilidade } from "@/types/aprendizado";

interface AtividadeComContexto {
  atividade: FuncaoAtividade;
  responsabilidade?: FuncaoResponsabilidade | null;
  ferramentas?: string;
  conteudos?: string;
}

interface GerarPopsEmLoteModalProps {
  open: boolean;
  onClose: () => void;
  atividadesSemPop: AtividadeComContexto[];
  funcaoNome?: string;
  nivel?: string;
  gerarPopIA: (params: Record<string, string | undefined>) => Promise<Record<string, unknown>>;
  criarPop: (input: {
    atividade_id: string;
    titulo: string;
    gerado_por_ia: boolean;
    popContent?: Record<string, unknown>;
  }) => Promise<unknown>;
}

interface ResultadoItem {
  atividadeId: string;
  nome: string;
  status: "pendente" | "gerando" | "sucesso" | "erro";
  erro?: string;
}

export function GerarPopsEmLoteModal({
  open, onClose, atividadesSemPop, funcaoNome, nivel, gerarPopIA, criarPop,
}: GerarPopsEmLoteModalProps) {
  const [gerando, setGerando] = useState(false);
  const [resultados, setResultados] = useState<ResultadoItem[]>([]);
  const [concluido, setConcluido] = useState(false);
  const canceladoRef = useRef(false);

  const total = atividadesSemPop.length;
  const processados = resultados.filter(r => r.status === "sucesso" || r.status === "erro").length;
  const sucessos = resultados.filter(r => r.status === "sucesso").length;
  const erros = resultados.filter(r => r.status === "erro").length;
  const progresso = total > 0 ? Math.round((processados / total) * 100) : 0;

  const handleIniciar = async () => {
    canceladoRef.current = false;
    setGerando(true);
    setConcluido(false);

    const items: ResultadoItem[] = atividadesSemPop.map(a => ({
      atividadeId: a.atividade.id,
      nome: a.atividade.nome,
      status: "pendente" as const,
    }));
    setResultados(items);

    // Contadores locais: o `sucessos`/`erros` derivados de estado ficam defasados
    // dentro deste loop (setState é assíncrono), então o toast final usa estes.
    let okLocal = 0;
    let errosLocal = 0;

    for (let i = 0; i < atividadesSemPop.length; i++) {
      if (canceladoRef.current) break;

      const { atividade, responsabilidade, ferramentas, conteudos } = atividadesSemPop[i];

      // Mark as generating
      setResultados(prev => prev.map((r, idx) =>
        idx === i ? { ...r, status: "gerando" } : r
      ));

      try {
        const pop = await gerarPopIA({
          funcao_nome: funcaoNome,
          nivel,
          atividade_nome: atividade.nome,
          atividade_descricao: atividade.descricao || undefined,
          frequencia: atividade.frequencia,
          complexidade: atividade.complexidade,
          classificacao: atividade.classificacao,
          ferramentas: ferramentas || undefined,
          interfaces: responsabilidade?.interfaces || undefined,
          responsavel_direto: responsabilidade?.responsavel_direto || undefined,
          consequencia_erro: responsabilidade?.consequencia_erro || undefined,
          conteudos_relacionados: conteudos || undefined,
        });

        await criarPop({
          atividade_id: atividade.id,
          titulo: `POP – ${atividade.nome}`,
          gerado_por_ia: true,
          popContent: pop,
        });

        okLocal++;
        setResultados(prev => prev.map((r, idx) =>
          idx === i ? { ...r, status: "sucesso" } : r
        ));
      } catch (err: any) {
        errosLocal++;
        setResultados(prev => prev.map((r, idx) =>
          idx === i ? { ...r, status: "erro", erro: err.message || "Erro desconhecido" } : r
        ));
      }
    }

    setGerando(false);
    setConcluido(true);
    if (errosLocal > 0) {
      toast.warning(`POPs gerados: ${okLocal} de ${total} (${errosLocal} com erro)`);
    } else {
      toast.success(`POPs gerados: ${okLocal} de ${total}`);
    }
  };

  const handleCancelar = () => {
    canceladoRef.current = true;
  };

  const handleFechar = () => {
    if (!gerando) {
      setResultados([]);
      setConcluido(false);
      onClose();
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && handleFechar()}>
      <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Sparkles className="w-5 h-5 text-primary" />
            Gerar POPs em lote via IA
          </DialogTitle>
        </DialogHeader>

        {!gerando && !concluido && (
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              A IA irá gerar automaticamente o POP (Procedimento Operacional Padrão) para cada atividade que ainda não possui um.
              Todos os POPs gerados poderão ser editados posteriormente.
            </p>

            <div className="bg-muted/50 rounded-lg p-3 space-y-1">
              <p className="text-sm font-medium">{total} atividade{total !== 1 ? "s" : ""} sem POP</p>
              <ul className="text-xs text-muted-foreground space-y-0.5 max-h-32 overflow-y-auto">
                {atividadesSemPop.map(a => (
                  <li key={a.atividade.id} className="truncate">• {a.atividade.nome}</li>
                ))}
              </ul>
            </div>

            <div className="flex items-center gap-2 bg-warning/10 border border-warning/30 rounded-lg px-3 py-2 text-sm">
              <AlertTriangle className="w-4 h-4 text-warning shrink-0" />
              <span>Cada POP será gerado individualmente. O processo pode levar alguns minutos.</span>
            </div>

            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={handleFechar}>Cancelar</Button>
              <Button onClick={handleIniciar} className="gap-2">
                <Sparkles className="w-4 h-4" />
                Gerar {total} POP{total !== 1 ? "s" : ""}
              </Button>
            </div>
          </div>
        )}

        {(gerando || concluido) && (
          <div className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span>{gerando ? "Gerando..." : "Concluído"}</span>
                <span className="text-muted-foreground">{processados}/{total}</span>
              </div>
              <Progress value={progresso} className="h-2" />
            </div>

            <div className="space-y-1.5 max-h-48 overflow-y-auto">
              {resultados.map((r) => (
                <div key={r.atividadeId} className="flex items-center gap-2 text-sm">
                  {r.status === "pendente" && <div className="w-4 h-4 rounded-full border border-muted-foreground/30" />}
                  {r.status === "gerando" && <Loader2 className="w-4 h-4 animate-spin text-primary" />}
                  {r.status === "sucesso" && <CheckCircle2 className="w-4 h-4 text-green-600" />}
                  {r.status === "erro" && <XCircle className="w-4 h-4 text-destructive" />}
                  <span className="truncate flex-1">{r.nome}</span>
                  {r.status === "sucesso" && <Badge variant="outline" className="text-xs text-green-700">OK</Badge>}
                  {r.status === "erro" && (
                    <Badge variant="outline" className="text-xs text-destructive">{r.erro?.slice(0, 30)}</Badge>
                  )}
                </div>
              ))}
            </div>

            {concluido && (
              <div className="bg-muted/50 rounded-lg p-3 text-sm space-y-1">
                <p><strong>{sucessos}</strong> POP{sucessos !== 1 ? "s" : ""} gerado{sucessos !== 1 ? "s" : ""} com sucesso</p>
                {erros > 0 && <p className="text-destructive"><strong>{erros}</strong> com erro</p>}
                <p className="text-muted-foreground text-xs">Todos os POPs podem ser editados clicando em "Editar" em cada atividade.</p>
              </div>
            )}

            <div className="flex justify-end gap-2">
              {gerando && (
                <Button variant="outline" onClick={handleCancelar}>Parar</Button>
              )}
              {concluido && (
                <Button onClick={handleFechar}>Fechar</Button>
              )}
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

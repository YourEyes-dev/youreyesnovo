import { useState, useRef } from "react";
import { Mic, MicOff, Upload, Loader2, Check, X, FileAudio, Square, AlertTriangle, Info } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useAudioRecorder } from "@/hooks/useAudioRecorder";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface AtividadeExtraida {
  nome: string;
  descricao: string;
  frequencia: string;
  complexidade: string;
  classificacao: string;
  selecionada: boolean;
}

interface AudioAtividadesImportProps {
  funcaoNome?: string;
  onImportar: (atividades: Omit<AtividadeExtraida, "selecionada">[]) => Promise<void>;
}

const FREQ_LABELS: Record<string, string> = { diaria: "Diária", semanal: "Semanal", mensal: "Mensal", eventual: "Eventual" };
const COMPL_LABELS: Record<string, string> = { baixa: "Baixa", media: "Média", alta: "Alta" };
const CLASS_LABELS: Record<string, string> = { rotineira: "Rotineira", critica: "Crítica", excepcional: "Excepcional" };

export function AudioAtividadesImport({ funcaoNome, onImportar }: AudioAtividadesImportProps) {
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState<"gravar" | "processando" | "resultado">("gravar");
  const [atividades, setAtividades] = useState<AtividadeExtraida[]>([]);
  const [transcricao, setTranscricao] = useState("");
  const [importando, setImportando] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const recorder = useAudioRecorder({ maxDuration: 3600 }); // 1 hora

  const processarAudio = async (audioBase64: string) => {
    setStep("processando");
    try {
      const { data, error } = await supabase.functions.invoke("ai-audio-atividades", {
        body: { audioBase64, funcaoNome },
      });

      if (error) throw new Error(error.message);
      if (data.error) throw new Error(data.error);

      setTranscricao(data.transcricao || "");
      setAtividades((data.atividades || []).map((a: any) => ({ ...a, selecionada: true })));
      setStep("resultado");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Erro ao processar áudio";
      toast.error(msg);
      setStep("gravar");
    }
  };

  const handlePararGravacao = () => {
    recorder.stopRecording();
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith("audio/")) {
      toast.error("Selecione um arquivo de áudio");
      return;
    }

    const reader = new FileReader();
    reader.onload = async () => {
      const base64 = reader.result as string;
      await processarAudio(base64);
    };
    reader.readAsDataURL(file);
    e.target.value = "";
  };

  const toggleAtividade = (index: number) => {
    setAtividades(prev => prev.map((a, i) => i === index ? { ...a, selecionada: !a.selecionada } : a));
  };

  const toggleTodas = () => {
    const todasSelecionadas = atividades.every(a => a.selecionada);
    setAtividades(prev => prev.map(a => ({ ...a, selecionada: !todasSelecionadas })));
  };

  const handleImportar = async () => {
    const selecionadas = atividades.filter(a => a.selecionada);
    if (selecionadas.length === 0) {
      toast.error("Selecione ao menos uma atividade");
      return;
    }

    setImportando(true);
    try {
      await onImportar(selecionadas.map(({ selecionada, ...rest }) => rest));
      toast.success(`${selecionadas.length} atividade(s) importada(s) com sucesso!`);
      handleClose();
    } catch {
      toast.error("Erro ao importar atividades");
    } finally {
      setImportando(false);
    }
  };

  const handleClose = () => {
    setOpen(false);
    setStep("gravar");
    setAtividades([]);
    setTranscricao("");
    recorder.clearRecording();
  };

  const selecionadasCount = atividades.filter(a => a.selecionada).length;
  const complColor: Record<string, string> = { baixa: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300", media: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300", alta: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300" };

  return (
    <>
      <Button variant="outline" size="sm" className="gap-1.5" onClick={() => setOpen(true)}>
        <Mic className="w-4 h-4" /> Importar por Áudio
      </Button>

      <input type="file" ref={fileInputRef} className="hidden" accept="audio/*" onChange={handleFileUpload} />

      <Dialog open={open} onOpenChange={(v) => { if (!v) handleClose(); }}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <FileAudio className="w-5 h-5" /> Importar Atividades por Áudio
            </DialogTitle>
            <DialogDescription>
              Grave uma entrevista ou importe um áudio. A IA irá transcrever e extrair as atividades automaticamente.
            </DialogDescription>
          </DialogHeader>

          {step === "gravar" && (
            <div className="flex flex-col items-center gap-6 py-6">
              {/* Aviso de qualidade */}
              <div className="bg-warning/10 border border-warning/40 rounded-lg p-4 w-full">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="w-5 h-5 text-warning shrink-0 mt-0.5" />
                  <div className="space-y-1.5">
                    <p className="font-semibold text-sm text-foreground">Dicas para uma boa transcrição:</p>
                    <ul className="text-xs text-muted-foreground space-y-1 list-disc list-inside">
                      <li>Use um <strong>microfone de boa qualidade</strong> para captar o áudio com nitidez</li>
                      <li>Grave em um <strong>ambiente silencioso</strong>, sem ruídos de fundo</li>
                      <li>Fale de forma <strong>clara e pausada</strong> para a IA entender corretamente</li>
                      <li>Certifique-se de <strong>permitir o uso do microfone</strong> no navegador quando solicitado</li>
                    </ul>
                  </div>
                </div>
              </div>

              {!recorder.isRecording && !recorder.audioUrl && (
                <div className="flex flex-col items-center gap-4">
                  <p className="text-sm text-muted-foreground text-center max-w-md">
                    Grave a entrevista com o colaborador narrando suas atividades do dia a dia, ou importe um áudio já gravado.
                  </p>
                  <div className="flex gap-3">
                    <Button size="lg" className="gap-2" onClick={recorder.startRecording}>
                      <Mic className="w-5 h-5" /> Gravar Áudio
                    </Button>
                    <Button size="lg" variant="outline" className="gap-2" onClick={() => fileInputRef.current?.click()}>
                      <Upload className="w-5 h-5" /> Importar Arquivo
                    </Button>
                  </div>
                </div>
              )}

              {recorder.isRecording && (
                <div className="flex flex-col items-center gap-4">
                  <div className="relative">
                    <div className="w-24 h-24 rounded-full bg-destructive/10 flex items-center justify-center animate-pulse">
                      <MicOff className="w-10 h-10 text-destructive" />
                    </div>
                  </div>
                  <div className="text-2xl font-mono font-bold text-foreground">{recorder.formattedDuration}</div>
                  <p className="text-sm text-muted-foreground">Gravando... (máx. 1 hora)</p>
                  <Button variant="destructive" size="lg" className="gap-2" onClick={handlePararGravacao}>
                    <Square className="w-4 h-4" /> Parar Gravação
                  </Button>
                </div>
              )}

              {recorder.audioUrl && !recorder.isRecording && (
                <div className="flex flex-col items-center gap-4 w-full max-w-md">
                  <audio controls src={recorder.audioUrl} className="w-full" />
                  <div className="flex gap-3">
                    <Button variant="outline" onClick={() => recorder.clearRecording()}>
                      Descartar
                    </Button>
                    <Button className="gap-2" onClick={async () => {
                      const base64 = await recorder.getBase64();
                      if (base64) await processarAudio(base64);
                    }}>
                      <Loader2 className="w-4 h-4 hidden" /> Processar com IA
                    </Button>
                  </div>
                </div>
              )}

              {recorder.error && (
                <p className="text-sm text-destructive">{recorder.error}</p>
              )}
            </div>
          )}

          {step === "processando" && (
            <div className="flex flex-col items-center gap-4 py-12">
              <Loader2 className="w-10 h-10 animate-spin text-primary" />
              <p className="text-sm text-muted-foreground">Transcrevendo e extraindo atividades...</p>
              <p className="text-xs text-muted-foreground">Isso pode levar alguns segundos</p>
            </div>
          )}

          {step === "resultado" && (
            <div className="flex flex-col gap-3 min-h-0 flex-1 overflow-hidden">
              {transcricao && (
                <div className="bg-muted/50 rounded-lg p-3 text-sm flex-shrink-0">
                  <p className="font-medium text-xs text-muted-foreground mb-1">Transcrição:</p>
                  <ScrollArea className="max-h-20">
                    <p className="text-foreground">{transcricao}</p>
                  </ScrollArea>
                </div>
              )}

              <div className="flex items-center justify-between flex-shrink-0">
                <p className="text-sm font-medium">{atividades.length} atividade(s) identificada(s)</p>
                <Button variant="ghost" size="sm" onClick={toggleTodas}>
                  {atividades.every(a => a.selecionada) ? "Desmarcar todas" : "Selecionar todas"}
                </Button>
              </div>

              <ScrollArea className="flex-1 min-h-0 max-h-[40vh]">
                <div className="space-y-2 pr-3">
                  {atividades.map((at, i) => (
                    <div
                      key={i}
                      className={`border rounded-lg p-3 cursor-pointer transition-colors ${at.selecionada ? "border-primary bg-primary/5" : "border-border opacity-60"}`}
                      onClick={() => toggleAtividade(i)}
                    >
                      <div className="flex items-start gap-3">
                        <Checkbox checked={at.selecionada} className="mt-0.5" />
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-sm">{at.nome}</p>
                          <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{at.descricao}</p>
                          <div className="flex gap-1.5 mt-2 flex-wrap">
                            <Badge variant="outline" className="text-xs">{FREQ_LABELS[at.frequencia] || at.frequencia}</Badge>
                            <Badge className={`text-xs ${complColor[at.complexidade] || ""}`}>{COMPL_LABELS[at.complexidade] || at.complexidade}</Badge>
                            <Badge className="text-xs bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300">{CLASS_LABELS[at.classificacao] || at.classificacao}</Badge>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </ScrollArea>

              <div className="flex items-center justify-between pt-2 border-t flex-shrink-0">
                <Button variant="ghost" onClick={handleClose}>Cancelar</Button>
                <Button className="gap-2" onClick={handleImportar} disabled={importando || selecionadasCount === 0}>
                  {importando ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                  Importar {selecionadasCount} atividade(s)
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}

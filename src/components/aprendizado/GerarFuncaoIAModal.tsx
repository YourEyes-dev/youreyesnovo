import { useState, useRef, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Loader2, Sparkles, Wand2, CheckCircle2, ArrowLeft, RefreshCw, Trash2, Save, Pencil, Plus, Mic, Square, Upload, Pen, FileAudio } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useQueryClient } from "@tanstack/react-query";
import { useAudioRecorder } from "@/hooks/useAudioRecorder";

type EntradaModo = "texto" | "audio";

interface GerarFuncaoIAModalProps {
  open: boolean;
  onClose: () => void;
  cargoId: string;
  cargoNome: string;
  onSuccess?: () => void;
  /** Modo de entrada inicial (usado pelo estado guiado da função vazia). */
  entradaInicial?: EntradaModo;
}

const MAX_CHARS = 30000;

type Resultado = {
  nome?: string;
  nivel?: string;
  descricao?: string;
  objetivo_funcao?: string;
  escopo_geral?: string;
  responsabilidade?: string;
  atividades?: any[];
  competencias?: any[];
  indicadores?: any[];
  [k: string]: any;
};

export function GerarFuncaoIAModal({ open, onClose, cargoId, cargoNome, onSuccess, entradaInicial = "texto" }: GerarFuncaoIAModalProps) {
  const [descricao, setDescricao] = useState("");
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [resultado, setResultado] = useState<Resultado | null>(null);
  const [editingIdx, setEditingIdx] = useState<{ tipo: string; idx: number } | null>(null);
  const [entrada, setEntrada] = useState<EntradaModo>(entradaInicial);
  const [transcrevendo, setTranscrevendo] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const audioFileRef = useRef<HTMLInputElement>(null);
  const recorder = useAudioRecorder({ maxDuration: 3600 }); // 1 hora
  const qc = useQueryClient();

  // Ao (re)abrir, respeita o modo de entrada pedido pelo chamador.
  useEffect(() => {
    if (open) setEntrada(entradaInicial);
  }, [open, entradaInicial]);

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["cargos"] });
    qc.invalidateQueries({ queryKey: ["funcao_atividades", cargoId] });
    qc.invalidateQueries({ queryKey: ["funcao_competencias", cargoId] });
    qc.invalidateQueries({ queryKey: ["funcao_indicadores", cargoId] });
    qc.invalidateQueries({ queryKey: ["funcao_responsabilidades"] });
  };

  const extractError = async (error: any) => {
    let msg = error?.message || "Erro ao processar";
    try {
      const ctx = error?.context;
      if (ctx && typeof ctx.json === "function") {
        const body = await ctx.json();
        if (body?.error) msg = body.error;
      }
    } catch { /* ignore */ }
    return msg;
  };

  const handleGerar = async () => {
    const texto = descricao.trim() || cargoNome;
    if (texto.length < 3) {
      toast.error("Descreva a função com pelo menos 3 caracteres.");
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke("ai-gerar-funcao-completa", {
        body: { descricao_livre: texto, cargo_id: cargoId, persistir: false },
      });
      if (error) throw new Error(await extractError(error));
      if (data?.error) throw new Error(data.error);
      setResultado(data.resultado);
      toast.success("Prévia gerada! Revise, edite e clique em Aplicar para salvar.");
    } catch (err: any) {
      toast.error(err.message || "Erro ao gerar função com IA");
    } finally {
      setLoading(false);
    }
  };

  const handleRegenerar = async () => {
    setResultado(null);
    await handleGerar();
  };

  const handleAplicar = async () => {
    if (!resultado) return;
    setSaving(true);
    try {
      const { data, error } = await supabase.functions.invoke("ai-gerar-funcao-completa", {
        body: { cargo_id: cargoId, dados: resultado },
      });
      if (error) throw new Error(await extractError(error));
      if (data?.error) throw new Error(data.error);
      invalidate();
      toast.success(
        `Aplicado! ${resultado.atividades?.length || 0} atividades, ${resultado.competencias?.length || 0} competências e ${resultado.indicadores?.length || 0} indicadores salvos.`
      );
      onSuccess?.();
      handleClose();
    } catch (err: any) {
      toast.error(err.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  // Áudio → transcrição → vira o comando de texto (mesmo pipeline da geração).
  const processarAudio = async (audioBase64: string) => {
    setTranscrevendo(true);
    try {
      const { data, error } = await supabase.functions.invoke("ai-audio-atividades", {
        body: { audioBase64, funcaoNome: cargoNome },
      });
      if (error) throw new Error(await extractError(error));
      if (data?.error) throw new Error(data.error);
      const transcricao = (data?.transcricao || "").trim();
      if (!transcricao) throw new Error("Não foi possível transcrever o áudio.");
      setDescricao((prev) => (prev.trim() ? `${prev.trim()}\n\n${transcricao}` : transcricao).slice(0, MAX_CHARS));
      setEntrada("texto");
      recorder.clearRecording();
      toast.success("Áudio transcrito! Revise o texto abaixo e gere a prévia.");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Erro ao transcrever o áudio");
    } finally {
      setTranscrevendo(false);
    }
  };

  const handleAudioFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!file.type.startsWith("audio/")) {
      toast.error("Selecione um arquivo de áudio.");
      e.target.value = "";
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

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const ext = file.name.toLowerCase().slice(file.name.lastIndexOf("."));
    const permitidos = [".txt", ".csv", ".md", ".text", ".doc", ".docx"];
    if (!permitidos.includes(ext)) {
      toast.error("Formato não suportado. Use .txt, .csv, .md, .doc ou .docx.");
      e.target.value = "";
      return;
    }
    try {
      let conteudo = "";
      if (ext === ".docx" || ext === ".doc") {
        const mammoth = await import("mammoth");
        const arrayBuffer = await file.arrayBuffer();
        const result = await mammoth.extractRawText({ arrayBuffer });
        conteudo = (result.value || "").trim();
        if (!conteudo) {
          toast.error("Não foi possível extrair texto do arquivo. Tente salvar como .docx ou .txt.");
          e.target.value = "";
          return;
        }
      } else {
        conteudo = await file.text();
      }
      conteudo = conteudo.replace(/\r\n/g, "\n").split("\u0000").join("").trim();
      setDescricao(conteudo.slice(0, MAX_CHARS));
      if (conteudo.length > MAX_CHARS) {
        toast.info(`Arquivo longo: usando os primeiros ${MAX_CHARS.toLocaleString("pt-BR")} caracteres.`);
      } else {
        toast.success(`Arquivo carregado (${conteudo.length.toLocaleString("pt-BR")} caracteres).`);
      }
    } catch (err) {
      console.error("Erro ao ler arquivo:", err);
      toast.error("Erro ao ler o arquivo. Para .doc antigos, salve como .docx.");
    }
    e.target.value = "";
  };

  const handleClose = () => {
    setDescricao("");
    setResultado(null);
    setEditingIdx(null);
    setEntrada(entradaInicial);
    recorder.clearRecording();
    onClose();
  };

  const updateItem = (tipo: "atividades" | "competencias" | "indicadores", idx: number, patch: any) => {
    if (!resultado) return;
    const arr = [...(resultado[tipo] || [])];
    arr[idx] = { ...arr[idx], ...patch };
    setResultado({ ...resultado, [tipo]: arr });
  };

  const removeItem = (tipo: "atividades" | "competencias" | "indicadores", idx: number) => {
    if (!resultado) return;
    const arr = [...(resultado[tipo] || [])];
    arr.splice(idx, 1);
    setResultado({ ...resultado, [tipo]: arr });
  };

  const addItem = (tipo: "atividades" | "competencias" | "indicadores") => {
    if (!resultado) return;
    const template: any = {
      atividades: { nome: "Nova atividade", descricao: "", frequencia: "diaria", complexidade: "media", classificacao: "rotineira" },
      competencias: { nome: "Nova competência", tipo: "tecnica", descricao: "" },
      indicadores: { nome: "Novo indicador", descricao: "", meta: "", periodicidade: "mensal" },
    }[tipo];
    setResultado({ ...resultado, [tipo]: [...(resultado[tipo] || []), template] });
    setEditingIdx({ tipo, idx: (resultado[tipo]?.length || 0) });
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && !saving && handleClose()}>
      <DialogContent className="max-w-4xl max-h-[90vh] p-0 flex flex-col overflow-hidden">
        <DialogHeader className="px-6 pt-6 pb-2 shrink-0 border-b">
          <DialogTitle className="flex items-center gap-2">
            <Wand2 className="w-5 h-5 text-primary" />
            Gerar Função Completa com IA
          </DialogTitle>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto px-6 py-4">
          {!resultado ? (
            <div className="space-y-4">
              <input
                type="file"
                ref={fileInputRef}
                className="hidden"
                accept=".txt,.csv,.md,.text,.doc,.docx,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                onChange={handleFileUpload}
              />

              <div className="bg-primary/5 border border-primary/20 rounded-lg p-4">
                <p className="text-sm text-muted-foreground">
                  Alimente a função por qualquer caminho — a IA gera atividades, competências,
                  indicadores (KPIs), responsabilidades e requisitos de uma vez.
                </p>
                <p className="text-xs text-muted-foreground mt-2">
                  💡 Você poderá revisar, editar e excluir itens antes de salvar. Nada é aplicado até clicar em <b>Aplicar</b>.
                </p>
              </div>

              {/* Seletor de entrada unificado (O1-C) */}
              <div className="grid grid-cols-2 gap-2">
                <Button
                  type="button"
                  variant={entrada === "texto" ? "default" : "outline"}
                  className="gap-2"
                  onClick={() => setEntrada("texto")}
                  disabled={loading || transcrevendo}
                >
                  <Pen className="w-4 h-4" /> Descrever / colar texto
                </Button>
                <Button
                  type="button"
                  variant={entrada === "audio" ? "default" : "outline"}
                  className="gap-2"
                  onClick={() => setEntrada("audio")}
                  disabled={loading || transcrevendo}
                >
                  <Mic className="w-4 h-4" /> Gravar / enviar áudio
                </Button>
              </div>

              {entrada === "texto" && (
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <Label>Descreva a função ou cole uma descrição existente</Label>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      className="gap-1.5"
                      onClick={() => fileInputRef.current?.click()}
                      disabled={loading}
                    >
                      <Upload className="w-3.5 h-3.5" /> Enviar arquivo
                    </Button>
                  </div>
                  <Textarea
                    placeholder={`Ex: "${cargoNome} responsável por gestão financeira, contas a pagar e receber..." — ou cole uma job description / envie um arquivo (.txt, .docx).`}
                    value={descricao}
                    onChange={(e) => setDescricao(e.target.value)}
                    className="min-h-[220px] resize-y"
                    maxLength={MAX_CHARS}
                    disabled={loading}
                  />
                  <div className="flex justify-between text-xs text-muted-foreground">
                    <span>Deixe vazio para usar apenas o nome do cargo: "{cargoNome}"</span>
                    <span className={descricao.length > 27000 ? "text-destructive font-medium" : ""}>
                      {descricao.length.toLocaleString("pt-BR")}/30.000
                    </span>
                  </div>
                  <div className="flex justify-end gap-2 pt-1">
                    <Button variant="ghost" onClick={handleClose} disabled={loading}>Cancelar</Button>
                    <Button onClick={handleGerar} disabled={loading} className="gap-2">
                      {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Sparkles className="w-4 h-4" />}
                      {loading ? "Gerando prévia..." : "Gerar prévia com IA"}
                    </Button>
                  </div>
                </div>
              )}

              {entrada === "audio" && (
                <div className="space-y-4">
                  <input
                    type="file"
                    ref={audioFileRef}
                    className="hidden"
                    accept="audio/*"
                    onChange={handleAudioFileUpload}
                  />
                  <div className="rounded-lg border border-warning/40 bg-warning/10 p-3 text-xs text-muted-foreground">
                    Grave uma entrevista (ou envie um áudio) narrando a rotina da função. A IA transcreve,
                    o texto vira o comando abaixo e você revisa antes de gerar a prévia.
                  </div>

                  {transcrevendo ? (
                    <div className="flex flex-col items-center gap-3 py-8">
                      <Loader2 className="w-8 h-8 animate-spin text-primary" />
                      <p className="text-sm text-muted-foreground">Transcrevendo o áudio...</p>
                    </div>
                  ) : (
                    <div className="flex flex-col items-center gap-4 py-4">
                      {!recorder.isRecording && !recorder.audioUrl && (
                        <div className="flex gap-3">
                          <Button className="gap-2" onClick={recorder.startRecording}>
                            <Mic className="w-4 h-4" /> Gravar áudio
                          </Button>
                          <Button variant="outline" className="gap-2" onClick={() => audioFileRef.current?.click()}>
                            <Upload className="w-4 h-4" /> Enviar arquivo de áudio
                          </Button>
                        </div>
                      )}

                      {recorder.isRecording && (
                        <div className="flex flex-col items-center gap-3">
                          <div className="w-16 h-16 rounded-full bg-destructive/10 flex items-center justify-center animate-pulse">
                            <Mic className="w-7 h-7 text-destructive" />
                          </div>
                          <div className="text-xl font-mono font-bold">{recorder.formattedDuration}</div>
                          <Button variant="destructive" className="gap-2" onClick={recorder.stopRecording}>
                            <Square className="w-4 h-4" /> Parar gravação
                          </Button>
                        </div>
                      )}

                      {recorder.audioUrl && !recorder.isRecording && (
                        <div className="flex flex-col items-center gap-3 w-full max-w-md">
                          <audio controls src={recorder.audioUrl} className="w-full" />
                          <div className="flex gap-3">
                            <Button variant="outline" onClick={() => recorder.clearRecording()}>Descartar</Button>
                            <Button
                              className="gap-2"
                              onClick={async () => {
                                const base64 = await recorder.getBase64();
                                if (base64) await processarAudio(base64);
                              }}
                            >
                              <FileAudio className="w-4 h-4" /> Transcrever
                            </Button>
                          </div>
                        </div>
                      )}

                      {recorder.error && <p className="text-sm text-destructive">{recorder.error}</p>}
                    </div>
                  )}

                  <div className="flex justify-end">
                    <Button variant="ghost" onClick={handleClose} disabled={transcrevendo}>Cancelar</Button>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="space-y-5">
              <div className="bg-amber-500/10 border border-amber-500/30 rounded-lg p-4 flex items-start gap-3">
                <CheckCircle2 className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-foreground">Prévia gerada — ainda NÃO foi salvo</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    Revise, edite ou remova itens. Se preferir, ajuste o comando e regere. Clique em <b>Aplicar</b> para salvar tudo.
                  </p>
                </div>
              </div>

              {/* Comando editável + regenerar */}
              <div className="rounded-lg border bg-card p-4 space-y-2">
                <Label className="text-xs font-semibold text-muted-foreground">📝 Comando enviado à IA (edite para refinar)</Label>
                <Textarea
                  value={descricao}
                  onChange={(e) => setDescricao(e.target.value)}
                  className="min-h-[100px] resize-y text-sm"
                  maxLength={30000}
                  disabled={loading || saving}
                />
                <div className="flex justify-between items-center">
                  <span className="text-[11px] text-muted-foreground">
                    {descricao.length.toLocaleString("pt-BR")}/30.000
                  </span>
                  <Button size="sm" variant="outline" onClick={handleRegenerar} disabled={loading || saving} className="gap-2">
                    {loading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <RefreshCw className="w-3.5 h-3.5" />}
                    Regenerar
                  </Button>
                </div>
              </div>

              {resultado.objetivo_funcao !== undefined && (
                <EditableTextBlock
                  label="🎯 Objetivo"
                  value={resultado.objetivo_funcao || ""}
                  onChange={(v) => setResultado({ ...resultado, objetivo_funcao: v })}
                />
              )}

              {resultado.escopo_geral !== undefined && (
                <EditableTextBlock
                  label="📋 Escopo"
                  value={resultado.escopo_geral || ""}
                  onChange={(v) => setResultado({ ...resultado, escopo_geral: v })}
                />
              )}

              {/* Atividades */}
              <ListSection
                title="📌 Atividades"
                count={resultado.atividades?.length || 0}
                onAdd={() => addItem("atividades")}
              >
                {resultado.atividades?.map((a: any, i: number) => {
                  const isEdit = editingIdx?.tipo === "atividades" && editingIdx.idx === i;
                  return (
                    <div key={i} className="rounded-md border bg-background p-3">
                      <div className="flex items-start justify-between gap-2 mb-1">
                        <div className="flex-1 min-w-0">
                          {isEdit ? (
                            <Input
                              value={a.nome || ""}
                              onChange={(e) => updateItem("atividades", i, { nome: e.target.value })}
                              className="text-sm font-medium mb-2"
                            />
                          ) : (
                            <p className="text-sm font-medium text-foreground">{i + 1}. {a.nome}</p>
                          )}
                        </div>
                        <div className="flex gap-1 shrink-0">
                          <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setEditingIdx(isEdit ? null : { tipo: "atividades", idx: i })}>
                            {isEdit ? <Save className="w-3.5 h-3.5 text-primary" /> : <Pencil className="w-3.5 h-3.5" />}
                          </Button>
                          <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive hover:text-destructive" onClick={() => removeItem("atividades", i)}>
                            <Trash2 className="w-3.5 h-3.5" />
                          </Button>
                        </div>
                      </div>
                      {isEdit ? (
                        <Textarea
                          value={a.descricao || ""}
                          onChange={(e) => updateItem("atividades", i, { descricao: e.target.value })}
                          className="text-xs min-h-[70px]"
                          placeholder="Descrição"
                        />
                      ) : (
                        a.descricao && <p className="text-xs text-muted-foreground">{a.descricao}</p>
                      )}
                      <div className="flex gap-1 flex-wrap mt-2">
                        {a.frequencia && <span className="text-[10px] px-1.5 py-0.5 rounded bg-primary/10 text-primary">{a.frequencia}</span>}
                        {a.complexidade && <span className="text-[10px] px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-700 dark:text-amber-400">{a.complexidade}</span>}
                        {a.classificacao && <span className="text-[10px] px-1.5 py-0.5 rounded bg-blue-500/10 text-blue-700 dark:text-blue-400">{a.classificacao}</span>}
                      </div>
                    </div>
                  );
                })}
              </ListSection>

              {/* Competências */}
              <ListSection
                title="🧠 Competências"
                count={resultado.competencias?.length || 0}
                onAdd={() => addItem("competencias")}
              >
                {resultado.competencias?.map((c: any, i: number) => {
                  const isEdit = editingIdx?.tipo === "competencias" && editingIdx.idx === i;
                  return (
                    <div key={i} className="rounded-md border bg-background p-2 flex items-center gap-2">
                      {isEdit ? (
                        <Input
                          value={c.nome || ""}
                          onChange={(e) => updateItem("competencias", i, { nome: e.target.value })}
                          className="text-sm flex-1"
                        />
                      ) : (
                        <div className="flex-1">
                          <p className="text-sm text-foreground">{c.nome || c.competencia || c.titulo}</p>
                          {c.tipo && <p className="text-[10px] text-muted-foreground uppercase">{c.tipo}</p>}
                        </div>
                      )}
                      <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setEditingIdx(isEdit ? null : { tipo: "competencias", idx: i })}>
                        {isEdit ? <Save className="w-3.5 h-3.5 text-primary" /> : <Pencil className="w-3.5 h-3.5" />}
                      </Button>
                      <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive hover:text-destructive" onClick={() => removeItem("competencias", i)}>
                        <Trash2 className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  );
                })}
              </ListSection>

              {/* Indicadores */}
              <ListSection
                title="📊 Indicadores"
                count={resultado.indicadores?.length || 0}
                onAdd={() => addItem("indicadores")}
              >
                {resultado.indicadores?.map((ind: any, i: number) => {
                  const isEdit = editingIdx?.tipo === "indicadores" && editingIdx.idx === i;
                  return (
                    <div key={i} className="rounded-md border bg-background p-2">
                      <div className="flex items-start gap-2">
                        <div className="flex-1 min-w-0">
                          {isEdit ? (
                            <div className="space-y-1.5">
                              <Input
                                value={ind.nome || ""}
                                onChange={(e) => updateItem("indicadores", i, { nome: e.target.value })}
                                className="text-sm"
                                placeholder="Nome do KPI"
                              />
                              <Input
                                value={ind.meta || ""}
                                onChange={(e) => updateItem("indicadores", i, { meta: e.target.value })}
                                className="text-xs"
                                placeholder="Meta"
                              />
                            </div>
                          ) : (
                            <p className="text-sm text-muted-foreground">
                              • <span className="text-foreground">{ind.nome || ind.indicador || ind.titulo}</span>
                              {ind.meta && <span className="text-xs opacity-70"> — meta: {ind.meta}</span>}
                            </p>
                          )}
                        </div>
                        <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setEditingIdx(isEdit ? null : { tipo: "indicadores", idx: i })}>
                          {isEdit ? <Save className="w-3.5 h-3.5 text-primary" /> : <Pencil className="w-3.5 h-3.5" />}
                        </Button>
                        <Button size="icon" variant="ghost" className="h-7 w-7 text-destructive hover:text-destructive" onClick={() => removeItem("indicadores", i)}>
                          <Trash2 className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </ListSection>
            </div>
          )}
        </div>

        {resultado && (
          <div className="flex justify-between items-center gap-2 px-6 py-3 border-t bg-background shrink-0">
            <Button variant="ghost" onClick={() => setResultado(null)} disabled={saving} className="gap-2">
              <ArrowLeft className="w-4 h-4" /> Voltar ao comando
            </Button>
            <div className="flex gap-2">
              <Button variant="outline" onClick={handleClose} disabled={saving}>Descartar</Button>
              <Button onClick={handleAplicar} disabled={saving} className="gap-2">
                {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle2 className="w-4 h-4" />}
                {saving ? "Salvando..." : "Aplicar e Salvar"}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditableTextBlock({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  const [editing, setEditing] = useState(false);
  return (
    <div className="rounded-lg border bg-card p-4">
      <div className="flex items-center justify-between mb-1">
        <p className="font-medium text-foreground">{label}</p>
        <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setEditing(!editing)}>
          {editing ? <Save className="w-3.5 h-3.5 text-primary" /> : <Pencil className="w-3.5 h-3.5" />}
        </Button>
      </div>
      {editing ? (
        <Textarea value={value} onChange={(e) => onChange(e.target.value)} className="min-h-[100px] text-sm" />
      ) : (
        <p className="text-sm text-muted-foreground whitespace-pre-wrap">{value || <em className="opacity-60">(vazio)</em>}</p>
      )}
    </div>
  );
}

function ListSection({ title, count, onAdd, children }: { title: string; count: number; onAdd: () => void; children: React.ReactNode }) {
  return (
    <div className="rounded-lg border bg-card p-4">
      <div className="flex items-center justify-between mb-3">
        <p className="font-medium text-foreground">{title} ({count})</p>
        <Button size="sm" variant="outline" onClick={onAdd} className="gap-1 h-7">
          <Plus className="w-3.5 h-3.5" /> Adicionar
        </Button>
      </div>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

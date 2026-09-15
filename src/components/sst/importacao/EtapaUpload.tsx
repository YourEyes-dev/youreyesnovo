import { useCallback, useState } from "react";
import { useDropzone } from "react-dropzone";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import {
  Upload, FileText, X, AlertCircle, Loader2, CheckCircle2,
  ShieldAlert, Activity, Microscope, ClipboardList, Wrench, Zap, FileSearch
} from "lucide-react";
import { ImportacaoState } from "./ImportacaoInteligente";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

const MAX_SIZE_MB = 50;
const MAX_SIZE_BYTES = MAX_SIZE_MB * 1024 * 1024;

export const TIPOS_DOCUMENTO = [
  { value: "PGR", label: "PGR — Programa de Gerenciamento de Riscos" },
  { value: "PCMSO", label: "PCMSO — Controle Médico de Saúde Ocupacional" },
  { value: "LTCAT", label: "LTCAT — Laudo Técnico das Condições Ambientais" },
  { value: "PPP", label: "PPP — Perfil Profissiográfico Previdenciário" },
  { value: "APR", label: "APR — Análise Preliminar de Risco" },
  { value: "NR12", label: "NR-12 — Análise de Risco de Máquinas" },
  { value: "AEP", label: "AEP — Análise Ergonômica Preliminar" },
  { value: "AET", label: "AET — Análise Ergonômica do Trabalho" },
  { value: "LAUDO_INSALUBRIDADE", label: "Laudo de Insalubridade" },
  { value: "LAUDO_PERICULOSIDADE", label: "Laudo de Periculosidade" },
  { value: "AVALIACAO_AMBIENTAL", label: "Avaliação Ambiental / Higiene Ocupacional" },
  { value: "RELATORIO_MEDICOES", label: "Relatório de Medições" },
  { value: "RELATORIO_AUDITORIA", label: "Relatório de Auditoria SST" },
  { value: "PARECER_TECNICO", label: "Parecer Técnico" },
  { value: "OUTROS", label: "Outros" },
];

type TipoInfo = {
  icon: React.ElementType;
  color: string;
  titulo: string;
  descricao: string;
  extrai: string[];
};

const TIPO_INFO: Record<string, TipoInfo> = {
  PGR: {
    icon: ShieldAlert,
    color: "text-orange-600",
    titulo: "Inventário de Riscos + Plano de Ação",
    descricao: "O sistema irá importar todos os riscos identificados (físicos, químicos, biológicos, ergonômicos, de acidente) e as ações do plano 5W2H.",
    extrai: ["Inventário de riscos por setor/função", "Plano de ação (5W2H)", "Fontes geradoras e medidas de controle", "Estrutura organizacional e GHOs"],
  },
  PCMSO: {
    icon: Activity,
    color: "text-blue-600",
    titulo: "Exames por Função + Periodicidade",
    descricao: "O sistema irá importar a matriz de exames ocupacionais por cargo/função, incluindo exames clínicos, complementares e periodicidade.",
    extrai: ["Exames por cargo/função", "Periodicidade dos exames (admissional, periódico, etc.)", "Riscos relacionados a cada função", "Ações de adequação do programa"],
  },
  LTCAT: {
    icon: Microscope,
    color: "text-purple-600",
    titulo: "Periculosidade, Insalubridade e Aposentadoria Especial",
    descricao: "O sistema irá importar a avaliação dos agentes nocivos com foco previdenciário, incluindo enquadramento, limites de tolerância e conclusão técnica.",
    extrai: ["Agentes nocivos avaliados (Decreto 3048/99)", "Concentrações/intensidades e limites de tolerância", "Conclusão sobre exposição habitual e permanente", "Enquadramento para aposentadoria especial", "Ações corretivas do laudo"],
  },
  LAUDO_INSALUBRIDADE: {
    icon: ShieldAlert,
    color: "text-red-600",
    titulo: "Agentes Insalubres + Grau",
    descricao: "O sistema irá importar os agentes insalubres avaliados, medições, comparação com limites de tolerância e conclusão do laudo.",
    extrai: ["Agentes insalubres por setor/função", "Grau de insalubridade (mínimo, médio, máximo)", "Medições e comparação com limites NR-15", "Ações de controle e adequação"],
  },
  LAUDO_PERICULOSIDADE: {
    icon: Zap,
    color: "text-yellow-600",
    titulo: "Condições Perigosas + Caracterização",
    descricao: "O sistema irá importar as condições perigosas avaliadas, enquadramento legal, habitualidade e conclusão da periculosidade.",
    extrai: ["Condições perigosas por setor/função", "Enquadramento legal (NR-16)", "Habitualidade e permanência", "Conclusão de caracterização", "Ações de adequação"],
  },
  AET: {
    icon: ClipboardList,
    color: "text-green-600",
    titulo: "Fatores Ergonômicos + Recomendações",
    descricao: "O sistema irá importar os fatores ergonômicos analisados por posto de trabalho e todas as recomendações da AET.",
    extrai: ["Fatores ergonômicos por posto/função", "Postura, repetitividade, esforço físico, mobiliário", "Nível de risco por fator (alto/médio/baixo)", "Ações e recomendações ergonômicas"],
  },
  APR: {
    icon: FileSearch,
    color: "text-cyan-600",
    titulo: "Riscos por Tarefa + Medidas de Controle",
    descricao: "O sistema irá importar os riscos identificados por tarefa, medidas de controle previstas e ações do plano.",
    extrai: ["Riscos por tarefa/atividade", "Medidas de controle (EPC, EPI)", "Ações preventivas e corretivas"],
  },
  NR12: {
    icon: Wrench,
    color: "text-indigo-600",
    titulo: "Riscos de Máquinas + Adequações NR-12",
    descricao: "O sistema irá importar os riscos identificados nas máquinas/equipamentos e as adequações exigidas pela NR-12.",
    extrai: ["Riscos por máquina/equipamento", "Não conformidades NR-12", "Ações de adequação e prazo"],
  },
};

const TIPO_INFO_GENERICO: TipoInfo = {
  icon: FileText,
  color: "text-muted-foreground",
  titulo: "Dados Gerais + Riscos + Ações",
  descricao: "O sistema irá importar os dados gerais do documento, riscos/agentes identificados e ações quando presentes.",
  extrai: ["Dados gerais e responsáveis técnicos", "Riscos/agentes identificados", "Ações e recomendações quando presentes"],
};

async function extractTextViaEdgeFunction(file: File): Promise<{ texto: string; chars: number; palavras: number; qualidade: string }> {
  const { data: { session } } = await supabase.auth.getSession();
  const formData = new FormData();
  formData.append("file", file);

  const resp = await fetch(
    `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/sst-pdf-extract`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${session?.access_token || import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY}` },
      body: formData,
    }
  );

  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}));
    // 546 é o código do Supabase para "o processamento estourou os recursos e
    // foi encerrado". Chegava cru na tela ("Erro 546 na extração do arquivo"),
    // sem dizer nada a ninguém. Vira uma orientação do que fazer.
    if (resp.status === 546) {
      throw new Error(
        "O documento é pesado demais para a leitura automática e o processamento foi interrompido. " +
        "Tente enviar um PDF menor — por exemplo, só as páginas do inventário de riscos e do plano de ação — " +
        "ou um arquivo gerado direto do editor, em vez de digitalizado."
      );
    }
    throw new Error(err.error || `Erro ${resp.status} na extração do arquivo`);
  }

  return resp.json();
}

interface Props {
  state: ImportacaoState;
  updateState: (partial: Partial<ImportacaoState>) => void;
}

export function EtapaUpload({ state, updateState }: Props) {
  const [processando, setProcessando] = useState(false);
  const [tipoSelecionado, setTipoSelecionado] = useState(state.tipoDetectado || "");

  const onDrop = useCallback(async (acceptedFiles: File[]) => {
    const file = acceptedFiles[0];
    if (!file) return;
    if (file.size > MAX_SIZE_BYTES) {
      toast.error(`Arquivo muito grande. Máximo ${MAX_SIZE_MB}MB.`);
      return;
    }
    updateState({ arquivo: file });
  }, [updateState]);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      "application/pdf": [".pdf"],
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document": [".docx"],
      "application/msword": [".doc"],
    },
    maxFiles: 1,
    disabled: processando,
  });

  const tipoInfo = tipoSelecionado ? (TIPO_INFO[tipoSelecionado] || TIPO_INFO_GENERICO) : null;
  const TipoIcon = tipoInfo?.icon || FileText;

  const handleAvancar = async () => {
    if (!state.arquivo) return;
    if (!tipoSelecionado) {
      toast.error("Selecione o tipo do documento antes de continuar");
      return;
    }

    setProcessando(true);
    updateState({ processando: true, erro: null });

    try {
      toast.info("Enviando arquivo para extração inteligente...");
      const result = await extractTextViaEdgeFunction(state.arquivo);
      toast.success(`Texto extraído: ${result.palavras.toLocaleString("pt-BR")} palavras`);
      // Pula diretamente para extração (etapa 3), com tipo já definido
      updateState({
        textoExtraido: result.texto,
        tipoDetectado: tipoSelecionado,
        confiancaClassificacao: 100,
        justificativaClassificacao: "Tipo definido manualmente pelo usuário",
        etapa: 3,
        processando: false,
      });
    } catch (err: any) {
      updateState({ erro: err.message, processando: false });
      toast.error("Erro ao extrair arquivo: " + err.message);
    } finally {
      setProcessando(false);
    }
  };

  return (
    <div className="space-y-4">
      {/* Seleção do tipo de documento */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <FileText className="w-4 h-4 text-primary" />
            Tipo de Documento
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label className="text-sm font-medium mb-1.5 block">
              Selecione o tipo antes de enviar
              <span className="text-destructive ml-1">*</span>
            </Label>
            <Select value={tipoSelecionado} onValueChange={setTipoSelecionado}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Selecione o tipo do documento..." />
              </SelectTrigger>
              <SelectContent>
                {TIPOS_DOCUMENTO.map(t => (
                  <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground mt-1.5">
              Informar o tipo com antecedência garante extração precisa e adequada para cada documento.
            </p>
          </div>

          {/* Preview do que será extraído */}
          {tipoInfo && (
            <div className={`rounded-xl border p-4 bg-muted/30 space-y-2`}>
              <div className="flex items-center gap-2">
                <TipoIcon className={`w-4 h-4 ${tipoInfo.color}`} />
                <span className="text-sm font-semibold">{tipoInfo.titulo}</span>
              </div>
              <p className="text-xs text-muted-foreground">{tipoInfo.descricao}</p>
              <div className="space-y-1 pt-1">
                <p className="text-xs font-medium text-foreground">O sistema irá importar:</p>
                <ul className="space-y-1">
                  {tipoInfo.extrai.map((item, i) => (
                    <li key={i} className="flex items-start gap-1.5 text-xs text-muted-foreground">
                      <CheckCircle2 className="w-3.5 h-3.5 text-green-600 mt-0.5 flex-shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Upload do arquivo */}
      <Card>
        <CardContent className="pt-6">
          <div
            {...getRootProps()}
            className={`border-2 border-dashed rounded-xl p-8 text-center cursor-pointer transition-all ${
              isDragActive
                ? "border-primary bg-primary/5"
                : state.arquivo
                ? "border-primary/40 bg-primary/5"
                : "border-muted-foreground/30 hover:border-primary/50 hover:bg-muted/30"
            }`}
          >
            <input {...getInputProps()} />
            {state.arquivo ? (
              <div className="flex flex-col items-center gap-3">
                <div className="p-3 bg-primary/10 rounded-xl">
                  <FileText className="w-8 h-8 text-primary" />
                </div>
                <div>
                  <p className="font-semibold text-foreground">{state.arquivo.name}</p>
                  <p className="text-sm text-muted-foreground mt-1">
                    {(state.arquivo.size / 1024 / 1024).toFixed(2)} MB
                  </p>
                </div>
                <div className="flex gap-2">
                  <Badge variant="secondary">Arquivo selecionado</Badge>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={(e) => { e.stopPropagation(); updateState({ arquivo: null }); }}
                  >
                    <X className="w-4 h-4 mr-1" /> Remover
                  </Button>
                </div>
              </div>
            ) : (
              <div className="flex flex-col items-center gap-3">
                <div className="p-3 bg-muted rounded-xl">
                  <Upload className="w-8 h-8 text-muted-foreground" />
                </div>
                <div>
                  <p className="font-semibold">
                    {isDragActive ? "Solte o arquivo aqui" : "Arraste ou clique para selecionar"}
                  </p>
                  <p className="text-sm text-muted-foreground mt-1">PDF, DOCX ou DOC — máximo {MAX_SIZE_MB}MB</p>
                </div>
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Aviso de qualidade */}
      <Card className="border-amber-500/30 bg-amber-50 dark:bg-amber-950/20">
        <CardContent className="py-3 px-4 flex items-start gap-3">
          <AlertCircle className="w-4 h-4 text-amber-600 dark:text-amber-400 mt-0.5 flex-shrink-0" />
          <p className="text-xs text-amber-800 dark:text-amber-200">
            <strong>Melhor resultado com PDFs nativos (texto selecionável).</strong> PDFs digitalizados (imagens) podem ter qualidade reduzida. Ao selecionar o tipo correto, a IA aplica regras específicas de extração para aquele documento.
          </p>
        </CardContent>
      </Card>

      <div className="flex justify-end">
        <Button
          onClick={handleAvancar}
          disabled={!state.arquivo || !tipoSelecionado || processando}
          size="lg"
        >
          {processando ? (
            <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Extraindo texto...</>
          ) : (
            <><CheckCircle2 className="w-4 h-4 mr-2" />Extrair Dados — {TIPOS_DOCUMENTO.find(t => t.value === tipoSelecionado)?.label?.split(" — ")[0] || "Selecionar tipo"}</>
          )}
        </Button>
      </div>
    </div>
  );
}
